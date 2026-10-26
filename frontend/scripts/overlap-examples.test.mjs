import assert from "node:assert/strict";
import { test } from "node:test";
import { DuckDBInstance } from "@duckdb/node-api";
import { overlapExamplesSql } from "../src/lib/exports/overlapQuery.ts";

// Fixed rows shaped like SB724 on 2022-05-10: an amendment first (lowest id), passage in the middle, a later
// emergency-clause vote, and Senate ids where plain string order puts vote10 before vote2.
async function run(rows, examples = 5) {
  const conn = await (await DuckDBInstance.create(":memory:")).connect();
  await conn.run(`create table ov (official_id varchar, industry varchar, chamber varchar, vote_id varchar,
    session_code varchar, vote_date date, bill varchar, short_title varchar, vote_cast varchar, vote_description varchar,
    vote_source_url varchar, bill_source_url varchar)`);
  for (const [vote_id, date, bill, desc, chamber = "state_senate", session = "S1"] of rows) {
    await conn.run(`insert into ov values ('A','Gas',?,?,?,?,?,'t','yea',?,?,'b')`, [
      chamber,
      vote_id,
      session,
      date,
      bill,
      desc,
      vote_id,
    ]);
  }
  const sql = overlapExamplesSql(examples, "ov");
  return (await conn.runAndReadAll(sql)).getRowObjectsJson();
}
const J = "https://x/RDay1.pdf#vote";
const PASS = "On motion of Senator B, SB 724 was read the 3rd time and passed by the following vote:";
const AMEND = "Senator B moved that SA 2 to SB 724 be adopted, which motion prevailed by the following vote:";
const EMERG = "The emergency clause was adopted by the following vote:";

test("passage beats an earlier amendment and a later emergency-clause vote on the same day", async () => {
  const rows = await run([
    [`${J}0`, "2022-05-10", "SB724", AMEND],
    [`${J}1`, "2022-05-10", "SB724", PASS],
    [`${J}2`, "2022-05-10", "SB724", EMERG],
  ]);
  assert.deepEqual(
    rows.map((r) => r.vote_source_url),
    [`${J}1`],
  );
});

test("an amendment is shown only when nothing else was voted that day, and the last one wins", async () => {
  const rows = await run([
    [`${J}2`, "2022-05-10", "SB724", AMEND],
    [`${J}10`, "2022-05-10", "SB724", AMEND],
  ]);
  assert.deepEqual(
    rows.map((r) => r.vote_source_url),
    [`${J}10`],
  );
});

test("without a question text (House) the day's last roll call is shown", async () => {
  const H = "https://d/rollcalls/068.0";
  const rows = await run([
    [`${H}14.pdf`, "2022-05-10", "SB724", "SBs FOR THIRD READING", "state_house"],
    [`${H}43.pdf`, "2022-05-10", "SB724", "SBs FOR THIRD READING", "state_house"],
    [`${H}20.pdf`, "2022-05-10", "SB724", null, "state_house"],
  ]);
  assert.deepEqual(
    rows.map((r) => r.vote_source_url),
    [`${H}43.pdf`],
  );
});

test("one example per bill; a later day beats a better vote on an earlier day; newest bills first", async () => {
  const rows = await run([
    [`${J}0`, "2022-05-09", "SB1", PASS],
    [`${J}0`, "2022-05-10", "SB1", AMEND],
    [`${J}0`, "2022-05-10", "SB2", PASS],
    [`${J}1`, "2022-05-10", "SB2", AMEND],
  ]);
  assert.deepEqual(
    rows.map((r) => [r.bill, r.vote_date]),
    [
      ["SB1", "2022-05-10"],
      ["SB2", "2022-05-10"],
    ],
  );
  assert.equal(rows[1].vote_source_url, `${J}0`);
});

test("the cap applies to bills, not roll calls", async () => {
  const many = [];
  for (let i = 0; i < 8; i++) many.push([`${J}${i}`, "2022-05-10", "SB900", PASS]);
  many.push([`${J}0`, "2022-05-09", "SB5", PASS]);
  const rows = await run(many, 2);
  assert.deepEqual(
    rows.map((r) => r.bill),
    ["SB900", "SB5"],
  );
});

test("a non-amendment, non-passage vote beats a later amendment", async () => {
  const rows = await run([
    [`${J}0`, "2022-05-10", "SB724", EMERG],
    [`${J}1`, "2022-05-10", "SB724", AMEND],
    [`${J}2`, "2022-05-10", "SB724", "Senator B moved that HA 1 to SB 724 be adopted, which motion failed:"],
    [`${J}3`, "2022-05-10", "SB724", "SSA 1 to SB 724 failed of adoption by the following vote:"],
  ]);
  assert.deepEqual(
    rows.map((r) => r.vote_source_url),
    [`${J}0`],
  );
});

test("a motion to reconsider passage is not passage, even though it says 'finally passed'", async () => {
  const rows = await run([
    [`${J}4`, "2020-05-14", "SB782", PASS],
    [
      `${J}7`,
      "2020-05-14",
      "SB782",
      "Senator B moved that the vote by which SB 782 finally passed be reconsidered:",
    ],
  ]);
  assert.deepEqual(
    rows.map((r) => r.vote_source_url),
    [`${J}4`],
  );
});

test("the same bill number in two sessions is two examples", async () => {
  const rows = await run([
    [`${J}0`, "2018-05-10", "SB782", PASS, "state_senate", "181"],
    [`${J}1`, "2020-05-10", "SB782", PASS, "state_senate", "201"],
  ]);
  assert.deepEqual(
    rows.map((r) => r.vote_date),
    ["2020-05-10", "2018-05-10"],
  );
});
