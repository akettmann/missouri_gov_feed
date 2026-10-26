// Client side of "find my officials": point-in-polygon against /lookup/districts.json, then the officials
// for each district, grouped by level. Runs entirely in the browser.
import { renderBadges, type Badge } from "../lib/awardBadges";
import { countyView } from "../lib/countyView";
import type { DistrictShape } from "../lib/exports/districts";
import { inside } from "../lib/geo";

export interface Lookup {
  vintage: number | null;
  shapes: DistrictShape[];
  officials: Record<string, string[]>;
  statewide: string[];
  /** ZIP -> [lon, lat, equal-area radius in meters] */
  zips: Record<string, [number, number, number]>;
  /** county district_id -> ids of the House, Senate and congressional districts that intersect it */
  countyDistricts: Record<string, string[]>;
  countyCities: Record<string, string[]>;
  /** slug -> [full name, office line, party, office, current award badges when they hold any] */
  directory: Record<string, [string, string, string | null, string, Badge[]?]>;
}

export { inside };

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

/** The official's award icons, drawn by the same renderer the built pages use. */
function badgesFor(badges: Badge[] | undefined, base: string): DocumentFragment {
  return document.createRange().createContextualFragment(renderBadges(badges ?? [], base));
}

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

/** A list of districts, each with its current members (reused for "may also reach" and the county view). */
function districtList(data: Lookup, districts: { name: string; district_id: string }[]) {
  const base = import.meta.env.BASE_URL.replace(/\/$/, "");
  const list = el("ul", { className: "people" });
  for (const d of districts) {
    const li = el("li");
    li.append(el("strong", { textContent: d.name }));
    const members = data.officials[d.district_id] ?? [];
    if (!members.length)
      li.append(el("span", { className: "muted", textContent: " · no current member in our data" }));
    for (const s of members) {
      li.append(" · ");
      li.append(el("a", { href: `${base}/officials/${s}/`, textContent: data.directory[s][0] }));
      li.append(badgesFor(data.directory[s][4], base));
    }
    list.append(li);
  }
  return list;
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
    const box = el("div", { className: "also" });
    box.append(
      el("h3", { textContent: "This ZIP may also reach" }),
      el("p", {
        className: "small muted",
        textContent:
          "A ZIP code can cross district lines. If you live near the edge of this ZIP, one of these may be yours; use your location or the map for an exact answer.",
      }),
    );
    const list = districtList(data, also);
    box.append(list);
    out.append(box);
  }
  return [lon, lat];
}

/** Officials grouped by level (statewide first, courts collapsed). */
function renderGroups(data: Lookup, slugs: Set<string>, out: HTMLElement) {
  const base = import.meta.env.BASE_URL.replace(/\/$/, "");
  for (const g of GROUPS) {
    const members = [...slugs].filter((s) => g.offices.includes(data.directory[s]?.[3]));
    if (!members.length) continue;
    const list = el("ul", { className: "people" });
    for (const s of members.sort((a, b) => data.directory[a][0].localeCompare(data.directory[b][0]))) {
      const [name, office, party, , badges] = data.directory[s];
      const li = el("li");
      li.append(el("a", { href: `${base}/officials/${s}/`, textContent: name }));
      li.append(badgesFor(badges, base));
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

/** Renders the officials at a point; returns the county's district_id, or null when the point isn't in Missouri. */
export function lookup(
  data: Lookup,
  lon: number,
  lat: number,
  out: HTMLElement,
  status: HTMLElement,
): string | null {
  const hits = hitsAt(data, lon, lat);
  out.replaceChildren();
  if (!hits.some((h) => h.district_type === "county")) {
    status.textContent = "That point isn't in Missouri. Try another spot.";
    out.append(el("p", { className: "muted", textContent: "No Missouri districts at that location." }));
    return null;
  }
  const county = hits.find((h) => h.district_type === "county")!;
  status.textContent = `${county.name}: ${hits
    .filter((h) => h.district_type !== "county" && h.district_type !== "place")
    .map((h) => h.name)
    .join(", ")}`;

  renderGroups(
    data,
    new Set([...data.statewide, ...hits.flatMap((h) => data.officials[h.district_id] ?? [])]),
    out,
  );
  return county.district_id;
}

/**
 * The county view for a shared ?county= link: offices that are the same everywhere in the county, then every
 * district that intersects it. Returns the card title, or null for an unknown county.
 */
export function lookupCounty(
  data: Lookup,
  fips: string,
  out: HTMLElement,
  status: HTMLElement,
): string | null {
  const view = countyView(data, fips);
  out.replaceChildren();
  if (!view) return null;
  renderGroups(data, new Set(view.slugs), out);
  const box = el("div", { className: "also" });
  box.append(
    el("h3", { textContent: "Districts in this county" }),
    el("p", {
      className: "small muted",
      textContent:
        "Your State House, State Senate and congressional members depend on where you live in the county. Click the map or enter a ZIP code for your own.",
    }),
  );
  box.append(districtList(data, view.districts));
  out.append(box);
  status.textContent = `${view.title}: ${view.districts.length} legislative and congressional districts reach this county.`;
  return view.title;
}
