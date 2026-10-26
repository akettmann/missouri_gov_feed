// Pure helpers for the per-district EPA site list: the URL slug and the CSV download. No I/O so
// scripts/siteCsv.test.mjs can run them on fixed inputs.
import { donorNamesText } from "./donorLinks.ts";
import type { SiteRow } from "./exports/types";

/** URL-safe form of district_id ("state_house:135" -> "state_house-135") */
export const districtSlug = (districtId: string) => districtId.replaceAll(":", "-");

/** Spreadsheet apps read a text cell starting with one of these as a formula (OWASP CSV injection). */
const FORMULA_TRIGGER = /^[=+\-@\t\r]/;

/**
 * RFC 4180 field: null is empty, booleans are true/false, and any field with a comma, quote, CR or LF is quoted.
 * Text starting with = + - @ tab or CR gets a leading ' so Excel/Sheets show it as text instead of running it.
 * Only strings are guarded: every column of the site list is text (postal_code included, so a "-" prefix
 * means a name or address, never a number), while a real number (typeof "number") is written as is so a
 * negative value would not be mangled.
 */
export const cell = (v: string | number | boolean | null | undefined): string => {
  let s = v === null || v === undefined ? "" : String(v);
  if (typeof v === "string" && FORMULA_TRIGGER.test(s)) s = `'${s}`;
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
  "donor_links",
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
      donorNamesText(r.donors),
      r.donor_links,
      r.frs_url,
    ]
      .map(cell)
      .join(","),
  );
  return [SITE_CSV_HEADER.join(","), ...lines].join("\n") + "\n";
}
