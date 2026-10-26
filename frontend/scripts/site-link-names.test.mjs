import assert from "node:assert/strict";
import { test } from "node:test";
import { registryIdOf, siteLinkContexts, sitePlace } from "../src/lib/siteLinkNames.ts";

const url = (id) => `https://frs.example/facility?p_registry_id=${id}`;
const site = (facility_name, address, city, id) => ({ facility_name, address, city, frs_url: url(id) });

test("registryIdOf reads the id from the record url", () => {
  assert.equal(registryIdOf(url("110001")), "110001");
  assert.equal(registryIdOf("https://x.example/?a=1&p_registry_id=7&b=2"), "7");
  assert.equal(registryIdOf(null), null);
  assert.equal(registryIdOf("https://x.example/"), null);
});

test("same-named sites at different addresses get different names", () => {
  const out = siteLinkContexts([
    site("UNITED PARCEL SERVICE", "1 Main St", "Joplin", "1"),
    site("UNITED PARCEL SERVICE", "9 Oak Ave", "Joplin", "2"),
  ]);
  assert.deepEqual(out, [
    "for UNITED PARCEL SERVICE, 1 Main St, Joplin",
    "for UNITED PARCEL SERVICE, 9 Oak Ave, Joplin",
  ]);
});

test("sites identical in name, address and city fall back to the registry id", () => {
  const out = siteLinkContexts([
    site("ACME", "1 Main St", "Joplin", "11"),
    site("ACME", "1 Main St", "Joplin", "22"),
  ]);
  assert.equal(new Set(out).size, 2);
  assert.match(out[0], /registry ID 11$/);
  assert.match(out[1], /registry ID 22$/);
});

test("unique sites do not get a registry id; missing parts are skipped", () => {
  assert.deepEqual(siteLinkContexts([{ facility_name: null, city: null, frs_url: url("5") }]), [
    "for unnamed site",
  ]);
  assert.deepEqual(siteLinkContexts([site("A", null, "Joplin", "1"), site("B", null, "Joplin", "2")]), [
    "for A, Joplin",
    "for B, Joplin",
  ]);
});

test("names differing only by internal spacing or case count as duplicates", () => {
  const out = siteLinkContexts([
    site("ACME", "1  Main", "Joplin", "11"),
    site("acme", "1 Main", "Joplin", "22"),
  ]);
  assert.equal(new Set(out).size, 2);
  assert.match(out[0], /registry ID 11$/);
  assert.match(out[1], /registry ID 22$/);
  assert.ok(out.every((n) => !/\s{2}/.test(n)));
});

test("stray commas and whitespace are trimmed from each part", () => {
  assert.deepEqual(siteLinkContexts([site("BUTTERBALL,", " 28802 HWY 43 ", "BRONAUGH", "1")]), [
    "for BUTTERBALL, 28802 HWY 43, BRONAUGH",
  ]);
});

test("duplicates without a usable registry id fall back to record N of M", () => {
  const out = siteLinkContexts([
    { facility_name: "ACME", city: "Joplin", frs_url: null },
    { facility_name: "ACME", city: "Joplin", frs_url: null },
    site("ACME", null, "Joplin", "9"),
    site("ACME", null, "Joplin", "9"),
  ]);
  assert.equal(new Set(out).size, 4);
  assert.match(out[0], /record 1 of 4$/);
  assert.match(out[1], /record 2 of 4$/);
});

test("sitePlace joins the address and city that exist, tidied", () => {
  assert.equal(sitePlace("1 Main St", "Joplin"), "1 Main St, Joplin");
  assert.equal(sitePlace(null, "Joplin"), "Joplin");
  assert.equal(sitePlace("900 WATSON DR,", "BRONAUGH"), "900 WATSON DR, BRONAUGH");
  assert.equal(sitePlace("  ", null), "");
  assert.equal(sitePlace(undefined, undefined), "");
});
