// Page-weight budgets for the big shared payloads in dist/ (checked by `pnpm sizes`, after `pnpm build`).
// Sizes measured 2026-10 with the badge fix: lookup/districts.json ~1.12 MB raw / ~313 KB gzipped;
// awards/index.html 339 KB raw / 19 KB gzipped (753 KB / 28 KB before the repeated badges were dropped). Budgets leave ~30% headroom so normal data growth
// passes but a payload that doubles (say, a repeated field added to every row) fails the build check.
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { gzipSync } from "node:zlib";

export const BUDGETS = [
  { file: "lookup/districts.json", maxRawKB: 1500, maxGzKB: 410 },
  { file: "awards/index.html", maxRawKB: 450, maxGzKB: 25 },
];

const kb = (n) => `${(n / 1024).toFixed(1)} KB`;

/**
 * Compare measured sizes with budgets. `sizes` maps file -> {raw, gz} in bytes; a missing file is skipped
 * (the page may be absent when its export is). Returns one error message per exceeded limit.
 */
export function overBudget(sizes, budgets = BUDGETS) {
  const errors = [];
  for (const b of budgets) {
    const s = sizes[b.file];
    if (!s) continue;
    if (s.raw > b.maxRawKB * 1024)
      errors.push(`${b.file} is ${kb(s.raw)}, over its ${b.maxRawKB} KB budget (raw)`);
    if (s.gz > b.maxGzKB * 1024)
      errors.push(`${b.file} is ${kb(s.gz)} gzipped, over its ${b.maxGzKB} KB budget (gzipped)`);
  }
  return errors;
}

/** Measure each budgeted file under `distDir`; files that were not built are left out. */
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
