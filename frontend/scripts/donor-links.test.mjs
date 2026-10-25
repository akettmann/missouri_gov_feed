import assert from "node:assert/strict";
import { test } from "node:test";
import { donorLinkLabel, parseDonorLinks } from "../src/lib/donorLinks.ts";

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
