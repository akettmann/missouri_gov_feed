import assert from "node:assert/strict";
import { test } from "node:test";
import {
  countyDistrictId,
  countyFips,
  findHref,
  interiorPoint,
  parseFindParams,
} from "../src/lib/findUrl.ts";

const counties = new Set(["29001", "29510"]);

test("county param parses, whitespace trimmed", () => {
  assert.deepEqual(parseFindParams("?county=29001", counties), { kind: "county", fips: "29001" });
  assert.deepEqual(parseFindParams("?county=%2029510%20", counties), { kind: "county", fips: "29510" });
});

test("invalid or unknown county is invalid, never a lookup", () => {
  for (const v of ["", "abc", "29", "29999", "01001", "29001x", "<script>"]) {
    const r = parseFindParams(`?county=${encodeURIComponent(v)}`, counties);
    assert.equal(r.kind, "invalid", v);
    assert.match(r.message, /county code/);
  }
});

test("zip param", () => {
  assert.deepEqual(parseFindParams("?zip=65101", counties), { kind: "zip", zip: "65101" });
  assert.equal(parseFindParams("?zip=6510", counties).kind, "invalid");
  assert.equal(parseFindParams("?zip=65101a", counties).kind, "invalid");
});

test("no params, unrelated params, county wins over zip", () => {
  assert.deepEqual(parseFindParams("", counties), { kind: "none" });
  assert.deepEqual(parseFindParams("?utm=1", counties), { kind: "none" });
  assert.equal(parseFindParams("?zip=65101&county=29001", counties).kind, "county");
});

test("district id <-> fips", () => {
  assert.equal(countyFips("county:29001"), "29001");
  assert.equal(countyFips("state_house:12"), null);
  assert.equal(countyFips("county:2900"), null);
  assert.equal(countyDistrictId("29001"), "county:29001");
});

test("href is base-aware and round-trips", () => {
  const sel = { kind: "county", fips: "29001" };
  assert.equal(findHref("/", sel), "/find/?county=29001");
  assert.equal(findHref("/missouri_gov_feed", sel), "/missouri_gov_feed/find/?county=29001");
  assert.equal(
    findHref("/missouri_gov_feed/", { kind: "zip", zip: "65101" }),
    "/missouri_gov_feed/find/?zip=65101",
  );
  assert.equal(findHref("/x/", { kind: "none" }), "/x/find/");
  const q = findHref("/missouri_gov_feed/", sel).split("?")[1];
  assert.deepEqual(parseFindParams(`?${q}`, counties), sel);
});

test("href never carries coordinates", () => {
  assert.doesNotMatch(findHref("/", { kind: "county", fips: "29001" }), /lat|lon|\d\.\d/);
});

// L-shaped county: bbox center (1,1) is outside; the point must still be inside.
const L = [[[0, 0, 2, 0, 2, 1, 1, 1, 1, 2, 0, 2]]];
const inL = (_p, x, y) => (x >= 0 && x <= 2 && y >= 0 && y <= 1) || (x >= 0 && x <= 1 && y >= 0 && y <= 2);
test("interiorPoint lands inside a non-convex county", () => {
  const p = interiorPoint(L, inL);
  assert.ok(p && inL(L, p[0], p[1]));
  assert.equal(interiorPoint([], inL), null);
});
