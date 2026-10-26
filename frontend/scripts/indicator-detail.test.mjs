import assert from "node:assert/strict";
import { test } from "node:test";
import { indicatorDetailText } from "../src/lib/indicators.ts";

test("party unity names the chamber and counts with separators", () => {
  assert.equal(
    indicatorDetailText("state_house: 1006 party-line votes"),
    "1,006 party-line votes cast in the Missouri House",
  );
  assert.equal(
    indicatorDetailText("state_senate: 2 party-line votes"),
    "2 party-line votes cast in the Missouri Senate",
  );
  assert.equal(
    indicatorDetailText("us_house: 1 party-line votes"),
    "1 party-line vote cast in the U.S. House",
  );
  assert.equal(
    indicatorDetailText("us_senate: 1234 party-line votes"),
    "1,234 party-line votes cast in the U.S. Senate",
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

test("Shor-McCarty service years get an en dash; unknown and empty pass through", () => {
  assert.equal(
    indicatorDetailText("Shor-McCarty career ideal point; served 2009-2022"),
    "Shor-McCarty career ideal point; served 2009\u20132022",
  );
  assert.equal(indicatorDetailText("something else"), "something else");
  assert.equal(indicatorDetailText(null), "");
});
