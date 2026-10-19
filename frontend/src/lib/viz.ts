// Chart specs for the profile sections. Each spec turns a bundle into table rows; the server renders the
// table (works without JS) and the client renders the same rows as an Observable Plot chart, re-running
// the spec when "hide possible matches" changes. Pure TS, safe to bundle for the browser.
import type { OfficialBundle } from "./exports/types";
import { count, money } from "./format";
import { DONOR_GROUPS, GIFT_GROUPS, giftGroup, sumBy, withoutMedium } from "./rollups";

type DonorGroup = (typeof DONOR_GROUPS)[number];
type GiftGroup = (typeof GIFT_GROUPS)[number];

export type Row = Record<string, string | number>;
export interface Column {
  key: string;
  label: string;
  money?: boolean;
  num?: boolean;
  /** value is a URL rendered as a "source" link */
  link?: boolean;
}

export interface VizSpec {
  title: string;
  /** stack: x = category axis, series stacked; hbar: one bar per y category */
  kind: "stack" | "hbar";
  x: string;
  y: string;
  series?: string;
  seriesOrder?: string[];
  columns: Column[];
  rows: (b: OfficialBundle, hideMedium: boolean) => Row[];
  /** does hiding medium matches change this spec? */
  usesConfidence: boolean;
  note?: string;
}

const FED_RECEIPT_KINDS = [
  "PAC contributions",
  "individual contributions",
  "party contributions",
  "candidate self-funding",
];
const FED_SIZE_LABEL: Record<string, string> = {
  "0": "Under $200",
  "200": "$200–$499",
  "500": "$500–$999",
  "1000": "$1,000–$1,999",
  "2000": "$2,000+",
};

export const MEDIUM_SUFFIX = " (possible match)";

/** Table cell text; the label's "(possible match)" suffix (needed to keep chart bars distinct) becomes a badge. */
export function cellText(c: Column, r: Row): string {
  const v = r[c.key];
  if (c.money) return money(Number(v));
  if (c.num) return count(Number(v));
  return String(v).replace(MEDIUM_SUFFIX, "");
}

const cmp = (a: Row, b: Row, ...keys: string[]) => {
  for (const k of keys) if (a[k] !== b[k]) return a[k] < b[k] ? -1 : 1;
  return 0;
};

