import assert from "node:assert/strict";
import { test } from "node:test";
import { donorLinkLabel } from "../src/lib/donorLinks.ts";

test("MEC links are the receiving (official's) committee, FEC links the donor's", () => {
  assert.equal(
    donorLinkLabel("https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C221944"),
    "official's committee (MEC)",
  );
  assert.equal(
    donorLinkLabel("https://www.fec.gov/data/disbursements/?committee_id=C00235739&recipient_name=C00000001"),
    "donor's gifts to this committee (FEC)",
  );
});

test("unknown or missing URL gets a neutral label, never 'reports'", () => {
  assert.equal(donorLinkLabel("https://example.org/x"), "committee page");
  assert.equal(donorLinkLabel(null), "committee page");
});
