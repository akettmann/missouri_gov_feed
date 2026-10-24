import assert from "node:assert/strict";
import { test } from "node:test";
import { businessCounts } from "../src/lib/businessCounts.ts";

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
  contributions_url: null,
  sites: Array.from({ length: nSites }, () => site),
});
const industries = [
  { sector_code: "31", sector_name: "Mfg", n_sites: 10, n_donor_sites: 3 },
  { sector_code: null, sector_name: "No industry code", n_sites: 5, n_donor_sites: 0 },
];
// load.ts groups sites by the "; "-joined set of contributors matched to one site, so a site that
// matches two companies yields a combined group alongside each company's own group.
const biz = {
  donors: [
    donor("AMEREN CORPORATION; AT&T INC.", "high", 1),
    donor("AMEREN CORPORATION", "high", 2),
    donor("AT&T INC.", "high", 1),
    donor("ACME CO", "medium", 1),
  ],
  industries,
};

test("businessCounts sums sites and counts distinct companies, not donor groups", () => {
  assert.deepEqual(businessCounts(biz, false), { totalSites: 15, donorCompanies: 3, donorSites: 5 });
});

test("businessCounts drops possible-match donors when hidden but keeps the site total", () => {
  assert.deepEqual(businessCounts(biz, true), { totalSites: 15, donorCompanies: 2, donorSites: 4 });
});

test("businessCounts only counts companies from groups that survive the possible-match filter", () => {
  const only = {
    donors: [
      donor("ACME CO; BETA LLC", "medium", 1),
      donor("ACME CO", "high", 1),
      donor("BETA LLC", "medium", 1),
    ],
    industries,
  };
  assert.equal(businessCounts(only, false).donorCompanies, 2);
  assert.equal(businessCounts(only, true).donorCompanies, 1);
});

test("businessCounts is null when not applicable or missing", () => {
  assert.equal(businessCounts(null, false), null);
  assert.equal(businessCounts({ donors: [], industries: [] }, false), null);
});
