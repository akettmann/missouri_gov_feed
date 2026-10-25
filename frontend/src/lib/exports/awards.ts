// rpt_awards for the awards page: each award ranks one measured number within one office, paired with its
// opposite. The ranking itself is done in dbt; this only attaches names and links.
import {
  assertKnownPeriodKinds,
  assertPeriodKindColumn,
  awardCyclesGate,
  type PeriodKind,
} from "./awardDefs";
import { hasExport, query } from "./db";
import { currentAwards, pluralOfficeLabel, type Badge } from "../awardBadges";
import { allOfficials } from "./load";

export interface AwardEntry {
  rank: number;
  slug: string;
  name: string;
  party: string | null;
  metric: number;
  sample_size: number | null;
  /** Consecutive yearly periods qualified, up to this one; null for the lifetime period. */
  streak_years: number | null;
}
export interface AwardList {
  award: string;
  office: string;
  period: string;
  /** From rpt_awards.period_kind: a calendar year, a two-year FEC cycle (even end year) or lifetime. */
  period_kind: PeriodKind;
  group_size: number;
  entries: AwardEntry[];
}

export {
  AWARD_PAIRS,
  AWARDS,
  assertCyclePeriods,
  assertKnownPeriodKinds,
  assertPeriodKindColumn,
  awardCyclesGate,
  skipAwardCyclesCheck,
  cycleLabel,
  isCycleList,
  officeHasCycles,
  periodWhen,
} from "./awardDefs";

let cache: Promise<AwardList[] | null> | undefined;

/** null when the rpt_awards export is missing. */
export function awardLists(): Promise<AwardList[] | null> {
  cache ??= load();
  return cache;
}

async function load(): Promise<AwardList[] | null> {
  if (!hasExport("rpt_awards")) return null;
  const columns = await query<{ column_name: string }>(
    "select column_name from (describe select * from {rpt_awards})",
  );
  assertPeriodKindColumn(columns.map((c) => c.column_name));
  const officials = new Map((await allOfficials()).map((b) => [b.official.official_id, b.official]));
  const rows = await query<{
    award: string;
    office: string;
    period: string;
    period_kind: PeriodKind;
    award_rank: number;
    official_id: string;
    metric: number;
    sample_size: number | null;
    group_size: number;
    streak_years: number | null;
  }>(`
    select award, office, period, period_kind, cast(award_rank as integer) as award_rank, official_id,
           cast(metric as double) as metric, cast(sample_size as double) as sample_size,
           cast(group_size as integer) as group_size, cast(streak_years as integer) as streak_years
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
      period_kind: r.period_kind,
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
      streak_years: r.streak_years,
    });
    lists.set(key, list);
  }
  const out = [...lists.values()];
  assertKnownPeriodKinds(out);
  awardCyclesGate(out, process.env, console.warn);
  return out;
}

let currentCache: Promise<Map<string, Badge[]>> | undefined;

/** slug -> the awards that official holds now (empty map when the export is missing). */
export function currentAwardsBySlug(): Promise<Map<string, Badge[]>> {
  currentCache ??= awardLists().then((lists) => currentAwards(lists ?? [], pluralOfficeLabel));
  return currentCache;
}
