import assert from "node:assert/strict";
import { test } from "node:test";
import { officeLine, yearRanges } from "../src/lib/format.ts";
import { groupPast, linkSameName, normalizeName } from "../src/lib/exports/past.ts";

const slugFor = (name, id) => `${name.toLowerCase().replaceAll(" ", "-")}-${id}`;
const row = (year, official_id, full_name, extra = {}) => ({
  year,
  official_id,
  has_profile: false,
  full_name,
  party: "R",
  level: "state",
  office: "mo_house",
  office_title: null,
  district: "1",
  source: "mo_house roster",
  ...extra,
});

test("yearRanges collapses runs and dedupes", () => {
  assert.equal(yearRanges([2017, 2018, 2019, 2022, 2022, 2024]), "2017–2019, 2022, 2024");
});

test("groupPast groups stints per person, skips the current year, sorts years", () => {
  const rows = [
    row(2024, "a", "Ann Roe"),
    row(2023, "a", "Ann Roe"),
    row(2022, "a", "Ann Roe", { district: "2" }),
  ];
  const { people, years } = groupPast([...rows, row(2025, "z", "Now Person")], 2025, new Map(), slugFor);
  assert.equal(people.length, 1);
  assert.deepEqual(
    people[0].stints.map((s) => s.years),
    [[2023, 2024], [2022]],
  );
  assert.equal(years.has(2025), false);
});

test("groupPast: a slug claimed by a profile cannot be reused by a past person", () => {
  const profiles = new Map([["p1", "ann-roe-b"]]);
  assert.throws(() => groupPast([row(2020, "b", "Ann Roe")], 2025, profiles, () => "ann-roe-b"), /collision/);
});

test("groupPast: two past people on one slug collide", () => {
  assert.throws(
    () => groupPast([row(2020, "b", "A"), row(2020, "c", "B")], 2025, new Map(), () => "same"),
    /collision/,
  );
});

test("normalizeName ignores case, accents, punctuation", () => {
  assert.equal(normalizeName("  José  O'Neil-Smith "), normalizeName("jose o neil smith"));
});

test("linkSameName links exact normalized names only, never merges", () => {
  const { people } = groupPast(
    [row(2020, "a", "Bennie Cook"), row(2019, "b", "Bennie  COOK"), row(2018, "c", "Bennie Cooke")],
    2025,
    new Map(),
    slugFor,
  );
  linkSameName(people, [{ full_name: "Bennie Cook", slug: "bennie-cook-x" }]);
  const [a, b, c] = people;
  assert.deepEqual(
    a.same_name.map((e) => [e.kind, e.slug]),
    [
      ["current", "bennie-cook-x"],
      ["past", b.slug],
    ],
  );
  assert.deepEqual(c.same_name, []);
  assert.equal(people.length, 3);
});

test("officeLine drops the raw court key for federal judges but keeps real districts", () => {
  const judge = {
    office: "us_district_court",
    office_title: "Judge, U.S. District Court for the Eastern District of Missouri",
    district: "moed",
  };
  assert.equal(officeLine(judge), "Judge, U.S. District Court for the Eastern District of Missouri");
  assert.equal(
    officeLine({ office: "mo_house", office_title: "State Representative", district: "12" }),
    "State Representative, district 12",
  );
});
