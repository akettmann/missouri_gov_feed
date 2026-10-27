/**
 * Link label for an overlap example's vote source. House roll calls are one PDF per vote; Senate votes only exist
 * inside the day's journal PDF, and the landed data keeps no page per vote (the loader joins the pages' text), so
 * the link opens the day's journal, not the vote. Say so instead of promising "roll call".
 */
export function voteLinkLabel(url: string | null): string {
  return url !== null && /\/Journals\/[^/]+\.pdf/i.test(url) ? "Senate journal for that day" : "roll call";
}

/**
 * "1 most recent bill" / "5 most recent bills", plus "+ 2 recusals" for recused votes listed beyond the recent
 * ones (#154). A recusal already among the recent bills is not counted twice.
 */
export function mostRecentBillsLabel(n: number, extraRecusals = 0): string {
  const base = `${n} most recent ${n === 1 ? "bill" : "bills"}`;
  if (extraRecusals === 0) return base;
  const extra = `${extraRecusals} ${extraRecusals === 1 ? "recusal" : "recusals"}`;
  return n === 0 ? extra : `${base} + ${extra}`;
}

/** The "Recused" cell: a count for Senate votes, an em dash where the source records no recusals (House). */
export function recusedCell(
  recused: number | null,
  senateRollCalls = 0,
  rollCalls = senateRollCalls,
): string {
  if (recused === null) return "—";
  // Mixed chamber: the House votes in roll_calls record no recusals, so say which roll calls the count covers.
  return senateRollCalls < rollCalls ? `${recused} of ${senateRollCalls} Senate` : String(recused);
}

/**
 * The note's two-chamber sentence, or null when the page has no mixed row (Senate-only or House-only members).
 * It quotes the first mixed row's own numbers, so the example is never someone else's data.
 */
export function mixedChamberNote(
  rows: readonly { recused: number | null; senate_roll_calls: number; roll_calls: number }[],
): string | null {
  const mixed = rows.find((r) => r.recused !== null && r.senate_roll_calls < r.roll_calls);
  if (mixed === undefined) return null;
  const cell = recusedCell(mixed.recused, mixed.senate_roll_calls, mixed.roll_calls);
  return `For a legislator who served in both chambers, the count covers only their Senate roll calls ("${cell}").`;
}
