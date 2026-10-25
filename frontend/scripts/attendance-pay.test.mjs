import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { coverageNote, dollars, payBasisText, payPerVoteBlocks } from "../src/lib/attendancePay.ts";

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
  dollars_per_vote_attended: 1000,
  ...extra,
});
const noPay = { pay_amount: null, pay_basis: null, pay_source_url: null, dollars_per_vote_attended: null };
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

test("pay basis wording names what the pay is", () => {
  assert.match(payBasisText("gross pay"), /gross pay.*everything paid/);
  assert.match(payBasisText("statutory salary"), /statutory annual salary/);
});

test("the profile section renders the table from the pay rows and links the methodology note", () => {
  const section = readFileSync(new URL("../src/components/SectionVoting.astro", import.meta.url), "utf8");
  assert.match(section, /payPerVoteBlocks\(/);
  assert.match(section, /methodology\/#pay-per-vote/);
});
