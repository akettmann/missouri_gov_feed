// Side-by-side rows for the compare page, computed from two per-official bundles. Pure (runs in the browser).
// Every row is one measured or published number; nothing is combined into a score.
import { payPerVote, payPerVoteSources } from "./comparePay.ts";
import { businessCounts, donorsText, plural, sitesText } from "./businessCounts.ts";
import type { OfficialBundle } from "./exports/types";
import { count, HIDE_UNLESS_AVAILABLE, money, pct, statusKind } from "./format.ts";
import { indicatorMeta } from "./indicators.ts";
import { withoutMedium } from "./rollups.ts";

export interface CompareRow {
  section: string;
  label: string;
  /** one cell per official, already formatted; "—" when the measure doesn't apply or isn't available */
  values: string[];
  /** short caveat shown under the label */
  note?: string;
  /** a site path (no base) linked after the note, e.g. the methodology section */
  noteHref?: string;
  /** the text of the noteHref link; required with it, so a row cannot pick up another row's wording */
  noteLinkText?: string;
  /** per official (same order as values): links to where that cell's figure came from */
  valueLinks?: { text: string; href: string; context?: string }[][];
}

const NA = "—";

function indicatorCells(b: OfficialBundle, key: string): string {
  const rows = b.indicators.filter((i) => i.indicator === key && i.value != null);
  if (!rows.length) return NA;
  const current = rows.find((r) => r.detail?.startsWith(`${b.official.office}:`)) ?? rows[0];
  const latest = rows.reduce((a, r) => ((r.period ?? 0) > (a.period ?? 0) ? r : a), current);
  const v = latest.value!;
  const shown = key === "party_unity_pct" ? pct(v) : v.toFixed(2);
  const peer = b.peers.find(
    (p) => p.indicator === key && p.period === latest.period && p.detail === latest.detail,
  );
  if (!peer?.peer_median) return shown;
  const median = key === "party_unity_pct" ? pct(peer.peer_median) : peer.peer_median.toFixed(2);
  return `${shown} (chamber median ${median})`;
}

function attendance(b: OfficialBundle): [string, string] {
  const rows = b.voting.attendance ?? [];
  if (!rows.length) return [NA, NA];
  const recorded = rows.reduce((s, r) => s + r.votes_recorded, 0);
  const present = rows.reduce((s, r) => s + r.votes_present, 0);
  const last = rows[rows.length - 1];
  return [
    recorded ? pct((100 * present) / recorded) : NA,
    `${pct(last.attendance_pct)} (chamber ${pct(last.chamber_attendance_pct)})`,
  ];
}

function moneyCells(b: OfficialBundle, hideMedium: boolean): [string, string, string] {
  const rows = withoutMedium(b.money.cycles.rows, hideMedium);
  if (!rows.length) return [NA, NA, NA];
  const total = rows.reduce((s, r) => s + r.total_amount, 0);
  const lastCycle = Math.max(...rows.map((r) => r.cycle));
  const last = rows.filter((r) => r.cycle === lastCycle).reduce((s, r) => s + r.total_amount, 0);
  // MEC files PACs under "committee", so state money only splits cleanly into committees vs everyone else
  const pac = rows
    .filter((r) => r.donor_group === "PAC" || r.donor_group === "Committees & parties")
    .reduce((s, r) => s + r.total_amount, 0);
  const sample = b.money.cycles.sample ? " (sample data)" : "";
  return [`${money(total)}${sample}`, `${money(last)} (${lastCycle})`, total ? pct((100 * pac) / total) : NA];
}

function giftCells(b: OfficialBundle, hideMedium: boolean): [string, string] {
  const rows = withoutMedium(b.gifts.rows, hideMedium);
  if (!rows.length) return [NA, NA];
  const total = rows.reduce((s, r) => s + r.total_amount, 0);
  const n = rows.reduce((s, r) => s + r.gift_count, 0);
  const byPrincipal = new Map<string, number>();
  for (const r of rows)
    byPrincipal.set(r.lobbyist_principal, (byPrincipal.get(r.lobbyist_principal) ?? 0) + r.total_amount);
  const [top] = [...byPrincipal].sort((x, y) => y[1] - x[1]);
  const sample = b.gifts.sample ? " (sample data)" : "";
  return [`${money(total)} in ${plural(n, "gift", "gifts")}${sample}`, `${top[0]} (${money(top[1])})`];
}

