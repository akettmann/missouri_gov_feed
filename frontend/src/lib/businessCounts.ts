// Counts for the compare page's businesses-in-their-area rows, from the per-official `businesses` block.
// Pure (only imports the pure format helpers) so node:test can load it.
import type { DistrictDonor, DistrictIndustry } from "./exports/types";
import { splitDonorNames } from "./donorLinks.ts";
import { plural } from "./format.ts";

export interface BusinessCounts {
  /** every EPA-regulated site in the official's district or city */
  totalSites: number;
  /** inferred number of donors with sites there; see `countDonors` for the rule */
  donors: number;
  /** sites tied to those donors */
  donorSites: number;
  /** true when the possible-match toggle hid every donor group, so "none" would be misleading */
  allHidden: boolean;
}

/** null when the official has no area businesses (statewide office, judge, or the export is missing). */
export function businessCounts(
  businesses: { donors: DistrictDonor[]; industries: DistrictIndustry[] } | null,
  hideMedium: boolean,
): BusinessCounts | null {
  if (!businesses || businesses.industries.length === 0) return null;
  const groups = hideMedium
    ? businesses.donors.filter((d) => d.match_confidence !== "medium")
    : businesses.donors;
  return {
    totalSites: businesses.industries.reduce((n, i) => n + i.n_sites, 0),
    donors: countDonors(groups),
    donorSites: groups.reduce((n, d) => n + d.sites.length, 0),
    allHidden: groups.length === 0 && businesses.donors.length > 0,
  };
}

/**
 * Infers how many donors the surviving groups represent. The export has no organisation key, so this
 * works from the name groups. Each group is the set of contributor names (one per filing committee or
 * spelling) matched to the same sites, so:
 *  - one organisation's spellings usually arrive together in one group ("SPIRE PAC; SPIRE POLITICAL
 *    ACTION COMMITTEE"): that group is one donor, not one per name;
 *  - a site matching two organisations yields a combined group ("AMEREN CORPORATION; AT&T INC.") next to
 *    each organisation's own group: the combined group is redundant.
 * Rule: take the minimal groups (drop any group whose name set strictly contains another remaining
 * group's set, and collapse groups with identical sets) and count one donor per minimal group. A name
 * that appears only in dropped groups (e.g. {A, B} alongside only {A}) is covered by no minimal group,
 * so it counts as one more donor each; otherwise a donor whose only evidence is a combined group would
 * vanish. This can still over-count (an organisation split across disjoint groups) or under-count
 * (two organisations always matched to exactly the same sites), but it only ever sees what the export
 * carries.
 */
export function countDonors(groups: DistrictDonor[]): number {
  const sets = new Map<string, Set<string>>();
  for (const g of groups) {
    const names = new Set<string>();
    for (const part of splitDonorNames(g.donor_names)) {
      const name = part.replace(/\s+/g, " ").trim();
      if (name) names.add(name);
    }
    if (names.size) sets.set(JSON.stringify([...names].sort()), names);
  }
  const all = [...sets.values()];
  const minimal = all.filter(
    (s) => !all.some((o) => o !== s && o.size < s.size && [...o].every((n) => s.has(n))),
  );
  const covered = new Set(minimal.flatMap((s) => [...s]));
  const uncovered = new Set(all.flatMap((s) => [...s]).filter((n) => !covered.has(n)));
  return minimal.length + uncovered.size;
}

export const sitesText = (n: number) => plural(n, "site", "sites");

/** compare-table cell for the donors row */
export function donorsText(x: BusinessCounts): string {
  return x.allHidden
    ? "none (possible matches hidden)"
    : `${plural(x.donors, "donor", "donors")} (${sitesText(x.donorSites)})`;
}

/** "3 contributions" under a donor's total */
export const contributionsText = (n: number) => plural(n, "contribution", "contributions");

/** page description of a district's site list */
export const sitesDescription = (n: number, area: string) =>
  `All ${plural(n, "EPA-regulated site", "EPA-regulated sites")} in the area of ${area}.`;
