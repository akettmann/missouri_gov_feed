import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// Pins the profile section order (#801): money in first, then what the official holds or receives, then
// sponsorship and votes, ideology near the end. Read from source so the test needs no exports.
const read = (p) => readFileSync(new URL(p, import.meta.url), "utf8");

export const sectionOrder = (page) =>
  [...page.matchAll(/^\s*<(Section[A-Za-z]+)\b/gm)].map((m) => m[1].replace(/^Section/, ""));

export const coverageKeys = (load) => {
  const block = load.match(/export const COVERAGE[^=]*=\s*\[([\s\S]*?)\n\];/);
  return [...block[1].matchAll(/key:\s*"([a-z_]+)"/g)].map((m) => m[1]);
};

test("sectionOrder reads tags in page order (fixed input)", () => {
  assert.deepEqual(sectionOrder("  <SectionB a={1} />\n  <SectionA\n  x />"), ["B", "A"]);
});

test("profile renders sections money-first", () => {
  assert.deepEqual(sectionOrder(read("../src/pages/officials/[slug].astro")), [
    "Money",
    "Gifts",
    "Interests",
    "Businesses",
    "Overlap",
    "Sponsorship",
    "Voting",
    "Committees",
    "Expenses",
    "Ideology",
    "Courts",
  ]);
});

test("coverage strip order matches the page", () => {
  assert.deepEqual(coverageKeys(read("../src/lib/exports/load.ts")), [
    "donations",
    "disclosures",
    "commercial_ties",
    "family_ties",
    "voluntary_disclosures",
    "votes",
    "bias",
    "cases",
  ]);
});
