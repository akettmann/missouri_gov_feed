// Groups the long table fct_jurisdiction_business_donors (one row per official, facility, donor and filing
// page) into what the pages and downloads show per facility: the donors in order, and the filing pages as
// `<url> <donor name>` lines. Pure and import-free so node:test can load it (#370).

export interface SiteDonorRow {
  official_id: string;
  registry_id: string;
  donor_name: string | null;
  /** a filing page of the donor's gifts; null when the donor has none */
  source_url: string | null;
}

export interface SiteDonors {
  /** donor names as filed, in the order given, each once */
  donors: string[];
  /** one `<url> <donor name>` line per donor and page, newline-joined; null when no donor has a page */
  donor_links: string | null;
}

/** map key for one facility of one official */
export const siteKey = (officialId: string, registryId: string) => `${officialId}|${registryId}`;

/**
 * Group rows by (official, facility). Rows must arrive ordered by official, facility, donor name, url (the
 * loader's `order by`): donors and links keep that order, so the pages list them the way the mart's old
 * delimited columns did. A blank donor name is dropped, and so is a link without a url.
 */
export function groupSiteDonors(rows: readonly SiteDonorRow[]): Map<string, SiteDonors> {
  const out = new Map<string, SiteDonors>();
  const lines = new Map<string, string[]>();
  for (const r of rows) {
    const donor = (r.donor_name ?? "").trim();
    if (!donor) continue;
    const key = siteKey(r.official_id, r.registry_id);
    let site = out.get(key);
    if (!site) {
      site = { donors: [], donor_links: null };
      out.set(key, site);
      lines.set(key, []);
    }
    if (!site.donors.includes(donor)) site.donors.push(donor);
    if (r.source_url) lines.get(key)!.push(`${r.source_url} ${donor}`);
  }
  for (const [key, list] of lines) if (list.length) out.get(key)!.donor_links = list.join("\n");
  return out;
}

/** Facility rows of a donor-tied set, grouped under the same donors. */
export interface DonorGroupInput {
  official_id: string;
  registry_id: string;
  donated_amount: number;
}

/**
 * Group an official's donor-tied facilities by their set of donors, in the order a page lists them: largest
 * total first, then by the donors' names, compared name by name (a set that is a prefix of another comes
 * first). The sets are keyed on the JSON of the names array, so no name, whatever characters it holds, can make
 * two different sets collide. `make` builds a group from its first facility; `add` adds each facility to its group.
 */
export function groupBySiteDonors<Row extends DonorGroupInput, Group extends { donated_amount: number }>(
  rows: readonly Row[],
  donorsOf: (row: Row) => readonly string[],
  make: (row: Row, donors: string[]) => Group,
  add: (group: Group, row: Row) => void,
): Map<string, Group[]> {
  const byKey = new Map<string, { group: Group; names: string[] }>();
  const perOfficial = new Map<string, { group: Group; names: string[] }[]>();
  for (const row of rows) {
    const donors = [...donorsOf(row)];
    const key = JSON.stringify([row.official_id, donors]);
    let entry = byKey.get(key);
    if (!entry) {
      entry = { group: make(row, donors), names: donors };
      byKey.set(key, entry);
      const list = perOfficial.get(row.official_id);
      if (list) list.push(entry);
      else perOfficial.set(row.official_id, [entry]);
    }
    add(entry.group, row);
  }
  const out = new Map<string, Group[]>();
  for (const [official, list] of perOfficial) {
    list.sort((a, b) => b.group.donated_amount - a.group.donated_amount || compareNames(a.names, b.names));
    out.set(
      official,
      list.map((e) => e.group),
    );
  }
  return out;
}

/** Name-by-name order; a list that is a prefix of another comes first. */
function compareNames(a: readonly string[], b: readonly string[]): number {
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return a.length - b.length;
}
