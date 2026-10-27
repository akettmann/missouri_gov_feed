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
