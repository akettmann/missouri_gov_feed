import assert from "node:assert/strict";
import { test } from "node:test";
import { sitesText } from "../src/lib/businessCounts.ts";
import { plural } from "../src/lib/format.ts";

test("plural uses the singular for exactly 1", () => {
  assert.equal(plural(1, "case", "cases"), "1 case");
  assert.equal(plural(0, "case", "cases"), "0 cases");
  assert.equal(plural(2, "case", "cases"), "2 cases");
  assert.equal(plural(1234, "case", "cases"), "1,234 cases");
  assert.equal(sitesText(1), "1 site");
});

test("plural words the strings that used to print '1 <plural>'", () => {
  assert.equal(plural(1, "recorded vote", "recorded votes"), "1 recorded vote");
  assert.equal(plural(1, "official", "officials"), "1 official");
  assert.equal(plural(1, "docket", "dockets"), "1 docket");
  assert.equal(plural(1, "contribution", "contributions"), "1 contribution");
  assert.equal(sitesText(2), "2 sites");
});
