// The one place that declares which columns the site needs from an export table that was added to or
// widened after the first release. query() checks every `{table}` it reads against this before running,
// so a stale export fails with one clear re-export message instead of a raw DuckDB binder error.
// Add a table's new column here in the same change that starts selecting it.
// (rpt_awards.period_kind is checked separately in awardDefs.ts: it has a documented skip switch.)

// Tables not listed here still get a clear message: query() turns a binder error naming a column an
// export lacks into the same stale-export error. Listing a column here only adds the up-front, all-at-once report.
export const REQUIRED_COLUMNS: Record<string, readonly string[]> = {
  rpt_attendance: ["recused_from_voting"],
  rpt_interest_vote_overlap: ["vote_description"],
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
    "is_current_official",
    "source_url",
  ],
  fct_sponsorship_outcomes: [
    "official_id",
    "session_code",
    "session_year",
    "is_session_over",
    "bills_sponsored",
    "bills_decided",
    "bills_passed_house",
    "bills_became_law",
    "source_url",
  ],
  fct_committee_memberships: [
    "official_id",
    "session_code",
    "committee_name",
    "position_name",
    "is_subcommittee",
    "source",
    "source_url",
    "is_current_official",
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
    "donated_amount",
    "n_contributions",
    "first_year",
    "last_year",
    "match_confidence",
    "frs_url",
  ],
  fct_jurisdiction_business_donors: ["official_id", "registry_id", "donor_name", "source_url"],
};

/**
 * Tables that must be exported together: an export of the key table from before a sibling existed is stale even
 * though every one of its own columns is present, and a missing sibling would otherwise just look like "no data".
 * fct_jurisdiction_businesses lost its donor_name_list and donor_links columns to this table (#370).
 */
export const REQUIRED_TABLES: Record<string, readonly string[]> = {
  fct_jurisdiction_businesses: ["fct_jurisdiction_business_donors"],
  fct_jurisdiction_business_donors: ["fct_jurisdiction_businesses"],
};

/** Sibling tables missing from an export, per table that is there. Empty when all is well. */
export function missingTables(
  used: readonly string[],
  exists: (table: string) => boolean,
  required: Record<string, readonly string[]> = REQUIRED_TABLES,
): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const table of used) {
    if (!exists(table)) continue;
    const missing = (required[table] ?? []).filter((t) => !exists(t));
    if (missing.length > 0) out[table] = missing;
  }
  return out;
}

/** Throws one error naming every table whose required sibling table is not exported, with the re-export commands. */
export function assertNoMissingTables(
  used: readonly string[],
  exists: (table: string) => boolean,
  required: Record<string, readonly string[]> = REQUIRED_TABLES,
): void {
  const missing = missingTables(used, exists, required);
  const tables = Object.keys(missing);
  if (tables.length === 0) return;
  const detail = tables.map((t) => `${t} needs ${missing[t].join(", ")}`).join("; ");
  throw new Error(
    `stale export: ${detail}, which ${tables.length === 1 && missing[tables[0]].length === 1 ? "is" : "are"} not exported ` +
      `(exported before that table was added). Re-export: ${REEXPORT_COMMANDS}.`,
  );
}

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

/** The error for a table the SQL needs that has no export file: build first, since an old export may predate the model. */
export function missingExportMessage(file: string): string {
  return `missing export ${file}; the export may predate this table. Re-export: ${REEXPORT_COMMANDS}.`;
}
