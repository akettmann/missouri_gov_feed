import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { budgetGate, formatBudgetError, measure, overBudget, skipRequested } from "./size-budget.mjs";

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

test("a missing file's message points at BUDGETS/the build, not at trimming", () => {
  const [missing] = overBudget({}, budgets);
  const msg = formatBudgetError(missing);
  assert.match(msg, /update BUDGETS in scripts\/size-budget\.mjs/);
  assert.doesNotMatch(msg, /Trim the payload/);
  const [over] = overBudget({ "a.json": { raw: 11 * 1024, gz: 1 } }, budgets);
  assert.match(formatBudgetError(over), /^OVER BUDGET: .*Trim the payload/);
});

test("MOGOV_SKIP_SIZE_BUDGET skips only when exactly 1", () => {
  assert.equal(skipRequested({ MOGOV_SKIP_SIZE_BUDGET: "1" }), true);
  for (const v of ["0", "", "true", undefined])
    assert.equal(skipRequested({ MOGOV_SKIP_SIZE_BUDGET: v }), false);
});

test("budgetGate runs the check before publishing, blocks on failure, and skips only on =1", () => {
  const calls = [];
  const log = { log: (m) => calls.push(["log", m]), error: (m) => calls.push(["error", m]) };
  const spawn = (status) => () => (calls.push(["spawn"]), { status });
  assert.equal(budgetGate({ cwd: "x", env: {}, spawn: spawn(0), log }), true);
  assert.deepEqual(calls.splice(0), [["spawn"]]);
  assert.equal(budgetGate({ cwd: "x", env: { MOGOV_SKIP_SIZE_BUDGET: "0" }, spawn: spawn(1), log }), false);
  assert.deepEqual(
    calls.splice(0).map((c) => c[0]),
    ["spawn", "error"],
  );
  assert.equal(budgetGate({ cwd: "x", env: { MOGOV_SKIP_SIZE_BUDGET: "1" }, spawn: spawn(1), log }), true);
  assert.deepEqual(
    calls.splice(0).map((c) => c[0]),
    ["log"],
  );
});
