import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  coverageNote,
  dollars,
  payBasisText,
  payPerVoteBlocks,
  totalWithoutMedium,
} from "../src/lib/attendancePay.ts";

const pay = (chamber, period, extra = {}) => ({
  chamber,
  period,
  calendar_year: period === "covered years" ? null : Number(period),
  voting_years: 1,
  covered_years: 1,
  votes_recorded: 60,
  votes_attended: 50,
  pay_amount: 50000,
  pay_basis: "gross pay",
  pay_source_url: "https://pay.example/",
  match_confidence: "high",
  dollars_per_vote_attended: 1000,
  ...extra,
});
const noPay = {
  match_confidence: null,
  pay_amount: null,
  pay_basis: null,
  pay_source_url: null,
  dollars_per_vote_attended: null,
};
const session = (chamber, first, last) => ({ chamber, first_vote_date: first, last_vote_date: last });

test("the table covers exactly the years of the sessions the chart shows", () => {
  const rows = [
    pay("state_house", "2019"),
    pay("state_house", "2021"),
    pay("state_house", "2022"),
    pay("state_house", "covered years"),
  ];
  // the chart shows only the 2021 and 2022 sessions: the 2019 row must not appear
  const [block] = payPerVoteBlocks(
    [session("state_house", "2021-01-06", "2021-05-14"), session("state_house", "2022-01-05", "2022-05-13")],
    rows,
  );
  assert.deepEqual(
    block.years.map((y) => y.period),
    ["2021", "2022"],
  );
  assert.equal(block.total.period, "covered years");
});

test("a session that crosses New Year gets a row for each year", () => {
  const rows = [pay("us_house", "2023"), pay("us_house", "2024"), pay("us_house", "covered years")];
  const [block] = payPerVoteBlocks([session("us_house", "2023-01-09", "2024-12-20")], rows);
  assert.deepEqual(
    block.years.map((y) => y.calendar_year),
    [2023, 2024],
  );
});

test("one block per chamber in chart order, each with its own rows", () => {
  const rows = [
    pay("state_senate", "2023", { dollars_per_vote_attended: 4000 }),
    pay("state_senate", "covered years"),
    pay("state_house", "2022"),
    pay("state_house", "covered years"),
  ];
  const blocks = payPerVoteBlocks(
    [session("state_house", "2022-01-05", "2022-05-13"), session("state_senate", "2023-01-04", "2023-05-12")],
    rows,
  );
  assert.deepEqual(
    blocks.map((b) => b.chamber),
    ["state_house", "state_senate"],
  );
  assert.equal(blocks[1].years[0].dollars_per_vote_attended, 4000);
});

test("no block when the chamber has no total (no year with pay), and none for a chamber not shown", () => {
  const rows = [
    pay("state_house", "2016", noPay),
    pay("us_senate", "2023"),
    pay("us_senate", "covered years"),
  ];
  assert.deepEqual(payPerVoteBlocks([session("state_house", "2016-01-06", "2016-05-13")], rows), []);
});

test("the basis and source come from a year that has pay", () => {
  const rows = [
    pay("state_house", "2016", noPay),
    pay("state_house", "2017"),
    pay("state_house", "covered years"),
  ];
  const [block] = payPerVoteBlocks([session("state_house", "2016-01-06", "2017-05-12")], rows);
  assert.equal(block.basis, "gross pay");
  assert.equal(block.sourceUrl, "https://pay.example/");
  assert.equal(block.years[0].dollars_per_vote_attended, null);
});

test("dollars shows a dash for a missing figure, never infinity or zero", () => {
  assert.equal(dollars(null), "—");
  assert.equal(dollars(undefined), "—");
  assert.equal(dollars(1000), "$1,000");
  assert.equal(dollars(79.88), "$80");
});

test("coverage note says how many years the total leaves out", () => {
  assert.equal(coverageNote({ covered_years: 3, voting_years: 3 }), "all 3 years with votes");
  assert.equal(coverageNote({ covered_years: 1, voting_years: 1 }), "the 1 year with votes");
  assert.equal(
    coverageNote({ covered_years: 2, voting_years: 4 }),
    "2 of 4 years with votes (the rest have no pay counted)",
  );
});

test("coverage note singular and plural, and what hidden possible matches add", () => {
  assert.equal(
    coverageNote({ covered_years: 0, voting_years: 1 }),
    "0 of 1 year with votes (the rest have no pay counted)",
  );
  assert.equal(
    coverageNote({ covered_years: 0, voting_years: 4 }, true),
    "0 of 4 years with votes (the rest have no pay counted or only a possible match)",
  );
});

test("hiding every possible match keeps all years with votes as the denominator", () => {
  const years = ["2018", "2019", "2020", "2021"].map((y) =>
    pay("state_senate", y, { match_confidence: "medium" }),
  );
  const t = totalWithoutMedium(years);
  assert.deepEqual([t.covered_years, t.voting_years], [0, 4]);
  assert.equal(
    coverageNote(t, true),
    "0 of 4 years with votes (the rest have no pay counted or only a possible match)",
  );
});

test("pay basis wording names what the pay is", () => {
  assert.match(payBasisText("gross pay"), /gross pay.*everything paid/);
  assert.match(payBasisText("statutory salary"), /statutory annual salary/);
});

