// Counts for the compare page's businesses-in-their-area rows, from the per-official `businesses` block.
// Pure and import-free so node:test can load it.
import type { DistrictDonor, DistrictIndustry } from "./exports/types";

export interface BusinessCounts {
  /** every EPA-regulated site in the official's district or city */
  totalSites: number;
  /**
   * distinct contributor names that gave to the official and have sites there. A combined group naming
   * two contributors counts both; a name in several groups counts once. The export has no company key,
   * so one organisation filing under several names (state PAC variants) counts once per name.
   */
  donorCompanies: number;
  /** sites tied to those donors */
  donorSites: number;
}

/** load.ts groups sites by `donor_names`, the "; "-joined set of contributors matched to one site. */
const NAME_SEPARATOR = ";";

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
    donorCompanies: distinctCompanies(donors),
    donorSites: donors.reduce((n, d) => n + d.sites.length, 0),
  };
}

function distinctCompanies(donors: DistrictDonor[]): number {
  const names = new Set<string>();
  for (const d of donors) {
    for (const part of d.donor_names.split(NAME_SEPARATOR)) {
      const name = part.replace(/\s+/g, " ").trim();
      if (name) names.add(name);
    }
  }
  return names.size;
}
