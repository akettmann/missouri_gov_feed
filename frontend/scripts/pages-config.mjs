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

/** Thrown (the caller then exits 130) when Ctrl+C / SIGINT arrives while a deploy is staged. */
export class InterruptedError extends Error {
  constructor() {
    super("Interrupted.");
    this.name = "InterruptedError";
  }
}

/** True for a child's exit that means "it was Ctrl+C'd": SIGINT, POSIX 130, or Windows STATUS_CONTROL_C_EXIT. */
export function isInterruptExit(status, signal) {
  return signal === "SIGINT" || status === 130 || status === 3221225786;
}

/**
 * Run `await fn(dir, guard)` in a fresh temp dir that is removed afterwards, even when fn throws, unless keep is set.
 * The first SIGINT rejects the returned promise with InterruptedError at once, even while fn is mid-await (the caller
 * then exits 130); the dir is removed unless keep. Further SIGINTs are ignored until that cleanup has finished, so
 * a second Ctrl+C cannot kill the process mid-delete. fn must not block the event loop (no *Sync calls for long work,
 * use async spawn), otherwise the signal cannot be delivered until the block ends; as a backstop `await guard.check()`
 * yields one event-loop turn (delivering a pending signal) and throws InterruptedError if an interrupt arrived, and
 * callers must call it immediately before any irreversible step (git push). `proc` and `remove` (the deleter) are injectable for tests.
 */
export async function withTempDir(
  prefix,
  fn,
  { keep = false, root = tmpdir(), proc = process, remove = rmSync } = {},
) {
  const dir = mkdtempSync(path.join(root, prefix));
  let interrupted = false;
  let cleaning = false;
  let rejectInterrupt;
  const interrupt = new Promise((_, reject) => {
    rejectInterrupt = reject;
  });
  const guard = {
    get interrupted() {
      return interrupted;
    },
    async check() {
      await new Promise((resolve) => setImmediate(resolve)); // let a pending signal's listener run first
      if (interrupted) throw new InterruptedError();
    },
  };
  const onSigint = () => {
    if (cleaning || interrupted) return; // stay installed (and ignore Ctrl+C) until the dir is gone
    interrupted = true;
    rejectInterrupt(new InterruptedError());
  };
  proc.on("SIGINT", onSigint);
  const work = (async () => fn(dir, guard))(); // also tolerates a plain (sync) fn
  work.catch(() => {}); // after an interrupt fn may still fail; the race below already reported the interrupt
  try {
    return await Promise.race([work, interrupt]);
  } finally {
    cleaning = true;
    try {
      if (!keep) remove(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
    } finally {
      proc.removeListener("SIGINT", onSigint);
    }
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
