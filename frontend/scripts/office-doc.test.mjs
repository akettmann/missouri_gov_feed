import assert from "node:assert/strict";
import { test } from "node:test";
import { officeCoverage, parseOfficeDoc } from "../src/lib/officeDoc.ts";
import { DOC_MODELS, loaderNames, loadResponsibilities, readDoc } from "../src/lib/officeDocLoad.ts";

const OPT = { requireData: true, loaders: new Set(["voteview", "mo_house"]), models: new Set() };
const wrap = (bullets, notes = "") =>
  [
    "# T",
    "",
    "Legal text checked 2026-10-27 (issue #1).",
    "",
    "## Office A",
    "",
    ...bullets,
    ...(notes ? ["", "Notes:", "", notes] : []),
    "",
    "[c1]: https://example.gov/1",
    "",
  ].join("\n");
const GOOD = "- **Duty.** Do it. ([Art. 1][c1]) Data: roll calls (`voteview`).";

test("a well-formed section parses: label, citation, sources, footnote", () => {
  const d = parseOfficeDoc(wrap([GOOD], "- [1] Exception. ([Art. 1][c1])"), OPT);
  const s = d.offices[0];
  assert.equal(d.checked, "2026-10-27");
  assert.equal(s.bullets[0].label, "Duty");
  assert.deepEqual(s.bullets[0].citations, [{ text: "Art. 1", href: "https://example.gov/1" }]);
  assert.deepEqual(s.bullets[0].sources, ["voteview"]);
  assert.equal(s.bullets[0].noData, false);
  assert.equal(s.notes[0].n, 1);
  assert.match(s.bullets[0].html, /<a href="https:\/\/example.gov\/1">Art. 1<\/a>/);
  assert.doesNotMatch(s.bullets[0].html, /Data/);
});

test("a bullet without a citation link fails", () => {
  assert.throws(
    () => parseOfficeDoc(wrap(["- **Duty.** Do it. Data: no data yet."]), OPT),
    /no citation link/,
  );
});

test("a citation whose reference is not defined fails (typo in the link label)", () => {
  assert.throws(
    () => parseOfficeDoc(wrap(["- **Duty.** Do it. ([Art. 1][nope]) Data: no data yet."]), OPT),
    /unresolved link reference|no citation link/,
  );
});

test("a bullet without a Data clause, or with a non-https link, fails", () => {
  assert.throws(() => parseOfficeDoc(wrap(["- **Duty.** Do it. ([Art. 1][c1])"]), OPT), /no "Data:" clause/);
  assert.throws(
    () => parseOfficeDoc(wrap(["- **Duty.** Do it. ([x](http://a.gov)) Data: no data yet."]), OPT),
    /not an https URL/,
  );
});

test("a bullet needs a bold label", () => {
  assert.throws(
    () => parseOfficeDoc(wrap(["- Do it. ([Art. 1][c1]) Data: no data yet."]), OPT),
    /bold label/,
  );
});

test("footnotes must be numbered in order and carry a citation", () => {
  assert.throws(() => parseOfficeDoc(wrap([GOOD], "- [2] Late. ([Art. 1][c1])"), OPT), /expected \[1\]/);
  assert.throws(() => parseOfficeDoc(wrap([GOOD], "- [1] No cite."), OPT), /no citation link/);
});

test("a Data clause may only name loaders, known models, or a source marked as a candidate", () => {
  const bad = "- **Duty.** Do it. ([Art. 1][c1]) Data: roll calls (`made_up`).";
  assert.throws(() => parseOfficeDoc(wrap([bad]), OPT), /"made_up" in Data/);
  const cand = "- **Duty.** Do it. ([Art. 1][c1]) Data: no data yet (`mo_sos_rules` is a candidate).";
  const b = parseOfficeDoc(wrap([cand]), OPT).offices[0].bullets[0];
  assert.deepEqual(b.candidates, ["mo_sos_rules"]);
  assert.equal(b.noData, true);
});

test("a Data clause with no source must say so", () => {
  assert.throws(
    () => parseOfficeDoc(wrap(["- **Duty.** Do it. ([A][c1]) Data: later."]), OPT),
    /no loaded source/,
  );
});

test("a missing 'Legal text checked' date fails", () => {
  assert.throws(
    () => parseOfficeDoc(wrap([GOOD]).replace("Legal text checked", "Looked at"), OPT),
    /checked/,
  );
});

test("coverage counts bullets per source, loaded before candidates, ordered by name", () => {
  const md = wrap([
    "- **Duty.** A. ([x][c1]) Data: `voteview`, `mo_house`.",
    "- **Duty.** B. ([x][c1]) Data: `voteview`.",
    "- **Duty.** C. ([x][c1]) Data: no data yet (`zz` is a candidate).",
  ]);
  const cov = officeCoverage(parseOfficeDoc(md, OPT).offices[0]);
  assert.deepEqual(
    cov.cells.map((c) => [c.source, c.kind, c.bullets]),
    [
      ["mo_house", "loaded", 1],
      ["voteview", "loaded", 2],
      ["zz", "candidate", 1],
    ],
  );
  assert.equal(cov.total, 3);
  assert.equal(cov.noData, 1);
});

test("the real responsibilities doc parses: every office has bullets, citations and footnotes in order", () => {
  const d = loadResponsibilities();
  const titles = d.offices.map((o) => o.title);
  for (const t of [
    "Missouri House of Representatives",
    "Missouri Senate",
    "Governor",
    "Lieutenant Governor",
    "State Treasurer",
    "Attorney General",
    "U.S. House of Representatives",
    "U.S. Senate",
    "Federal judges",
  ])
    assert.ok(titles.includes(t), `missing office ${t}`);
  assert.ok(titles.some((t) => t.startsWith("Missouri judges")));
  for (const o of d.offices) {
    assert.ok(o.bullets.length > 0);
    for (const b of o.bullets) assert.ok(b.citations.length > 0, `${o.title}: ${b.label}`);
    assert.deepEqual(
      o.notes.map((n) => n.n),
      o.notes.map((_, i) => i + 1),
    );
  }
  assert.match(d.checked, /^\d{4}-\d{2}-\d{2}$/);
});

test("every link reference in the real doc is defined, and every definition is used", () => {
  const md = readDoc("office_responsibilities.md");
  const defs = [...md.matchAll(/^\[([^\]]+)\]:\s*\S+/gm)].map((m) => m[1]);
  const body = md.replace(/^\[[^\]]+\]:.*$/gm, "");
  const used = new Set([...body.matchAll(/\]\[([^\]]+)\]/g)].map((m) => m[1]));
  assert.deepEqual(
    [...used].filter((u) => !defs.includes(u)),
    [],
  );
  assert.deepEqual(
    defs.filter((d) => !used.has(d)),
    [],
  );
});

test("loader names come from src/mogov/loaders and the doc's models are listed", () => {
  const names = loaderNames();
  assert.ok(names.has("voteview") && names.has("mo_house") && !names.has("__init__"));
  assert.ok(DOC_MODELS.has("fct_judicial_retention"));
});
