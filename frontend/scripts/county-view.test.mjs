import assert from "node:assert/strict";
import { test } from "node:test";
import { countyView } from "../src/lib/countyView.ts";

const rect = (x0, y0, x1, y1) => [[[x0, y0, x1, y0, x1, y1, x0, y1]]];
const shape = (id, type, name, x0, y0, x1, y1) => ({
  district_id: id,
  district_type: type,
  name,
  bbox: [x0, y0, x1, y1],
  polygons: rect(x0, y0, x1, y1),
});

// A 10x10 world. County A is the left half, county B the right half, county C a small box inside B.
// State house H1 covers x<4 (inside A only), H2 covers 4..6 (spans A and B), H3 covers x>6 (B and all of C).
// One senate district covers everything; congressional district U1 is y<5, U2 is y>=5.
const shapes = [
  shape("county:29001", "county", "A County", 0, 0, 5, 10),
  shape("county:29002", "county", "B County", 5, 0, 10, 10),
  shape("county:29510", "county", "Sample city", 7, 7, 8, 8),
  shape("us_house:119:1", "us_house", "Congressional District 1", 0, 0, 10, 5),
  shape("us_house:119:2", "us_house", "Congressional District 2", 0, 5, 10, 10),
  shape("state_senate:1", "state_senate", "State Senate District 1", 0, 0, 10, 10),
  shape("state_house:1", "state_house", "State House District 1", 0, 0, 4, 10),
  shape("state_house:2", "state_house", "State House District 2", 4, 0, 6, 10),
  shape("state_house:3", "state_house", "State House District 3", 6, 0, 10, 10),
];

const data = {
  shapes,
  statewide: ["gov", "sen-a"],
  officials: {
    "county:29001": ["judge-a"],
    "state_house:2": ["rep-two"],
    "us_house:119:1": ["cong-one"],
    "place:2965000": ["mayor-spencer"],
    "place:2938000": ["mayor-kc"],
  },
  // as fct_county_districts exports it: ordered congressional, senate, house; real overlaps only
  countyDistricts: {
    "county:29001": ["us_house:119:1", "us_house:119:2", "state_senate:1", "state_house:1", "state_house:2"],
    "county:29002": ["us_house:119:1", "state_senate:1", "state_house:2", "state_house:3"],
    "county:29510": ["us_house:119:2", "state_senate:1", "state_house:3"],
  },
  // St. Louis city is a county and a city at once; Kansas City only part of several counties, so it is absent
  countyCities: { "county:29510": ["place:2965000"] },
};

test("view: title uses the data's name, city capitalized", () => {
  assert.equal(countyView(data, "29001").title, "Officials for A County");
  assert.equal(countyView(data, "29510").title, "Officials for Sample City");
  assert.equal(countyView(data, "29999"), null);
});

test("view: same-everywhere offices only (statewide + county-keyed), no point-dependent members", () => {
  const v = countyView(data, "29001");
  assert.deepEqual(v.slugs, ["gov", "sen-a", "judge-a"]);
  assert.ok(!v.slugs.includes("rep-two") && !v.slugs.includes("cong-one"));
});

test("view: districts carry members; empty seats stay listed", () => {
  const v = countyView(data, "29001");
  assert.deepEqual(
    v.districts.map((d) => [d.name, d.members]),
    [
      ["Congressional District 1", ["cong-one"]],
      ["Congressional District 2", []],
      ["State Senate District 1", []],
      ["State House District 1", []],
      ["State House District 2", ["rep-two"]],
    ],
  );
});

test("view: the mayor of a city that is the whole county is county-wide; other cities' mayors are not", () => {
  assert.deepEqual(countyView(data, "29510").slugs, ["gov", "sen-a", "mayor-spencer"]);
  for (const fips of ["29001", "29002"]) assert.ok(!countyView(data, fips).slugs.includes("mayor-kc"));
});

test("view: districts come from the export in its order, with their members", () => {
  const v = countyView(data, "29002");
  assert.deepEqual(
    v.districts.map((d) => d.district_id),
    ["us_house:119:1", "state_senate:1", "state_house:2", "state_house:3"],
  );
  assert.deepEqual(countyView(data, "29002").districts[2].members, ["rep-two"]);
});
