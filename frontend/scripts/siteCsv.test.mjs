import assert from "node:assert/strict";
import { test } from "node:test";
import { cell, districtSlug, SITE_CSV_HEADER, sitesCsv } from "../src/lib/siteCsv.ts";

const site = (extra = {}) => ({
  registry_id: "1",
  facility_name: "Acme",
  address: "1 Main St",
  city: "Joplin",
  postal_code: "64801",
  naics_description: "Mining",
  owner_name: "Acme LLC",
  parent_company_name: null,
  is_donor: false,
  matched_by: null,
  donor_names: null,
  match_confidence: null,
  donor_links: null,
  frs_url: "https://example.test/frs?id=1",
  ...extra,
});

test("districtSlug replaces colons", () => {
  assert.equal(districtSlug("state_house:135"), "state_house-135");
  assert.equal(districtSlug("us_house:119-7"), "us_house-119-7");
});

test("cell leaves plain values alone and renders null and booleans", () => {
  assert.equal(cell("plain text"), "plain text");
  assert.equal(cell(null), "");
  assert.equal(cell(true), "true");
  assert.equal(cell(false), "false");
  assert.equal(cell(12), "12");
});

test("cell quotes commas, quotes, CR and LF and doubles embedded quotes", () => {
  assert.equal(cell("a,b"), '"a,b"');
  assert.equal(cell('say "hi"'), '"say ""hi"""');
  assert.equal(cell("line1\nline2"), '"line1\nline2"');
  assert.equal(cell("line1\r\nline2"), '"line1\r\nline2"');
  assert.equal(cell("a\rb"), '"a\rb"');
});

test("cell prefixes text that a spreadsheet would run as a formula", () => {
  for (const c of ["=", "+", "-", "@", "\t", "\r"]) {
    const out = cell(`${c}SUM(A1)`);
    assert.ok(out.replace(/^"/, "").startsWith(`'${c}`), `trigger ${JSON.stringify(c)}: ${out}`);
  }
  assert.equal(cell("=1+1"), "'=1+1");
  assert.equal(cell("@SUM(A1)"), "'@SUM(A1)");
  assert.equal(cell("\t=1"), "'\t=1");
  assert.equal(cell('=HYPERLINK("http://x","y")'), '"\'=HYPERLINK(""http://x"",""y"")"');
  assert.equal(cell("\r=1"), '"\'\r=1"');
});

test("cell leaves safe text and real numbers alone and only guards the first character", () => {
  for (const s of [
    "Acme",
    "a=b",
    "a+b",
    "a-b",
    "x@y.test",
    "https://example.test/a?b=-1",
    "",
    " =1",
    "1-2",
  ]) {
    assert.equal(cell(s), s);
  }
  assert.equal(cell(-5), "-5");
  assert.equal(cell(0), "0");
});

test("sitesCsv guards every text column", () => {
  const csv = sitesCsv([
    site({ facility_name: "=cmd|' /C calc'!A0", address: "+1 Main", donor_names: "@x" }),
  ]);
  assert.equal(
    csv.split("\n")[1],
    "'=cmd|' /C calc'!A0,'+1 Main,Joplin,64801,Mining,Acme LLC,,false,,,'@x,,https://example.test/frs?id=1",
  );
});

test("sitesCsv writes the header first, in order, then one line per site", () => {
  const csv = sitesCsv([site(), site({ facility_name: "Bob's, Inc." })]);
  const lines = csv.split("\n");
  assert.equal(
    lines[0],
    "facility_name,address,city,postal_code,industry,owner_name,parent_company_name,donor_matched," +
      "match_confidence,matched_by,donor_names,donor_links,epa_record_url",
  );
  assert.equal(lines[0], SITE_CSV_HEADER.join(","));
  assert.equal(
    lines[1],
    "Acme,1 Main St,Joplin,64801,Mining,Acme LLC,,false,,,,,https://example.test/frs?id=1",
  );
  assert.ok(lines[2].startsWith('"Bob\'s, Inc.",'));
  assert.equal(lines.at(-1), "");
});

test("sitesCsv carries the donor match columns and escapes them", () => {
  const csv = sitesCsv([
    site({
      is_donor: true,
      matched_by: "same company",
      donor_names: 'ACME "HOLDINGS"; ACME, LLC',
      match_confidence: "medium",
      donor_links: "https://example.test/c ACME",
    }),
  ]);
  assert.equal(
    csv.split("\n")[1],
    'Acme,1 Main St,Joplin,64801,Mining,Acme LLC,,true,medium,same company,"ACME ""HOLDINGS""; ACME, LLC",' +
      "https://example.test/c ACME,https://example.test/frs?id=1",
  );
});

test("sitesCsv with no rows is just the header", () => {
  assert.equal(sitesCsv([]), SITE_CSV_HEADER.join(",") + "\n");
});
