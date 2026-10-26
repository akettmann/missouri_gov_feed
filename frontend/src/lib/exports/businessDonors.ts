// Reads fct_jurisdiction_business_donors once and groups it per facility (#370). Shared by the per-official
// bundles (load.ts) and the district site lists (districtSites.ts).
import { groupSiteDonors, type SiteDonorRow, type SiteDonors } from "../siteDonors";
import { query } from "./db";

let loaded: Promise<Map<string, SiteDonors>> | undefined;

/** (official, facility) -> its donors and filing-page lines; see siteKey. */
export function siteDonors(): Promise<Map<string, SiteDonors>> {
  loaded ??= query<SiteDonorRow>(`
    select official_id, registry_id, donor_name, source_url
    from {fct_jurisdiction_business_donors}
    order by official_id, registry_id, donor_name, source_url`).then(groupSiteDonors);
  // a failed read (stale export) must not stick for the life of an `astro dev` process
  loaded.catch(() => (loaded = undefined));
  return loaded;
}
