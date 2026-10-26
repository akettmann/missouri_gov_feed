import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, test } from "node:test";
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

// End to end through query(): a stale parquet gives the clear message (listed or not), a current one runs,
// real SQL bugs pass through. db.ts reads MOGOV_EXPORTS once at import, so all tests share one directory.
const dir = mkdtempSync(path.join(tmpdir(), "275-exports-"));
process.env.MOGOV_EXPORTS = dir;
after(() => rmSync(dir, { recursive: true, force: true }));

async function withExports(files, fn) {
  const c = await (await DuckDBInstance.create(":memory:")).connect();
  for (const [table, select] of Object.entries(files)) {
    const file = path.join(dir, `${table}.parquet`).replaceAll("\\", "/");
    await c.run(`copy (${select}) to '${file}' (format parquet)`);
  }
  const { query } = await import("../src/lib/exports/db.ts");
  await fn(query);
}

test("query() reports a stale fct_jurisdiction_businesses export instead of a binder error", () =>
  withExports(
    { fct_jurisdiction_businesses: "select 'x' as official_id, 'y' as donor_names" },
    async (query) => {
      await assert.rejects(
        query("select donor_links from {fct_jurisdiction_businesses}"),
        (e) =>
          /stale export: fct_jurisdiction_businesses lacks .*donor_links/.test(e.message) &&
          !/Binder/.test(e.message),
      );
    },
  ));

test("query() explains a missing column on a table REQUIRED_COLUMNS does not list", () =>
  withExports({ t_unlisted: "select 1 as a" }, async (query) => {
    await assert.rejects(
      query("select a, newer from {t_unlisted}"),
      (e) =>
        /stale export: t_unlisted lacks newer/.test(e.message) &&
        /Re-export/.test(e.message) &&
        !/Binder/.test(e.message),
    );
  }));

test("query() runs against a current export", () =>
  withExports({ t_current: "select 1 as a, 2 as newer" }, async (query) => {
    assert.deepEqual(await query("select a, newer from {t_current}"), [{ a: 1, newer: 2 }]);
  }));

test("query() rethrows a genuine SQL error on a current export unchanged", () =>
  withExports({ t_current2: "select 1 as a" }, async (query) => {
    await assert.rejects(
      query("select a, count(*) from {t_current2}"),
      (e) => /Binder Error/.test(e.message) && !/stale export/.test(e.message),
    );
  }));
