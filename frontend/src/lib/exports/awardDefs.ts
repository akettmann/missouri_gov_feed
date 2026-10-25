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
  { name: string; title: string; unit: "pct" | "money"; outOf?: "votes" | "raised" }
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
  },
  most_party_loyal: {
    name: "The “Team Player” Award",
    title: "Votes with their party most often",
    unit: "pct",
  },
};
