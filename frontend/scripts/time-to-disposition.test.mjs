import assert from "node:assert/strict";
import { test } from "node:test";
import {
  LOW_COVERAGE_SHARE,
  CASE_TYPES,
  EXCLUDED_TYPES_TEXT,
  caseTypeHeading,
  coverageText,
  hiddenMedianText,
  noDocketsText,
  federalDocketsText,
  measuredTypedDocketsText,
  MIN_MEASURED,
  daysLabel,
  timeToDispositionView,
  caseTypeBlocks,
  districtText,
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

test("every label names the case type the number counts", () => {
  assert.equal(caseTypeHeading("civil"), "Median time to disposition: civil cases");
  assert.equal(caseTypeHeading("criminal"), "Median time to disposition: criminal cases");
  assert.equal(federalDocketsText(1, "criminal"), "1 federal criminal docket");
  assert.equal(federalDocketsText(2093, "civil"), "2,093 federal civil dockets");
  assert.equal(measuredTypedDocketsText(12, "criminal"), "12 criminal dockets");
  assert.equal(coverageText(146, 256, "criminal"), "146 of 256 assigned criminal dockets measured");
  assert.equal(coverageText(1, 1, "civil"), "1 of 1 assigned civil docket measured");
});

test("a hidden median says what was counted: measured dockets, the minimum, and what measured means", () => {
  const t = hiddenMedianText(12, "criminal");
  assert.match(
    t,
    /^Not shown: only 12 criminal dockets were measured, and the page needs at least 30 for a median\./,
  );
  assert.match(t, /both its filing date and its termination date/);
  assert.match(t, /did not end before it was filed/);
  assert.match(hiddenMedianText(1, "civil"), /only 1 civil docket was measured/);
  // it never promises a median or a method for a number that is not shown
  assert.doesNotMatch(t, /median days|may understate/i);
});

test("a judge with only civil dockets is told there are no criminal ones; one with both is told nothing", () => {
  assert.deepEqual(CASE_TYPES, ["civil", "criminal"]);
  assert.equal(
    noDocketsText("criminal"),
    "CourtListener's Missouri federal district dockets list no criminal dockets for this judge. CourtListener holds few criminal dockets, so this does not mean the judge had no criminal cases.",
  );
  assert.equal(
    noDocketsText("civil"),
    "CourtListener's Missouri federal district dockets list no civil dockets for this judge.",
  );
});

test("the note on what is in neither median names miscellaneous and other dockets", () => {
  assert.match(EXCLUDED_TYPES_TEXT, /Miscellaneous dockets \(warrants, subpoenas, complaints\)/);
  assert.match(EXCLUDED_TYPES_TEXT, /other or unclassified types/);
  assert.match(EXCLUDED_TYPES_TEXT, /in neither\.$/);
});

test("a hidden median keeps the district and the ends-before-filed count", () => {
  const t = hiddenMedianText(12, "criminal", 2, "moed");
  assert.match(t, /only 12 criminal dockets in the Eastern District of Missouri were measured/);
  assert.match(t, /2 dockets that end before they were filed \(a source error\) are left out\.$/);
  assert.doesNotMatch(hiddenMedianText(12, "criminal", 0, "mowd"), /left out/);
  assert.doesNotMatch(hiddenMedianText(12, "criminal"), /District/);
  assert.equal(districtText("moed+mowd"), "the Eastern and Western Districts of Missouri");
  assert.equal(districtText("xyz"), "xyz");
});

const full = (case_type, extra = {}) => ({ case_type, court_id: "moed", ...row(), ...extra });

test("blocks follow CASE_TYPES order whichever rows exist, with a none block for a missing type", () => {
  const onlyCriminal = caseTypeBlocks([full("criminal")]);
  assert.deepEqual(
    onlyCriminal.map((b) => [b.type, b.kind]),
    [
      ["civil", "none"],
      ["criminal", "data"],
    ],
  );
  const reversed = caseTypeBlocks([full("criminal"), full("civil")]);
  assert.deepEqual(
    reversed.map((b) => b.type),
    ["civil", "criminal"],
  );
  assert.deepEqual(caseTypeBlocks([]), []);
});

test("the median and method note show only with a median; the low-coverage note only with a median and low coverage", () => {
  const [civil] = caseTypeBlocks([full("civil")]);
  assert.equal(civil.showMedian, true);
  assert.equal(civil.showLowCoverageNote, false);
  assert.equal(civil.hiddenText, null);

  const [low] = caseTypeBlocks([full("civil", { dockets_assigned: 1000, dockets_measured: 465 })]);
  assert.equal(low.showMedian, true);
  assert.equal(low.showLowCoverageNote, true);

  // thin and low coverage: no median, so no method line and no "this median may understate" note
  const [thin] = caseTypeBlocks([
    full("civil", { dockets_assigned: 100, dockets_measured: 12, dockets_ends_before_filed: 1 }),
  ]);
  assert.equal(thin.showMedian, false);
  assert.equal(thin.showLowCoverageNote, false);
  assert.equal(thin.view.lowCoverage, true);
  assert.match(thin.hiddenText, /only 12 civil dockets in the Eastern District of Missouri were measured/);
  assert.match(thin.hiddenText, /1 docket that ends before it was filed/);

  // enough dockets but the export has no median
  const [noMedian] = caseTypeBlocks([full("civil", { median_days_to_disposition: null })]);
  assert.equal(noMedian.showMedian, false);
  assert.equal(noMedian.showLowCoverageNote, false);
  assert.equal(
    noMedian.hiddenText,
    "Not shown: 7,793 civil dockets in the Eastern District of Missouri were measured, but the data has no median for them. 3 dockets that end before they were filed (a source error) are left out.",
  );
});
