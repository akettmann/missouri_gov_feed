import assert from "node:assert/strict";
import { test } from "node:test";
import { DuckDBInstance } from "@duckdb/node-api";
import { trailDonorNamesSql, trailRowsSql } from "../src/lib/exports/trailQuery.ts";

// Both tables carry donor_mec_committee_id, the shape that made an unqualified reference bind to the wrong table.
async function run(sql) {
  const conn = await (await DuckDBInstance.create(":memory:")).connect();
  await conn.run(`create table rollup (official_id varchar, donor_mec_committee_id varchar, donor_name varchar,
    total_amount double, transaction_year integer, donor_link_confidence varchar)`);
  await conn.run(`create table donors (mec_committee_id varchar, donor_mec_committee_id varchar)`);
  // official A: committees C1..C6 by amount; C1 has no donor list, so the top 2 shown must be C2, C3.
  await conn.run(`insert into rollup values
    ('A','C1','One',600,2020,'high'), ('A','C2','Two',500,2020,'high'), ('A','C3','Three',400,2021,'medium')`);
  await conn.run(`insert into donors values ('C2', null), ('C3', 'C1')`);
  return (await conn.runAndReadAll(sql)).getRowObjectsJson();
}

test("trail ranking skips committees without a donor list, even when donors has its own donor_mec_committee_id", async () => {
  const rows = await run(trailRowsSql(2, "rollup", "donors"));
  assert.deepEqual(
    rows.map((r) => r.mec_committee_id),
    ["C2", "C3"],
  );
});

test("the exists filter is qualified against the rollup alias", () => {
  assert.match(trailRowsSql(5, "r", "d"), /cd\.mec_committee_id = dr\.donor_mec_committee_id/);
});

test("donor names come back one row per name, only for the shown committees, with ';' inside a name intact", async () => {
  const conn = await (await DuckDBInstance.create(":memory:")).connect();
  await conn.run(`create table rollup (official_id varchar, donor_mec_committee_id varchar, donor_name varchar,
    total_amount double, transaction_year integer, donor_link_confidence varchar)`);
  await conn.run(`create table donors (mec_committee_id varchar, donor_mec_committee_id varchar)`);
  await conn.run(`insert into rollup values
    ('A','C2','Zed PAC',500,2020,'high'), ('A','C2','Alpha; Inc',100,2021,'high'), ('A','C2','Alpha; Inc',50,2022,'high'),
    ('A','C3','Three',10,2020,'high')`);
  await conn.run(`insert into donors values ('C2', null), ('C3', null)`);
  const rows = (await conn.runAndReadAll(trailDonorNamesSql(1, "rollup", "donors"))).getRowObjectsJson();
  assert.deepEqual(rows, [
    { official_id: "A", mec_committee_id: "C2", donor_name: "Alpha; Inc" },
    { official_id: "A", mec_committee_id: "C2", donor_name: "Zed PAC" },
  ]);
});
