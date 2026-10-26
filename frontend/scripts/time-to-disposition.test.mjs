import assert from "node:assert/strict";
import { test } from "node:test";
import {
  LOW_COVERAGE_SHARE,
  MIN_MEASURED,
  daysLabel,
  timeToDispositionView,
} from "../src/lib/timeToDisposition.ts";

const row = (extra = {}) => ({
  dockets_assigned: 7796,
  dockets_measured: 7793,
  dockets_ends_before_filed: 3,
  share_with_both_dates: 1,
  median_days_to_disposition: 238,
  ...extra,
});

test("a long-serving judge gets the median with its n", () => {
  assert.deepEqual(timeToDispositionView(row()), {
    median: 238,
    measured: 7793,
    assigned: 7796,
    coveragePct: 99.9,
    lowCoverage: false,
    excluded: 3,
  });
});

test("the minimum sample is inclusive: MIN_MEASURED dockets show a median, one fewer does not", () => {
  assert.equal(MIN_MEASURED, 30);
  assert.equal(timeToDispositionView(row({ dockets_measured: 30 })).median, 238);
  const thin = timeToDispositionView(row({ dockets_measured: 29 }));
  assert.equal(thin.median, null);
  assert.equal(thin.measured, 29);
});

test("no median in the export means none is shown, even with enough dockets", () => {
  assert.equal(timeToDispositionView(row({ median_days_to_disposition: null })).median, null);
});

test("a zero-day median is a real number, not a missing one", () => {
  assert.equal(timeToDispositionView(row({ median_days_to_disposition: 0 })).median, 0);
});

test("low coverage is measured / assigned, flagged below the threshold only", () => {
  assert.equal(LOW_COVERAGE_SHARE, 0.8);
  const edge = timeToDispositionView(row({ dockets_assigned: 100, dockets_measured: 80 }));
  assert.equal(edge.lowCoverage, false);
  assert.equal(edge.coveragePct, 80);
  const v = timeToDispositionView(row({ dockets_assigned: 1000, dockets_measured: 465 }));
  assert.equal(v.lowCoverage, true);
  assert.equal(v.coveragePct, 46.5);
});

test("the percent follows the counts, not the mart's share (which includes ends-before-filed)", () => {
  const v = timeToDispositionView(
    row({
      dockets_assigned: 1000,
      dockets_measured: 790,
      dockets_ends_before_filed: 10,
      share_with_both_dates: 0.8,
    }),
  );
  assert.equal(v.coveragePct, 79);
  assert.equal(v.lowCoverage, true);
});

test("no assigned dockets: no division by zero", () => {
  const v = timeToDispositionView(row({ dockets_assigned: 0, dockets_measured: 0 }));
  assert.equal(v.coveragePct, 0);
  assert.equal(v.lowCoverage, false);
});

test("daysLabel: singular, plural, half days", () => {
  assert.equal(daysLabel(1), "1 day");
  assert.equal(daysLabel(238), "238 days");
  assert.equal(daysLabel(276.5), "276.5 days");
  assert.equal(daysLabel(0), "0 days");
  assert.equal(daysLabel(2), "2 days");
  assert.equal(daysLabel(1234), "1,234 days");
  assert.equal(daysLabel(1234.5), "1,234.5 days");
});
