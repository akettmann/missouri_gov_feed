// URL <-> selection for "Find my officials", so a result can be bookmarked and shared. Pure helpers: the page
// does the history.replaceState and the lookup. Only a county FIPS or a typed ZIP ever goes in the URL, never
// coordinates (a "use my location" pick records just the county it lands in).
import { withBase } from "./basePath.ts";

export type FindParams =
  | { kind: "none" }
  | { kind: "county"; fips: string }
  | { kind: "zip"; zip: string }
  | { kind: "invalid"; message: string };

const FIPS = /^29\d{3}$/;
const ZIP = /^\d{5}$/;

/** "county:29001" (dim_district id) -> "29001"; anything else -> null. */
export function countyFips(districtId: string): string | null {
  const m = /^county:(\d{5})$/.exec(districtId);
  return m ? m[1] : null;
}

export const countyDistrictId = (fips: string) => `county:${fips}`;

/**
 * Read ?county=29001 or ?zip=65101 from a location.search string. `counties` is the set of FIPS codes the
 * build knows; a well-formed code outside it is invalid too. county wins if both are present.
 */
export function parseFindParams(search: string, counties: ReadonlySet<string>): FindParams {
  const q = new URLSearchParams(search);
  const county = q.get("county");
  if (county !== null) {
    const v = county.trim();
    return FIPS.test(v) && counties.has(v)
      ? { kind: "county", fips: v }
      : { kind: "invalid", message: `"${v.slice(0, 20)}" isn't a Missouri county code in this link.` };
  }
  const zip = q.get("zip");
  if (zip !== null) {
    const v = zip.trim();
    return ZIP.test(v)
      ? { kind: "zip", zip: v }
      : { kind: "invalid", message: `"${v.slice(0, 20)}" isn't a five-digit ZIP code in this link.` };
  }
  return { kind: "none" };
}

/** The shareable path for a selection, under the site base: "/missouri_gov_feed/find/?county=29001". */
export function findHref(baseUrl: string, sel: Exclude<FindParams, { kind: "invalid" }>): string {
  const path = withBase(baseUrl, "/find/");
  if (sel.kind === "county") return `${path}?county=${sel.fips}`;
  if (sel.kind === "zip") return `${path}?zip=${sel.zip}`;
  return path;
}
