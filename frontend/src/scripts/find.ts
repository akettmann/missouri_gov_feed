// Client side of "find my officials": point-in-polygon against /data/districts.json, then the officials
// for each district, grouped by level. Runs entirely in the browser.
import type { DistrictShape } from "../lib/exports/districts";

export interface Lookup {
  vintage: number | null;
  shapes: DistrictShape[];
  officials: Record<string, string[]>;
  statewide: string[];
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

export function lookup(data: Lookup, lon: number, lat: number, out: HTMLElement, status: HTMLElement) {
  const hits = data.shapes.filter(
    (s) =>
      lon >= s.bbox[0] &&
      lon <= s.bbox[2] &&
      lat >= s.bbox[1] &&
      lat <= s.bbox[3] &&
      inside(s.polygons, lon, lat),
  );
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
