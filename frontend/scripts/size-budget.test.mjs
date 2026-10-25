import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { measure, overBudget } from "./size-budget.mjs";

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

test("a budgeted file that was not built is reported, not skipped", () => {
  const errs = overBudget({}, budgets);
  assert.equal(errs.length, 1);
  assert.match(errs[0], /a\.json is budgeted but was not found/);
});

test("measure leaves out files that are not in the build output", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "budget-"));
  try {
    writeFileSync(path.join(dir, "a.json"), "x".repeat(100));
    const two = [...budgets, { file: "b.json", maxRawKB: 1, maxGzKB: 1 }];
    const sizes = measure(dir, two);
    assert.deepEqual(Object.keys(sizes), ["a.json"]);
    assert.equal(sizes["a.json"].raw, 100);
    assert.equal(overBudget(sizes, two).length, 1);
  } finally {
    rmSync(dir, { recursive: true });
  }
});
