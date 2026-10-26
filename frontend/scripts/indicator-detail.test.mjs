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
  assert.match(src, /indicatorDetailText\(latest\.detail\)/);
  assert.match(src, /indicatorDetailText\(r\.detail\)/);
});
