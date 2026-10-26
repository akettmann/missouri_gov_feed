// Screen-reader text that tells EPA record links apart. Many facilities share a name (a parcel carrier has
// hundreds of sites), so "EPA record for UNITED PARCEL SERVICE" repeated is not a usable list of links.

export interface SiteLinkParts {
  facility_name: string | null;
  address?: string | null;
  city: string | null;
  frs_url: string | null;
}

/** The registry id in an EPA record URL (`...?p_registry_id=110000123456`), or null. */
export function registryIdOf(frsUrl: string | null): string | null {
  const m = frsUrl?.match(/[?&]p_registry_id=([^&#]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}

/**
 * One accessible-name suffix per site, in order: "for NAME, ADDRESS, CITY". Where that still repeats within
 * the list (same name at the same address or in the same city) the registry id is added, so no two links in
 * the list share a name.
 */
export function siteLinkContexts(sites: SiteLinkParts[]): string[] {
  const base = sites.map((s) =>
    [s.facility_name ?? "unnamed site", s.address, s.city].filter((p) => p && p.trim()).join(", "),
  );
  const seen = new Map<string, number>();
  for (const b of base) seen.set(b, (seen.get(b) ?? 0) + 1);
  return sites.map((s, i) => {
    const id = (seen.get(base[i]) ?? 0) > 1 ? registryIdOf(s.frs_url) : null;
    return `for ${base[i]}${id ? `, registry ID ${id}` : ""}`;
  });
}
