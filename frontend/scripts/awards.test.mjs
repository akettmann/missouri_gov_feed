import assert from "node:assert/strict";
import { test } from "node:test";
import { streakMarker } from "../src/lib/format.ts";

test("streakMarker shows X<n> with a spoken label from 2 years", () => {
  assert.deepEqual(streakMarker(3), { text: "X3", label: "3 years in a row" });
  assert.deepEqual(streakMarker(2), { text: "X2", label: "2 years in a row" });
});

test("streakMarker is absent for a single year, lifetime rows (null) and missing values", () => {
  assert.equal(streakMarker(1), null);
  assert.equal(streakMarker(null), null);
  assert.equal(streakMarker(undefined), null);
});
