// SAMPLE DATA stand-ins used only when data/exports has no rpt_donor_rollup / rpt_gift_rollup parquet
// (e.g. a fresh environment where the reporting models haven't been built). Same shapes the build derives
// from the real exports. Deterministic per official so rebuilds don't churn, and generated only for
// officials whose real fact tables have rows (n_donations / n_lobbyist_gifts), so nobody gets invented
// activity. Names are deliberately placeholders ("Sample ...") so a screenshot can't pass as real.
import { createHash } from "node:crypto";
import { DONOR_GROUPS } from "../rollups";
import type { DonorCycleRow, GiftRollupRow, TopDonorRow } from "./types";

function rng(seed: string): () => number {
  let a = createHash("sha1").update(seed).digest().readUInt32LE(0);
  return () => {
    // mulberry32
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const pick = <T>(r: () => number, xs: readonly T[]): T => xs[Math.floor(r() * xs.length)];
const round2 = (n: number) => Math.round(n * 100) / 100;
const CYCLES = [2018, 2020, 2022, 2024];

export function sampleDonorCycles(officialId: string): DonorCycleRow[] {
  const r = rng(`cycles:${officialId}`);
  return CYCLES.flatMap((cycle) =>
    DONOR_GROUPS.filter(() => r() < 0.8).map((donor_group) => ({
      cycle,
      donor_group,
      match_confidence: r() < 0.15 ? "medium" : "exact (MEC crosswalk)",
      total_amount: round2(500 + r() * 60000),
      contribution_count: 1 + Math.floor(r() * 200),
    })),
  );
}

export function sampleTopDonors(officialId: string): TopDonorRow[] {
  const r = rng(`donors:${officialId}`);
  return Array.from({ length: 12 }, (_, i) => {
    const first = pick(r, CYCLES) - 1;
    return {
      donor_name: `Sample Organization ${String(i + 1).padStart(2, "0")}`,
      donor_group: pick(r, DONOR_GROUPS.slice(0, 3)),
      match_confidence: r() < 0.15 ? "medium" : "exact (MEC crosswalk)",
      source: "sample",
      source_url: null,
      total_amount: round2(250 + r() ** 2 * 40000),
      contribution_count: 1 + Math.floor(r() * 12),
      first_year: first,
      last_year: Math.min(2025, first + Math.floor(r() * 6)),
    };
  }).sort((a, b) => b.total_amount - a.total_amount);
}

const GIFT_CATEGORIES = ["MEALS, FOOD, & BEVERAGE", "ENTERTAINMENT", "GIFT", "TRAVEL", "OTHER"] as const;

export function sampleGiftRollup(officialId: string): GiftRollupRow[] {
  const r = rng(`gifts:${officialId}`);
  const principals = Array.from({ length: 8 }, (_, i) => ({
    name: `Sample Principal ${String.fromCharCode(65 + i)}`,
    medium: r() < 0.1,
  }));
  const rows: GiftRollupRow[] = [];
  for (let year = 2012 + Math.floor(r() * 6); year <= 2025; year++) {
    for (const p of principals) {
      if (r() > 0.3) continue;
      // meals dominate the real MEC data (~85% of rows), so weight the sample the same way
      const category = r() < 0.8 ? GIFT_CATEGORIES[0] : pick(r, GIFT_CATEGORIES.slice(1));
      const count = 1 + Math.floor(r() * 4);
      rows.push({
        year,
        lobbyist_principal: p.name,
        expenditure_category: category,
        match_confidence: p.medium ? "medium" : "high",
        source: "sample",
        source_url: null,
        total_amount: round2(count * (8 + r() * 60)),
        gift_count: count,
        lobbyist_count: 1,
      });
    }
  }
  return rows;
}
