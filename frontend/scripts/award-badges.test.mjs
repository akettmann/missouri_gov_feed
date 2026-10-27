import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  AWARD_ICONS,
  OFFICE_GROUP_LABELS,
  currentAwards,
  metricText,
  ordinal,
  renderBadges,
} from "../src/lib/awardBadges.ts";
import { AWARD_PAIRS, AWARDS, assertCyclePeriods } from "../src/lib/exports/awardDefs.ts";

const e = (slug, rank, metric, streak_years = null, sample_size = 100) => ({
  rank,
  slug,
  metric,
  sample_size,
  streak_years,
});
const list = (
  award,
  period,
  entries,
  office = "state_house",
  group_size = 62,
  period_kind = period === "lifetime" ? "lifetime" : "year",
) => ({
  award,
  office,
  period,
  period_kind,
  group_size,
  entries,
});

const LISTS = [
  list("highest_attendance", "2024", [e("old-timer", 1, 99, 5)]),
  list("highest_attendance", "2025", [e("ann", 1, 99.5, 3, 678), e("bob", 2, 99, 1, 678)]),
  list("highest_attendance", "lifetime", [e("zed", 1, 98)]),
  list("most_committee_money", "2025", [e("ann", 2, 50000, 2, 80000)]),
  list("lowest_attendance", "2025", [e("ann", 1, 60, null, 678)]),
  list("most_committee_money", "2024", [e("old-timer", 1, 1000, 1)]),
  // no 2025 list for this award (thin field): its newest ranked year, 2024, is the current one
  list("least_committee_money_share", "2024", [e("cy", 1, 3, 2, 900)]),
  list("least_committee_money_share", "2023", [e("dee", 1, 2, 1, 900)]),
  list("most_party_breaks", "lifetime", [e("zed", 1, 12.5, 4)]),
];

test("current awards are each award's latest yearly list; lifetime only for awards with no yearly list", () => {
  const m = currentAwards(LISTS);
  assert.deepEqual([...m.keys()].sort(), ["ann", "bob", "cy", "zed"]);
  assert.equal(m.has("old-timer"), false, "superseded years are not current");
  assert.equal(m.has("dee"), false);
  assert.match(m.get("cy")[0][2], / in 2024: /, "the badge says which year it is for");
  assert.deepEqual(
    m.get("bob").map((b) => b[0]),
    ["highest_attendance"],
  );
  // zed's lifetime attendance is ignored (attendance has yearly lists); party breaks is lifetime-only
  assert.deepEqual(
    m.get("zed").map((b) => b[0]),
    ["most_party_breaks"],
  );
});

test("awards are ordered like the awards page, not by rank or input order", () => {
  const order = currentAwards(LISTS)
    .get("ann")
    .map((b) => b[0]);
  assert.deepEqual(order, ["lowest_attendance", "highest_attendance", "most_committee_money"]);
  const all = AWARD_PAIRS.flat();
  assert.ok(order.every((a, i) => i === 0 || all.indexOf(order[i - 1]) < all.indexOf(a)));
});

test("streak comes from the yearly row and is never set for lifetime awards", () => {
  const m = currentAwards(LISTS);
  assert.equal(m.get("ann").find((b) => b[0] === "highest_attendance")[1], 3);
  assert.equal(m.get("ann").find((b) => b[0] === "lowest_attendance")[1], null);
  assert.equal(m.get("zed")[0][1], null, "lifetime row keeps no streak even if the data carries one");
});

test("an official ranked under two offices keeps the better rank once", () => {
  const m = currentAwards([
    list("highest_attendance", "2025", [e("ann", 4, 90, 1)]),
    list("highest_attendance", "2025", [e("ann", 2, 95, 2)]),
  ]);
  assert.equal(m.get("ann").length, 1);
  assert.equal(m.get("ann")[0][1], 2);
});

