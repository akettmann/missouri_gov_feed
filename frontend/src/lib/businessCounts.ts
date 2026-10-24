// Counts for the compare page's businesses-in-their-area rows, from the per-official `businesses` block.
// Pure and import-free so node:test can load it.
import type { DistrictDonor, DistrictIndustry } from "./exports/types";

export interface BusinessCounts {
  /** every EPA-regulated site in the official's district or city */
  totalSites: number;
  /** donor companies (as matched rows) that gave to the official and have sites there */
  donorCompanies: number;
  /** sites tied to those donors */
  donorSites: number;
}

/** null when the official has no area businesses (statewide office, judge, or the export is missing). */
export function businessCounts(
  businesses: { donors: DistrictDonor[]; industries: DistrictIndustry[] } | null,
  hideMedium: boolean,
): BusinessCounts | null {
  if (!businesses || businesses.industries.length === 0) return null;
  const donors = hideMedium
    ? businesses.donors.filter((d) => d.match_confidence !== "medium")
    : businesses.donors;
  return {
    totalSites: businesses.industries.reduce((n, i) => n + i.n_sites, 0),
    donorCompanies: donors.length,
    donorSites: donors.reduce((n, d) => n + d.sites.length, 0),
  };
}
