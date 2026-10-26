// Wording and thresholds for a federal district judge's median time to disposition (fct_judge_time_to_disposition).
// Pure (imports only the pure format helpers) so node can test it directly. The mart carries no minimum sample size; the page applies one.
import { count, plural } from "./format.ts";

/** Fewest measured dockets a median is shown for; below it the page shows the count and no median. */
export const MIN_MEASURED = 30;
/** When fewer than this share of the judge's assigned dockets have both dates, the page says the median covers a part. */
export const LOW_COVERAGE_SHARE = 0.8;

export interface TimeToDispositionInput {
  dockets_assigned: number;
  dockets_measured: number;
  dockets_ends_before_filed: number;
  share_with_both_dates: number;
  median_days_to_disposition: number | null;
}

export interface TimeToDispositionView {
  /** null when too few dockets were measured (or the export has no median) */
  median: number | null;
  measured: number;
  assigned: number;
  /** measured / assigned, as a percent rounded down to one decimal (so 7,793 of 7,796 reads 99.9, never 100) */
  coveragePct: number;
  lowCoverage: boolean;
  /** dockets left out because they end before they were filed */
  excluded: number;
}

export function timeToDispositionView(r: TimeToDispositionInput): TimeToDispositionView {
  // Derived from the counts shown on the page, not the mart's share (which also counts dockets that end before filing).
  const share = r.dockets_assigned > 0 ? r.dockets_measured / r.dockets_assigned : null;
  const enough = r.dockets_measured >= MIN_MEASURED && r.median_days_to_disposition != null;
  return {
    median: enough ? r.median_days_to_disposition : null,
    measured: r.dockets_measured,
    assigned: r.dockets_assigned,
    coveragePct: share === null ? 0 : Math.floor(share * 1000) / 10,
    lowCoverage: share !== null && share < LOW_COVERAGE_SHARE,
    excluded: r.dockets_ends_before_filed,
  };
}

/** "238 days" / "1 day" / "1,234 days"; whole days, with a half day (an even count of dockets) kept as "276.5". */
export function daysLabel(n: number): string {
  return plural(Number.isInteger(n) ? n : Number(n.toFixed(1)), "day", "days");
}

/** the "only N dockets with both dates" clause shown when too few were measured */
export const measuredDocketsText = (n: number) => plural(n, "docket", "dockets");

/** sentence appended when some dockets end before they were filed */
export const excludedDocketsText = (n: number) =>
  n === 1
    ? `${plural(n, "docket", "dockets")} that ends before it was filed (a source error) is left out.`
    : `${plural(n, "docket", "dockets")} that end before they were filed (a source error) are left out.`;

/** "N federal dockets" in the method note */
export const federalDocketsText = (n: number) => plural(n, "federal docket", "federal dockets");

/** "M of N assigned dockets measured" coverage line */
export const coverageText = (measured: number, assigned: number) =>
  `${count(measured)} of ${plural(assigned, "assigned docket", "assigned dockets")} measured`;
