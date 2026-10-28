// Pure helpers for the per-district EPA site list: the URL slug and the CSV download. No I/O so
// scripts/siteCsv.test.mjs can run them on fixed inputs.
import { parseDonorLinks } from "./donorLinks.ts";
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
  "registry_id",
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
  "epa_record_url",
] as const;

/** One line per (site, donor, filing page) in sites-donors.csv; registry_id joins back to the site list. */
export const SITE_DONOR_CSV_HEADER = [
  "registry_id",
  "facility_name",
  "donor_name",
  "filing_page_url",
] as const;

/**
 * Header plus one line per site, LF-terminated. Every column holds one value: the donors (several per site)
 * are in sitesDonorsCsv, not packed into a cell (#370, #849).
 */
export function sitesCsv(rows: SiteRow[]): string {
  const lines = rows.map((r) =>
    [
      r.registry_id,
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
      r.frs_url,
    ]
      .map(cell)
      .join(","),
  );
  return [SITE_CSV_HEADER.join(","), ...lines].join("\n") + "\n";
}

/**
 * Long table behind the site list's donor match: one line per site, donor and filing page, in the order of
 * `rows`, then donor name, then url. A donor with no filing page gets one line with an empty filing_page_url.
 * A site with no matched donor has no line. (registry_id, donor_name, filing_page_url) is unique.
 */
export function sitesDonorsCsv(rows: SiteRow[]): string {
  const lines: string[] = [];
  for (const r of rows) {
    const links = parseDonorLinks(r.donor_links);
    const donors = [...r.donors];
    for (const l of links) if (!donors.includes(l.donor)) donors.push(l.donor);
    for (const donor of donors) {
      const urls = [...new Set(links.filter((l) => l.donor === donor).map((l) => l.url))];
      for (const url of urls.length ? urls : [null]) {
        lines.push([r.registry_id, r.facility_name, donor, url].map(cell).join(","));
      }
    }
  }
  return [SITE_DONOR_CSV_HEADER.join(","), ...lines].join("\n") + "\n";
}
