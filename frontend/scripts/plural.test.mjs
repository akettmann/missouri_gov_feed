import assert from "node:assert/strict";
import { test } from "node:test";
import { contributionsText, sitesDescription, sitesText } from "../src/lib/businessCounts.ts";
import { filterStatusText } from "../src/lib/compareFilter.ts";
import { plural } from "../src/lib/format.ts";
import { breaksText, peerStripLead } from "../src/lib/indicators.ts";
import { metricText } from "../src/lib/awardBadges.ts";
import {
  coverageText,
  excludedDocketsText,
  federalDocketsText,
  measuredTypedDocketsText,
} from "../src/lib/timeToDisposition.ts";

test("plural uses the singular for exactly 1", () => {
  assert.equal(plural(1, "case", "cases"), "1 case");
  assert.equal(plural(0, "case", "cases"), "0 cases");
  assert.equal(plural(2, "case", "cases"), "2 cases");
  assert.equal(plural(1234, "case", "cases"), "1,234 cases");
});

test("peer strip lead", () => {
  const lead = (n, chamber, indicator, period) => peerStripLead(n, chamber, indicator, period);
  // federal DW-NOMINATE: a Congress number, ordinal, counted as current Missouri members
  assert.equal(
    lead(2, "us_senate", "dw_nominate_dim1", 119),
    "Among 2 current Missouri U.S. senators with a score in the 119th Congress:",
  );
  assert.equal(
    lead(1, "us_senate", "dw_nominate_dim1", 112),
    "Among 1 current Missouri U.S. senator with a score in the 112th Congress:",
  );
  assert.equal(
    lead(8, "us_house", "dw_nominate_dim1", 111),
    "Among 8 current Missouri U.S. House members with a score in the 111th Congress:",
  );
  assert.equal(
    lead(4, "us_house", "dw_nominate_dim1", 121),
    "Among 4 current Missouri U.S. House members with a score in the 121st Congress:",
  );
  assert.equal(
    lead(4, "us_house", "dw_nominate_dim1", 122),
    "Among 4 current Missouri U.S. House members with a score in the 122nd Congress:",
  );
  assert.equal(
    lead(1, "us_house", "dw_nominate_dim1", 113),
    "Among 1 current Missouri U.S. House member with a score in the 113th Congress:",
  );
  assert.equal(
    lead(2, "us_house", "dw_nominate_dim1", null),
    "Among 2 current Missouri U.S. House members with a score:",
  );
  // federal party unity: the sitting delegation, by chamber voted in
  assert.equal(
    lead(8, "us_house", "party_unity_pct", null),
    "Among 8 current Missouri U.S. House members who cast party-line votes in the U.S. House:",
  );
  // state groups are current officials of any office, named by the chamber of the measurement, never the office
  assert.equal(
    lead(178, "state_house", "party_unity_pct", null),
    "Among 178 current officials who cast party-line votes in the Missouri House:",
  );
  assert.equal(
    lead(35, "state_senate", "party_unity_pct", null),
    "Among 35 current officials who cast party-line votes in the Missouri Senate:",
  );
  assert.equal(
    lead(80, "state_house", "shor_mccarty_np", 2018),
    "Among 80 current officials whose Shor-McCarty career score was last measured in the Missouri House:",
  );
  assert.equal(
    lead(1, "state_senate", "shor_mccarty_np", 2022),
    "Among 1 current official whose Shor-McCarty career score was last measured in the Missouri Senate:",
  );
});

test("award badge sample sizes", () => {
  assert.equal(metricText("highest_attendance", 100, 1), "100.0% of 1 vote");
  assert.equal(metricText("highest_attendance", 99.5, 2), "99.5% of 2 votes");
  assert.equal(metricText("highest_attendance", 99.5, 1203), "99.5% of 1,203 votes");
  assert.equal(metricText("most_party_loyal", 90, 1), "90.0% with party, of 1 party-line vote");
  assert.equal(metricText("most_party_loyal", 90, 20), "90.0% with party, of 20 party-line votes");
  assert.equal(metricText("most_bills_passed_house", 50, 1), "50.0% of 1 decided bill");
  assert.equal(metricText("most_bills_passed_house", 30.4, 23), "30.4% of 23 decided bills");
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
  assert.equal(measuredTypedDocketsText(1, "civil"), "1 civil docket");
  assert.equal(measuredTypedDocketsText(2, "civil"), "2 civil dockets");
  assert.equal(
    excludedDocketsText(1),
    "1 docket that ends before it was filed (a source error) is left out.",
  );
  assert.equal(
    excludedDocketsText(2),
    "2 dockets that end before they were filed (a source error) are left out.",
  );
  assert.equal(federalDocketsText(1, "civil"), "1 federal civil docket");
  assert.equal(federalDocketsText(2, "criminal"), "2 federal criminal dockets");
  assert.equal(coverageText(0, 1, "civil"), "0 of 1 assigned civil docket measured");
  assert.equal(coverageText(1, 2, "criminal"), "1 of 2 assigned criminal dockets measured");
});
