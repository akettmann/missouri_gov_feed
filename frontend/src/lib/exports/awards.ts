// rpt_awards for the awards page: each award ranks one measured number within one office, paired with its
// opposite. The ranking itself is done in dbt; this only attaches names and links.
import { hasExport, query } from "./db";
import { allOfficials } from "./load";

export interface AwardEntry {
  rank: number;
  slug: string;
  name: string;
  party: string | null;
  metric: number;
  sample_size: number | null;
}
export interface AwardList {
  award: string;
  office: string;
  period: string;
  group_size: number;
  entries: AwardEntry[];
}

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

let cache: Promise<AwardList[] | null> | undefined;

/** null when the rpt_awards export is missing. */
export function awardLists(): Promise<AwardList[] | null> {
  cache ??= load();
  return cache;
}

async function load(): Promise<AwardList[] | null> {
  if (!hasExport("rpt_awards")) return null;
  const officials = new Map((await allOfficials()).map((b) => [b.official.official_id, b.official]));
  const rows = await query<{
    award: string;
    office: string;
    period: string;
    award_rank: number;
    official_id: string;
    metric: number;
    sample_size: number | null;
    group_size: number;
  }>(`
    select award, office, period, cast(award_rank as integer) as award_rank, official_id,
           cast(metric as double) as metric, cast(sample_size as double) as sample_size,
           cast(group_size as integer) as group_size
    from {rpt_awards} order by award, office, period, award_rank`);
  const lists = new Map<string, AwardList>();
  for (const r of rows) {
    const o = officials.get(r.official_id);
    if (!o) continue;
    const key = `${r.award}|${r.office}|${r.period}`;
    const list = lists.get(key) ?? {
      award: r.award,
      office: r.office,
      period: r.period,
      group_size: r.group_size,
      entries: [],
    };
    list.entries.push({
      rank: r.award_rank,
      slug: o.slug,
      name: o.full_name,
      party: o.party,
      metric: r.metric,
      sample_size: r.sample_size,
    });
    lists.set(key, list);
  }
  return [...lists.values()];
}
