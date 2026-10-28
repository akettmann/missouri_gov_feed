import assert from "node:assert/strict";
import { test } from "node:test";
import { quotedNames, trailsGiveToEachOther } from "../src/lib/trailNames.ts";

test("names read as a sentence fragment, keeping commas and semicolons inside a name", () => {
  assert.equal(quotedNames([]), "");
  assert.equal(quotedNames(["A PAC"]), '"A PAC"');
  assert.equal(quotedNames(["A PAC", "B; Inc."]), '"A PAC" and "B; Inc."');
  assert.equal(quotedNames(["A", "B, C", "D"]), '"A", "B, C" and "D"');
});

const t = (id, ...donorIds) => ({
  mec_committee_id: id,
  donors: donorIds.map((d) => ({ donor_mec_committee_id: d })),
});

test("the double-count note applies only when a listed committee funds another listed one", () => {
  assert.equal(trailsGiveToEachOther([]), false);
  assert.equal(trailsGiveToEachOther([t("C1", null), t("C2", "C9")]), false);
  assert.equal(trailsGiveToEachOther([t("C1", "C2"), t("C2", null)]), true);
  assert.equal(trailsGiveToEachOther([t("C1", "C1"), t("C2")]), false);
});
