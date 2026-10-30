// Publish a locally built site to GitHub Pages via an orphan `gh-pages` branch (Pages source: "Deploy from a
// branch"). CI has no data, so the build happens here. Only the `gh-pages` branch is ever written, and its
// history is replaced on every deploy (force push) so ~600 MB snapshots do not pile up; main is untouched.
// The live branch is fetched into frontend/.pages-cache first, so the push only uploads files that changed.
//   pnpm deploy:pages --dry-run   # build, check, commit into the cache, report the change; pushes nothing
//   pnpm deploy:pages             # the same, then force-push to gh-pages (publishes the site!)
// The branch is fixed to gh-pages (there is no --branch flag). Flags: --skip-build (reuse dist/, which must
// have been built with the Pages base), --allow-stale, --allow-dirty (deploy with uncommitted frontend/
// changes), --keep (keep the temp dir with the throwaway index), --remote NAME (default origin; only used to learn which GitHub repo
// this is: the push goes to https://github.com/<owner>/<name>.git).
import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  beginPush,
  checkLimits,
  failureReport,
  InterruptedError,
  isInterruptExit,
  PAGES_BRANCH,
  pagesTarget,
  parseArgs,
  pushUrl,
  redactUrl,
  repoFromRemote,
  withTempDir,
} from "./pages-config.mjs";
import { budgetGate } from "./size-budget.mjs";
import { resolveDbPath, resolveExportsDir, staleExportsWarning } from "./stale-exports.mjs";

// Everything below resolves from frontend/ (this file's parent), so the cwd the script is started from is irrelevant.
const FRONTEND = fileURLToPath(new URL("..", import.meta.url));
const DIST = path.join(FRONTEND, "dist");
// Kept between deploys (gitignored): holds the live gh-pages objects so a push only sends what changed.
// Safe to delete; the next deploy fetches the live branch again.
const CACHE = path.join(FRONTEND, ".pages-cache");

function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", cwd: FRONTEND, ...opts });
  if (r.status !== 0) {
    if (r.stderr) console.error(redactUrl(r.stderr));
    throw new Error(`${cmd} ${redactUrl(args.join(" "))} failed (${r.status ?? r.error?.message}).`);
  }
  return (r.stdout ?? "").trimEnd();
}

// Async so the event loop keeps turning (and a Ctrl+C reaches withTempDir's listener) while git works.
function runAsync(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd: FRONTEND, ...opts });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (d) => (stdout += d));
    child.stderr.setEncoding("utf8").on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (status, signal) => {
      if (status === 0) return resolve(stdout.trimEnd());
      if (isInterruptExit(status, signal)) return reject(new InterruptedError());
      if (stderr) console.error(redactUrl(stderr));
      reject(new Error(`${cmd} ${redactUrl(args.join(" "))} failed (${status ?? signal}).`));
    });
  });
}

async function listFiles(dir, rel = "") {
  const entries = await readdir(path.join(dir, rel), { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (e) => {
      const p = path.join(rel, e.name);
      return e.isDirectory() ? listFiles(dir, p) : [{ path: p, size: (await stat(path.join(dir, p))).size }];
    }),
  );
  return nested.flat();
}

const { opts, errors } = parseArgs(process.argv.slice(2));
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(2);
}

const remoteUrl = run("git", ["remote", "get-url", opts.remote]);
const repo = repoFromRemote(remoteUrl);
if (!repo) {
  console.error(`Cannot tell the GitHub repo from remote ${opts.remote} (${redactUrl(remoteUrl)}).`);
  process.exit(2);
}
const target = pagesTarget(repo);
const pushTo = pushUrl(repo);

// dist/ is built from the working tree; make sure what gets published is what is committed.
const dirty = run("git", ["status", "--porcelain", "--", "."]);
if (dirty && !opts.allowDirty) {
  console.error(`Uncommitted changes in frontend/:\n${dirty}\nCommit them first (or pass --allow-dirty).`);
  process.exit(1);
}

const stale = staleExportsWarning(
  resolveDbPath(process.env, FRONTEND),
  resolveExportsDir(process.env, FRONTEND),
);
if (stale && !opts.allowStale) {
  console.error(`${stale}\nRefusing to deploy stale data (override with --allow-stale).`);
  process.exit(1);
}

