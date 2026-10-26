import assert from "node:assert/strict";
import { test } from "node:test";
import { contributionsText, sitesDescription, sitesText } from "../src/lib/businessCounts.ts";
import { filterStatusText } from "../src/lib/compareFilter.ts";
import { plural } from "../src/lib/format.ts";
import { breaksText } from "../src/lib/indicators.ts";
import { excludedDocketsText, measuredDocketsText } from "../src/lib/timeToDisposition.ts";

test("plural uses the singular for exactly 1", () => {
  assert.equal(plural(1, "case", "cases"), "1 case");
  assert.equal(plural(0, "case", "cases"), "0 cases");
  assert.equal(plural(2, "case", "cases"), "2 cases");
  assert.equal(plural(1234, "case", "cases"), "1,234 cases");
});

test("voting breaks sentence", () => {
  assert.match(breaksText(1), /^1 recorded vote against /);
  assert.match(breaksText(2), /^2 recorded votes against /);
  assert.match(breaksText(0), /^No recorded votes/);
});

test("compare filter status line", () => {
  assert.equal(filterStatusText(1, true, "Legislature"), "Showing 1 official: Legislature.");
  assert.equal(filterStatusText(2, true, "Legislature"), "Showing 2 officials: Legislature.");
  assert.equal(filterStatusText(1, false, ""), "Showing the 1 official.");
  assert.equal(filterStatusText(2, false, ""), "Showing all 2 officials.");
});

test("district sites strings", () => {
  assert.equal(sitesText(1), "1 site");
  assert.equal(sitesText(2), "2 sites");
  assert.equal(sitesDescription(1, "MO-1"), "All 1 EPA-regulated site in the area of MO-1.");
  assert.equal(sitesDescription(2, "MO-1"), "All 2 EPA-regulated sites in the area of MO-1.");
});

test("business contributions", () => {
  assert.equal(contributionsText(1), "1 contribution");
  assert.equal(contributionsText(2), "2 contributions");
});

test("court docket strings", () => {
  assert.equal(measuredDocketsText(1), "1 docket");
  assert.equal(measuredDocketsText(2), "2 dockets");
  assert.match(excludedDocketsText(1), /^1 docket that end.* is left out\.$/);
  assert.match(excludedDocketsText(2), /^2 dockets that end.* are left out\.$/);
});
