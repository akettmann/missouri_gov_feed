// Pure helpers behind the past-officeholder pages. No imports beyond types, so node:test can load this file
// directly (scripts/past.test.mjs) with fixed inputs.
import type { PastOfficeholder, PastPerson, SameNameLink } from "./types";

export interface RosterRow extends Omit<PastOfficeholder, "slug"> {
  year: number;
  official_id: string;
  source: string | null;
  source_url: string | null;
}

/** Shown under the same-name links: the match is on the name alone, so say plainly what is not known. */
export const SAME_NAME_NOTE =
  "Our data does not link these records, so they may or may not be the same person.";

/** What a same-name link points at, as the reader sees it. */
export function sameNameKindLabel(kind: SameNameLink["kind"]): string {
  return kind === "current" ? "current profile" : "past roster entry";
}

/** Name comparison key: case, accents, punctuation and spacing ignored. Used only to offer a cross-link. */
export function normalizeName(name: string): string {
  return name
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function addRoster(person: PastPerson, source: string, url: string | null, year: number): void {
  let entry = person.sources.find((s) => s.source === source);
  if (!entry) person.sources.push((entry = { source, links: [] }));
  let link = entry.links.find((l) => l.url === url);
  if (!link) entry.links.push((link = { url, years: [] }));
  if (!link.years.includes(year)) link.years.push(year);
}

/**
 * Group roster rows (newest year first) into per-year lists plus one small-page record per person without a
 * profile. `profileSlugs` maps official_id -> slug for people with a full profile; `slugFor` makes the rest.
 * Throws if two different ids land on one slug, counting profile slugs too.
 */
export function groupPast(
  rows: RosterRow[],
  currentYear: number,
  profileSlugs: Map<string, string>,
  slugFor: (name: string, id: string) => string,
): { years: Map<number, PastOfficeholder[]>; people: PastPerson[] } {
  const years = new Map<number, PastOfficeholder[]>();
  const people = new Map<string, PastPerson>();
  const claimed = new Map<string, string>(); // slug -> official_id
  for (const [id, slug] of profileSlugs) claimed.set(slug, id);
  for (const { year, official_id, source, source_url, ...r } of rows) {
    if (year === currentYear) continue;
    const known = people.get(official_id);
    const slug = r.has_profile
      ? (profileSlugs.get(official_id) ?? slugFor(r.full_name, official_id))
      : (known?.slug ?? slugFor(r.full_name, official_id));
    if (!r.has_profile) {
      const owner = claimed.get(slug);
      if (owner && owner !== official_id) throw new Error(`slug collision on ${slug}`);
      claimed.set(slug, official_id);
      const person: PastPerson = known ?? {
        slug,
        official_id,
        full_name: r.full_name,
        party: r.party,
        sources: [],
        stints: [],
        same_name: [],
      };
      people.set(official_id, person);
      if (source) addRoster(person, source, source_url, year);
      const stint = person.stints.find(
        (s) => s.office === r.office && s.district === r.district && s.party === r.party,
      );
      if (stint) stint.years.push(year);
      else
        person.stints.push({
          office: r.office,
          office_title: r.office_title,
          level: r.level,
          district: r.district,
          party: r.party,
          years: [year],
        });
    }
    const list = years.get(year);
    const entry = { ...r, slug };
    if (list) list.push(entry);
    else years.set(year, [entry]);
  }
  for (const p of people.values()) {
    for (const s of p.stints) s.years.sort((a, b) => a - b);
    for (const s of p.sources) {
      for (const l of s.links) l.years.sort((a, b) => a - b);
      s.links.sort((a, b) => a.years[0] - b.years[0]);
    }
  }
  return { years, people: [...people.values()] };
}

/**
 * Fill each person's `same_name`: current profiles and other roster entries whose normalized full name is
 * identical. A pointer for the reader, never a claim that they are the same person.
 */
export function linkSameName(people: PastPerson[], current: { full_name: string; slug: string }[]): void {
  const byName = new Map<string, SameNameLink[]>();
  const add = (key: string, e: SameNameLink) => {
    const l = byName.get(key);
    if (l) l.push(e);
    else byName.set(key, [e]);
  };
  for (const c of current) add(normalizeName(c.full_name), { kind: "current", ...c });
  for (const p of people)
    add(normalizeName(p.full_name), { kind: "past", slug: p.slug, full_name: p.full_name });
  for (const p of people)
    p.same_name = (byName.get(normalizeName(p.full_name)) ?? []).filter((e) => e.slug !== p.slug);
}
