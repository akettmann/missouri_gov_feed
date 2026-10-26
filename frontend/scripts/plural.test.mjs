import assert from "node:assert/strict";
import { test } from "node:test";
import { plural, sitesText } from "../src/lib/businessCounts.ts";

test("plural uses the singular for exactly 1", () => {
  assert.equal(plural(1, "case", "cases"), "1 case");
  assert.equal(plural(0, "case", "cases"), "0 cases");
  assert.equal(plural(2, "case", "cases"), "2 cases");
  assert.equal(plural(1234, "case", "cases"), "1,234 cases");
  assert.equal(sitesText(1), "1 site");
});
