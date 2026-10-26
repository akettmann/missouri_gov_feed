import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionLabel } from "../src/lib/format.ts";

test("House: the House's name for every session shape, however irregular the code", () => {
  // 183 is the 2018 "Special Session" and 184 its "1st Extraordinary Session": no last-digit rule gives this
  assert.equal(sessionLabel("state_house", "183", "2018 Special Session"), "2018 Special Session");
  assert.equal(
    sessionLabel("state_house", "184", "2018 1st Extraordinary Session"),
    "2018 1st Extraordinary Session",
  );
  assert.equal(
    sessionLabel("state_house", "253", "2025 1st Extraordinary Session"),
    "2025 1st Extraordinary Session",
  );
});

test("House: an unnamed session shows its code, not a guess", () => {
  assert.equal(sessionLabel("state_house", "183", null), "session code 183");
  assert.equal(sessionLabel("state_house", "253"), "session code 253");
});

test("Senate shows its year and Congress its number, whatever name is passed", () => {
  assert.equal(sessionLabel("state_senate", "2025"), "2025");
  assert.equal(sessionLabel("us_house", "119"), "119th Congress");
  assert.equal(sessionLabel("us_senate", "119", "ignored"), "119th Congress");
});
