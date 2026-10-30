// Page-weight budgets for the big shared payloads in dist/ (checked by `pnpm sizes`, after `pnpm build`).
// Sizes measured 2026-10 with the badge fix: lookup/districts.json ~1147 KB raw / ~309 KB gzipped;
// awards/index.html 339 KB raw / 19 KB gzipped (753 KB / 28 KB before the repeated badges were dropped), grown to
// 453 KB / 25 KB by 2026-10-29 as awards were added (budget raised then). Budgets leave ~30% headroom so normal data growth
// passes but a payload that doubles (say, a repeated field added to every row) fails the build check.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { gzipSync } from "node:zlib";

export const BUDGETS = [
  { file: "lookup/districts.json", maxRawKB: 1500, maxGzKB: 410 },
  { file: "awards/index.html", maxRawKB: 600, maxGzKB: 33 },
  // The largest RSMo section page (260.700, 69.6k characters of law text), measured 2026-10 (#840): ~74 KB raw /
  // ~18.5 KB gzipped. Only built when the statute exports are there; the "not loaded yet" build has no such page.
  {
    file: "statutes/260.700/index.html",
    maxRawKB: 100,
    maxGzKB: 25,
    skipIfPresent: "statutes/not-loaded/index.html",
  },
];

/** Budgets that apply to this build: one with `skipIfPresent` is dropped when that marker file was built. */
export function activeBudgets(distDir, budgets = BUDGETS, exists = existsSync) {
  return budgets.filter((b) => !(b.skipIfPresent && exists(path.join(distDir, b.skipIfPresent))));
}

/** Total bytes of every file under `dir` (0 when it does not exist). */
export function dirBytes(dir) {
  if (!existsSync(dir)) return 0;
  return readdirSync(dir, { withFileTypes: true }).reduce(
    (n, e) =>
      n + (e.isDirectory() ? dirBytes(path.join(dir, e.name)) : statSync(path.join(dir, e.name)).size),
    0,
  );
}

const kb = (n) => `${(n / 1024).toFixed(1)} KB`;

/**
 * Compare measured sizes with budgets. `sizes` maps file -> {raw, gz} in bytes. Returns one error message per
 * exceeded limit, and one per budgeted file that was not built: both budgeted pages are always emitted (they
 * fall back to an empty page without their export), so a missing file means a renamed page or a broken build
 * and the budget would otherwise stop guarding it without anyone noticing.
 */
export function overBudget(sizes, budgets = BUDGETS) {
  const errors = [];
  for (const b of budgets) {
    const s = sizes[b.file];
    if (!s) {
      errors.push(
        `${b.file} is budgeted but was not found in the build output (renamed or dropped? update BUDGETS)`,
      );
      continue;
    }
    if (s.raw > b.maxRawKB * 1024)
      errors.push(`${b.file} is ${kb(s.raw)}, over its ${b.maxRawKB} KB budget (raw)`);
    if (s.gz > b.maxGzKB * 1024)
      errors.push(`${b.file} is ${kb(s.gz)} gzipped, over its ${b.maxGzKB} KB budget (gzipped)`);
  }
  return errors;
}

/** Measure each budgeted file under `distDir`; files that were not built are left out (overBudget reports them). */
export function measure(distDir, budgets = BUDGETS) {
  const sizes = {};
  for (const { file } of budgets) {
    const p = path.join(distDir, file);
    if (!existsSync(p)) continue;
    const buf = readFileSync(p);
    sizes[file] = { raw: buf.length, gz: gzipSync(buf).length };
  }
  return sizes;
}

/** MOGOV_SKIP_SIZE_BUDGET skips the budget only when it is exactly "1" (so "0" or "" still check). */
export function skipRequested(env = process.env) {
  return env.MOGOV_SKIP_SIZE_BUDGET === "1";
}

/** The console line for one overBudget() error: a missing file needs a BUDGETS/build fix, not a trim. */
export function formatBudgetError(error) {
  return /was not found in the build output/.test(error)
    ? `MISSING FROM BUILD: ${error}. Check the build, or update BUDGETS in scripts/size-budget.mjs.`
    : `OVER BUDGET: ${error}. Trim the payload or raise the budget in scripts/size-budget.mjs.`;
}

/** Run the budget check (scripts/export-sizes.mjs) on `cwd`'s dist/ before publishing. Returns true to go ahead. */
export function budgetGate({ cwd, env = process.env, spawn, log = console }) {
  if (skipRequested(env)) {
    log.log("MOGOV_SKIP_SIZE_BUDGET=1: publishing without the size budget check.");
    return true;
  }
  const r = spawn(process.execPath, [path.join(cwd, "scripts", "export-sizes.mjs")], {
    cwd,
    stdio: "inherit",
  });
  if (r.status === 0) return true;
  log.error(
    "Size budget check failed: not publishing (fix it, or set MOGOV_SKIP_SIZE_BUDGET=1 to publish anyway).",
  );
  return false;
}
