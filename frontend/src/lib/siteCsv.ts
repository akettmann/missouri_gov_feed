// Pure helpers for the per-district EPA site list: the URL slug and the CSV download. No I/O so
// scripts/siteCsv.test.mjs can run them on fixed inputs.
import type { SiteRow } from "./exports/types";

/** URL-safe form of district_id ("state_house:135" -> "state_house-135") */
export const districtSlug = (districtId: string) => districtId.replaceAll(":", "-");

/** RFC 4180 field: null is empty, booleans are true/false, and any field with a comma, quote, CR or LF is quoted. */
export const cell = (v: string | number | boolean | null | undefined): string => {
  const s = v === null || v === undefined ? "" : String(v);
  return /[",\r\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
};

export const SITE_CSV_HEADER = [
  "facility_name",
  "address",
  "city",
  "postal_code",
  "industry",
  "owner_name",
  "parent_company_name",
  "donor_matched",
  "match_confidence",
  "matched_by",
  "donor_names",
  "contributions_url",
  "epa_record_url",
] as const;

/** Header plus one line per site, LF-terminated, same columns as the page. */
export function sitesCsv(rows: SiteRow[]): string {
  const lines = rows.map((r) =>
    [
      r.facility_name,
      r.address,
      r.city,
      r.postal_code,
      r.naics_description,
      r.owner_name,
      r.parent_company_name,
      r.is_donor,
      r.match_confidence,
      r.matched_by,
      r.donor_names,
      r.contributions_url,
      r.frs_url,
    ]
      .map(cell)
      .join(","),
  );
  return [SITE_CSV_HEADER.join(","), ...lines].join("\n") + "\n";
}