test("the profile section renders the table from the pay rows and links the methodology note", () => {
  const section = readFileSync(new URL("../src/components/SectionVoting.astro", import.meta.url), "utf8");
  assert.match(section, /payPerVoteBlocks\(/);
  assert.match(section, /methodology\/#pay-per-vote/);
});

test("hiding possible matches recomputes the total from the visible years", () => {
  const years = [
    pay("state_house", "2019", { pay_amount: 10000, votes_attended: 10 }),
    pay("state_house", "2020", { pay_amount: 30000, votes_attended: 10, match_confidence: "medium" }),
    pay("state_house", "2021", { pay_amount: 6000, votes_attended: 4 }),
    pay("state_house", "2016", noPay),
  ];
  const t = totalWithoutMedium(years);
  assert.equal(t.pay_amount, 16000);
  assert.equal(t.votes_attended, 14);
  assert.equal(t.dollars_per_vote_attended, 1142.86);
  // all 4 voting years stay in the denominator; 2 of them (2019, 2021) have pay that is not a possible match
  assert.deepEqual([t.voting_years, t.covered_years], [4, 2]);
});

test("when every year is a possible match the hidden total has no figure", () => {
  const t = totalWithoutMedium([pay("state_house", "2020", { match_confidence: "medium" })]);
  assert.equal(t.pay_amount, null);
  assert.equal(t.dollars_per_vote_attended, null);
});

test("medium years are flagged in the table and the profile has a total without them", () => {
  const section = readFileSync(new URL("../src/components/SectionVoting.astro", import.meta.url), "utf8");
  assert.match(section, /data-confidence=\{y\.match_confidence === "medium"/);
  assert.match(section, /<ConfidenceBadge/);
  assert.match(section, /totalWithoutMedium\(/);
});

test("year rows must add up to the dbt total, else the mismatch names the official", async () => {
  const { payYearsMismatch, payYearsProblems } = await import("../src/lib/attendancePay.ts");
  const att = [
    session("state_house", "2021-01-06", "2021-05-14"),
    session("state_house", "2022-01-05", "2022-05-13"),
  ];
  const two = { voting_years: 2, covered_years: 2 };
  const ok = [
    pay("state_house", "2021"),
    pay("state_house", "2022"),
    pay("state_house", "covered years", two),
  ];
  const [block] = payPerVoteBlocks(att, ok);
  assert.equal(payYearsMismatch(block), null);
  // stale rpt_attendance: the chart lacks 2021, but the total still covers 2021-2022
  const [stale] = payPerVoteBlocks([att[1]], ok);
  assert.match(payYearsMismatch(stale), /1 year rows \(1 with pay\) but the total covers 2 of 2/);
  // a year without pay is fine as long as the total says so
  const gap = [
    pay("state_house", "2021", noPay),
    pay("state_house", "2022"),
    pay("state_house", "covered years", { voting_years: 2, covered_years: 1 }),
  ];
  assert.equal(payYearsMismatch(payPerVoteBlocks(att, gap)[0]), null);
  // covered_years half: right number of year rows, but pay on a different set of years than the total says
  // (rpt_attendance_pay from another build). Row counts match, so only withPay !== covered_years catches it.
  const drifted = [
    pay("state_house", "2021", noPay),
    pay("state_house", "2022"),
    pay("state_house", "covered years", two),
  ];
  assert.match(
    payYearsMismatch(payPerVoteBlocks(att, drifted)[0]),
    /2 year rows \(1 with pay\) but the total covers 2 of 2/,
  );
  const bundle = (name, a) => ({
    official: { full_name: name, official_id: "x" },
    voting: { attendance: a, attendance_pay: ok },
  });
  const problems = payYearsProblems([bundle("Good Person", att), bundle("Bennie Cook", [att[1]])]);
  assert.equal(problems.length, 1);
  assert.match(problems[0], /^Bennie Cook/);
});

test("MOGOV_SKIP_PAY_YEARS_CHECK skips only when exactly 1, and says so", async () => {
  const { payYearsGate, skipPayYearsCheck } = await import("../src/lib/attendancePay.ts");
  const att = [session("state_house", "2022-01-05", "2022-05-13")];
  const rows = [
    pay("state_house", "2021"),
    pay("state_house", "2022"),
    pay("state_house", "covered years", { voting_years: 2, covered_years: 2 }),
  ];
  const bundles = [
    {
      official: { full_name: "Bennie Cook", official_id: "x" },
      voting: { attendance: att, attendance_pay: rows },
    },
  ];
  const logs = [];
  for (const v of ["0", "", "true", undefined]) {
    assert.equal(skipPayYearsCheck({ MOGOV_SKIP_PAY_YEARS_CHECK: v }), false);
    assert.equal(payYearsGate(bundles, { MOGOV_SKIP_PAY_YEARS_CHECK: v }, (m) => logs.push(m)).length, 1);
  }
  assert.deepEqual(logs, []);
  assert.deepEqual(
    payYearsGate(bundles, { MOGOV_SKIP_PAY_YEARS_CHECK: "1" }, (m) => logs.push(m)),
    [],
  );
  assert.equal(logs.length, 1);
  assert.match(logs[0], /MOGOV_SKIP_PAY_YEARS_CHECK=1/);
});
