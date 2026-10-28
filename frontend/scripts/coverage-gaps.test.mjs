import assert from "node:assert/strict";
import { test } from "node:test";
import { coverageGaps } from "../src/lib/format.ts";

const item = (label, status) => ({ key: label, label, status, count: 0 });

test("lists not-public and none-found items, skips available and n/a", () => {
  const g = coverageGaps([
    item("Donations", "available"),
    item(
      "Financial disclosures",
      "not public (MO personal financial disclosure: Sunshine Law request to Missouri Ethics Commission)",
    ),
    item("Court cases", "none found (CourtListener covers appellate + federal courts only)"),
    item("Votes", "not applicable"),
    item("Family ties", "none found"),
  ]);
  assert.deepEqual(g.cant, [
    "financial disclosures (MO personal financial disclosure: Sunshine Law request to Missouri Ethics Commission)",
  ]);
  assert.deepEqual(g.none, [
    "court cases (CourtListener covers appellate + federal courts only)",
    "family ties",
  ]);
});

test("nothing missing: both lists empty", () => {
  const g = coverageGaps([item("Votes", "available"), item("Court cases", "not applicable")]);
  assert.deepEqual(g, { cant: [], none: [] });
});

test("'none recorded' counts as none found", () => {
  assert.deepEqual(
    coverageGaps([item("Voluntary disclosures", "none recorded (no public list exists)")]).none,
    ["voluntary disclosures (no public list exists)"],
  );
});
