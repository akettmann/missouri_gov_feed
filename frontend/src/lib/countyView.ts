// The "county view" behind a shared ?county= link: what is true everywhere in a county (statewide offices, U.S.
// senators, county-keyed courts) plus every legislative/congressional district that touches it. Pure, so tests
// can feed it fixed data.
import { countyDistrictId } from "./findUrl.ts";

export interface CountyViewData {
  shapes: { district_id: string; district_type: string; name: string }[];
  officials: Record<string, string[]>;
  statewide: string[];
  countyDistricts: Record<string, string[]>;
  /** cities whose boundary covers the whole county, so their officials serve everyone in it */
  countyCities: Record<string, string[]>;
}

export interface CountyView {
  title: string;
  /** slugs of officials the same everywhere in the county: statewide, U.S. Senate, county-keyed courts, and the
   * mayor of a city that is the whole county (St. Louis city) */
  slugs: string[];
  /** districts intersecting the county, each with its members' slugs */
  districts: { district_id: string; name: string; members: string[] }[];
}

/** "St. Louis city" -> "St. Louis City"; "Boone County" is left alone. */
const titleCase = (name: string) => name.replace(/ city$/, " City");

export function countyView(data: CountyViewData, fips: string): CountyView | null {
  const id = countyDistrictId(fips);
  const county = data.shapes.find((s) => s.district_id === id);
  if (!county) return null;
  const names = new Map(data.shapes.map((s) => [s.district_id, s.name]));
  return {
    title: `Officials for ${titleCase(county.name)}`,
    slugs: [
      ...new Set([
        ...data.statewide,
        ...(data.officials[id] ?? []),
        ...(data.countyCities[id] ?? []).flatMap((p) => data.officials[p] ?? []),
      ]),
    ],
    districts: (data.countyDistricts[id] ?? []).map((d) => ({
      district_id: d,
      name: names.get(d) ?? d,
      members: data.officials[d] ?? [],
    })),
  };
}
