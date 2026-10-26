// Wording and thresholds for a federal district judge's median time to disposition (fct_judge_time_to_disposition),
// one median per case type: civil and criminal dockets are never mixed (criminal ones take about twice as long).
// Pure (imports only the pure format helpers) so node can test it directly. The mart carries no minimum sample size; the page applies one.
import { count, plural } from "./format.ts";

/** Fewest measured dockets a median is shown for; below it the page shows the count and no median. */
export const MIN_MEASURED = 30;
/** When fewer than this share of the judge's assigned dockets have both dates, the page says the median covers a part. */
export const LOW_COVERAGE_SHARE = 0.8;

/** The case types the mart carries a row for; miscellaneous dockets (warrants, subpoenas) are not in it. */
export type CaseType = "civil" | "criminal";

export interface TimeToDispositionInput {
  case_type?: CaseType;
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

/** sentence appended when some dockets end before they were filed */
export const excludedDocketsText = (n: number) =>
  n === 1
    ? `${plural(n, "docket", "dockets")} that ends before it was filed (a source error) is left out.`
    : `${plural(n, "docket", "dockets")} that end before they were filed (a source error) are left out.`;

/** "N federal civil dockets" / "N federal criminal dockets" in the method note */
export const federalDocketsText = (n: number, type: CaseType) =>
  plural(n, `federal ${type} docket`, `federal ${type} dockets`);

/** heading for one case type's median */
export const caseTypeHeading = (type: CaseType) => `Median time to disposition: ${type} cases`;

/** "N civil dockets" clause for the count shown when too few were measured */
export const measuredTypedDocketsText = (n: number, type: CaseType) =>
  plural(n, `${type} docket`, `${type} dockets`);

/** Why no median is shown. "Measured" is what dockets_measured counts: both dates, and the end not before the filing. */
export const hiddenMedianText = (measured: number, type: CaseType) =>
  `Not shown: only ${measuredTypedDocketsText(measured, type)} could be measured, and the page needs at least ${MIN_MEASURED} for a median. A docket is measured when CourtListener has both its filing date and its termination date and it did not end before it was filed.`;

/** Every case type gets a block, in this order, so a judge with none of a type says so instead of going quiet. */
export const CASE_TYPES: readonly CaseType[] = ["civil", "criminal"];

/** Shown in place of a block when the judge has no docket of that type in the mart. */
export const noDocketsText = (type: CaseType) =>
  `No ${type} dockets assigned to this judge in CourtListener.`;

/** Which types have no row, in display order (a judge with no rows at all gets no time-to-disposition section). */
export const missingCaseTypes = (present: readonly (CaseType | undefined)[]): CaseType[] =>
  present.length === 0 ? [] : CASE_TYPES.filter((t) => !present.includes(t));

/** Closing note: the dockets in neither median. The count of 'other' dockets lives in docs/sources.md (#465). */
export const EXCLUDED_TYPES_TEXT =
  "Miscellaneous dockets (warrants, subpoenas, complaints) and dockets of other or unclassified types are in neither.";

/** "M of N assigned civil dockets measured" coverage line */
export const coverageText = (measured: number, assigned: number, type: CaseType) =>
  `${count(measured)} of ${plural(assigned, `assigned ${type} docket`, `assigned ${type} dockets`)} measured`;
