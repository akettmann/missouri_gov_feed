// Shared by the home page (build time and its year control) and the static years/<year>/ pages, so both
// name the same offices a past year lacks.
import { pluralOfficeLabel } from "./awardBadges.ts";
import { OFFICE_GROUPS, officeGroup } from "./format.ts";

export type OfficeGroup = { key: string; label: string; offices: (readonly [string, string])[] };

/** Offices of any year, bucketed into the display groups; labels fall back to the shared plural office label, never one holder's title. */
export function buildOfficeGroups(rows: { office: string; office_title?: string | null }[]): OfficeGroup[] {
  const titles = new Map<string, string>();
  for (const o of rows) {
    if (!titles.has(o.office)) titles.set(o.office, pluralOfficeLabel(o.office, o.office_title));
  }
  return [
    ...OFFICE_GROUPS,
    { key: "other", label: "Other offices", offices: {} as Record<string, string> },
  ].flatMap((g) => {
    const offices = [...titles.keys()]
      .filter((o) => officeGroup(o) === g.key)
      .sort((a, b) => {
        const order = Object.keys(g.offices);
        return order.indexOf(a) - order.indexOf(b) || a.localeCompare(b);
      })
      .map((o) => [o, g.offices[o] ?? titles.get(o)!] as const);
    return offices.length ? [{ key: g.key, label: g.label, offices }] : [];
  });
}

/**
 * Labels of the currently held offices a past year has no rows for: the group's label when the whole group is
 * missing, otherwise the individual office labels.
 * @param groups display groups, each with its office keys
 * @param currentOffices office key -> label, for offices held now
 * @param held office keys present in the past year
 */
export function missingOfficeLabels(
  groups: { label: string; offices: string[] }[],
  currentOffices: Record<string, string>,
  held: Set<string>,
): string[] {
  return groups.flatMap(({ label, offices }) => {
    const now = offices.filter((o) => o in currentOffices);
    const gone = now.filter((o) => !held.has(o));
    if (!gone.length) return [];
    return gone.length === now.length ? [label] : gone.map((o) => currentOffices[o]);
  });
}

/** The look-back lede for a past year, shared word for word by the JS year control and the static page. */
export function pastNote(year: string | number, currentYear: string | number, missing: string[]): string {
  return (
    `Everyone recorded as holding these offices at some point in ${year}. Names link to a profile only for ` +
    `people serving now.` +
    (missing.length
      ? ` No ${year} records for: ${missing.join(", ")}; those are listed for ${currentYear} only.`
      : "")
  );
}
