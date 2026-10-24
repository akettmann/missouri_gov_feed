// Pure math for the attendance chart's "not attended" view (no imports, so node can test it directly).
// Percentages are of the votes on which the official was listed, rounded to one decimal like the export.

const round1 = (n: number) => Math.round(n * 10) / 10;

export interface MissedInput {
  votes_recorded: number;
  absent: number;
  absent_with_leave: number;
  not_voting: number;
  chamber_attendance_pct: number;
}

export interface Missed {
  /** absent or not voting, % of votes recorded */
  unexcused: number;
  /** absent with leave (an excused absence), % of votes recorded */
  excused: number;
  /** the whole chamber's share of votes not attended; the export does not split out its excused absences */
  chamber: number;
}

export function missedShares(r: MissedInput): Missed {
  const share = (n: number) => (r.votes_recorded > 0 ? round1((100 * n) / r.votes_recorded) : 0);
  return {
    unexcused: share(r.absent + r.not_voting),
    excused: share(r.absent_with_leave),
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
