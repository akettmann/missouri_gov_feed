// Sums the committee-donor trails (rpt_committee_donors) by trail_status, for the summary above the trails in
// the Money section (#803). It covers only the committees listed for the official: each committee's top 10
// non-individual donors plus its summed individuals, not all of the official's money.
// Pure and import-free so node:test can load it.

export interface TrailDonorLike {
  trail_status: string;
  total_amount: number;
}
export interface TrailLike {
  donors: TrailDonorLike[];
}

/** Order the kinds are shown in; the same for every official. */
export const TRAIL_KINDS = [
  "end of trail",
  "not an mec filer",
  "ambiguous mec name",
  "individuals",
  "mec committee",
] as const;
export type TrailKind = (typeof TRAIL_KINDS)[number];

export interface TrailSum {
  kind: TrailKind;
  /** exact dollars (summed as whole cents, so no float drift) */
  amount: number;
  /** donor rows counted, each once */
  rows: number;
}

/**
 * Dollars by trail_status across the given trails, every donor row counted once. Kinds with no rows are left
 * out. A status outside TRAIL_KINDS is not dropped silently: it throws, so a new status in the export fails
 * the build instead of vanishing from the totals.
 */
export function sumByTrailStatus(trails: readonly TrailLike[]): TrailSum[] {
  const cents = new Map<string, { cents: number; rows: number }>();
  for (const t of trails) {
    for (const d of t.donors) {
      if (!(TRAIL_KINDS as readonly string[]).includes(d.trail_status)) {
        throw new Error(`unknown trail_status: ${d.trail_status}`);
      }
      const e = cents.get(d.trail_status) ?? { cents: 0, rows: 0 };
      e.cents += Math.round(d.total_amount * 100);
      e.rows += 1;
      cents.set(d.trail_status, e);
    }
  }
  return TRAIL_KINDS.flatMap((kind) => {
    const e = cents.get(kind);
    return e ? [{ kind, amount: e.cents / 100, rows: e.rows }] : [];
  });
}
