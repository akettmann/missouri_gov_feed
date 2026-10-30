import assert from "node:assert/strict";
import { test } from "node:test";
import { coverageGaps, STATUS_SHORT, statusKind } from "../src/lib/format.ts";

const item = (label, status) => ({ key: label, label, status, count: 0 });

test("lists not-public and none-found items, skips available and n/a", () => {
  const g = coverageGaps([
    item("Donations", "available"),
    item(
      "Financial disclosures",
      "not public (MO personal financial disclosure: Sunshine Law request to Missouri Ethics Commission)",
    ),
    item("Court cases", "none found (CourtListener has no Missouri circuit-court cases)"),
    item("Votes", "not applicable"),
    item("Family ties", "none found"),
  ]);
  assert.deepEqual(g.cant, [
    "financial disclosures (MO personal financial disclosure: Sunshine Law request to Missouri Ethics Commission)",
  ]);
  assert.deepEqual(g.none, [
    "court cases (CourtListener has no Missouri circuit-court cases)",
    "family ties",
  ]);
});

test("nothing missing: both lists empty", () => {
  const g = coverageGaps([item("Votes", "available"), item("Court cases", "not applicable")]);
  assert.deepEqual(g, { cant: [], none: [], unrecorded: [] });
});

test("'none recorded' is its own list, with the whole parenthetical", () => {
  const g = coverageGaps([
    item("Voluntary disclosures", "none recorded (no public list exists; we add these by hand)"),
    item("Family ties", "none found"),
  ]);
  assert.deepEqual(g.unrecorded, ["voluntary disclosures (no public list exists; we add these by hand)"]);
  assert.deepEqual(g.none, ["family ties"]);
});

test("a parenthetical with a semicolon is kept whole", () => {
  assert.deepEqual(
    coverageGaps([
      item(
        "Business ties",
        "not public (state disclosures not online; Secretary of State business registry not machine-accessible)",
      ),
    ]).cant,
    [
      "business ties (state disclosures not online; Secretary of State business registry not machine-accessible)",
    ],
  );
});

test("a none-recorded status gets its own kind and cell text, not 'none found'", () => {
  const status = "none recorded (no public list exists; we add these by hand)";
  assert.equal(statusKind(status), "unrecorded");
  assert.equal(STATUS_SHORT[statusKind(status)], "none recorded");
  assert.equal(STATUS_SHORT[statusKind("none found")], "none found");
});