export function compareRows(bundles: OfficialBundle[], hideMedium: boolean): CompareRow[] {
  const each = (f: (b: OfficialBundle) => string) => bundles.map(f);
  const rows: CompareRow[] = [
    { section: "Office", label: "Office", values: each((b) => b.official.office_title ?? b.official.office) },
    { section: "Office", label: "Party", values: each((b) => b.official.party ?? "none listed") },
  ];

  const indicators = [...new Set(bundles.flatMap((b) => b.indicators.map((i) => i.indicator)))];
  for (const key of indicators)
    rows.push({
      section: "Ideology",
      label: indicatorMeta(key).label,
      values: each((b) => indicatorCells(b, key)),
    });

  rows.push({
    section: "Voting",
    label: "Votes against their party (party-line votes)",
    values: each((b) => (b.voting.party_breaks ? count(b.voting.party_breaks.length) : NA)),
  });
  const att = bundles.map(attendance);
  rows.push({ section: "Voting", label: "Attendance, all loaded sessions", values: att.map((a) => a[0]) });
  rows.push({ section: "Voting", label: "Attendance, latest session", values: att.map((a) => a[1]) });

  const pay = bundles.map((b) => payPerVote(b, hideMedium));
  const payNote =
    "Pay divided by votes attended. State officials: gross pay from the state payroll. U.S. Congress: the statutory salary of the office. These are different measures, so compare within one basis.";
  rows.push({
    section: "Voting",
    label: "Pay per vote attended, covered years",
    values: pay.map((x) => x[0]),
    note: payNote,
    noteHref: "/methodology/#pay-per-vote",
    noteLinkText: "How pay per vote is counted",
    valueLinks: bundles.map(payPerVoteSources),
  });
  rows.push({
    section: "Voting",
    label: "Pay per vote attended, latest year with pay",
    values: pay.map((x) => x[1]),
  });

  const m = bundles.map((b) => moneyCells(b, hideMedium));
  rows.push({ section: "Money in", label: "Received, all loaded years", values: m.map((x) => x[0]) });
  rows.push({ section: "Money in", label: "Received, latest cycle", values: m.map((x) => x[1]) });
  rows.push({
    section: "Money in",
    label: "Share from PACs, committees & parties",
    values: m.map((x) => x[2]),
  });

  const g = bundles.map((b) => giftCells(b, hideMedium));
  rows.push({ section: "Lobbyist gifts", label: "Total", values: g.map((x) => x[0]) });
  rows.push({ section: "Lobbyist gifts", label: "Largest principal", values: g.map((x) => x[1]) });

  const biz = bundles.map((b) => businessCounts(b.businesses, hideMedium));
  rows.push({
    section: "Businesses in their area",
    label: "EPA-regulated sites in their district or city",
    values: biz.map((x) => (x ? sitesText(x.totalSites) : NA)),
  });
  rows.push({
    section: "Businesses in their area",
    label: "Donors with sites there (co-occurrence, not influence)",
    values: biz.map((x) => (x ? donorsText(x) : NA)),
    note: "One donor can file under several names, so counts are inferred from matched name groups.",
  });

  // disclosures and commercial ties exist for federal officials only: show a row only if one side has data
  const anyAvailable = (key: string) =>
    bundles.some((b) => statusKind(b.coverage.find((x) => x.key === key)?.status ?? "") === "available");
  if (anyAvailable("commercial_ties"))
    rows.push({
      section: "Personal interests",
      label: "Commercial ties (latest report)",
      values: each((b) =>
        statusKind(b.interests.commercial_ties_status) === "available"
          ? count(b.interests.commercial_ties.length)
          : NA,
      ),
    });
  rows.push({
    section: "Personal interests",
    label: "Family ties",
    values: each((b) => count(b.interests.family_ties.length)),
  });
  for (const c of bundles[0]?.coverage ?? [])
    if (!HIDE_UNLESS_AVAILABLE.includes(c.key) || anyAvailable(c.key))
      rows.push({
        section: "Coverage",
        label: c.label,
        values: each((b) => b.coverage.find((x) => x.key === c.key)?.status ?? NA),
      });
  return rows;
}
