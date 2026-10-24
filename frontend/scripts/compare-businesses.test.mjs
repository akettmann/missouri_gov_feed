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
const donor = (match_confidence, nSites) => ({
  donor_names: "ACME",
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
const biz = { donors: [donor("high", 2), donor("medium", 1)], industries };

test("businessCounts sums sites and donors", () => {
  assert.deepEqual(businessCounts(biz, false), { totalSites: 15, donorCompanies: 2, donorSites: 3 });
});

test("businessCounts drops possible-match donors when hidden but keeps the site total", () => {
  assert.deepEqual(businessCounts(biz, true), { totalSites: 15, donorCompanies: 1, donorSites: 2 });
});

test("businessCounts is null when not applicable or missing", () => {
  assert.equal(businessCounts(null, false), null);
  assert.equal(businessCounts({ donors: [], industries: [] }, false), null);
});
