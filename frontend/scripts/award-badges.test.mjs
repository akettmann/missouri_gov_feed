import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import { test } from "node:test";
import { AWARD_ICONS, currentAwards, metricText, renderBadges } from "../src/lib/awardBadges.ts";
import { AWARD_PAIRS } from "../src/lib/exports/awardDefs.ts";

const e = (slug, rank, metric, streak_years = null, sample_size = 100) => ({
  rank,
  slug,
  metric,
  sample_size,
  streak_years,
});
const list = (award, period, entries) => ({ award, period, entries });

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
  assert.match(m.get("cy")[0][2], /, 2024: /, "the badge says which year it is for");
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

test("no data means no badges", () => {
  assert.equal(currentAwards([]).size, 0);
  assert.equal(renderBadges([], "/x"), "");
});

test("metricText shows the number with what it is out of", () => {
  assert.equal(metricText("highest_attendance", 99.5, 678), "99.5% of 678 votes");
  assert.equal(metricText("most_committee_money", 50000, 80000), "$50,000 of $80,000 raised");
  assert.equal(metricText("most_party_breaks", 12.5, null), "12.5%");
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
    /<span class="sr-only">Award: Highest attendance, 2025: 99.5% of 678 votes; 3 qualifying years in a row<\/span>/,
  );
  assert.equal(html.match(/award-streak/g).length, 2, "X3 and X2 only; no marker on a single year");
  assert.doesNotMatch(html, /aria-label/);
});

test("streaks:false drops the marker everywhere but keeps the spoken award", () => {
  const html = renderBadges(currentAwards(LISTS).get("ann"), "", false);
  assert.doesNotMatch(html, /award-streak|in a row/);
  assert.match(html, /Highest attendance, 2025/);
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
    "pages/awards.astro",
    "pages/districts/[district]/sites.astro",
    "components/PastOfficeholder.astro",
  ])
    assert.match(read(p), /<AwardBadges slug=/, p);
  for (const p of ["scripts/find.ts", "pages/compare.astro", "pages/index.astro"])
    assert.match(read(p), /renderBadges\(/, p);
});
