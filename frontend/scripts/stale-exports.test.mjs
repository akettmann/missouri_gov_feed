import assert from "node:assert/strict";
import { mkdtempSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { resolveDbPath, staleExportsWarning } from "./stale-exports.mjs";

/** Fixed ages (seconds before now) so the outcome never depends on real data. */
function setup(dbAge, files) {
  const dir = mkdtempSync(path.join(tmpdir(), "stale-"));
  const now = Date.now() / 1000;
  const db = path.join(dir, "mogov.duckdb");
  writeFileSync(db, "");
  utimesSync(db, now - dbAge, now - dbAge);
  for (const [name, age] of Object.entries(files)) {
    const p = path.join(dir, name);
    writeFileSync(p, "");
    utimesSync(p, now - age, now - age);
  }
  return { db, dir };
}

test("warns and names only the stale files", () => {
  const { db, dir } = setup(100, { "old.parquet": 7200, "fresh.parquet": 10 });
  const msg = staleExportsWarning(db, dir);
  assert.match(msg, /old\.parquet/);
  assert.doesNotMatch(msg, /fresh\.parquet/);
  assert.match(msg, /uv run mogov export/);
});

test("silent when exports are newer", () => {
  const { db, dir } = setup(100, { "a.parquet": 10 });
  assert.equal(staleExportsWarning(db, dir), null);
});

test("silent when the DuckDB file is absent", () => {
  const { dir } = setup(100, { "a.parquet": 9999 });
  assert.equal(staleExportsWarning(path.join(dir, "nope.duckdb"), dir), null);
});

test("MOGOV_DB wins over MOGOV_DATA_DIR", () => {
  assert.equal(resolveDbPath({ MOGOV_DB: "/x/a.duckdb", MOGOV_DATA_DIR: "/y" }), path.resolve("/x/a.duckdb"));
  assert.equal(resolveDbPath({ MOGOV_DATA_DIR: "/y" }), path.resolve("/y/mogov.duckdb"));
});
