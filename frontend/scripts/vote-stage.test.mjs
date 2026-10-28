import assert from "node:assert/strict";
import { test } from "node:test";
import { stageLabel } from "../src/lib/voteStage.ts";

test("a Missouri roll call shows its stage in words", () => {
  assert.equal(stageLabel("state_house", "perfection", false), "Perfection");
  assert.equal(stageLabel("state_senate", "third_reading", false), "Third reading");
  assert.equal(stageLabel("state_house", "procedural_motion", false), "Procedural motion");
  assert.equal(stageLabel("state_house", "quorum", null), "Quorum call");
});

test("consent-calendar and informal-calendar votes are labeled as such", () => {
  assert.equal(stageLabel("state_house", "third_reading_consent", false), "Consent calendar, third reading");
  assert.equal(stageLabel("state_house", "third_reading", true), "Third reading (informal calendar)");
  assert.equal(
    stageLabel("state_house", "third_reading_consent", true),
    "Consent calendar, third reading (informal calendar)",
  );
});

test("an unmatched, missing or unrecognised Missouri stage says it is not identified, never a guess", () => {
  assert.equal(stageLabel("state_senate", "unknown", false), "Stage not identified");
  assert.equal(stageLabel("state_house", null, null), "Stage not identified");
  assert.equal(stageLabel("state_house", "some_new_stage", false), "Stage not identified");
});

test("a federal vote gets no stage label", () => {
  assert.equal(stageLabel("us_house", null, null), null);
  assert.equal(stageLabel("us_senate", "third_reading", false), null);
});

test("the stage join matches a Senate overlap row whose session is the bill session, not the year", async () => {
  const { DuckDBInstance } = await import("@duckdb/node-api");
  const { withVoteStages } = await import("../src/lib/exports/voteStageQuery.ts");
  const conn = await (await DuckDBInstance.create(":memory:")).connect();
  await conn.run(`create table fv (chamber varchar, session_code varchar, vote_id varchar, vote_stage varchar,
    vote_informal boolean, official_id varchar)`);
  await conn.run(`insert into fv values ('state_senate','2022','v1','third_reading',false,'a'),
    ('state_senate','2022','v1','third_reading',false,'b'),
    ('state_senate','2023','v1','third_reading',false,'c')`);
  await conn.run(`create table ov (chamber varchar, session_code varchar, vote_id varchar)`);
  await conn.run(`insert into ov values ('state_senate','221','v1')`);
  const joined = withVoteStages("ov").replace("{fct_votes}", "fv");
  const rows = (await conn.runAndReadAll(`select vote_id, vote_stage from ${joined}`)).getRowObjectsJson();
  assert.deepEqual(rows, [{ vote_id: "v1", vote_stage: "third_reading" }]);
});
