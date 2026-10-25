import assert from "node:assert/strict";
import { test } from "node:test";
import { overBudget } from "./size-budget.mjs";

const budgets = [{ file: "a.json", maxRawKB: 10, maxGzKB: 2 }];

test("sizes within budget pass", () => {
  assert.deepEqual(overBudget({ "a.json": { raw: 10 * 1024, gz: 2 * 1024 } }, budgets), []);
});

test("raw over budget fails with the file, size and limit", () => {
  const errs = overBudget({ "a.json": { raw: 10 * 1024 + 1, gz: 100 } }, budgets);
  assert.equal(errs.length, 1);
  assert.match(errs[0], /a\.json is 10\.0 KB, over its 10 KB budget \(raw\)/);
});

test("gzipped over budget fails on its own", () => {
  const errs = overBudget({ "a.json": { raw: 100, gz: 3 * 1024 } }, budgets);
  assert.equal(errs.length, 1);
  assert.match(errs[0], /gzipped/);
});

test("a file that was not built is skipped", () => {
  assert.deepEqual(overBudget({}, budgets), []);
});
