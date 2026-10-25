import assert from "node:assert/strict";
import { test } from "node:test";
import { countyDistricts } from "../src/lib/countyDistricts.ts";
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

test("county -> districts lists every intersecting district, no others, in type order", () => {
  const r = countyDistricts(shapes);
  assert.deepEqual(r["county:29001"], [
    "us_house:119:1",
    "us_house:119:2",
    "state_senate:1",
    "state_house:1",
    "state_house:2",
  ]);
  assert.deepEqual(r["county:29002"], [
    "us_house:119:1",
    "us_house:119:2",
    "state_senate:1",
    "state_house:2",
    "state_house:3",
  ]);
});

test("a small county gets sampled finely enough to land in one district only", () => {
  assert.deepEqual(countyDistricts(shapes)["county:29510"], [
    "us_house:119:2",
    "state_senate:1",
    "state_house:3",
  ]);
});

test("a hole in a district does not count as inside it", () => {
  const donut = shape("state_house:9", "state_house", "Donut", 0, 0, 10, 10);
  donut.polygons = [
    [
      [0, 0, 10, 0, 10, 10, 0, 10],
      [6.5, 6.5, 8.5, 6.5, 8.5, 8.5, 6.5, 8.5],
    ],
  ];
  const city = shape("county:29510", "county", "Sample city", 7, 7, 8, 8);
  assert.deepEqual(countyDistricts([city, donut])["county:29510"], []);
});

const data = {
  shapes,
  statewide: ["gov", "sen-a"],
  officials: {
    "county:29001": ["judge-a"],
    "state_house:2": ["rep-two"],
    "us_house:119:1": ["cong-one"],
  },
  countyDistricts: countyDistricts(shapes),
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

// Bounding boxes overlap but the shapes do not: a triangle (below the diagonal) and a box in the far corner.
const triangle = (id, type, name) => ({
  district_id: id,
  district_type: type,
  name,
  bbox: [0, 0, 10, 10],
  polygons: [[[0, 0, 10, 0, 0, 10]]],
});
test("overlapping bounding boxes are not intersections (district and county side)", () => {
  const corner = shape("county:29003", "county", "Corner County", 8, 8, 10, 10);
  const tri = triangle("state_house:7", "state_house", "Triangle");
  assert.deepEqual(countyDistricts([corner, tri])["county:29003"], []);
  const triCounty = { ...triangle("county:29004", "county", "Tri County") };
  const box = shape("state_house:8", "state_house", "Corner box", 8, 8, 10, 10);
  assert.deepEqual(countyDistricts([triCounty, box])["county:29004"], []);
  const low = shape("state_house:9", "state_house", "Low box", 1, 1, 3, 3);
  assert.deepEqual(countyDistricts([triCounty, low])["county:29004"], ["state_house:9"]);
});
