// Pure helpers shared by astro.config.mjs and deploy-pages.mjs (kept dependency-free so tests can import them).

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
  const site = `https://${owner.toLowerCase()}.github.io`;
  const userSite = name.toLowerCase() === `${owner.toLowerCase()}.github.io`;
  const base = userSite ? undefined : `/${name}`;
  return { site, base, url: `${site}${base ?? ""}/` };
}

/** Extract "owner/name" from an https or ssh GitHub remote URL, or null. */
export function repoFromRemote(url) {
  const m = /github\.com[:/]([^/\s]+)\/([^/\s]+?)(?:\.git)?\/?$/.exec((url ?? "").trim());
  return m ? `${m[1]}/${m[2]}` : null;
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

/** Parse `deploy:pages` flags. Unknown flags are errors so typos never trigger a real push. */
export function parseArgs(argv) {
  const opts = { dryRun: false, skipBuild: false, allowStale: false, remote: "origin", branch: "gh-pages" };
  const errors = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") opts.dryRun = true;
    else if (a === "--skip-build") opts.skipBuild = true;
    else if (a === "--allow-stale") opts.allowStale = true;
    else if (a === "--remote" || a === "--branch") {
      const v = argv[++i];
      if (!v || v.startsWith("--")) errors.push(`${a} needs a value`);
      else opts[a.slice(2)] = v;
    } else errors.push(`unknown argument ${a}`);
  }
  return { opts, errors };
}
