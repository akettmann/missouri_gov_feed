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

type Ring = number[];

/**
 * A point inside a county (outer ring even-odd, holes excluded) near its bounding-box center, for restoring a
 * county from a link. Coarse grid scan; null only for empty geometry.
 */
export function interiorPoint(
  polygons: Ring[][],
  inside: (polys: Ring[][], x: number, y: number) => boolean,
): [number, number] | null {
  let [x0, y0, x1, y1] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const rings of polygons)
    for (const r of rings)
      for (let i = 0; i < r.length; i += 2) {
        x0 = Math.min(x0, r[i]);
        x1 = Math.max(x1, r[i]);
        y0 = Math.min(y0, r[i + 1]);
        y1 = Math.max(y1, r[i + 1]);
      }
  if (!isFinite(x0)) return null;
  const [cx, cy] = [(x0 + x1) / 2, (y0 + y1) / 2];
  let best: [number, number] | null = null;
  let bestD = Infinity;
  const N = 24;
  for (let i = 0; i <= N; i++)
    for (let j = 0; j <= N; j++) {
      const x = x0 + ((x1 - x0) * i) / N;
      const y = y0 + ((y1 - y0) * j) / N;
      const d = (x - cx) ** 2 + (y - cy) ** 2;
      if (d < bestD && inside(polygons, x, y)) {
        best = [x, y];
        bestD = d;
      }
    }
  return best;
}