test("the latest period is chosen per award AND office, so one office's newer year doesn't hide another's", () => {
  const m = currentAwards([
    list("highest_attendance", "2026", [e("rep", 3, 99.6, 1, 561)], "state_house", 62),
    list("highest_attendance", "2025", [e("us-rep", 1, 99, 1, 400)], "us_house", 8),
    list("highest_attendance", "2024", [e("us-old", 1, 98, 1, 400)], "us_house", 8),
    // one office has yearly lists, another only a lifetime list, for the same award
    list("most_committee_money", "2024", [e("judge-a", 1, 5000, 1, 9000)], "associate_circuit_judge", 20),
    list("most_committee_money", "lifetime", [e("judge-b", 1, 7000, null, 9000)], "circuit_judge", 10),
    list("most_committee_money", "lifetime", [e("judge-a", 2, 1, null, 9)], "associate_circuit_judge", 20),
  ]);
  assert.equal(m.get("rep")[0][0], "highest_attendance");
  assert.equal(m.get("us-rep")?.[0][0], "highest_attendance", "us_house keeps its own latest year, 2025");
  assert.match(m.get("us-rep")[0][2], / in 2025: /);
  assert.equal(m.has("us-old"), false, "an office's superseded year is still not current");
  assert.equal(m.get("judge-b")?.[0][0], "most_committee_money", "lifetime-only office is kept");
  assert.match(m.get("judge-b")[0][2], /across all loaded years/);
  assert.match(m.get("judge-a")[0][2], / in 2024: /, "yearly list beats that office's own lifetime list");
});

test("badge text names the award, rank, group and office; rank is not always 'highest'", () => {
  const m = currentAwards(
    [list("highest_attendance", "2026", [e("rep", 3, 99.6, 1, 561)], "state_house", 62)],
    (o) => (o === "state_house" ? "State Representatives" : o),
  );
  assert.equal(
    currentAwards([list("most_committee_money", "2026", [e("p", 1, 5, 1, 9)])]).get("p")[0][2],
    "PAC Magnet (most money from PACs, committees & parties), ranked 1st of 62 state_house in 2026: $5.00 of $9.00 raised",
    "only the first letter of the plain title is lower-cased",
  );
  assert.equal(
    m.get("rep")[0][2],
    "Never Misses a Vote (highest attendance), ranked 3rd of 62 State Representatives in 2026: 99.6% of 561 votes",
  );
});

test("ordinals", () => {
  const got = [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 112].map(ordinal);
  assert.deepEqual(got, [
    "1st",
    "2nd",
    "3rd",
    "4th",
    "11th",
    "12th",
    "13th",
    "21st",
    "22nd",
    "23rd",
    "101st",
    "112th",
  ]);
});

test("no data means no badges", () => {
  assert.equal(currentAwards([]).size, 0);
  assert.equal(renderBadges([], "/x"), "");
});

test("metricText shows the number with what it is out of", () => {
  assert.equal(metricText("highest_attendance", 99.5, 678), "99.5% of 678 votes");
  assert.equal(metricText("most_committee_money", 50000, 80000), "$50,000 of $80,000 raised");
  assert.equal(metricText("most_party_breaks", 12.5, null), "12.5%");
  assert.equal(metricText("most_party_breaks", 30.8, 26), "30.8% with party, of 26 party-line votes");
});

test("badge HTML: icon and X marker aria-hidden, same words as sr-only text, link to the award key", () => {
  const html = renderBadges(currentAwards(LISTS).get("ann"), "/gov");
  assert.match(html, /^<span class="award-badges">/);
  assert.equal(html.match(/<a class="award-badge"/g).length, 3);
  assert.match(html, /href="\/gov\/awards\/#highest_attendance"/);
  assert.match(html, /<span class="award-icon" aria-hidden="true">△<\/span>/);
  assert.match(html, /<span class="award-streak" aria-hidden="true">X3<\/span>/);
  assert.match(
    html,
    /<span class="sr-only">Award: Never Misses a Vote \(highest attendance\), ranked 1st of 62 state_house in 2025: 99.5% of 678 votes; 3 qualifying years in a row<\/span>/,
  );
  assert.equal(html.match(/award-streak/g).length, 2, "X3 and X2 only; no marker on a single year");
  assert.doesNotMatch(html, /aria-label/);
});

