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
