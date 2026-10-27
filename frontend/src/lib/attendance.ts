// Pure math for the attendance chart's "not attended" view (no imports, so node can test it directly).
// Percentages are of the votes on which the official was listed, rounded to one decimal like the export.

const round1 = (n: number) => Math.round(n * 10) / 10;

export interface MissedInput {
  votes_recorded: number;
  absent: number;
  absent_with_leave: number;
  not_voting: number;
  recused_from_voting: number;
  chamber_attendance_pct: number;
}

export interface Missed {
  /** absent or not voting, % of votes recorded */
  unexcused: number;
  /** absent with leave (an excused absence), % of votes recorded */
  excused: number;
  /** recused (MO Senate "Excused from voting", a Senate Rule 91 recusal by a member on the floor), % of votes recorded */
  recused: number;
  /** the whole chamber's share of votes not attended; the export does not split out its excused absences */
  chamber: number;
}

/** The stacked segments of the not-attended view, in stacking order (keys are the Missed fields). */
export const MISSED_PARTS = [
  { key: "unexcused", label: "Absent or not voting" },
  { key: "excused", label: "Absent with leave" },
  { key: "recused", label: "Recused" },
] as const;

/**
 * Only the MO Senate journal records leaves of absence and recusals. The House and Congress sources do not, so their
 * zeros mean "not recorded", not "never excused". Attendance cells for those chambers show an em dash (#604).
 */
export function recordsExcusals(chamber: string): boolean {
  return chamber === "state_senate";
}

/** A "leave"/"recused" cell: the formatted value where the chamber records it, an em dash where it does not. */
export function excusalCell(chamber: string, formatted: string): string {
  return recordsExcusals(chamber) ? formatted : "—";
}

/** The column+row decision behind the table cell: only columns flagged `excusal` are dashed, by the row's chamber. */
export function excusalCellFor(
  col: { excusal?: boolean },
  row: { chamberId?: unknown },
  formatted: string,
): string {
  return col.excusal ? excusalCell(String(row.chamberId), formatted) : formatted;
}

/** Public wording for a vote_cast value. Recusals are not absences, so say what they are. */
export function voteCastLabel(voteCast: string): string {
  return voteCast === "recused" ? "recused (Senate Rule 91)" : voteCast;
}

export function missedShares(r: MissedInput): Missed {
  const share = (n: number) => (r.votes_recorded > 0 ? round1((100 * n) / r.votes_recorded) : 0);
  return {
    unexcused: share(r.absent + r.not_voting),
    excused: share(r.absent_with_leave),
    recused: share(r.recused_from_voting),
    chamber: round1(100 - r.chamber_attendance_pct),
  };
}

/** Axis start for the attended view: values cluster near 100%, so start at the nearest 10 below the data. */
export function attendedAxisMin(values: number[]): number {
  return Math.max(0, Math.floor((Math.min(...values) - 2) / 10) * 10);
}

/** Axis end for the not-attended view: values cluster near 0%, so end at the next 5 above the data. */
export function missedAxisMax(values: number[]): number {
  return Math.min(100, Math.max(5, Math.ceil((Math.max(...values) + 1) / 5) * 5));
}
