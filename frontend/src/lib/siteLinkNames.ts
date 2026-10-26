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

/** Collapse whitespace and strip stray leading/trailing commas, so the name reads cleanly. */
function tidy(part: string): string {
  return part
    .replace(/\s+/g, " ")
    .replace(/^[\s,]+|[\s,]+$/g, "")
    .trim();
}

/** Where a site is, as shown after its name: "ADDRESS, CITY", whichever parts exist ("" when neither). */
export function sitePlace(address: string | null | undefined, city: string | null | undefined): string {
  return [address, city]
    .map((p) => (p ? tidy(p) : ""))
    .filter(Boolean)
    .join(", ");
}

/** What a screen reader hears: case and spacing differences do not make two names distinct. */
const keyOf = (name: string): string => name.toLowerCase();

function duplicateKeys(names: string[]): Set<string> {
  const seen = new Map<string, number>();
  for (const n of names) seen.set(keyOf(n), (seen.get(keyOf(n)) ?? 0) + 1);
  return new Set([...seen].filter(([, c]) => c > 1).map(([k]) => k));
}

/**
 * One accessible-name suffix per site, in order: "for NAME, ADDRESS, CITY". Where that still repeats within
 * the list (compared with whitespace collapsed and case ignored) the registry id is added; if the name still
 * repeats (no id, or the same id) "record N of M" is added, so no two links in the list share a name.
 */
export function siteLinkContexts(sites: SiteLinkParts[]): string[] {
  const base = sites.map((s) =>
    [s.facility_name ?? "unnamed site", s.address, s.city]
      .map((p) => (p ? tidy(p) : ""))
      .filter(Boolean)
      .join(", "),
  );
  const dup1 = duplicateKeys(base);
  const withId = base.map((b, i) => {
    const id = dup1.has(keyOf(b)) ? registryIdOf(sites[i].frs_url) : null;
    return id ? `${b}, registry ID ${tidy(id)}` : b;
  });
  const dup2 = duplicateKeys(withId);
  return withId.map((b, i) => `for ${dup2.has(keyOf(b)) ? `${b}, record ${i + 1} of ${sites.length}` : b}`);
}
