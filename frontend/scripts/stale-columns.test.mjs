import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { DuckDBInstance } from "@duckdb/node-api";
import {
  REQUIRED_COLUMNS,
  assertNoMissingColumns,
  assertNoMissingTables,
  missingColumns,
  missingExportMessage,
  missingTables,
} from "../src/lib/exports/requiredColumns.ts";

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

// a one-row select holding every column REQUIRED_COLUMNS lists for a table
const fullRow = (table) => "select " + REQUIRED_COLUMNS[table].map((c) => `'x' as ${c}`).join(", ");

test("query() reports a stale fct_jurisdiction_business_donors export instead of a binder error", () =>
  withExports(
    {
      fct_jurisdiction_businesses: fullRow("fct_jurisdiction_businesses"),
      fct_jurisdiction_business_donors: "select 'x' as official_id",
    },
    async (query) => {
      await assert.rejects(
        query("select source_url from {fct_jurisdiction_business_donors}"),
        (e) =>
          /stale export: fct_jurisdiction_business_donors lacks .*source_url/.test(e.message) &&
          !/Binder/.test(e.message),
      );
    },
  ));

test("a pre-#370 export (fct_jurisdiction_businesses alone, with donor_name_list) is stale, not 'no donors'", () => {
  const present = new Set(["fct_jurisdiction_businesses"]);
  assert.deepEqual(
    missingTables(["fct_jurisdiction_businesses"], (t) => present.has(t)),
    {
      fct_jurisdiction_businesses: ["fct_jurisdiction_business_donors"],
    },
  );
  assert.throws(
    () => assertNoMissingTables(["fct_jurisdiction_businesses"], (t) => present.has(t)),
    (e) =>
      /stale export: fct_jurisdiction_businesses needs fct_jurisdiction_business_donors, which is not exported/.test(
        e.message,
      ) && e.message.includes("uv run mogov export --format parquet"),
  );
  present.add("fct_jurisdiction_business_donors");
  assert.deepEqual(
    missingTables(["fct_jurisdiction_businesses"], (t) => present.has(t)),
    {},
  );
  // a table that is not exported at all is the caller's "missing export" case, not a stale one
  assert.deepEqual(
    missingTables(["fct_jurisdiction_businesses"], () => false),
    {},
  );
});

test("query() on the business table of a pre-#370 export fails loudly, before any SQL runs", () =>
  withExports(
    {
      fct_jurisdiction_businesses: `${fullRow("fct_jurisdiction_businesses")}, 'y' as donor_name_list, 'z' as donor_links`,
    },
    async (query) => {
      // the shared directory may still hold the donor table an earlier test wrote
      rmSync(path.join(dir, "fct_jurisdiction_business_donors.parquet"), { force: true });
      await assert.rejects(query("select official_id from {fct_jurisdiction_businesses}"), (e) =>
        /stale export: fct_jurisdiction_businesses needs fct_jurisdiction_business_donors/.test(e.message),
      );
    },
  ));

test("the new donor table is required, the delimited columns are not", () => {
  assert.deepEqual(REQUIRED_COLUMNS.fct_jurisdiction_business_donors, [
    "official_id",
    "registry_id",
    "donor_name",
    "source_url",
  ]);
  assert.equal(REQUIRED_COLUMNS.fct_jurisdiction_businesses.includes("donor_links"), false);
  assert.equal(REQUIRED_COLUMNS.fct_jurisdiction_businesses.includes("donor_name_list"), false);
});

const unlistedMessage = (e) =>
  /t_unlisted has no column newer: if the column is new, the export is stale/.test(e.message) &&
  e.message.includes("uv run mogov export --format parquet") &&
  /Otherwise the query is wrong/.test(e.message) &&
  /DuckDB: Binder Error/.test(e.message) &&
  e.cause instanceof Error &&
  /Binder Error/.test(e.cause.message);

test("query() explains a missing column on a table REQUIRED_COLUMNS does not list, keeping DuckDB's message", () =>
  withExports({ t_unlisted: "select 1 as a" }, async (query) => {
    await assert.rejects(query("select a, newer from {t_unlisted}"), unlistedMessage);
  }));

test("query() explains a qualified missing column (alias.column)", () =>
  withExports({ t_unlisted: "select 1 as a" }, async (query) => {
    await assert.rejects(query("select p.newer from {t_unlisted} p"), unlistedMessage);
  }));

test("query() names a column missing from every table of a join once, not per table", () =>
  withExports({ j1: "select 1 as a", j2: "select 1 as a" }, async (query) => {
    await assert.rejects(
      query("select zz from {j1} x join {j2} y on x.a = y.a"),
      (e) => /none of j1, j2 has column zz/.test(e.message) && !/j1 lacks/.test(e.message),
    );
  }));

test("up-front check names every missing required column of a listed table, before any SQL runs", () =>
  withExports({ rpt_attendance_pay: "select 1 as other" }, async (query) => {
    await assert.rejects(
      query("select other from {rpt_attendance_pay}"),
      (e) =>
        /^stale export: rpt_attendance_pay lacks .*pay_source_url/.test(e.message) &&
        /covered_years/.test(e.message) &&
        /voting_years/.test(e.message) &&
        !/Binder|query is wrong/.test(e.message),
    );
  }));

test("a binder error naming a column the export does have is not called stale", () =>
  withExports({ t_has: "select 1 as a, 2 as b" }, async (query) => {
    // `b` exists in the export; the error is about the query (a CTE alias hides it).
    await assert.rejects(
      query("with c as (select a from {t_has}) select b from c"),
      (e) => /Binder Error/.test(e.message) && !/stale|query is wrong/.test(e.message),
    );
  }));

test("a typo in a query on a current export is not called stale", () =>
  withExports({ t_typo: "select 1 as a" }, async (query) => {
    await assert.rejects(
      query("select a, aa from {t_typo}"),
      (e) =>
        /t_typo has no column aa: if the column is new/.test(e.message) &&
        /Otherwise the query is wrong/.test(e.message),
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

test("a missing export file says to build first, then export", () => {
  const msg = missingExportMessage("/x/fct_jurisdiction_business_donors.parquet");
  assert.match(msg, /missing export \/x\/fct_jurisdiction_business_donors\.parquet/);
  assert.ok(msg.includes("uv run mogov build"));
  assert.ok(msg.includes("uv run mogov export --format parquet"));
});
