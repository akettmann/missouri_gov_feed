import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { DuckDBInstance } from "@duckdb/node-api";
import { assertNoMissingColumns, missingColumns } from "../src/lib/exports/requiredColumns.ts";

const REQ = { t_one: ["a", "b"], t_two: ["c"] };

test("missingColumns lists only the absent required columns, per table", () => {
  assert.deepEqual(missingColumns({ t_one: ["a"], t_two: ["c", "x"], other: [] }, REQ), { t_one: ["b"] });
});

test("assertNoMissingColumns passes on a current export and ignores undeclared tables", () => {
  assert.doesNotThrow(() => assertNoMissingColumns({ t_one: ["a", "b", "extra"], other: ["z"] }, REQ));
});

test("assertNoMissingColumns names every stale table, its columns, and the re-export commands", () => {
  assert.throws(
    () => assertNoMissingColumns({ t_one: [], t_two: ["q"] }, REQ),
    (e) =>
      /stale export: t_one lacks a, b; t_two lacks c/.test(e.message) &&
      e.message.includes("uv run mogov build") &&
      e.message.includes("uv run mogov export --format parquet"),
  );
});

// End to end through query(): a stale parquet gives the clear message, a current one runs.
test("query() reports a stale fct_jurisdiction_businesses export instead of a binder error", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "275-exports-"));
  try {
    const db = await DuckDBInstance.create(":memory:");
    const c = await db.connect();
    const file = path.join(dir, "fct_jurisdiction_businesses.parquet").replaceAll("\\", "/");
    await c.run(`copy (select 'x' as official_id, 'y' as donor_names) to '${file}' (format parquet)`);
    process.env.MOGOV_EXPORTS = dir;
    const { query } = await import("../src/lib/exports/db.ts");
    await assert.rejects(
      query("select donor_links from {fct_jurisdiction_businesses}"),
      (e) =>
        /stale export: fct_jurisdiction_businesses lacks .*donor_links/.test(e.message) &&
        !/Binder/.test(e.message),
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
