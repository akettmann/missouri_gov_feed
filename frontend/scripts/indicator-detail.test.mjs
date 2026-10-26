import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { indicatorDetailText } from "../src/lib/indicators.ts";

test("party unity names the chamber and counts with separators", () => {
  assert.equal(
    indicatorDetailText("state_house: 1006 party-line votes"),
    "Based on 1,006 votes this official cast on party-line roll calls in the Missouri House",
  );
  assert.equal(
    indicatorDetailText("state_senate: 2 party-line votes"),
    "Based on 2 votes this official cast on party-line roll calls in the Missouri Senate",
  );
  assert.equal(
    indicatorDetailText("us_house: 1 party-line votes"),
    "Based on 1 vote this official cast on party-line roll calls in the U.S. House",
  );
  assert.equal(
    indicatorDetailText("us_senate: 1234 party-line votes"),
    "Based on 1,234 votes this official cast on party-line roll calls in the U.S. Senate",
  );
});

test("party unity states the official's own first-last vote year", () => {
  const d = "state_house: 1006 party-line votes";
  assert.equal(
    indicatorDetailText(d, { first_vote_year: 2017, last_vote_year: 2026 }),
    "Based on 1,006 votes this official cast on party-line roll calls in the Missouri House, 2017–2026",
  );
  assert.equal(
    indicatorDetailText("us_senate: 3 party-line votes", { first_vote_year: 2023, last_vote_year: 2023 }),
    "Based on 3 votes this official cast on party-line roll calls in the U.S. Senate, 2023",
  );
  // missing years (older export) leave the caption as before rather than printing "null"
  assert.equal(
    indicatorDetailText(d, { first_vote_year: null, last_vote_year: null }),
    "Based on 1,006 votes this official cast on party-line roll calls in the Missouri House",
  );
  // years never alter other indicators' captions
  assert.equal(
    indicatorDetailText("Voteview DW-NOMINATE, House 119th Congress", {
      first_vote_year: 2017,
      last_vote_year: 2026,
    }),
    "Voteview DW-NOMINATE, U.S. House, 119th Congress",
  );
});

test("DW-NOMINATE keeps the Congress ordinal as written", () => {
  assert.equal(
    indicatorDetailText("Voteview DW-NOMINATE, House 119th Congress"),
    "Voteview DW-NOMINATE, U.S. House, 119th Congress",
  );
  assert.equal(
    indicatorDetailText("Voteview DW-NOMINATE, Senate 121st Congress"),
    "Voteview DW-NOMINATE, U.S. Senate, 121st Congress",
  );
});

test("Shor-McCarty year range gets an en dash; unknown and empty pass through", () => {
  assert.equal(
    indicatorDetailText(
      "Shor-McCarty career ideal point; in the Shor-McCarty data 2009-2022 (data ends 2022)",
    ),
    "Shor-McCarty career ideal point; in the Shor-McCarty data 2009\u20132022 (data ends 2022)",
  );
  assert.equal(indicatorDetailText("something else"), "something else");
  assert.equal(indicatorDetailText(null), "");
});

test("SectionIdeology renders every indicator detail through the formatter", () => {
  const src = readFileSync(new URL("../src/components/SectionIdeology.astro", import.meta.url), "utf8");
  assert.doesNotMatch(src, /\.detail\s*\}/, "raw .detail rendered; wrap it in indicatorDetailText()");
  assert.match(src, /indicatorDetailText\(latest\.detail, latest\)/);
  assert.match(src, /indicatorDetailText\(r\.detail, r\)/);
});

test("formatter matches the exact Shor-McCarty strings the dbt unit test expects", () => {
  const yml = readFileSync(new URL("../../dbt/models/marts/_marts__unit_tests.yml", import.meta.url), "utf8");
  const details = [...yml.matchAll(/detail: '(Shor-McCarty career ideal point;[^']*)'/g)].map((m) => m[1]);
  assert.ok(details.length >= 2, "dbt unit test no longer expects Shor-McCarty details");
  for (const d of details) {
    const out = indicatorDetailText(d);
    assert.notEqual(out, d, `formatter did not recognise dbt wording: ${d}`);
    assert.equal(out, d.replace(/(\d{4})-(\d{4})/, "$1–$2"));
  }
});
