import assert from "node:assert/strict";
import { test } from "node:test";
import { donorEntries, donorLinkIds, donorLinkLabel, parseDonorLinks } from "../src/lib/donorLinks.ts";

const FEC = "https://www.fec.gov/data/disbursements/?committee_id=C00235739&recipient_name=C00000001";
const MEC = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C221944";

test("MEC links are the receiving (official's) committee, FEC links the donor's gifts to it", () => {
  assert.equal(donorLinkLabel(MEC), "official's committee (MEC)");
  assert.equal(donorLinkLabel(FEC), "donor's gifts to the official's committee (FEC)");
});

test("unknown or missing URL gets a neutral label, never 'reports'", () => {
  assert.equal(donorLinkLabel("https://example.org/x"), "committee page");
  assert.equal(donorLinkLabel(null), "committee page");
});

test("parseDonorLinks gives every donor its own link, keeping MEC and FEC pages apart", () => {
  const raw = [
    `${FEC} AMEREN CORPORATION`,
    `${MEC} AMEREN CORPORATION`,
    "https://www.fec.gov/x AT&T INC.",
  ].join("\n");
  assert.deepEqual(parseDonorLinks(raw), [
    { url: FEC, donor: "AMEREN CORPORATION" },
    { url: MEC, donor: "AMEREN CORPORATION" },
    { url: "https://www.fec.gov/x", donor: "AT&T INC." },
  ]);
});

test("parseDonorLinks splits at the first space so donor names keep theirs", () => {
  assert.deepEqual(parseDonorLinks(`${FEC} Acme Holdings, Inc.`), [
    { url: FEC, donor: "Acme Holdings, Inc." },
  ]);
});

test("parseDonorLinks drops empty input and malformed lines", () => {
  assert.deepEqual(parseDonorLinks(null), []);
  assert.deepEqual(parseDonorLinks(""), []);
  assert.deepEqual(parseDonorLinks([FEC, " AMEREN", `${FEC} `].join("\n")), []);
});

test("donorEntries gives each donor its names and all its pages, in donor_names order", () => {
  const raw = [`${FEC} AMEREN CORPORATION`, `${MEC} AMEREN CORPORATION`].join("\n");
  assert.deepEqual(donorEntries("AMEREN CORPORATION; AT&T INC.", raw), [
    { donor: "AMEREN CORPORATION", urls: [FEC, MEC] },
    { donor: "AT&T INC.", urls: [] },
  ]);
});

test("donorEntries marks a donor with no link line as having no urls (rendered 'no link')", () => {
  assert.deepEqual(donorEntries("ACME", null), [{ donor: "ACME", urls: [] }]);
  assert.deepEqual(donorEntries(null, null), []);
});

test("donorEntries keeps a linked donor missing from donor_names and does not repeat names", () => {
  assert.deepEqual(donorEntries("ACME; ACME", `${FEC} OTHER`), [
    { donor: "ACME", urls: [] },
    { donor: "OTHER", urls: [FEC] },
  ]);
});

test("donorLinkIds gives every link on a row, and every row, a distinct id pair", () => {
  assert.deepEqual(donorLinkIds("site3", 1, 0), { nameId: "site3-d1-name", labelId: "site3-d1-l0" });
  const ids = [];
  for (const prefix of ["site0", "site1"])
    for (let d = 0; d < 2; d++)
      for (let u = 0; u < 2; u++) {
        const { nameId, labelId } = donorLinkIds(prefix, d, u);
        ids.push(labelId);
        if (u === 0) ids.push(nameId);
      }
  assert.equal(new Set(ids).size, ids.length);
  // the name id is shared by a donor's links; the label id is not
  assert.equal(donorLinkIds("p", 0, 0).nameId, donorLinkIds("p", 0, 1).nameId);
  assert.notEqual(donorLinkIds("p", 0, 0).labelId, donorLinkIds("p", 0, 1).labelId);
});

test("a donor with 2+ pages of one kind gets the differing committee id in each label (#268)", () => {
  const f1 = "https://www.fec.gov/data/disbursements/?committee_id=C00001&recipient_name=C00481309";
  const f2 = "https://www.fec.gov/data/disbursements/?committee_id=C00001&recipient_name=C00902783";
  const m1 = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C171365";
  const m2 = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C222315";
  const urls = [f1, f2, m1, m2];
  assert.equal(donorLinkLabel(f1, urls), "donor's gifts to the official's committee (FEC, C00481309)");
  assert.equal(donorLinkLabel(f2, urls), "donor's gifts to the official's committee (FEC, C00902783)");
  assert.equal(donorLinkLabel(m1, urls), "official's committee (MEC, C171365)");
  assert.equal(donorLinkLabel(m2, urls), "official's committee (MEC, C222315)");
  // one page per kind stays unchanged
  assert.equal(donorLinkLabel(f1, [f1, m1]), "donor's gifts to the official's committee (FEC)");
  assert.equal(donorLinkLabel(m1, [f1, m1]), "official's committee (MEC)");
});
