// Award keys, their names and display order. Dependency-free so browser code and tests can import it.

/** Display order and pairing: each pair is [the award, its positive opposite]. */
export const AWARD_PAIRS: [string, string][] = [
  ["lowest_attendance", "highest_attendance"],
  ["most_committee_money", "least_committee_money_share"],
  ["most_party_breaks", "most_party_loyal"],
];

/** `name` is the award's nickname (the heading); `title` says plainly what is measured, shown under it. */
export const AWARDS: Record<
  string,
  { name: string; title: string; unit: "pct" | "money"; outOf?: "votes" | "raised" | "party-line votes" }
> = {
  lowest_attendance: {
    name: "The “Where Do I Work Again?” Award",
    title: "Lowest attendance",
    unit: "pct",
    outOf: "votes",
  },
  highest_attendance: {
    name: "The “Never Misses a Vote” Award",
    title: "Highest attendance",
    unit: "pct",
    outOf: "votes",
  },
  most_committee_money: {
    name: "The “PAC Magnet” Award",
    title: "Most money from PACs, committees & parties",
    unit: "money",
    outOf: "raised",
  },
  least_committee_money_share: {
    name: "The “Grassroots Funded” Award",
    title: "Least reliant on PACs, committees & parties",
    unit: "pct",
    outOf: "raised",
  },
  most_party_breaks: {
    name: "The “Maverick” Award",
    title: "Breaks with their party most often",
    unit: "pct",
    outOf: "party-line votes",
  },
  most_party_loyal: {
    name: "The “Team Player” Award",
    title: "Votes with their party most often",
    unit: "pct",
    outOf: "party-line votes",
  },
};

/** Federal offices whose money share is ranked per FEC two-year cycle (calendar years everywhere else). */
const CYCLE_OFFICES = new Set(["us_house", "us_senate"]);

/**
 * True when a list's period is a two-year FEC cycle named by its even end year: the money-share award for
 * federal offices (rpt_awards.sql). Every other award, and every state office, ranks calendar years.
 */
export function isCycleList(award: string, office: string): boolean {
  return award === "least_committee_money_share" && CYCLE_OFFICES.has(office);
}

/** True for offices that have any cycle-based list, so their period picker needs the cycle wording. */
export function officeHasCycles(office: string): boolean {
  return CYCLE_OFFICES.has(office);
}

/** "2025–26" for the cycle ending in 2026 (an even year, the way rpt_awards names it). */
export function cycleLabel(endYear: string): string {
  const y = Number(endYear);
  return Number.isInteger(y) ? `${y - 1}–${String(y).slice(-2)}` : endYear;
}

/** "in 2025", or "in the 2025–26 cycle" for a federal money-share cycle; lifetime is "across all loaded years". */
export function periodWhen(period: string, cycle: boolean): string {
  if (period === "lifetime") return "across all loaded years";
  return cycle ? `in the ${cycleLabel(period)} cycle` : `in ${period}`;
}
