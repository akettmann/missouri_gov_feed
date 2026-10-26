// Loader for the "Per diem and mileage" section (fct_legislator_expenses); kept out of load.ts so that file only
// gains an import and two lines. Row selection only: the pairing of payees with officials is dbt's.
import type { LegislatorExpenseRow } from "../legislatorExpenses";
import { hasExport, query } from "./db";

/** official_id -> that official's rows; null when the export is missing (the section says so). */
export async function loadLegislatorExpenses(): Promise<Map<string, LegislatorExpenseRow[]> | null> {
  if (!hasExport("fct_legislator_expenses")) return null;
  const rows = await query<LegislatorExpenseRow & { official_id: string }>(`
    select official_id, cast(fiscal_year as integer) as fiscal_year, expense_type, payee_name,
           cast(amount as double) as amount, match_confidence, source_url
    from {fct_legislator_expenses}
    order by official_id, expense_type, fiscal_year desc`);
  const byOfficial = new Map<string, LegislatorExpenseRow[]>();
  for (const { official_id, ...row } of rows) {
    const mine = byOfficial.get(official_id) ?? [];
    mine.push(row);
    byOfficial.set(official_id, mine);
  }
  return byOfficial;
}
