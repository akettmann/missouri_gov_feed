// Publish a locally built site to GitHub Pages via an orphan `gh-pages` branch (Pages source: "Deploy from a
// branch"). CI has no data, so the build happens here. Only the `gh-pages` branch is ever written, and its
// history is replaced on every deploy (force push) so 170+ MB snapshots do not pile up; main is untouched.
//   pnpm deploy:pages --dry-run   # build, check, commit into a temp repo, report; pushes nothing
//   pnpm deploy:pages             # the same, then force-push to gh-pages (publishes the site!)
// Flags: --skip-build (reuse dist/, which must have been built with the Pages base), --allow-stale,
// --remote NAME (default origin), --branch NAME (default gh-pages).
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { checkLimits, pagesTarget, parseArgs, repoFromRemote } from "./pages-config.mjs";
import { resolveDbPath, resolveExportsDir, staleExportsWarning } from "./stale-exports.mjs";

function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", ...opts });
  if (r.status !== 0) {
    if (r.stderr) console.error(r.stderr);
    console.error(`${cmd} ${args.join(" ")} failed (${r.status ?? r.error?.message}).`);
    process.exit(r.status ?? 1);
  }
  return (r.stdout ?? "").trim();
}

function listFiles(dir, rel = "") {
  return readdirSync(path.join(dir, rel), { withFileTypes: true }).flatMap((e) => {
    const p = path.join(rel, e.name);
    return e.isDirectory() ? listFiles(dir, p) : [{ path: p, size: statSync(path.join(dir, p)).size }];
  });
}

const { opts, errors } = parseArgs(process.argv.slice(2));
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(2);
}

const remoteUrl = run("git", ["remote", "get-url", opts.remote]);
const repo = process.env.MOGOV_PAGES_REPO ?? repoFromRemote(remoteUrl);
if (!repo) {
  console.error(`Cannot tell the GitHub repo from remote ${remoteUrl}; set MOGOV_PAGES_REPO=owner/name.`);
  process.exit(2);
}
const target = pagesTarget(repo);

const stale = staleExportsWarning(resolveDbPath(), resolveExportsDir());
if (stale && !opts.allowStale) {
  console.error(`${stale}\nRefusing to deploy stale data (override with --allow-stale).`);
  process.exit(1);
}

if (opts.skipBuild) {
  if (!existsSync("dist/index.html")) {
    console.error("dist/ is missing: drop --skip-build.");
    process.exit(2);
  }
} else {
  console.log(`> pnpm build (base ${target.base ?? "/"}, site ${target.site})`);
  const r = spawnSync("pnpm", ["build"], {
    stdio: "inherit",
    shell: process.platform === "win32",
    env: { ...process.env, PUBLIC_SITE_URL: target.site, PUBLIC_BASE_PATH: target.base ?? "" },
  });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

// Every root-relative link must resolve under the Pages base; a --skip-build dist from the wrong build fails here.
const lc = spawnSync(process.execPath, ["scripts/link-check.mjs", "dist", target.base ?? ""], {
  stdio: "inherit",
});
if (lc.status !== 0) {
  console.error("Link check failed: was dist/ built with the Pages base?");
  process.exit(1);
}

const work = mkdtempSync(path.join(tmpdir(), "mogov-pages-"));
cpSync("dist", work, { recursive: true });
writeFileSync(path.join(work, ".nojekyll"), ""); // serve _astro/ as-is
if (!existsSync(path.join(work, "404.html"))) console.warn("warning: dist has no 404.html");

const { totalBytes, largest, problems } = checkLimits(listFiles(work));
const mb = (n) => (n / 1048576).toFixed(1);
console.log(`${mb(totalBytes)} MB total, largest file ${largest?.path} (${mb(largest?.size ?? 0)} MB)`);
if (problems.length) {
  console.error(problems.join("\n"));
  rmSync(work, { recursive: true, force: true });
  process.exit(1);
}

const identity = ["-c", "user.name=mogov deploy", "-c", "user.email=noreply@users.noreply.github.com"];
const git = (...a) => run("git", [...identity, ...a], { cwd: work });
git("init", "-q", "-b", opts.branch);
git("add", "-A");
git("commit", "-q", "-m", `Deploy site (${new Date().toISOString()})`);
const sha = git("rev-parse", "--short", "HEAD");

if (opts.dryRun) {
  console.log(`Dry run: committed ${sha} on ${opts.branch} in ${work}; nothing pushed.`);
  console.log(`Would run: git push --force ${remoteUrl} ${opts.branch}:refs/heads/${opts.branch}`);
  console.log(`Would be live at ${target.url}`);
} else {
  git("push", "--force", remoteUrl, `${opts.branch}:refs/heads/${opts.branch}`);
  rmSync(work, { recursive: true, force: true });
  console.log(`Pushed ${sha} to ${opts.branch}. Live shortly at ${target.url}`);
}
