// Bill sponsorship outcomes per House member and session (fct_sponsorship_outcomes): counts from the House's own
// bill actions, each shown with its n. Pure helpers so the wording and the share rule are tested on fixed rows.
import { count, plural, sessionLabel } from "./format.ts";

/** A share is shown as a percent only when at least this many bills were decided; under it, counts only. */
export const MIN_DECIDED_FOR_SHARE = 5;

/** The mart's counts for one member and session (the shares are recomputed here from the counts). */
export interface SponsorshipRow {
  official_id: string;
  session_code: string;
  session_year: number;
  is_session_over: boolean;
  bills_sponsored: number;
  bills_decided: number;
  bills_passed_house: number;
  bills_became_law: number;
  /** the House XML export the actions come from (fct_sponsorship_outcomes.source_url) */
  source_url: string;
}

export interface SponsorshipSession {
  session_code: string;
  session_year: number;
  /** the House's own session name; "session code NNN" if unnamed */
  label: string;
  /** true while the session is still running: pending bills are not counted as decided */
  in_progress: boolean;
  bills_sponsored: number;
  bills_decided: number;
  bills_passed_house: number;
  bills_became_law: number;
  /** whole-percent shares of the decided bills; null when fewer than MIN_DECIDED_FOR_SHARE bills were decided */
  passed_house_pct: number | null;
  became_law_pct: number | null;
  /** one sentence in the issue's words, counts only */
  summary: string;
  source_url: string;
}

/** Whole percent of `part` in `whole`; null under the minimum n (or no bills), so a thin count never reads as a rate. */
export function sharePct(part: number, whole: number): number | null {
  if (whole < MIN_DECIDED_FOR_SHARE) return null;
  return Math.round((part / whole) * 100);
}

/** "Sponsored 12 bills; 3 passed the House; 1 became law", with the decided n and the in-progress state spelled out. */
export function summaryLine(r: SponsorshipRow): string {
  const bills = plural(r.bills_sponsored, "bill", "bills");
  if (r.bills_decided === 0) {
    return `Sponsored ${bills}; none decided yet${r.is_session_over ? "" : " (session in progress)"}`;
  }
  return (
    `Sponsored ${bills}, ${count(r.bills_decided)} decided; ${count(r.bills_passed_house)} passed the House; ` +
    `${count(r.bills_became_law)} became law` +
    (r.is_session_over ? "" : " (session in progress)")
  );
}

/** Per official, newest session first. */
export function buildSponsorshipSessions(
  rows: SponsorshipRow[],
  /** House session names by session code (dim_house_session) */
  names: ReadonlyMap<string, string> = new Map(),
): Map<string, SponsorshipSession[]> {
  const out = new Map<string, SponsorshipSession[]>();
  for (const r of rows) {
    const s: SponsorshipSession = {
      session_code: r.session_code,
      session_year: r.session_year,
      label: sessionLabel("state_house", r.session_code, names.get(r.session_code)),
      in_progress: !r.is_session_over,
      bills_sponsored: r.bills_sponsored,
      bills_decided: r.bills_decided,
      bills_passed_house: r.bills_passed_house,
      bills_became_law: r.bills_became_law,
      passed_house_pct: sharePct(r.bills_passed_house, r.bills_decided),
      became_law_pct: sharePct(r.bills_became_law, r.bills_decided),
      summary: summaryLine(r),
      source_url: r.source_url,
    };
    out.set(r.official_id, [...(out.get(r.official_id) ?? []), s]);
  }
  for (const list of out.values()) list.sort((a, b) => b.session_code.localeCompare(a.session_code));
  return out;
}

/** "3 of 8 decided (38%)" or, under the minimum n, "3 of 4 decided". */
export function countWithShare(part: number, decided: number, pct: number | null): string {
  return `${count(part)} of ${count(decided)}${pct === null ? "" : ` (${pct}%)`}`;
}