test("streaks:false drops the marker everywhere but keeps the spoken award", () => {
  const html = renderBadges(currentAwards(LISTS).get("ann"), "", false);
  assert.doesNotMatch(html, /award-streak|in a row/);
  assert.match(html, /Never Misses a Vote \(highest attendance\), ranked 1st of 62 state_house in 2025/);
});

test("every award on the awards page has a placeholder icon, and text is escaped", () => {
  for (const a of AWARD_PAIRS.flat()) assert.ok(AWARD_ICONS[a], a);
  const html = renderBadges([["highest_attendance", null, 'x"><script>']], '/a"b');
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /href="\/a&quot;b\/awards/);
});

test("every page or script that renders an official's name draws badges through the shared code", () => {
  const read = (p) => readFileSync(new URL(`../src/${p}`, import.meta.url), "utf8");
  for (const p of [
    "pages/officials/[slug].astro",
    "pages/index.astro",
    "pages/years/[year].astro",
    "pages/districts/[district]/sites.astro",
    "components/PastOfficeholder.astro",
  ])
    assert.match(read(p), /<AwardBadges slug=/, p);
  for (const p of ["scripts/find.ts", "pages/compare.astro", "pages/index.astro"])
    assert.match(read(p), /renderBadges\(/, p);
  // a row on /awards already is an award listing: repeating every badge on every hidden block bloated the page
  assert.doesNotMatch(read("pages/awards.astro"), /AwardBadges/);
});

test("plural office label is circuit-free and does not depend on which judge came last", async () => {
  const { pluralOfficeLabel, singularOfficeLabel } = await import("../src/lib/awardBadges.ts");
  const a = pluralOfficeLabel("mo_circuit_judge");
  const b = pluralOfficeLabel("mo_circuit_judge");
  assert.equal(a, "Circuit Judges");
  assert.equal(a, b);
  assert.equal(pluralOfficeLabel("mo_associate_circuit_judge"), "Associate Circuit Judges");
  assert.equal(pluralOfficeLabel("state_senate"), "State Senators");
  assert.equal(singularOfficeLabel("mo_associate_circuit_judge"), "Associate Circuit Judge");
  assert.equal(singularOfficeLabel("secretary_of_state"), "Secretary of State");
});

test("unknown office is labelled from the key's words only", async () => {
  const { pluralOfficeLabel } = await import("../src/lib/awardBadges.ts");
  assert.equal(pluralOfficeLabel("new_judge"), "New Judges");
  assert.equal(pluralOfficeLabel("county_clerk"), "County Clerks");
  assert.equal(pluralOfficeLabel("kc_mayor"), "Kc Mayors");
  // known crude plural: not worth a real pluralizer; map the key in OFFICE_GROUP_LABELS instead
  assert.equal(pluralOfficeLabel("appeals_east"), "Appeals Easts");
});

test("every office key in dim_official has a plural label", (t) => {
  const dir = process.env.MOGOV_EXPORTS ?? path.join(process.cwd(), "..", "data", "exports");
  const file = path.join(dir, "dim_official.csv");
  if (!existsSync(file)) {
    t.skip("no exports at MOGOV_EXPORTS");
    return;
  }
  const [head, ...lines] = readFileSync(file, "utf8").trim().split(/\r?\n/);
  const col = head.split(",").indexOf("office");
  assert.ok(col >= 0);
  const keys = new Set();
  for (const l of lines) {
    // dim_official quotes fields containing commas; walk the line honouring quotes.
    const f = [];
    let cur = "";
    let q = false;
    for (const ch of l) {
      if (ch === '"') q = !q;
      else if (ch === "," && !q) {
        f.push(cur);
        cur = "";
      } else cur += ch;
    }
    f.push(cur);
    if (f[col]) keys.add(f[col]);
  }
  assert.ok(keys.size > 5, "found office keys");
  const missing = [...keys].filter((k) => !(k in OFFICE_GROUP_LABELS));
  assert.deepEqual(missing, []);
});

test("buildOfficeGroups labels an unmapped office from its key words, never a holder's title", async () => {
  const { buildOfficeGroups } = await import("../src/lib/lookback.ts");
  const groups = buildOfficeGroups([
    { office: "mo_circuit_judge", office_title: "Circuit Judge, 22 Judicial Circuit" },
    { office: "county_clerk", office_title: "County Clerk, 7 Judicial Circuit" },
    { office: "county_clerk", office_title: "County Clerk, 9 Judicial Circuit" },
    { office: "kc_mayor", office_title: "Mayor of Kansas City" },
  ]);
  assert.deepEqual(groups.find((g) => g.key === "other").offices, [
    ["county_clerk", "County Clerks"],
    ["kc_mayor", "Kc Mayors"],
  ]);
  assert.deepEqual(groups.find((g) => g.key === "state_courts").offices, [
    ["mo_circuit_judge", "Circuit judges"],
  ]);
});

test("federal money-share badges say the FEC cycle and count cycles, not years", () => {
  const lists = [
    list("least_committee_money_share", "2026", [e("rep", 1, 4, 3, 900000)], "us_house", 10, "fec_cycle"),
    list("least_committee_money_share", "2026", [e("st", 1, 4, 3, 9000)], "state_house"),
  ];
  const awards = currentAwards(lists, (o) => o);
  const fed = awards.get("rep")[0];
  assert.match(fed[2], /in the 2025–26 cycle:/);
  assert.doesNotMatch(fed[2], /in 2026/);
  const html = renderBadges([fed], "");
  assert.match(html, /3 qualifying cycles in a row/);
  assert.doesNotMatch(html, /qualifying years/);
  const state = awards.get("st")[0];
  assert.match(state[2], /in 2026:/);
  assert.match(renderBadges([state], ""), /3 qualifying years in a row/);
});

test("federal calendar-year awards (attendance, most money) stay in years", () => {
  const awards = currentAwards(
    [list("most_committee_money", "2026", [e("rep", 1, 5, 2, 9)], "us_house", 10)],
    (o) => o,
  );
  assert.match(awards.get("rep")[0][2], /in 2026:/);
});

test("a federal money-share list on an odd period (stale export) fails the build with a clear message", () => {
  const ok = [
    { office: "us_house", period: "2024", period_kind: "fec_cycle" },
    { office: "us_senate", period: "lifetime", period_kind: "lifetime" },
    { office: "state_house", period: "2025", period_kind: "year" },
    { office: "us_house", period: "2025", period_kind: "year" },
  ];
  assert.doesNotThrow(() => assertCyclePeriods(ok));
  assert.throws(
    () => assertCyclePeriods([...ok, { office: "us_house", period: "2025", period_kind: "fec_cycle" }]),
    /stale or inconsistent.*us_house 2025.*re-export/s,
  );
});

test("most_bills_passed_house is a one-award row that says exactly what it counts", () => {
  assert.ok(
    AWARD_PAIRS.some((p) => p.length === 1 && p[0] === "most_bills_passed_house"),
    "no fewest-passed opposite: that end would be a tie at 0% (#603)",
  );
  assert.equal(AWARDS.fewest_bills_passed_house, undefined);
  const { note, title, unit, outOf } = AWARDS.most_bills_passed_house;
  assert.equal(unit, "pct");
  assert.equal(outOf, "decided bills");
  assert.match(title, /sponsored House bills \(HB, HJR\) that passed the House/);
  for (const words of [
    /HB/,
    /HJR/,
    /primary sponsor/,
    /have ended/,
    /Appropriation bills are included/,
    /at least 10/,
  ]) {
    assert.match(note, words);
  }
  assert.ok(AWARD_ICONS.most_bills_passed_house, "has a badge icon");
});

test("a most_bills_passed_house badge states the share and what it is out of", () => {
  const m = currentAwards(
    [list("most_bills_passed_house", "2026", [e("amy", 1, 50, 2, 10)])],
    (o) => OFFICE_GROUP_LABELS[o],
  );
  const [award, streak, detail] = m.get("amy")[0];
  assert.equal(award, "most_bills_passed_house");
  assert.equal(streak, 2);
  assert.match(detail, /ranked 1st of 62 State Representatives in 2026: 50\.0% of 10 decided bills$/);
});
