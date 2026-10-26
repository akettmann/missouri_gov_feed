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

test("donorEntries collapses name variants that share the same pages into one entry (#276)", () => {
  const raw = [`${MEC} SPIRE PAC`, `${MEC} SPIRE POLITICAL ACTION COMMITTEE`, `${FEC} AT&T INC.`].join("\n");
  assert.deepEqual(donorEntries("AT&T INC.; SPIRE PAC; SPIRE POLITICAL ACTION COMMITTEE", raw), [
    { donor: "AT&T INC.", urls: [FEC] },
    { donor: "SPIRE PAC; SPIRE POLITICAL ACTION COMMITTEE", urls: [MEC] },
  ]);
});

test("donorEntries does not merge donors with no link, or with different pages (#276)", () => {
  assert.deepEqual(donorEntries("A; B; C", `${MEC} A\n${FEC} B`), [
    { donor: "A", urls: [MEC] },
    { donor: "B", urls: [FEC] },
    { donor: "C", urls: [] },
  ]);
  assert.deepEqual(donorEntries("A; B", ""), [
    { donor: "A", urls: [] },
    { donor: "B", urls: [] },
  ]);
});

test("donorEntries keeps a comma-joined name as one donor (#276)", () => {
  assert.deepEqual(donorEntries("NETJETS ASSOCIATION OF SHARED AIRCRAFT PILOTS PAC, NJASAP PAC", null), [
    { donor: "NETJETS ASSOCIATION OF SHARED AIRCRAFT PILOTS PAC, NJASAP PAC", urls: [] },
  ]);
});

const M1 = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C171365";
const M2 = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C222315";
const M3 = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C333333";
const lines = (...pairs) => pairs.map(([u, d]) => `${u} ${d}`).join("\n");

test("donorEntries folds a donor whose pages are a subset of another's into it (#342)", () => {
  const raw = lines([M1, "AMEREN MISSOURI PAC"], [M2, "AMEREN MISSOURI PAC"], [M2, "Ameren MO PAC"]);
  assert.deepEqual(donorEntries("AMEREN MISSOURI PAC; Ameren MO PAC", raw), [
    { donor: "AMEREN MISSOURI PAC; Ameren MO PAC", urls: [M1, M2] },
  ]);
  // the subset donor listed first still folds into the superset, keeping donor_names order in the label
  const rev = lines([M2, "Ameren MO PAC"], [M1, "AMEREN MISSOURI PAC"], [M2, "AMEREN MISSOURI PAC"]);
  assert.deepEqual(donorEntries("Ameren MO PAC; AMEREN MISSOURI PAC", rev), [
    { donor: "Ameren MO PAC; AMEREN MISSOURI PAC", urls: [M1, M2] },
  ]);
});

test("donorEntries does not merge partial overlap or chains (#342)", () => {
  // A={M1,M2}, B={M2,M3}: each has a page the other lacks
  const partial = lines([M1, "A"], [M2, "A"], [M2, "B"], [M3, "B"]);
  assert.deepEqual(donorEntries("A; B", partial), [
    { donor: "A", urls: [M1, M2] },
    { donor: "B", urls: [M2, M3] },
  ]);
  // chain A~B~C: A and C share nothing, so none of them join
  const chain = lines([M1, "A"], [M2, "A"], [M2, "B"], [M3, "B"], [M3, "C"], [FEC, "C"]);
  assert.equal(donorEntries("A; B; C", chain).length, 3);
});

test("donorEntries keeps differently sized partial overlaps apart (#342)", () => {
  // A={M1,M2,M3}, B={M3,FEC}: B is smaller but has FEC, which A lacks, so B is not a subset
  const a = lines([M1, "A"], [M2, "A"], [M3, "A"], [M3, "B"], [FEC, "B"]);
  assert.deepEqual(donorEntries("A; B", a), [
    { donor: "A", urls: [M1, M2, M3] },
    { donor: "B", urls: [M3, FEC] },
  ]);
  // A={M1,M2,M3}, B={M2,M4}: B shares M2 only
  const M4 = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C444444";
  const b = lines([M1, "A"], [M2, "A"], [M3, "A"], [M2, "B"], [M4, "B"]);
  assert.deepEqual(donorEntries("A; B", b), [
    { donor: "A", urls: [M1, M2, M3] },
    { donor: "B", urls: [M2, M4] },
  ]);
});

test("donorEntries does not fold into a group whose extra pages include an FEC link (#342)", () => {
  // B={M1} is a subset of A={M1,FEC}, but the FEC link is A's own gifts, not B's
  assert.deepEqual(donorEntries("A; B", lines([M1, "A"], [FEC, "A"], [M1, "B"])), [
    { donor: "A", urls: [M1, FEC] },
    { donor: "B", urls: [M1] },
  ]);
  // an FEC link both share is fine: the extra page is MEC only
  assert.deepEqual(donorEntries("A; B", lines([M1, "A"], [M2, "A"], [FEC, "A"], [M1, "B"], [FEC, "B"])), [
    { donor: "A; B", urls: [M1, M2, FEC] },
  ]);
});

test("donorEntries keeps a subset donor alone when two incomparable donors both contain it (#342)", () => {
  const raw = lines([M1, "A"], [M2, "A"], [M1, "B"], [M3, "B"], [M1, "C"]);
  assert.deepEqual(donorEntries("A; B; C", raw), [
    { donor: "A", urls: [M1, M2] },
    { donor: "B", urls: [M1, M3] },
    { donor: "C", urls: [M1] },
  ]);
});

test("donorEntries folds a nested chain A subset B subset C into C (#342)", () => {
  const raw = lines([M1, "A"], [M1, "B"], [M2, "B"], [M1, "C"], [M2, "C"], [M3, "C"]);
  assert.deepEqual(donorEntries("A; B; C", raw), [{ donor: "A; B; C", urls: [M1, M2, M3] }]);
});

test("donorEntries never folds a donor with no page (#342)", () => {
  assert.deepEqual(donorEntries("A; B", lines([M1, "A"])), [
    { donor: "A", urls: [M1] },
    { donor: "B", urls: [] },
  ]);
});
