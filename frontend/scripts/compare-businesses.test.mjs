import assert from "node:assert/strict";
import { test } from "node:test";
import { businessCounts, donorsText } from "../src/lib/businessCounts.ts";

const site = {
  facility_name: "S",
  city: "X",
  naics_description: null,
  matched_by: "same name",
  frs_url: null,
};
const donor = (donor_names, match_confidence, nSites) => ({
  donor_names,
  donated_amount: 100,
  n_contributions: 1,
  first_year: 2020,
  last_year: 2020,
  match_confidence,
  donor_links: null,
  sites: Array.from({ length: nSites }, () => site),
});
const industries = [
  { sector_code: "31", sector_name: "Mfg", n_sites: 10, n_donor_sites: 3 },
  { sector_code: null, sector_name: "No industry code", n_sites: 5, n_donor_sites: 0 },
];
const counts = (groups, hide = false) => businessCounts({ donors: groups, industries }, hide);

// load.ts groups sites by the "; "-joined set of contributor names matched to one site, so a site that
// matches two donors yields a combined group alongside each donor's own group.
const biz = {
  donors: [
    donor("AMEREN CORPORATION; AT&T INC.", "high", 1),
    donor("AMEREN CORPORATION", "high", 2),
    donor("AT&T INC.", "high", 1),
    donor("ACME CO", "medium", 1),
  ],
  industries,
};

test("businessCounts sums sites and counts donors, not donor groups", () => {
  assert.deepEqual(businessCounts(biz, false), {
    totalSites: 15,
    donors: 3,
    donorSites: 5,
    allHidden: false,
  });
});

test("businessCounts drops possible-match donors when hidden but keeps the site total", () => {
  assert.deepEqual(businessCounts(biz, true), {
    totalSites: 15,
    donors: 2,
    donorSites: 4,
    allHidden: false,
  });
});

test("one donor's brand variants in a single group count once", () => {
  assert.equal(counts([donor("SPIRE PAC; SPIRE POLITICAL ACTION COMMITTEE", "high", 1)]).donors, 1);
  assert.equal(
    counts([
      donor("AMEREN MO PAC; AMEREN MISSOURI PAC", "high", 3),
      donor("SPIRE PAC; SPIRE POLITICAL ACTION COMMITTEE", "high", 1),
    ]).donors,
    2,
  );
});

test("a combined group beside its separate groups is not a third donor", () => {
  const groups = [
    donor("AMEREN CORPORATION; AT&T INC.", "high", 1),
    donor("AMEREN CORPORATION", "high", 1),
    donor("AT&T INC.", "high", 1),
  ];
  assert.equal(counts(groups).donors, 2);
});

test("a name covered only by a non-minimal group still counts", () => {
  assert.equal(counts([donor("ACME CO; BETA LLC", "high", 1), donor("ACME CO", "high", 1)]).donors, 2);
});

test("identical name sets and whitespace differences collapse to one group", () => {
  assert.equal(
    counts([donor("A CO; B CO", "high", 1), donor("B CO;  A  CO", "high", 1), donor("", "high", 1)]).donors,
    1,
  );
});

test("the toggle removes the only group naming a donor", () => {
  const groups = [
    donor("ACME CO; BETA LLC", "medium", 1),
    donor("ACME CO", "high", 1),
    donor("BETA LLC", "medium", 1),
  ];
  assert.equal(counts(groups, false).donors, 2);
  assert.equal(counts(groups, true).donors, 1);
});

test("allHidden is set only when the toggle hides every group", () => {
  const groups = [donor("ACME CO", "medium", 1)];
  assert.equal(counts(groups, true).allHidden, true);
  assert.equal(counts(groups, true).donors, 0);
  assert.equal(counts(groups, false).allHidden, false);
  assert.equal(counts([], true).allHidden, false);
});

test("donors cell says none (possible matches hidden) when every donor is a possible match", () => {
  const b = { donors: [donor("ACME CO", "medium", 1)], industries };
  assert.equal(donorsText(businessCounts(b, true)), "none (possible matches hidden)");
  assert.equal(donorsText(businessCounts(b, false)), "1 donor (1 site)");
});

test("businessCounts is null when not applicable or missing", () => {
  assert.equal(businessCounts(null, false), null);
  assert.equal(businessCounts({ donors: [], industries: [] }, false), null);
});
