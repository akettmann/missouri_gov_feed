// Per-official payload sizes in dist/ (run after `pnpm build`): sets and checks the per-page JSON budget.
import { readdirSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { readFileSync } from "node:fs";
import path from "node:path";
import { measure, overBudget } from "./size-budget.mjs";

const dir = path.join("dist", "officials");
const BUDGET_GZ_KB = Number(process.env.JSON_BUDGET_GZ_KB ?? 100);

const rows = readdirSync(dir)
  .filter((f) => f.endsWith(".json"))
  .map((f) => {
    const file = path.join(dir, f);
    const html = path.join(dir, f.replace(/\.json$/, ""), "index.html");
    return {
      slug: f.replace(/\.json$/, ""),
      json: statSync(file).size,
      jsonGz: gzipSync(readFileSync(file)).length,
      html: statSync(html).size,
    };
  });

const kb = (n) => `${(n / 1024).toFixed(1)} KB`;
const pct = (xs, p) =>
  xs.toSorted((a, b) => a - b)[Math.min(xs.length - 1, Math.floor((p / 100) * xs.length))];
for (const key of ["json", "jsonGz", "html"]) {
  const xs = rows.map((r) => r[key]);
  console.log(`${key.padEnd(7)} p50 ${kb(pct(xs, 50))}  p95 ${kb(pct(xs, 95))}  max ${kb(Math.max(...xs))}`);
}
console.log("\nlargest JSON:");
for (const r of rows.toSorted((a, b) => b.json - a.json).slice(0, 5)) {
  console.log(`  ${r.slug.padEnd(40)} ${kb(r.json)} (${kb(r.jsonGz)} gz)`);
}
const over = rows.filter((r) => r.jsonGz > BUDGET_GZ_KB * 1024);
console.log(`\n${over.length} of ${rows.length} over the ${BUDGET_GZ_KB} KB gzipped budget`);

const sizes = measure("dist");
for (const [file, s] of Object.entries(sizes)) console.log(`${file}: ${kb(s.raw)} (${kb(s.gz)} gz)`);
const errors = overBudget(sizes);
for (const e of errors)
  console.error(`OVER BUDGET: ${e}. Trim the payload or raise the budget in scripts/size-budget.mjs.`);
process.exitCode = over.length || errors.length ? 1 : 0;
