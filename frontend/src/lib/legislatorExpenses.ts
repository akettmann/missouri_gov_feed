// Row selection and wording for the "Per diem and mileage" section (fct_legislator_expenses). No imports, so node
// can test it directly. The dbt model pairs the state's expenditure payees with officials; this only orders the
// rows and words what they cover.

export type ExpenseType = "per diem" | "mileage";

/** One official, state fiscal year and expense type (fct_legislator_expenses). */
export interface LegislatorExpenseRow {
  /** state fiscal year, July of the year before through June */
  fiscal_year: number;
  expense_type: ExpenseType;
  /** the payee as the state lists it ("ATCHISON, FRANKLIN D") */
  payee_name: string;
  /** dollars the state paid that payee for the line in that fiscal year (negative = net refund) */
  amount: number;
  match_confidence: string;
  /** the data.mo.gov dataset for that fiscal year */
  source_url: string | null;
}

/** Offices whose holders are paid per diem and mileage; the section shows for them even with no matched row. */
export const LEGISLATURE_OFFICES = ["state_house", "state_senate"];

/** The section shows for a seat in the Missouri legislature, or for anyone with a matched row (a former legislator). */
export function showsExpenses(office: string, rows: LegislatorExpenseRow[] | null): boolean {
  return LEGISLATURE_OFFICES.includes(office) || (rows?.length ?? 0) > 0;
}

/** The rows of one expense type, newest fiscal year first. */
export function expenseYears(rows: LegislatorExpenseRow[], type: ExpenseType): LegislatorExpenseRow[] {
  return rows.filter((r) => r.expense_type === type).sort((a, b) => b.fiscal_year - a.fiscal_year);
}

/** "FY2026 (July 2025 to June 2026)": the state's fiscal year, not a calendar year. */
export function fiscalYearLabel(fiscalYear: number): string {
  return `FY${fiscalYear} (July ${fiscalYear - 1} to June ${fiscalYear})`;
}

/** The fiscal years between the first and last row that have no row of this type (not paid, or not matched). */
export function gapYears(years: LegislatorExpenseRow[]): number[] {
  if (years.length < 2) return [];
  const have = new Set(years.map((y) => y.fiscal_year));
  const first = Math.min(...have);
  const last = Math.max(...have);
  const gaps: number[] = [];
  for (let y = first + 1; y < last; y++) if (!have.has(y)) gaps.push(y);
  return gaps;
}

/**
 * Group the whole export's rows by official. Null when the export holds no rows at all: that means the state
 * expenditures data was not loaded for this build, which is different from one official having no matched row.
 */
export function groupExpenses<T extends { official_id: string }>(
  rows: T[],
): Map<string, Omit<T, "official_id">[]> | null {
  if (rows.length === 0) return null;
  const byOfficial = new Map<string, Omit<T, "official_id">[]>();
  for (const { official_id, ...row } of rows) {
    const mine = byOfficial.get(official_id) ?? [];
    mine.push(row);
    byOfficial.set(official_id, mine);
  }
  return byOfficial;
}
