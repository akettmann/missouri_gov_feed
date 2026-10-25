// Which State House, State Senate and Congressional districts intersect each county. Computed at build time from
// the shipped (simplified) geometries by sampling a grid over the county, so the browser can show a county view
// without running a lookup at one arbitrary point. A district narrower than the grid step (about 1 km at most) that
// never lands on a sample is missed, and so are the hairline slivers where a district edge and a county edge
// disagree by the 50 m simplification (a 0.0015 degree grid finds those on 89 counties; they are not real overlap).
import { inside } from "./geo.ts";

export const SAMPLED_TYPES = ["us_house", "state_senate", "state_house"] as const;

interface Shape {
  district_id: string;
  district_type: string;
  bbox: [number, number, number, number];
  polygons: number[][][];
}

const MAX_STEP = 0.01; // degrees, about 1 km
const MIN_STEP = 0.002;
const SAMPLES = 4000; // aim for about this many grid points inside a bbox, so small counties are sampled finely

/** county district_id -> ids of the districts (in SAMPLED_TYPES order, then by shape order) it intersects. */
export function countyDistricts(shapes: Shape[]): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  const order = new Map<string, number>(shapes.map((s, i) => [s.district_id, i]));
  const sampled = shapes.filter((s) => (SAMPLED_TYPES as readonly string[]).includes(s.district_type));
  for (const county of shapes.filter((s) => s.district_type === "county")) {
    const [x0, y0, x1, y1] = county.bbox;
    const step = Math.min(MAX_STEP, Math.max(MIN_STEP, Math.sqrt(((x1 - x0) * (y1 - y0)) / SAMPLES)));
    const near = sampled.filter(
      (s) => s.bbox[0] <= x1 && s.bbox[2] >= x0 && s.bbox[1] <= y1 && s.bbox[3] >= y0,
    );
    const found = new Set<string>();
    for (let x = x0 + step / 2; x <= x1; x += step)
      for (let y = y0 + step / 2; y <= y1; y += step) {
        if (!inside(county.polygons, x, y)) continue;
        for (const t of SAMPLED_TYPES) {
          // districts of one type don't overlap: stop at the first that contains the point
          const hit = near.find(
            (s) =>
              s.district_type === t &&
              x >= s.bbox[0] &&
              x <= s.bbox[2] &&
              y >= s.bbox[1] &&
              y <= s.bbox[3] &&
              inside(s.polygons, x, y),
          );
          if (hit) found.add(hit.district_id);
        }
      }
    out[county.district_id] = [...found].sort(
      (a, b) =>
        SAMPLED_TYPES.indexOf(typeOf(a) as (typeof SAMPLED_TYPES)[number]) -
          SAMPLED_TYPES.indexOf(typeOf(b) as (typeof SAMPLED_TYPES)[number]) || order.get(a)! - order.get(b)!,
    );
  }
  return out;
}

const typeOf = (id: string) => id.replace(/:.*$/, "");
