import assert from "node:assert/strict";
import { test } from "node:test";
import {
  cell,
  districtSlug,
  SITE_CSV_HEADER,
  SITE_DONOR_CSV_HEADER,
  sitesCsv,
  sitesDonorsCsv,
} from "../src/lib/siteCsv.ts";

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
  donors: [],
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
  const rows = [site({ facility_name: "=cmd|' /C calc'!A0", address: "+1 Main", donors: ["@x"] })];
  assert.equal(
    sitesCsv(rows).split("\n")[1],
    "1,'=cmd|' /C calc'!A0,'+1 Main,Joplin,64801,Mining,Acme LLC,,false,,,https://example.test/frs?id=1",
  );
  assert.equal(sitesDonorsCsv(rows).split("\n")[1], "1,'=cmd|' /C calc'!A0,'@x,");
});

test("sitesCsv writes the header first, in order, then one line per site", () => {
  const csv = sitesCsv([site(), site({ registry_id: "2", facility_name: "Bob's, Inc." })]);
  const lines = csv.split("\n");
  assert.equal(
    lines[0],
    "registry_id,facility_name,address,city,postal_code,industry,owner_name,parent_company_name," +
      "donor_matched,match_confidence,matched_by,epa_record_url",
  );
  assert.equal(lines[0], SITE_CSV_HEADER.join(","));
  assert.equal(
    lines[1],
    "1,Acme,1 Main St,Joplin,64801,Mining,Acme LLC,,false,,,https://example.test/frs?id=1",
  );
  assert.ok(lines[2].startsWith('2,"Bob\'s, Inc.",'));
  assert.equal(lines.at(-1), "");
});

test("sitesCsv carries the match columns but no donor names or links", () => {
  const csv = sitesCsv([
    site({
      is_donor: true,
      matched_by: "same company",
      donors: ["ACME A", "ACME B"],
      match_confidence: "medium",
      donor_links: "https://example.test/c ACME A\nhttps://example.test/d ACME B",
    }),
  ]);
  assert.equal(
    csv.split("\n")[1],
    "1,Acme,1 Main St,Joplin,64801,Mining,Acme LLC,,true,medium,same company,https://example.test/frs?id=1",
  );
  assert.ok(!csv.includes("ACME"));
});

test("sitesDonorsCsv writes one line per donor name, in order", () => {
  const rows = [
    site({ registry_id: "1", donors: ["ACME A", "ACME B", "ACME C"] }),
    site({ registry_id: "2", facility_name: "Zed" }),
    site({ registry_id: "3", facility_name: "Yak", donors: ["YAK"] }),
  ];
  const lines = sitesDonorsCsv(rows).split("\n");
  assert.equal(lines[0], SITE_DONOR_CSV_HEADER.join(","));
  assert.deepEqual(lines.slice(1), ["1,Acme,ACME A,", "1,Acme,ACME B,", "1,Acme,ACME C,", "3,Yak,YAK,", ""]);
});

test("sitesDonorsCsv writes one line per filing page and keeps a page-less donor", () => {
  const lines = sitesDonorsCsv([
    site({
      donors: ["ACME A", "ACME B", "NO PAGE"],
      donor_links:
        "https://example.test/1 ACME A\nhttps://example.test/2 ACME A\nhttps://example.test/3 ACME B",
    }),
  ]).split("\n");
  assert.deepEqual(lines.slice(1), [
    "1,Acme,ACME A,https://example.test/1",
    "1,Acme,ACME A,https://example.test/2",
    "1,Acme,ACME B,https://example.test/3",
    "1,Acme,NO PAGE,",
    "",
  ]);
});

test("sitesDonorsCsv escapes a donor name that holds ; , or quotes and keeps it whole", () => {
  const csv = sitesDonorsCsv([site({ donors: ["ACME; LLC, THE", 'SAY "HI"'] })]);
  assert.equal(csv.split("\n").slice(1, 3).join("|"), '1,Acme,"ACME; LLC, THE",|1,Acme,"SAY ""HI""",');
});

/** Minimal RFC 4180 reader so the test sees what a spreadsheet sees. */
function parseCsv(text) {
  const rows = [[]];
  let f = "";
  let q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') {
        f += '"';
        i++;
      } else if (c === '"') q = false;
      else f += c;
    } else if (c === '"') q = true;
    else if (c === ",") {
      rows.at(-1).push(f);
      f = "";
    } else if (c === "\n") {
      rows.at(-1).push(f);
      f = "";
      rows.push([]);
    } else f += c;
  }
  rows.pop();
  return rows;
}

test("no generated CSV column packs several values into one cell (#370)", () => {
  const rows = [
    site({
      is_donor: true,
      matched_by: "same name",
      match_confidence: "high",
      donors: ["ACME A", "ACME B", "ACME; LLC"],
      donor_links: "https://example.test/1 ACME A\nhttps://example.test/2 ACME B",
    }),
  ];
  for (const csv of [sitesCsv(rows), sitesDonorsCsv(rows)]) {
    const [header, ...body] = parseCsv(csv);
    assert.ok(body.length >= 1);
    for (const row of body) {
      assert.equal(row.length, header.length);
      row.forEach((v, i) => {
        // ACME; LLC is one donor name as filed; a packed list is "ACME A; ACME B"
        assert.ok(!/ACME [AB]; /.test(v), `${header[i]} packs several donors: ${v}`);
        assert.ok(!v.includes("\n"), `${header[i]} holds several lines: ${JSON.stringify(v)}`);
      });
    }
  }
  assert.ok(!SITE_CSV_HEADER.some((h) => /donor_names|donor_links/.test(h)));
});

test("sitesCsv with no rows is just the header", () => {
  assert.equal(sitesCsv([]), SITE_CSV_HEADER.join(",") + "\n");
});

test("sitesDonorsCsv with no donors is just the header", () => {
  assert.equal(sitesDonorsCsv([site()]), SITE_DONOR_CSV_HEADER.join(",") + "\n");
});
