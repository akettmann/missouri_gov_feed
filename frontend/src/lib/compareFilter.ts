// Which officials the compare pickers offer, given the office filter bar. Pure (runs in the browser).
// The bar narrows the lists to one office group (e.g. the legislature) or one office (e.g. Missouri Senate);
// "All offices" lists everyone, so a deliberate cross-office comparison stays possible.
import { officeGroup } from "./format.ts";

export interface OfficeFilter {
  /** office group key from the tiles; "" = all offices */
  group: string;
  /** office key from the chips; "" = every office in the group */
  office: string;
}

export const ALL_OFFICES: OfficeFilter = { group: "", office: "" };

/** The narrowest filter that still keeps this office's group: used to follow the first pick. */
export function filterForOffice(office: string | undefined): OfficeFilter {
  return office ? { group: officeGroup(office), office: "" } : ALL_OFFICES;
}

export function matchesOffice(office: string, f: OfficeFilter): boolean {
  if (f.office) return office === f.office;
  return !f.group || officeGroup(office) === f.group;
}

/** Officials the pickers list under this filter, in their original order. */
export function filterOfficials<T extends { office: string }>(officials: T[], f: OfficeFilter): T[] {
  return officials.filter((o) => matchesOffice(o.office, f));
}

/**
 * Make a filter coherent, for values that arrive from a URL. An office that does not belong to the group is
 * dropped (the group wins, so the bar and the list agree); an office with no group names its own group.
 */
export function reconcileFilter(f: OfficeFilter): OfficeFilter {
  if (!f.office) return f;
  const g = officeGroup(f.office);
  if (!f.group) return { group: g, office: f.office };
  return g === f.group ? f : { group: f.group, office: "" };
}
