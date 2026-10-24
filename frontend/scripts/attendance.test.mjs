import assert from "node:assert/strict";
import { test } from "node:test";
import { attendedAxisMin, missedAxisMax, missedShares } from "../src/lib/attendance.ts";

const row = (extra = {}) => ({
  votes_recorded: 200,
  absent: 4,
  absent_with_leave: 6,
  not_voting: 2,
  chamber_attendance_pct: 94.5,
  ...extra,
});

test("missedShares keeps excused absence apart from absent + not voting", () => {
  assert.deepEqual(missedShares(row()), { unexcused: 3, excused: 3, chamber: 5.5 });
});

test("missedShares: shares are of votes recorded and rounded to one decimal", () => {
  const r = row({ votes_recorded: 7, absent: 1, absent_with_leave: 1, not_voting: 1 });
  const m = missedShares(r);
  assert.equal(m.unexcused, 28.6);
  assert.equal(m.excused, 14.3);
});

test("missedShares: no recorded votes gives zeros, not NaN", () => {
  const m = missedShares(row({ votes_recorded: 0, absent: 0, absent_with_leave: 0, not_voting: 0 }));
  assert.equal(m.unexcused, 0);
  assert.equal(m.excused, 0);
});

test("attendedAxisMin starts just below the data", () => {
  assert.equal(attendedAxisMin([97.1, 99.5]), 90);
  assert.equal(attendedAxisMin([71, 95]), 60);
  assert.equal(attendedAxisMin([1, 50]), 0);
});

test("missedAxisMax hugs low values and caps at 100", () => {
  assert.equal(missedAxisMax([0, 0.4]), 5);
  assert.equal(missedAxisMax([3, 5.5]), 10);
  assert.equal(missedAxisMax([12.4]), 15);
  assert.equal(missedAxisMax([99.9]), 100);
});
