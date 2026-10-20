// Client side of "find my officials": point-in-polygon against /lookup/districts.json, then the officials
// for each district, grouped by level. Runs entirely in the browser.
import type { DistrictShape } from "../lib/exports/districts";

export interface Lookup {
  vintage: number | null;
  shapes: DistrictShape[];
  officials: Record<string, string[]>;
  statewide: string[];
  /** ZIP -> [lon, lat, equal-area radius in meters] */
  zips: Record<string, [number, number, number]>;
  /** slug -> [full name, office line, party, office] */
  directory: Record<string, [string, string, string | null, string]>;
}

/** Even-odd ray casting over every ring, so holes (enclaves) count as outside. */
function inside(polygons: number[][][], x: number, y: number): boolean {
  let hit = false;
  for (const rings of polygons)
    for (const r of rings)
      for (let i = 0, j = r.length - 2; i < r.length; j = i, i += 2) {
        const [xi, yi, xj, yj] = [r[i], r[i + 1], r[j], r[j + 1]];
        if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) hit = !hit;
      }
  return hit;
}

const GROUPS: { title: string; offices: string[]; collapsed?: boolean }[] = [
  {
    title: "Statewide",
    offices: [
      "governor",
      "lt_governor",
      "secretary_of_state",
      "state_auditor",
      "state_treasurer",
      "attorney_general",
    ],
  },
  { title: "U.S. Senate", offices: ["us_senate"] },
  { title: "U.S. House", offices: ["us_house"] },
  { title: "Missouri Senate", offices: ["state_senate"] },
  { title: "Missouri House", offices: ["state_house"] },
  { title: "City", offices: ["mayor"] },
  {
    title: "Courts",
    offices: [
      "mo_supreme_court",
      "mo_court_of_appeals",
      "mo_circuit_judge",
      "mo_associate_circuit_judge",
      "us_court_of_appeals",
      "us_district_court",
    ],
    collapsed: true,
  },
];

const el = <K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> = {}) =>
  Object.assign(document.createElement(tag), props);

const hitsAt = (data: Lookup, lon: number, lat: number) =>
  data.shapes.filter(
    (s) =>
      lon >= s.bbox[0] &&
      lon <= s.bbox[2] &&
      lat >= s.bbox[1] &&
      lat <= s.bbox[3] &&
      inside(s.polygons, lon, lat),
  );

/** Districts a ZIP may also reach: sample a circle of the ZIP's land area around its internal point. */
const ALSO_TYPES = ["us_house", "state_senate", "state_house"];
function alsoReached(data: Lookup, lon: number, lat: number, radiusM: number, primary: Set<string>) {
  const found = new Map<string, Lookup["shapes"][number]>();
  const dLat = radiusM / 111_320;
  const dLon = radiusM / (111_320 * Math.cos((lat * Math.PI) / 180));
  for (const f of [0.5, 0.9])
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * 2 * Math.PI;
      for (const h of hitsAt(data, lon + f * dLon * Math.cos(a), lat + f * dLat * Math.sin(a)))
        if (ALSO_TYPES.includes(h.district_type) && !primary.has(h.district_id)) found.set(h.district_id, h);
    }
  return [...found.values()].sort(
    (a, b) => ALSO_TYPES.indexOf(a.district_type) - ALSO_TYPES.indexOf(b.district_type),
  );
}

/** Look up a typed ZIP: officials at the ZIP's internal point, then other districts the ZIP may reach. */
export function lookupZip(
  data: Lookup,
  zip: string,
  out: HTMLElement,
  status: HTMLElement,
): [number, number] | null {
  const z = data.zips?.[zip];
  if (!z) {
    out.replaceChildren(
      el("p", {
        className: "muted",
        textContent: `${zip} isn't a Missouri ZIP code in the Census ZIP areas (PO-box-only ZIPs have none). Try your location or the map.`,
      }),
    );
    status.textContent = "ZIP not found.";
    return null;
  }
  const [lon, lat, radius] = z;
  lookup(data, lon, lat, out, status);
  const primary = new Set(hitsAt(data, lon, lat).map((h) => h.district_id));
  const also = alsoReached(data, lon, lat, radius, primary);
  status.textContent = `ZIP ${zip}, at its center: ${status.textContent}`;
  if (also.length) {
    const base = import.meta.env.BASE_URL.replace(/\/$/, "");
    const box = el("div", { className: "also" });
    box.append(
      el("h3", { textContent: "This ZIP may also reach" }),
      el("p", {
        className: "small muted",
        textContent:
          "A ZIP code can cross district lines. If you live near the edge of this ZIP, one of these may be yours; use your location or the map for an exact answer.",
      }),
    );
    const list = el("ul", { className: "people" });
    for (const d of also) {
      const li = el("li");
      li.append(el("strong", { textContent: d.name }));
      const members = data.officials[d.district_id] ?? [];
      if (!members.length)
        li.append(el("span", { className: "muted", textContent: " · no current member in our data" }));
      for (const s of members) {
        li.append(" · ");
        li.append(el("a", { href: `${base}/officials/${s}/`, textContent: data.directory[s][0] }));
      }
      list.append(li);
    }
    box.append(list);
    out.append(box);
  }
  return [lon, lat];
}

export function lookup(data: Lookup, lon: number, lat: number, out: HTMLElement, status: HTMLElement) {
  const hits = hitsAt(data, lon, lat);
  out.replaceChildren();
  if (!hits.some((h) => h.district_type === "county")) {
    status.textContent = "That point isn't in Missouri. Try another spot.";
    out.append(el("p", { className: "muted", textContent: "No Missouri districts at that location." }));
    return;
  }
  const county = hits.find((h) => h.district_type === "county")!;
  status.textContent = `${county.name}: ${hits
    .filter((h) => h.district_type !== "county" && h.district_type !== "place")
    .map((h) => h.name)
    .join(", ")}`;

  const slugs = new Set([...data.statewide, ...hits.flatMap((h) => data.officials[h.district_id] ?? [])]);
  const base = import.meta.env.BASE_URL.replace(/\/$/, "");
  for (const g of GROUPS) {
    const members = [...slugs].filter((s) => g.offices.includes(data.directory[s]?.[3]));
    if (!members.length) continue;
    const list = el("ul", { className: "people" });
    for (const s of members.sort((a, b) => data.directory[a][0].localeCompare(data.directory[b][0]))) {
      const [name, office, party] = data.directory[s];
      const li = el("li");
      li.append(el("a", { href: `${base}/officials/${s}/`, textContent: name }));
      li.append(
        el("span", { className: "small muted", textContent: ` ${office}${party ? ` · ${party}` : ""}` }),
      );
      list.append(li);
    }
    if (g.collapsed) {
      const d = el("details");
      d.append(el("summary", { textContent: `${g.title} (${members.length})` }), list);
      out.append(d);
    } else {
      out.append(el("h3", { textContent: g.title }), list);
    }
  }
}
