// The one place that declares which columns the site needs from an export table that was added to or
// widened after the first release. query() checks every `{table}` it reads against this before running,
// so a stale export fails with one clear re-export message instead of a raw DuckDB binder error.
// Add a table's new column here in the same change that starts selecting it.
// (rpt_awards.period_kind is checked separately in awardDefs.ts: it has a documented skip switch.)

// Tables not listed here still get a clear message: query() turns a binder error naming a column an
// export lacks into the same stale-export error. Listing a column here only adds the up-front, all-at-once report.
export const REQUIRED_COLUMNS: Record<string, readonly string[]> = {
  rpt_attendance: ["recused_from_voting"],
  rpt_attendance_pay: ["pay_source_url", "covered_years", "voting_years"],
  fct_committee_posts: [
    "official_id",
    "session_code",
    "session_year",
    "committees_held",
    "chair_posts",
    "vice_chair_posts",
    "co_chair_posts",
    "ranking_posts",
  ],
  fct_committee_memberships: [
    "official_id",
    "session_code",
    "committee_name",
    "position_name",
    "is_subcommittee",
    "source",
  ],
  fct_jurisdiction_businesses: [
    "official_id",
    "district_id",
    "registry_id",
    "facility_name",
    "address",
    "city",
    "postal_code",
    "naics_description",
    "owner_name",
    "parent_company_name",
    "is_donor",
    "matched_by",
    "donor_names",
    "donated_amount",
    "n_contributions",
    "first_year",
    "last_year",
    "match_confidence",
    "donor_links",
    "frs_url",
  ],
};

export const REEXPORT_COMMANDS = "`uv run mogov build`, then `uv run mogov export --format parquet`";

/** Missing required columns per stale table, from each table's actual column list. Empty when all is well. */
export function missingColumns(
  actual: Record<string, readonly string[]>,
  required: Record<string, readonly string[]> = REQUIRED_COLUMNS,
): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const [table, columns] of Object.entries(actual)) {
    const missing = (required[table] ?? []).filter((c) => !columns.includes(c));
    if (missing.length > 0) out[table] = missing;
  }
  return out;
}

/** Throws one error naming every stale table and its missing columns, with the re-export commands. */
export function assertNoMissingColumns(
  actual: Record<string, readonly string[]>,
  required: Record<string, readonly string[]> = REQUIRED_COLUMNS,
): void {
  const missing = missingColumns(actual, required);
  const tables = Object.keys(missing);
  if (tables.length === 0) return;
  const detail = tables.map((t) => `${t} lacks ${missing[t].join(", ")}`).join("; ");
  throw new Error(
    `stale export: ${detail} (exported before ${tables.length === 1 ? "that column was" : "those columns were"} added). ` +
      `Re-export: ${REEXPORT_COMMANDS}.`,
  );
}
