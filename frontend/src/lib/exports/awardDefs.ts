// Award keys, their names and display order. Dependency-free so browser code and tests can import it.

/** Display order only: each pair is [the award, its positive opposite]. Whether a pair shares a field is decided in dbt. */
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

/** What rpt_awards.period_kind says a list's period is. */
export type PeriodKind = "year" | "fec_cycle" | "lifetime";

const PERIOD_KINDS: readonly string[] = ["year", "fec_cycle", "lifetime"];

/**
 * True when a list's period is a two-year FEC cycle named by its even end year. rpt_awards decides this and
 * exports it as `period_kind` (the federal money share); nothing here guesses from the award or office.
 */
export function isCycleList(list: { period_kind: PeriodKind }): boolean {
  return list.period_kind === "fec_cycle";
}

/** True for offices that have any cycle-based list, so their period picker needs the cycle wording. */
export function officeHasCycles(
  lists: { office: string; period_kind: PeriodKind }[],
  office: string,
): boolean {
  return lists.some((l) => l.office === office && isCycleList(l));
}

/**
 * Checks the rpt_awards export has `period_kind` (the column list from DESCRIBE). Returns true when it does.
 * Without it the pages cannot tell a calendar year from an FEC cycle, so by default this throws (same message
 * family as the cycle check). With MOGOV_SKIP_AWARD_CYCLES_CHECK=1 it logs one warning and returns false: the
 * caller then fills the kind with legacyPeriodKind, the inference period_kind replaced.
 */
export function assertPeriodKindColumn(
  columns: string[],
  env: Record<string, string | undefined> = {},
  log: (msg: string) => void = () => {},
): boolean {
  if (columns.includes("period_kind")) return true;
  if (skipAwardCyclesCheck(env)) {
    log(
      "MOGOV_SKIP_AWARD_CYCLES_CHECK=1: the rpt_awards export is stale (no period_kind column); " +
        "inferring period_kind from award and office. Re-export to stop inferring.",
    );
    return false;
  }
  throw new Error(
    "rpt_awards export is stale: it has no period_kind column (exported before period_kind was added). " +
      "Rebuild and re-export: `uv run mogov build` then `uv run mogov export --format parquet`, " +
      "or set MOGOV_SKIP_AWARD_CYCLES_CHECK=1 (exactly 1) to build anyway, inferring the kind.",
  );
}

/** The pre-period_kind rule, used only for a stale export under the switch: federal money share is a cycle. */
export function legacyPeriodKind(award: string, office: string, period: string): PeriodKind {
  if (period === "lifetime") return "lifetime";
  return award === "least_committee_money_share" && (office === "us_house" || office === "us_senate")
    ? "fec_cycle"
    : "year";
}

/** Throws on a period_kind value other than year / fec_cycle / lifetime (or a lifetime kind on a dated period). */
export function assertKnownPeriodKinds(lists: { period: string; period_kind: string }[]): void {
  const bad = lists.filter(
    (l) =>
      !PERIOD_KINDS.includes(l.period_kind) || (l.period_kind === "lifetime") !== (l.period === "lifetime"),
  );
  if (bad.length === 0) return;
  const seen = [...new Set(bad.map((l) => `${l.period} (${l.period_kind})`))].sort().join(", ");
  throw new Error(`rpt_awards export has an unexpected period_kind for: ${seen}.`);
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

/**
 * Consistency guard: throws when a period_kind = 'fec_cycle' list has an odd period. FEC cycles are named by
 * their even end year, so an odd one means rpt_awards is inconsistent (a calendar-year row tagged as a cycle),
 * and the pages would label it "2024–25 cycle". Fails the build rather than publish wrong wording.
 */
export function assertCyclePeriods(
  lists: { period: string; period_kind: PeriodKind; office?: string }[],
): void {
  const bad = lists.filter((l) => isCycleList(l) && Number(l.period) % 2 !== 0);
  if (bad.length === 0) return;
  const seen = [...new Set(bad.map((l) => `${l.office ?? "?"} ${l.period}`))].sort().join(", ");
  throw new Error(
    `rpt_awards export is stale or inconsistent: period_kind fec_cycle has odd (non-FEC-cycle) periods (${seen}). ` +
      "Rebuild and re-export: `uv run mogov build` then `uv run mogov export --format parquet`, or set MOGOV_SKIP_AWARD_CYCLES_CHECK=1 (exactly 1) to build anyway.",
  );
}

/** MOGOV_SKIP_AWARD_CYCLES_CHECK skips the check only when it is exactly "1" (like MOGOV_SKIP_PAY_YEARS_CHECK). */
export function skipAwardCyclesCheck(env: Record<string, string | undefined>): boolean {
  return env.MOGOV_SKIP_AWARD_CYCLES_CHECK === "1";
}

/**
 * assertCyclePeriods, or nothing (with a log line) when the escape hatch is set. Used by the awards loader;
 * separate from it so the gate is testable on fixed inputs.
 */
export function awardCyclesGate(
  lists: Parameters<typeof assertCyclePeriods>[0],
  env: Record<string, string | undefined>,
  log: (msg: string) => void,
): void {
  if (skipAwardCyclesCheck(env)) {
    log("MOGOV_SKIP_AWARD_CYCLES_CHECK=1: skipping the award-cycle period check.");
    return;
  }
  assertCyclePeriods(lists);
}