export const VIZ: Record<string, VizSpec> = {
  "donors-by-cycle": {
    title: "Money received by election cycle and donor type",
    kind: "stack",
    x: "cycle",
    y: "total",
    series: "group",
    seriesOrder: [...DONOR_GROUPS],
    usesConfidence: true,
    columns: [
      { key: "cycle", label: "Cycle" },
      { key: "group", label: "Donor type" },
      { key: "total", label: "Total", money: true },
      { key: "count", label: "Contributions", num: true },
    ],
    rows: (b, hide) => {
      const rows = withoutMedium(b.money.cycles.rows, hide);
      const key = (r: (typeof rows)[number]) => `${r.cycle}|${r.donor_group}`;
      const counts = new Map(sumBy(rows, key, (r) => r.contribution_count).map((c) => [c.key, c.total]));
      return sumBy(rows, key, (r) => r.total_amount)
        .map(({ key: k, total }) => {
          const [cycle, group] = String(k).split("|");
          return { cycle, group, total, count: counts.get(k) ?? 0 };
        })
        .sort(
          (a, b) =>
            cmp(a, b, "cycle") ||
            DONOR_GROUPS.indexOf(a.group as DonorGroup) - DONOR_GROUPS.indexOf(b.group as DonorGroup),
        );
    },
  },
  "top-donors": {
    title: "Top donor organizations, all years",
    kind: "hbar",
    x: "total",
    y: "label",
    usesConfidence: true,
    note: "Committees, PACs, businesses and parties. Individual donors are counted in the chart by cycle.",
    columns: [
      { key: "label", label: "Organization" },
      { key: "group", label: "Type" },
      { key: "years", label: "Years" },
      { key: "total", label: "Total", money: true },
      { key: "count", label: "Contributions", num: true },
      { key: "source_url", label: "Source", link: true },
    ],
    rows: (b, hide) =>
      withoutMedium(b.money.top_donors.rows, hide)
        .slice(0, 10)
        .map((r) => ({
          // the same donor can appear twice (a medium and a confirmed match); keep chart bars distinct
          label: r.match_confidence === "medium" ? `${r.donor_name}${MEDIUM_SUFFIX}` : r.donor_name,
          group: r.donor_group,
          years: r.first_year === r.last_year ? String(r.first_year) : `${r.first_year}–${r.last_year}`,
          total: r.total_amount,
          count: r.contribution_count,
          source_url: r.source_url ?? "",
          confidence: r.match_confidence,
        })),
  },
  "fed-receipts": {
    title: "Federal receipts by source and cycle (FEC)",
    kind: "stack",
    x: "cycle",
    y: "total",
    series: "source",
    seriesOrder: FED_RECEIPT_KINDS,
    usesConfidence: false,
    columns: [
      { key: "cycle", label: "Cycle" },
      { key: "source", label: "Source" },
      { key: "total", label: "Total", money: true },
    ],
    rows: (b) =>
      b.money.federal
        .filter(
          (r) => r.aggregate_kind === "cycle total" && FED_RECEIPT_KINDS.includes(r.bucket) && r.total > 0,
        )
        .map((r) => ({ cycle: String(r.cycle), source: r.bucket, total: r.total }))
        .sort(
          (a, b) =>
            cmp(a, b, "cycle") || FED_RECEIPT_KINDS.indexOf(a.source) - FED_RECEIPT_KINDS.indexOf(b.source),
        ),
  },
  "fed-size": {
    title: "Individual contributions by size and cycle (FEC)",
    kind: "stack",
    x: "cycle",
    y: "total",
    series: "band",
    seriesOrder: Object.values(FED_SIZE_LABEL),
    usesConfidence: false,
    note: "Size bands as the FEC API reports them (each band starts at the amount shown).",
    columns: [
      { key: "cycle", label: "Cycle" },
      { key: "band", label: "Size" },
      { key: "total", label: "Total", money: true },
    ],
    rows: (b) =>
      b.money.federal
        .filter((r) => r.aggregate_kind === "by_size")
        .map((r) => ({ cycle: String(r.cycle), band: FED_SIZE_LABEL[r.bucket] ?? r.bucket, total: r.total }))
        .sort(
          (a, b) =>
            cmp(a, b, "cycle") ||
            Object.values(FED_SIZE_LABEL).indexOf(a.band) - Object.values(FED_SIZE_LABEL).indexOf(b.band),
        ),
  },
  "fed-state": {
    title: "Itemized individual contributions from Missouri vs out of state (FEC)",
    kind: "stack",
    x: "cycle",
    y: "total",
    series: "where",
    seriesOrder: ["Missouri", "Out of state"],
    usesConfidence: false,
    columns: [
      { key: "cycle", label: "Cycle" },
      { key: "where", label: "Donor location" },
      { key: "total", label: "Total", money: true },
    ],
    rows: (b) =>
      b.money.federal
        .filter((r) => r.aggregate_kind === "by_state")
        .map((r) => ({ cycle: String(r.cycle), where: r.bucket, total: r.total }))
        .sort((a, b) => cmp(a, b, "cycle", "where")),
  },
  "gifts-by-year": {
    title: "Lobbyist gifts by year and category",
    kind: "stack",
    x: "year",
    y: "total",
    series: "category",
    seriesOrder: [...GIFT_GROUPS],
    usesConfidence: true,
    note: "Missouri's Amendment 1 (December 2018) banned most lobbyist gifts over $5, so totals drop after 2018.",
    columns: [
      { key: "year", label: "Year" },
      { key: "category", label: "Category" },
      { key: "total", label: "Total", money: true },
      { key: "count", label: "Gifts", num: true },
    ],
    rows: (b, hide) => {
      const rows = withoutMedium(b.gifts.rows, hide);
      const key = (r: (typeof rows)[number]) => `${r.year}|${giftGroup(r.expenditure_category)}`;
      const counts = new Map(sumBy(rows, key, (r) => r.gift_count).map((c) => [c.key, c.total]));
      return sumBy(rows, key, (r) => r.total_amount)
        .map(({ key: k, total }) => {
          const [year, category] = String(k).split("|");
          return { year, category, total, count: counts.get(k) ?? 0 };
        })
        .sort(
          (a, b) =>
            cmp(a, b, "year") ||
            GIFT_GROUPS.indexOf(a.category as GiftGroup) - GIFT_GROUPS.indexOf(b.category as GiftGroup),
        );
    },
  },
  "gifts-by-principal": {
    title: "Top lobbyist principals (who the lobbyist works for), all years",
    kind: "hbar",
    x: "total",
    y: "label",
    usesConfidence: true,
    columns: [
      { key: "label", label: "Principal" },
      { key: "years", label: "Years" },
      { key: "total", label: "Total", money: true },
      { key: "count", label: "Gifts", num: true },
      { key: "source_url", label: "Source", link: true },
    ],
    rows: (b, hide) => {
      const rows = withoutMedium(b.gifts.rows, hide);
      const groups = new Map<string, typeof rows>();
      for (const r of rows) {
        const k = `${r.lobbyist_principal}|${r.match_confidence === "medium" ? "medium" : ""}`;
        groups.set(k, [...(groups.get(k) ?? []), r]);
      }
      return [...groups]
        .map(([k, rs]) => {
          const [principal, medium] = k.split("|");
          const years = rs.map((r) => r.year);
          const [lo, hi] = [Math.min(...years), Math.max(...years)];
          return {
            label: medium ? `${principal}${MEDIUM_SUFFIX}` : principal,
            years: lo === hi ? String(lo) : `${lo}–${hi}`,
            total: rs.reduce((s, r) => s + r.total_amount, 0),
            count: rs.reduce((s, r) => s + r.gift_count, 0),
            source_url: rs[0].source_url ?? "",
            confidence: medium || "matched",
          };
        })
        .sort((a, b) => b.total - a.total)
        .slice(0, 10);
    },
  },
};
