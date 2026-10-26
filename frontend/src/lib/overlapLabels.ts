/**
 * Link label for an overlap example's vote source. House roll calls are one PDF per vote; Senate votes only exist
 * inside the day's journal PDF, and the landed data keeps no page per vote (the loader joins the pages' text), so
 * the link opens the day's journal, not the vote. Say so instead of promising "roll call".
 */
export function voteLinkLabel(url: string | null): string {
  return url !== null && /\/Journals\/[^/]+\.pdf/i.test(url) ? "Senate journal for that day" : "roll call";
}

/** "1 most recent bill" / "5 most recent bills" */
export function mostRecentBillsLabel(n: number): string {
  return `${n} most recent ${n === 1 ? "bill" : "bills"}`;
}
