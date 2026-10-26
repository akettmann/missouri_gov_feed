import assert from "node:assert/strict";
import { test } from "node:test";
import { groupBySiteDonors, groupSiteDonors, siteKey } from "../src/lib/siteDonors.ts";

const FEC = "https://www.fec.gov/data/disbursements/?committee_id=C1&recipient_name=C9";
const MEC = "https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=C221944";
const row = (registry_id, donor_name, source_url, official_id = "o1") => ({
  official_id,
  registry_id,
  donor_name,
  source_url,
});

test("groupSiteDonors lists each donor once and one `<url> <donor>` line per page, in row order", () => {
  const got = groupSiteDonors([
    row("F1", "ACME HOLDINGS INC", FEC),
    row("F1", "AMEREN CORPORATION", FEC),
    row("F1", "AMEREN CORPORATION", MEC),
  ]);
  assert.deepEqual(got.get(siteKey("o1", "F1")), {
    donors: ["ACME HOLDINGS INC", "AMEREN CORPORATION"],
    donor_links: `${FEC} ACME HOLDINGS INC\n${FEC} AMEREN CORPORATION\n${MEC} AMEREN CORPORATION`,
  });
});

test("a donor with no page is listed with no link line, and no page at all gives null links", () => {
  const got = groupSiteDonors([row("F1", "A", FEC), row("F1", "B", null), row("F2", "C", null)]);
  assert.deepEqual(got.get(siteKey("o1", "F1")), { donors: ["A", "B"], donor_links: `${FEC} A` });
  assert.deepEqual(got.get(siteKey("o1", "F2")), { donors: ["C"], donor_links: null });
});

test("a ';' or ',' in a donor name stays in that one donor", () => {
  const got = groupSiteDonors([row("F1", "Laborers; PAC", FEC), row("F1", "SMITH, JONES & CO", null)]);
  assert.deepEqual(got.get(siteKey("o1", "F1")).donors, ["Laborers; PAC", "SMITH, JONES & CO"]);
});

test("facilities and officials are kept apart; a blank donor name is dropped", () => {
  const got = groupSiteDonors([
    row("F1", "A", FEC),
    row("F1", "  ", FEC),
    row("F2", "B", FEC),
    row("F1", "C", FEC, "o2"),
  ]);
  assert.deepEqual([...got.keys()].sort(), ["o1|F1", "o1|F2", "o2|F1"]);
  assert.deepEqual(got.get("o1|F1").donors, ["A"]);
  assert.equal(got.has("o1|F3"), false);
});

const fac = (registry_id, donated_amount, official_id = "o1") => ({
  official_id,
  registry_id,
  donated_amount,
});
const group = (rows, donorsBy) =>
  groupBySiteDonors(
    rows,
    (r) => donorsBy[r.registry_id],
    (r, donors) => ({ donors, donated_amount: r.donated_amount, sites: [] }),
    (g, r) => g.sites.push(r.registry_id),
  );

test("groupBySiteDonors groups sites by donor set: biggest total first, then by names", () => {
  const out = group([fac("F1", 50), fac("F2", 100), fac("F3", 50), fac("F4", 100)], {
    F1: ["B"],
    F2: ["A", "B"],
    F3: ["A"],
    F4: ["A", "B"],
  });
  assert.deepEqual(
    out.get("o1").map((g) => [g.donors, g.sites]),
    [
      [
        ["A", "B"],
        ["F2", "F4"],
      ],
      [["A"], ["F3"]],
      [["B"], ["F1"]],
    ],
  );
});

test("groupBySiteDonors: a donor set that extends another sorts after it; a ';' name is one donor", () => {
  const out = group([fac("F1", 10), fac("F2", 10), fac("F3", 10)], {
    F1: ["A", "B"],
    F2: ["A"],
    F3: ["A; B"],
  });
  assert.deepEqual(
    out.get("o1").map((g) => g.donors),
    [["A"], ["A", "B"], ["A; B"]],
  );
});

test("groupBySiteDonors keeps officials apart", () => {
  const out = group([fac("F1", 1, "o1"), fac("F1", 1, "o2")], { F1: ["A"] });
  assert.equal(out.get("o1").length, 1);
  assert.equal(out.get("o2").length, 1);
});

test("groupBySiteDonors: a name holding the old separator cannot merge two different donor sets", () => {
  const out = group([fac("F1", 10), fac("F2", 10)], { F1: ["ab"], F2: ["a", "b"] });
  assert.deepEqual(
    out.get("o1").map((g) => [g.donors, g.sites]),
    [
      [["a", "b"], ["F2"]],
      [["ab"], ["F1"]],
    ],
  );
});
