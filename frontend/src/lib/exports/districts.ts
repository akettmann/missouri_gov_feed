// District boundaries for "find my officials": dim_district's TIGER GeoJSON, simplified and rounded at build
// time so the browser can do point-in-polygon itself (no address or location ever leaves the page).
import { hasExport, query } from "./db";
import { allOfficials } from "./load";

/** A ring is [lon, lat, lon, lat, ...] (flat, to keep the JSON small). */
export type Ring = number[];
export interface DistrictShape {
  district_id: string;
  district_type: string;
  name: string;
  /** [minLon, minLat, maxLon, maxLat]: lets the lookup skip most polygons cheaply */
  bbox: [number, number, number, number];
  /** polygons, each [outer ring, ...holes] */
  polygons: Ring[][];
}
export interface DistrictData {
  vintage: number | null;
  shapes: DistrictShape[];
  /** district_id -> slugs of the officials elected/appointed for it */
  officials: Record<string, string[]>;
  /** officials every Missourian has: statewide executives and U.S. senators */
  statewide: string[];
  /** county outlines for the clickable map, simplified harder */
  map: { district_id: string; name: string; polygons: Ring[][] }[];
  /** county district_id -> ids of the House, Senate and congressional districts that intersect it */
  countyDistricts: Record<string, string[]>;
  /** county district_id -> ids of cities whose boundary covers the whole county (St. Louis city) */
  countyCities: Record<string, string[]>;
  /** ZIP (ZCTA) -> [internal point lon, lat, radius in meters of a circle with the same land area] */
  zips: Record<string, [number, number, number]>;
}

type Pt = [number, number];

// Douglas-Peucker on a ring, tolerance in degrees (0.0005 deg is ~50 m north-south, ~40 m east-west in MO)
function simplify(points: Pt[], tol: number): Pt[] {
  if (points.length <= 4) return points;
  const keep = new Uint8Array(points.length);
  keep[0] = keep[points.length - 1] = 1;
  const stack: [number, number][] = [[0, points.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop()!;
    const [ax, ay] = points[a];
    const [bx, by] = points[b];
    const dx = bx - ax;
    const dy = by - ay;
    const len2 = dx * dx + dy * dy || 1e-18;
    let worst = -1;
    let idx = -1;
    for (let i = a + 1; i < b; i++) {
      const [px, py] = points[i];
      const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
      const d = (px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2;
      if (d > worst) {
        worst = d;
        idx = i;
      }
    }
    if (idx >= 0 && worst > tol * tol) {
      keep[idx] = 1;
      stack.push([a, idx], [idx, b]);
    }
  }
  const out = points.filter((_, i) => keep[i]);
  return out.length >= 4 ? out : points;
}

const round = (n: number) => Math.round(n * 1e5) / 1e5; // ~1 m

function shrink(geometry: { type: string; coordinates: unknown }, tol: number): Ring[][] {
  const polys = (geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates) as Pt[][][];
  return polys.map((rings) =>
    rings.map((ring) => simplify(ring, tol).flatMap(([x, y]) => [round(x), round(y)])),
  );
}

function bboxOf(polygons: Ring[][]): [number, number, number, number] {
  const b: [number, number, number, number] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const poly of polygons)
    for (let i = 0; i < poly[0].length; i += 2) {
      b[0] = Math.min(b[0], poly[0][i]);
      b[1] = Math.min(b[1], poly[0][i + 1]);
      b[2] = Math.max(b[2], poly[0][i]);
      b[3] = Math.max(b[3], poly[0][i + 1]);
    }
  return b;
}

const STATEWIDE = new Set([
  "governor",
  "lt_governor",
  "secretary_of_state",
  "state_auditor",
  "state_treasurer",
  "attorney_general",
  "us_senate",
]);

let cache: Promise<DistrictData | null> | undefined;

/** null when the district exports are missing (the find page then says so). */
export function districtData(): Promise<DistrictData | null> {
  cache ??= load();
  return cache;
}

async function load(): Promise<DistrictData | null> {
  if (
    !hasExport("dim_district") ||
    !hasExport("fct_official_districts") ||
    !hasExport("fct_county_districts")
  )
    return null;
  const bundles = await allOfficials();
  const slugOf = new Map(bundles.map((b) => [b.official.official_id, b.official.slug]));

  const links = await query<{ official_id: string; district_id: string }>(`
    select distinct official_id, district_id from {fct_official_districts}
    order by district_id, official_id`);
  const officials: Record<string, string[]> = {};
  for (const l of links) {
    const slug = slugOf.get(l.official_id);
    if (slug) (officials[l.district_id] ??= []).push(slug);
  }

  // only places that have an official (mayors); 1k+ other places would just be weight
  const rows = await query<{
    district_id: string;
    district_type: string;
    name: string;
    vintage: number | null;
    geometry_geojson: string;
  }>(`
    select district_id, district_type, name_with_type as name, vintage, geometry_geojson
    from {dim_district}
    where is_current and geometry_geojson is not null
      and (district_type <> 'place' or district_id in (select district_id from {fct_official_districts}))
    order by district_type, district_number, name, district_id`);

  const shapes: DistrictShape[] = [];
  const map: DistrictData["map"] = [];
  for (const r of rows) {
    const geometry = JSON.parse(r.geometry_geojson);
    const polygons = shrink(geometry, 0.0005);
    shapes.push({
      district_id: r.district_id,
      district_type: r.district_type,
      name: r.name,
      bbox: bboxOf(polygons),
      polygons,
    });
    if (r.district_type === "county")
      map.push({ district_id: r.district_id, name: r.name, polygons: shrink(geometry, 0.01) });
  }

  // ZIP lookup: the area's internal point, and how far the area reaches (equal-area circle) so the page can say
  // which other districts a ZIP may also cover
  const zips: DistrictData["zips"] = {};
  if (hasExport("dim_zcta")) {
    for (const z of await query<{ zcta: string; lon: number; lat: number; land: number }>(`
      select zcta, cast(interior_lon as double) as lon, cast(interior_lat as double) as lat,
             cast(coalesce(land_area_m2, 0) as double) as land
      from {dim_zcta}`)) {
      zips[z.zcta] = [round(z.lon), round(z.lat), Math.round(Math.sqrt(z.land / Math.PI))];
    }
  }

  // county -> districts reaching it, from the unsimplified boundaries (fct_county_districts), in the order
  // congressional, senate, house; plus cities that cover the whole county
  const countyDistricts: DistrictData["countyDistricts"] = {};
  const countyCities: DistrictData["countyCities"] = {};
  for (const r of await query<{ county_id: string; district_id: string; district_type: string }>(`
    select f.county_id, f.district_id, f.district_type
    from {fct_county_districts} as f
    left join {dim_district} as d on d.district_id = f.district_id
    order by f.county_id,
      case f.district_type when 'us_house' then 1 when 'state_senate' then 2 when 'state_house' then 3 else 4 end,
      d.district_number, f.district_id`)) {
    const into = r.district_type === "place" ? countyCities : countyDistricts;
    (into[r.county_id] ??= []).push(r.district_id);
  }

  return {
    zips,
    countyDistricts,
    countyCities,
    vintage: rows.find((r) => r.vintage != null)?.vintage ?? null,
    shapes,
    officials,
    statewide: bundles.filter((b) => STATEWIDE.has(b.official.office)).map((b) => b.official.slug),
    map,
  };
}
