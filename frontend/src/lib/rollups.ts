// Display grouping over rollup rows. Pure (no Node APIs): used by server-rendered tables and by the
// client charts, so a table and its chart always agree, including when medium matches are hidden.

export function sumBy<T>(
  rows: T[],
  key: (r: T) => string | number,
  value: (r: T) => number,
): { key: string | number; total: number }[] {
  const m = new Map<string | number, number>();
  for (const r of rows) m.set(key(r), (m.get(key(r)) ?? 0) + value(r));
  return [...m].map(([k, total]) => ({ key: k, total }));
}

export const withoutMedium = <T extends { match_confidence: string }>(rows: T[], hide: boolean) =>
  hide ? rows.filter((r) => r.match_confidence !== "medium") : rows;

/**
 * rpt_donor_rollup.donor_class folded to five display groups (the validated categorical palette has five
 * slots). Fixed order: color follows the group, so a hidden series never repaints the rest.
 */
export const DONOR_GROUPS = [
  "PAC",
  "Committees & parties",
  "Business or organization",
  "Individual",
  "Other",
] as const;

/** Same folding as SQL, for the build query (portable CASE). */
export const DONOR_GROUP_SQL = `case donor_class
  when 'pac' then 'PAC'
  when 'committee' then 'Committees & parties'
  when 'candidate committee' then 'Committees & parties'
  when 'party' then 'Committees & parties'
  when 'business or organization' then 'Business or organization'
  when 'individual' then 'Individual'
  else 'Other' end`;

/** MEC's upper-cased expenditure categories folded to five display groups. */
export const GIFT_GROUPS = ["Meals, food & beverage", "Entertainment", "Gift", "Travel", "Other"] as const;
export function giftGroup(category: string): string {
  const c = category.toUpperCase();
  if (c.startsWith("MEALS")) return "Meals, food & beverage";
  if (c === "ENTERTAINMENT") return "Entertainment";
  if (c === "GIFT") return "Gift";
  if (c === "TRAVEL") return "Travel";
  return "Other";
}