if (opts.skipBuild) {
  if (!existsSync(path.join(DIST, "index.html"))) {
    console.error("dist/ is missing: drop --skip-build.");
    process.exit(2);
  }
  // A --skip-build dist never went through the build's own budget check.
  if (!budgetGate({ cwd: FRONTEND, spawn: spawnSync })) process.exit(1);
} else {
  console.log(`> pnpm build (base ${target.base ?? "/"}, site ${target.site})`);
  const r = spawnSync("pnpm build", {
    // A single command string with shell: true (pnpm is pnpm.cmd on Windows) avoids Node's DEP0190 warning.
    shell: true,
    cwd: FRONTEND,
    stdio: "inherit",
    env: { ...process.env, PUBLIC_SITE_URL: target.site, PUBLIC_BASE_PATH: target.base ?? "" },
  });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

// Every root-relative link must resolve under the Pages base; a --skip-build dist from the wrong build fails here.
const lc = spawnSync(
  process.execPath,
  [path.join(FRONTEND, "scripts", "link-check.mjs"), DIST, target.base ?? ""],
  {
    cwd: FRONTEND,
    stdio: "inherit",
  },
);
if (lc.status !== 0) {
  console.error("Link check failed: was dist/ built with the Pages base?");
  process.exit(1);
}

const identity = ["-c", "user.name=mogov deploy", "-c", "user.email=noreply@users.noreply.github.com"];
const TRACKING = `refs/remotes/pages/${PAGES_BRANCH}`;
let keptDir = null;
let pushStarted = false;
try {
  await withTempDir(
    "mogov-pages-",
    async (work, guard) => {
      keptDir = work;
      await writeFile(path.join(DIST, ".nojekyll"), ""); // serve _astro/ as-is
      if (!existsSync(path.join(DIST, "404.html"))) console.warn("warning: dist has no 404.html");

      const { totalBytes, largest, problems } = checkLimits(await listFiles(DIST));
      const mb = (n) => (n / 1048576).toFixed(1);
      console.log(`${mb(totalBytes)} MB total, largest file ${largest?.path} (${mb(largest?.size ?? 0)} MB)`);
      if (problems.length) throw new Error(problems.join("\n"));

      // dist/ is the work tree, the cache holds the objects and the index is throwaway (in the temp dir).
      const env = { ...process.env, GIT_INDEX_FILE: path.join(work, "index") };
      const git = (...a) =>
        runAsync("git", [...identity, `--git-dir=${CACHE}`, `--work-tree=${DIST}`, ...a], { cwd: work, env });
      await guard.check();
      if (!existsSync(CACHE)) await runAsync("git", ["init", "-q", "--bare", CACHE]);
      // Fetch the live tip so the push can leave out every object the remote already has.
      const live = (await git("ls-remote", pushTo, `refs/heads/${PAGES_BRANCH}`)).split(/\s/)[0];
      if (live) {
        console.log(`> fetching the live ${PAGES_BRANCH} (${live.slice(0, 7)}) into ${CACHE}`);
        await git("fetch", "-q", "--depth", "1", pushTo, `+refs/heads/${PAGES_BRANCH}:${TRACKING}`);
      }
      await guard.check();
      await git("add", "-A");
      await guard.check();
      const tree = await git("write-tree");
      if (live && tree === (await git("rev-parse", `${live}^{tree}`))) {
        console.log(`No changes from the live ${PAGES_BRANCH}; nothing to push.`);
        return;
      }
      // Orphan commit (no parent): the branch keeps one snapshot, as before.
      const sha = await git("commit-tree", tree, "-m", `Deploy site (${new Date().toISOString()})`);
      await git("update-ref", `refs/heads/${PAGES_BRANCH}`, sha);
      console.log(
        live ? `Changes: ${await git("diff", "--shortstat", live, sha)}` : "First deploy: every file is new.",
      );

      if (opts.dryRun) {
        console.log(`Dry run: committed ${sha.slice(0, 7)} in ${CACHE}; nothing pushed.`);
        console.log(`Would run: git push --force ${pushTo} ${PAGES_BRANCH}:refs/heads/${PAGES_BRANCH}`);
        console.log(`Would be live at ${target.url}`);
      } else {
        await beginPush(guard, () => (pushStarted = true)); // last stop before the force-push
        await git("push", "-q", "--force", pushTo, `refs/heads/${PAGES_BRANCH}:refs/heads/${PAGES_BRANCH}`);
        await git("update-ref", TRACKING, sha);
        console.log(`Pushed ${sha.slice(0, 7)} to ${PAGES_BRANCH}. Live shortly at ${target.url}`);
      }
      await git("gc", "--auto", "--quiet"); // drop superseded snapshots' objects over time
    },
    { keep: opts.keep },
  );
  if (opts.keep) console.log(`Kept temp dir: ${keptDir}`);
} catch (e) {
  const report = failureReport(e, pushStarted);
  console.error(report.message);
  if (opts.keep) console.error(`Kept temp dir: ${keptDir}`);
  process.exit(report.code);
}
