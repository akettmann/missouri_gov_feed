// Chart specs for the profile sections. Each spec turns a bundle into table rows; the server renders the
// table (works without JS) and the client renders the same rows as an Observable Plot chart, re-running
// the spec when "hide possible matches" changes. Pure TS, safe to bundle for the browser.
import type { OfficialBundle } from "./exports/types";
import { count, money, pct, sessionLabel } from "./format";
import { DONOR_GROUPS, GIFT_GROUPS, giftGroup, sumBy, withoutMedium } from "./rollups";

type DonorGroup = (typeof DONOR_GROUPS)[number];
type GiftGroup = (typeof GIFT_GROUPS)[number];

export type Row = Record<string, string | number>;
export interface Column {
  key: string;
  label: string;
  money?: boolean;
  num?: boolean;
  pct?: boolean;
  /** value is a URL rendered as a "source" link */
  link?: boolean;
}

export interface VizSpec {
  title: string;
  /** stack: x = category axis, series stacked; hbar: one bar per y category; dumbbell: per y row, x is the
   *  official value and `x2` a reference (chamber) value on the same 0-100 scale */
  kind: "stack" | "hbar" | "dumbbell" | "hstack";
  /** hstack: wide columns stacked along x, one bar per y row (the table stays wide) */
  stackKeys?: { key: string; label: string }[];
  x2?: string;
  x: string;
  y: string;
  series?: string;
  seriesOrder?: string[];
  columns: Column[];
  rows: (b: OfficialBundle, hideMedium: boolean) => Row[];
  /** does hiding medium matches change this spec? */
  usesConfidence: boolean;
  note?: string;
  /** y is a count, not dollars (axis and tooltip formatting) */
  count?: boolean;
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
  if (c.pct) return pct(Number(v));
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
  "state-size": {
    title: "Contributions from individuals by size and cycle (MEC)",
    kind: "stack",
    x: "cycle",
    y: "total",
    series: "band",
    seriesOrder: Object.values(FED_SIZE_LABEL),
    usesConfidence: true,
    note: "Same bands as the federal chart. MEC itemizes only contributions over $100, so small donors are undercounted.",
    columns: [
      { key: "cycle", label: "Cycle" },
      { key: "band", label: "Size" },
      { key: "total", label: "Total", money: true },
    ],
    rows: (b, hide) => {
      const rows = withoutMedium(b.money.size ?? [], hide);
      const key = (r: (typeof rows)[number]) => `${r.cycle}|${r.band_floor}`;
      return sumBy(rows, key, (r) => r.total_amount)
        .map(({ key: k, total }) => {
          const [cycle, floor] = String(k).split("|");
          return { cycle, band: FED_SIZE_LABEL[floor], total };
        })
        .sort(
          (a, b) =>
            cmp(a, b, "cycle") ||
            Object.values(FED_SIZE_LABEL).indexOf(a.band) - Object.values(FED_SIZE_LABEL).indexOf(b.band),
        );
    },
  },
  "fed-size": {
    title: "Individual contributions by size and cycle (FEC)",
    kind: "stack",
    x: "cycle",
    y: "total",
    series: "band",
    seriesOrder: Object.values(FED_SIZE_LABEL),
    usesConfidence: false,
    note: "Bands as FEC reports them; the smallest includes unitemized contributions, so the bands add up to roughly the cycle's individual total.",
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
  "votes-by-subject": {
    title: "Votes on bills by subject (the 20 subjects with the most roll calls)",
    kind: "hstack",
    x: "n",
    y: "subject",
    stackKeys: [
      { key: "yea", label: "Yea" },
      { key: "nay", label: "Nay" },
      { key: "other", label: "Present / absent" },
    ],
    count: true,
    usesConfidence: false,
    note: "Counts of roll calls on bills carrying each subject term; one roll call can fall under several subjects.",
    columns: [
      { key: "subject", label: "Subject" },
      { key: "roll_calls", label: "Roll calls", num: true },
      { key: "yea", label: "Yea", num: true },
      { key: "nay", label: "Nay", num: true },
      { key: "other", label: "Present / absent", num: true },
    ],
    rows: (b) =>
      (b.voting.by_subject ?? []).map((r) => ({
        subject: r.subject_name.charAt(0) + r.subject_name.slice(1).toLowerCase(),
        roll_calls: r.roll_calls,
        yea: r.yea,
        nay: r.nay,
        other: r.other,
      })),
  },
  "cases-by-year": {
    title: "Cases per year",
    kind: "stack",
    x: "year",
    y: "cases",
    series: "role",
    seriesOrder: ["As judge", "As attorney"],
    count: true,
    usesConfidence: false,
    note: "Counts of cases only. Outcomes aren't summarized: that needs a reviewed method.",
    columns: [
      { key: "year", label: "Year filed" },
      { key: "role", label: "Role" },
      { key: "cases", label: "Cases", num: true },
    ],
    rows: (b) =>
      (b.courts.by_year ?? []).map((r) => ({
        year: String(r.year),
        role: r.role === "judge" ? "As judge" : "As attorney",
        cases: r.cases,
      })),
  },
  attendance: {
    title: "Votes attended per session, against the whole chamber",
    kind: "dumbbell",
    x: "official",
    x2: "chamber",
    y: "session",
    usesConfidence: false,
    note: "● this official · ○ chamber average. Attended = voted yea, nay or present on a recorded vote.",
    columns: [
      { key: "session", label: "Session" },
      { key: "official", label: "Attended", pct: true },
      { key: "chamber", label: "Chamber", pct: true },
      { key: "recorded", label: "Votes", num: true },
      { key: "absent", label: "Absent or not voting", num: true },
      { key: "excused", label: "Absent with leave", num: true },
    ],
    rows: (b) =>
      (b.voting.attendance ?? []).map((r) => ({
        session: sessionLabel(r.chamber, r.session_code),
        official: r.attendance_pct,
        chamber: r.chamber_attendance_pct,
        recorded: r.votes_recorded,
        absent: r.absent + r.not_voting,
        excused: r.absent_with_leave,
      })),
  },
};
