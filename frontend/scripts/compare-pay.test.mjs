import assert from "node:assert/strict";
import { test } from "node:test";
import { payPerVote, payPerVoteSources, yearsLabel } from "../src/lib/comparePay.ts";

const row = (year, extra = {}) => ({
  chamber: "state_house",
  period: String(year),
  calendar_year: year,
  voting_years: 1,
  covered_years: 1,
  votes_recorded: 100,
  votes_attended: 100,
  pay_amount: 50000,
  pay_basis: "gross pay",
  pay_source_url: null,
  match_confidence: "high",
  dollars_per_vote_attended: 500,
  ...extra,
});
const total = (extra = {}) => row(0, { period: "covered years", calendar_year: null, ...extra });
const session = (chamber, first, last) => ({ chamber, first_vote_date: first, last_vote_date: last });
const bundle = (attendance, pay) => ({ voting: { attendance, attendance_pay: pay } });

test("total and latest year name their years and pay basis", () => {
  const b = bundle(
    [session("state_house", "2019-01-10", "2020-05-01")],
    [
      row(2019),
      row(2020, { pay_amount: 60000, dollars_per_vote_attended: 600 }),
      total({ dollars_per_vote_attended: 550 }),
    ],
  );
  assert.deepEqual(payPerVote(b, false), [
    "$550 (2019–2020, state payroll gross pay)",
    "$600 (2020, state payroll gross pay)",
  ]);
});

test("federal pay is labelled as the statutory salary", () => {
  const b = bundle(
    [session("us_house", "2023-01-10", "2023-12-01")],
    [
      row(2023, { chamber: "us_house", pay_basis: "statutory salary", dollars_per_vote_attended: 300 }),
      total({ chamber: "us_house", pay_basis: "statutory salary", dollars_per_vote_attended: 300 }),
    ],
  );
  assert.match(payPerVote(b, false)[0], /federal statutory salary/);
});

test("possible-match years are flagged, then dropped and the total recomputed when hidden", () => {
  const b = bundle(
    [session("state_house", "2019-01-10", "2020-05-01")],
    [
      row(2019),
      row(2020, { match_confidence: "medium", pay_amount: 100000, dollars_per_vote_attended: 1000 }),
      total({ match_confidence: "medium", dollars_per_vote_attended: 750 }),
    ],
  );
  const [shownTotal, shownLatest] = payPerVote(b, false);
  assert.match(shownTotal, /^\$750 \(2019–2020, .*includes possible match\)$/);
  assert.match(shownLatest, /^\$1,000 \(2020, .*possible match\)$/);
  assert.deepEqual(payPerVote(b, true), [
    "$500 (2019, state payroll gross pay)",
    "$500 (2019, state payroll gross pay)",
  ]);
});

test("no pay, no export, or all years hidden gives a dash", () => {
  assert.deepEqual(payPerVote(bundle([], []), false), ["—", "—"]);
  assert.deepEqual(payPerVote(bundle([session("state_house", "2019-01-10", "2019-05-01")], null), false), [
    "—",
    "—",
  ]);
  const b = bundle(
    [session("state_house", "2019-01-10", "2019-05-01")],
    [row(2019, { match_confidence: "medium" }), total({ match_confidence: "medium" })],
  );
  assert.deepEqual(payPerVote(b, true), ["—", "—"]);
});

test("a member of two chambers gets one labelled figure per chamber", () => {
  const b = bundle(
    [session("state_house", "2019-01-10", "2019-05-01"), session("state_senate", "2021-01-10", "2021-05-01")],
    [
      row(2019),
      total(),
      row(2021, { chamber: "state_senate", dollars_per_vote_attended: 700 }),
      total({ chamber: "state_senate", dollars_per_vote_attended: 700 }),
    ],
  );
  const [t] = payPerVote(b, false);
  assert.match(t, /Missouri House: \$500 \(2019/);
  assert.match(t, /Missouri Senate: \$700 \(2021/);
});

test("years run together only when unbroken", () => {
  assert.equal(yearsLabel([2021, 2019, 2022, 2019]), "2019, 2021–2022");
  assert.equal(yearsLabel([2020]), "2020");
});

test("the pay rows' links: note text travels with noteHref, and each official's pay source is linked", async () => {
  const { compareRows } = await import("../src/lib/compare.ts");
  const b = (name, url) => ({
    official: { full_name: name, office: "state_house", office_title: "Rep.", party: "D" },
    indicators: [],
    peers: [],
    voting: {
      status: "available",
      party_breaks: null,
      attendance: [session("state_house", "2019-01-10", "2019-05-01")],
      attendance_pay: [row(2019, { pay_source_url: url }), total({ pay_source_url: url })],
    },
    money: { cycles: { rows: [] } },
    gifts: { rows: [] },
    businesses: null,
    coverage: [],
    interests: { family_ties: [], commercial_ties: [] },
  });
  const rows = compareRows([b("A", "https://pay.example/a"), b("B", null)], false);
  const pay = rows.find((r) => r.label.startsWith("Pay per vote attended, covered"));
  assert.equal(pay.noteHref, "/methodology/#pay-per-vote");
  assert.equal(pay.noteLinkText, "How pay per vote is counted");
  assert.deepEqual(pay.valueLinks, [
    [{ text: "pay source", href: "https://pay.example/a", context: "for A" }],
    [],
  ]);
  // no other row may carry a noteHref without its own link text
  for (const r of rows) if (r.noteHref) assert.ok(r.noteLinkText, r.label);
});

test("pay source links carry the official's name as screen-reader context", () => {
  const b = {
    official: { full_name: "Bennie Cook" },
    ...bundle(
      [session("state_house", "2019-01-10", "2019-05-01")],
      [
        row(2019, { pay_source_url: "https://pay.example/" }),
        total({ pay_source_url: "https://pay.example/" }),
      ],
    ),
  };
  assert.deepEqual(payPerVoteSources(b), [
    { text: "pay source", href: "https://pay.example/", context: "for Bennie Cook" },
  ]);
});
