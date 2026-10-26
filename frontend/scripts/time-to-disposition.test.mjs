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
    coveragePct: 100,
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

test("low date coverage flags below the threshold only", () => {
  assert.equal(LOW_COVERAGE_SHARE, 0.8);
  assert.equal(timeToDispositionView(row({ share_with_both_dates: 0.8 })).lowCoverage, false);
  const v = timeToDispositionView(row({ share_with_both_dates: 0.4653 }));
  assert.equal(v.lowCoverage, true);
  assert.equal(v.coveragePct, 47);
});

test("daysLabel: singular, plural, half days", () => {
  assert.equal(daysLabel(1), "1 day");
  assert.equal(daysLabel(238), "238 days");
  assert.equal(daysLabel(276.5), "276.5 days");
  assert.equal(daysLabel(0), "0 days");
});
