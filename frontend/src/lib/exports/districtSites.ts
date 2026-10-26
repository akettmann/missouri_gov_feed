// The full EPA-regulated site list per district (fct_jurisdiction_businesses), kept out of the per-official
// JSON: a U.S. House district holds ~10k sites. Each district gets a plain page and a CSV download.
// The table is read once (one query) and grouped in memory; per-route parquet scans cost minutes.
import { siteKey } from "../siteDonors";
import { siteDonors } from "./businessDonors";
import { districtSlug } from "../siteCsv";
import { hasExport, query } from "./db";
import { allOfficials } from "./load";
import type { SiteRow } from "./types";

export interface DistrictSiteList {
  district_id: string;
  slug: string;
  n_sites: number;
  n_donor_sites: number;
  /** slug of the official the district's rows were built for */
  official_slug: string;
}

interface Loaded {
  /** official_id -> that official's district list */
  lists: Map<string, DistrictSiteList>;
  /** district_id -> its sites, donor-tied first, then by city and name */
  sites: Map<string, SiteRow[]>;
}

let loaded: Promise<Loaded | null> | undefined;

function load(): Promise<Loaded | null> {
  loaded ??= (async () => {
    if (!hasExport("fct_jurisdiction_businesses")) return null;
    const slugs = new Map((await allOfficials()).map((b) => [b.official.official_id, b.official.slug]));
    const donorsBySite = await siteDonors();
    const rows = await query<
      Omit<SiteRow, "donors" | "donor_links"> & { official_id: string; district_id: string }
    >(`
      select official_id, district_id, registry_id, facility_name, address, city, postal_code,
             naics_description, owner_name, parent_company_name, is_donor, matched_by,
             match_confidence, frs_url
      from {fct_jurisdiction_businesses}
      order by district_id, is_donor desc, city, facility_name, frs_url`);

    // Pages are keyed by district but written for one official, so the district <-> official mapping
    // must be 1:1 (the table only guarantees uniqueness on (official_id, district_id)); fail loudly.
    const officialOf = new Map<string, string>();
    const districtOf = new Map<string, string>();
    const sites = new Map<string, SiteRow[]>();
    const seen = new Set<string>();
    for (const { official_id, district_id, ...rest } of rows) {
      const found = donorsBySite.get(siteKey(official_id, rest.registry_id));
      const site: SiteRow = { ...rest, donors: found?.donors ?? [], donor_links: found?.donor_links ?? null };
      for (const [map, key, other, what] of [
        [officialOf, district_id, official_id, "officials"],
        [districtOf, official_id, district_id, "districts"],
      ] as const) {
        const prev = map.get(key);
        if (prev !== undefined && prev !== other) {
          throw new Error(`fct_jurisdiction_businesses: ${key} maps to several ${what} (${prev}, ${other})`);
        }
        map.set(key, other);
      }
      const dup = `${district_id}\t${site.registry_id}`;
      if (seen.has(dup)) throw new Error(`fct_jurisdiction_businesses: duplicate site ${dup}`);
      seen.add(dup);
      const list = sites.get(district_id);
      if (list) list.push(site);
      else sites.set(district_id, [site]);
    }

    const lists = new Map<string, DistrictSiteList>();
    for (const [district_id, official_id] of officialOf) {
      const official_slug = slugs.get(official_id);
      if (!official_slug) {
        throw new Error(
          `fct_jurisdiction_businesses: ${official_id} (${district_id}) is not a profiled official`,
        );
      }
      const list = sites.get(district_id)!;
      lists.set(official_id, {
        district_id,
        slug: districtSlug(district_id),
        n_sites: list.length,
        n_donor_sites: list.filter((s) => s.is_donor).length,
        official_slug,
      });
    }
    return { lists, sites };
  })();
  return loaded;
}

/** official_id -> that official's district list; null when the export is missing. */
export async function districtSiteLists(): Promise<Map<string, DistrictSiteList> | null> {
  return (await load())?.lists ?? null;
}

/** Every site in the district, donor-tied sites first, then by city and name. */
export async function districtSites(districtId: string): Promise<SiteRow[]> {
  return (await load())?.sites.get(districtId) ?? [];
}
