// Helpers shared by astro.config.mjs and deploy-pages.mjs (no dependencies beyond node:, so tests can import them).
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

/** The only branch deploy:pages ever writes. Deliberately not configurable: it is force-pushed. */
export const PAGES_BRANCH = "gh-pages";

/** Where `repo` ("owner/name") is pushed to; derived from the same slug that sets the site URL and base. */
export function pushUrl(repo) {
  return `https://github.com/${repo}.git`;
}

/** Strip any user:password@ from a URL before it is printed. */
export function redactUrl(url) {
  return String(url).replace(/(\/\/)[^/@\s]+@/g, "$1***@");
}

/**
 * Run `await fn(dir, guard)` in a fresh temp dir that is removed afterwards, even when fn throws, unless keep is set.
 * fn must do its long work asynchronously (fs.promises, not *Sync) so the event loop can deliver SIGINT: the first
 * Ctrl+C removes the dir (unless keep) and exits 130 at once; a second one exits 130 without waiting. While fn is
 * blocked in a synchronous call (e.g. spawnSync) the signal is delivered when it returns, so `guard.check()`
 * throws if an interrupt arrived, and callers must call it immediately before any irreversible step (git push).
 * `proc` and `exit` are injectable for tests.
 */
export async function withTempDir(
  prefix,
  fn,
  { keep = false, root = tmpdir(), proc = process, exit = process.exit } = {},
) {
  const dir = mkdtempSync(path.join(root, prefix));
  let interrupted = false;
  const guard = {
    get interrupted() {
      return interrupted;
    },
    check() {
      if (interrupted) throw new Error("Interrupted (SIGINT); nothing was pushed.");
    },
  };
  const onSigint = () => {
    if (interrupted) return exit(130); // second Ctrl+C: leave immediately
    interrupted = true;
    if (!keep) rmSync(dir, { recursive: true, force: true });
    exit(130);
  };
  proc.on("SIGINT", onSigint);
  try {
    return await fn(dir, guard);
  } finally {
    proc.removeListener("SIGINT", onSigint);
    if (!keep) rmSync(dir, { recursive: true, force: true });
  }
}

/** Normalise a base path: "" / "/" / undefined -> undefined (Astro default), "x" or "/x/" -> "/x". */
export function normalizeBase(raw) {
  const trimmed = (raw ?? "").trim().replace(/^\/+|\/+$/g, "");
  // Git Bash on Windows rewrites "/x" in env vars to "C:/Program Files/Git/x"; fail loudly instead of shipping it.
  if (trimmed && !/^[A-Za-z0-9._~-]+(\/[A-Za-z0-9._~-]+)*$/.test(trimmed)) {
    throw new Error(
      `Invalid base path ${JSON.stringify(raw)} (MSYS path conversion? set MSYS_NO_PATHCONV=1).`,
    );
  }
  return trimmed ? `/${trimmed}` : undefined;
}

/** Where a GitHub Pages site for `owner/repo` is served. User/org sites (`owner.github.io`) live at the root. */
export function pagesTarget(repoSlug) {
  const m = /^([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)$/.exec(repoSlug ?? "");
  if (!m) throw new Error(`Expected a repo like "owner/name", got ${JSON.stringify(repoSlug)}.`);
  const [, owner, name] = m;
  if (/^\.+$/.test(name)) throw new Error(`Invalid repo name ${JSON.stringify(name)}.`);
  const site = `https://${owner.toLowerCase()}.github.io`;
  const userSite = name.toLowerCase() === `${owner.toLowerCase()}.github.io`;
  const base = userSite ? undefined : `/${name}`;
  return { site, base, url: `${site}${base ?? ""}/` };
}

/** Anchored at the start: an https/ssh URL or scp-style `user@` prefix, then the github.com host itself. */
const GITHUB_REMOTE =
  /^(?:(?:https?|ssh|git\+ssh):\/\/(?:[^@/\\\s]+@)?|[^@/\\\s:]+@)github\.com[:/]([^/\s]+)\/([^/\s]+?)(?:\.git)?\/?$/i;

/** Extract "owner/name" from an https or ssh GitHub remote URL, or null (other hosts, local paths, "."/".." names). */
export function repoFromRemote(url) {
  const m = GITHUB_REMOTE.exec((url ?? "").trim());
  if (!m || /^\.+$/.test(m[1]) || /^\.+$/.test(m[2])) return null;
  return `${m[1]}/${m[2]}`;
}

const MB = 1024 * 1024;
/** GitHub Pages limits: published site <= 1 GB, each file < 100 MB (git push rejects >= 100 MB). */
export const LIMITS = { siteBytes: 1024 * MB, fileBytes: 100 * MB };

/** files: [{path, size}] -> {totalBytes, largest, problems: string[]} */
export function checkLimits(files, limits = LIMITS) {
  const totalBytes = files.reduce((n, f) => n + f.size, 0);
  const largest = files.reduce((a, f) => (!a || f.size > a.size ? f : a), null);
  const problems = [];
  if (totalBytes > limits.siteBytes) {
    problems.push(
      `site is ${(totalBytes / MB).toFixed(0)} MB, over the ${limits.siteBytes / MB} MB Pages limit`,
    );
  }
  for (const f of files) {
    if (f.size >= limits.fileBytes) {
      problems.push(
        `${f.path} is ${(f.size / MB).toFixed(1)} MB, over the ${limits.fileBytes / MB} MB file limit`,
      );
    }
  }
  return { totalBytes, largest, problems };
}

/** Parse `deploy:pages` flags. Unknown flags (any --branch included) are errors: the target is fixed to PAGES_BRANCH. */
export function parseArgs(argv) {
  const opts = {
    dryRun: false,
    skipBuild: false,
    allowStale: false,
    allowDirty: false,
    keep: false,
    remote: "origin",
  };
  const errors = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") opts.dryRun = true;
    else if (a === "--skip-build") opts.skipBuild = true;
    else if (a === "--allow-stale") opts.allowStale = true;
    else if (a === "--allow-dirty") opts.allowDirty = true;
    else if (a === "--keep") opts.keep = true;
    else if (a === "--remote") {
      const v = argv[++i];
      if (!v || v.startsWith("--")) errors.push(`${a} needs a value`);
      else opts.remote = v;
    } else errors.push(`unknown argument ${a}`);
  }
  return { opts, errors };
}
