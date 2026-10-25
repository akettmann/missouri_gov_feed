import assert from "node:assert/strict";
import { test } from "node:test";
import {
  countyDistrictId,
  countyFips,
  findHref,
  parseFindParams,
  withShareNote,
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

test("share note matches what the written URL does, with a period before it", () => {
  assert.equal(
    withShareNote("Cole County: State House District 3", "county"),
    "Cole County: State House District 3. A shared link to this page shows the whole county.",
  );
  assert.equal(
    withShareNote("ZIP 65101, at its center: Cole County: House 3.", "zip"),
    "ZIP 65101, at its center: Cole County: House 3. A shared link reopens this ZIP.",
  );
  assert.doesNotMatch(withShareNote("x", "zip"), /whole county/);
  assert.doesNotMatch(withShareNote("x", "county"), /reopens this ZIP/);
});
