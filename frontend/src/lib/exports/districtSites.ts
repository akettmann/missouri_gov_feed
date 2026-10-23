// The full EPA-regulated site list per district (fct_jurisdiction_businesses), kept out of the per-official
// JSON: a U.S. House district holds ~10k sites. Each district gets a plain page and a CSV download.
import { hasExport, query } from "./db";
import { allOfficials } from "./load";

export interface DistrictSiteList {
  district_id: string;
  /** URL-safe form of district_id ("state_house:135" -> "state_house-135") */
  slug: string;
  n_sites: number;
  n_donor_sites: number;
  /** slug of the official the district's rows were built for */
  official_slug: string;
}

export interface SiteRow {
  facility_name: string | null;
  address: string | null;
  city: string | null;
  postal_code: string | null;
  naics_description: string | null;
  owner_name: string | null;
  parent_company_name: string | null;
  is_donor: boolean;
  frs_url: string | null;
}

export const districtSlug = (districtId: string) => districtId.replaceAll(":", "-");

let lists: Promise<Map<string, DistrictSiteList> | null> | undefined;

/** official_id -> that official's district list; null when the export is missing. */
export function districtSiteLists(): Promise<Map<string, DistrictSiteList> | null> {
  lists ??= (async () => {
    if (!hasExport("fct_jurisdiction_businesses")) return null;
    const slugs = new Map((await allOfficials()).map((b) => [b.official.official_id, b.official.slug]));
    const rows = await query<{
      official_id: string;
      district_id: string;
      n_sites: number;
      n_donor_sites: number;
    }>(`
      select official_id, district_id, cast(count(distinct registry_id) as integer) as n_sites,
             cast(count(distinct registry_id) filter (where is_donor) as integer) as n_donor_sites
      from {fct_jurisdiction_businesses} group by 1, 2 order by 2`);
    return new Map(
      rows.flatMap((r) => {
        const official_slug = slugs.get(r.official_id);
        return official_slug
          ? [[r.official_id, { ...r, slug: districtSlug(r.district_id), official_slug }] as const]
          : [];
      }),
    );
  })();
  return lists;
}

/** Every site in the district, donor-tied sites first, then by city and name. */
export async function districtSites(districtId: string): Promise<SiteRow[]> {
  const id = districtId.replaceAll("'", "''");
  return query<SiteRow>(`
    select facility_name, address, city, postal_code, naics_description, owner_name, parent_company_name,
           bool_or(is_donor) as is_donor, frs_url
    from {fct_jurisdiction_businesses} where district_id = '${id}'
    group by all order by is_donor desc, city, facility_name, frs_url`);
}
