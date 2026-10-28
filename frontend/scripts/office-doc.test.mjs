import assert from "node:assert/strict";
import { test } from "node:test";
import { officeCoverage, parseOfficeDoc } from "../src/lib/officeDoc.ts";
import {
  CANDIDATE_NAMES,
  docNames,
  DOC_MODELS,
  loaderNames,
  loadResponsibilities,
  MODEL_NAMES,
  readDoc,
  readSourcesDoc,
  sourceNames,
} from "../src/lib/officeDocLoad.ts";

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
  const cand = "- **Duty.** Do it. ([Art. 1][c1]) Data: no data yet (`mo_sos_rules` is not loaded yet).";
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
    "- **Duty.** C. ([x][c1]) Data: no data yet (`zz` is not loaded yet).",
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

test("a section of only link definitions renders no section", () => {
  const md = wrap([GOOD]) + "\n## Links\n\n[c2]: https://example.gov/2\n";
  const d = parseOfficeDoc(md, OPT);
  assert.deepEqual(
    [...d.offices, ...d.otherSections].map((s) => s.title),
    ["Office A"],
  );
});

test("maintainer comments are not rendered and the real doc shows no issue refs", () => {
  const md = wrap([GOOD]).replace("# T\n", "# T\n\n<!-- issue #9 -->\n");
  assert.doesNotMatch(parseOfficeDoc(md, OPT).prefaceHtml, /#9/);
  const d = loadResponsibilities();
  const all = [
    d.prefaceHtml,
    ...[...d.offices, ...d.otherSections].flatMap((s) => [
      s.introHtml,
      ...s.bullets.flatMap((b) => [b.html, b.dataHtml ?? ""]),
      ...s.notes.map((n) => n.html),
    ]),
  ].join("\n");
  assert.doesNotMatch(all, /\(#\d+\)|issue #\d+|Flesch|docs\/sources\.md/);
  assert.ok(!d.otherSections.some((s) => s.title === "Links"));
});

test("an unresolved bare [shortcut] reference fails, in a bullet, a note, the intro and the preface", () => {
  const bare = "- **Duty.** Do it. ([Art. 1][c1]) See [nope]. Data: no data yet.";
  assert.throws(() => parseOfficeDoc(wrap([bare]), OPT), /unresolved link reference in .*\[nope\]/);
  assert.throws(
    () => parseOfficeDoc(wrap([GOOD], "- [1] Exception [oops]. ([Art. 1][c1])"), OPT),
    /unresolved link reference/,
  );
  const intro = wrap([GOOD]).replace("## Office A\n", "## Office A\n\nIntro with [lost] link.\n");
  assert.throws(() => parseOfficeDoc(intro, OPT), /unresolved link reference/);
  const pre = wrap([GOOD]).replace("(issue #1).", "(issue #1) and [lost].");
  assert.throws(() => parseOfficeDoc(pre, OPT), /unresolved link reference/);
});

test("inline HTML comments are dropped from bullets, notes, intro and preface", () => {
  const b =
    "- **Duty.** Do it <!-- note #7 --> now. ([Art. 1][c1]) Data: roll calls <!-- x --> (`voteview`).";
  const md = wrap([b], "- [1] Note <!-- y --> text. ([Art. 1][c1])")
    .replace("## Office A\n", "## Office A\n\nIntro <!-- z --> text.\n")
    .replace("(issue #1).", "(issue #1) pre <!-- w --> face.");
  const d = parseOfficeDoc(md, OPT);
  const s = d.offices[0];
  const all = [d.prefaceHtml, s.introHtml, s.bullets[0].html, s.bullets[0].dataHtml, s.notes[0].html].join(
    "\n",
  );
  assert.doesNotMatch(all, /<!--|note #7|-->/);
  assert.match(s.bullets[0].html, /Do it\s+now\./);
  assert.deepEqual(s.bullets[0].sources, ["voteview"]);
});

test("code names show by their plain name in Data lines and notes; the strip uses it too", () => {
  const names = new Map([["voteview", "Voteview (Congress roll calls)"]]);
  const opt = { ...OPT, names };
  const d = parseOfficeDoc(wrap([GOOD], "- [1] See `voteview`. ([Art. 1][c1])"), opt);
  const s = d.offices[0];
  assert.equal(s.bullets[0].dataHtml, "roll calls (Voteview (Congress roll calls))");
  assert.deepEqual(s.bullets[0].sources, ["voteview"]);
  assert.match(s.notes[0].html, /See Voteview \(Congress roll calls\)\./);
  assert.equal(officeCoverage(s, d.names).cells[0].name, "Voteview (Congress roll calls)");
  assert.equal(officeCoverage(s).cells[0].name, "voteview");
});

test("sourceNames reads the Summary table of docs/sources.md and drops a trailing web address", () => {
  const md = [
    "| Loader | Source | Data it provides | Coverage | Gate |",
    "|---|---|---|---|---|",
    "| `a` | Alpha Agency (alpha.mo.gov) | things, more | all | |",
    "| `b` | Beta | judges, more | all | |",
  ].join("\n");
  assert.deepEqual(
    [...sourceNames(md)],
    [
      ["a", "Alpha Agency"],
      ["b", "Beta"],
    ],
  );
  assert.throws(() => sourceNames("no table here"), /no Summary table/);
});

test("every loader has a plain name, every candidate and model in the doc too, and no name is shown twice", () => {
  const names = sourceNames(readSourcesDoc());
  assert.deepEqual(
    [...loaderNames()].filter((l) => !names.has(l)),
    [],
    "a loader without a row in docs/sources.md (Summary table) has no plain name",
  );
  const md = readDoc("office_responsibilities.md");
  const candidates = [...md.matchAll(/`([a-z_0-9]+)` is not loaded yet/g)].map((m) => m[1]);
  assert.ok(candidates.length > 0);
  assert.deepEqual(
    candidates.filter((c) => !CANDIDATE_NAMES.has(c)),
    [],
  );
  assert.deepEqual(
    [...DOC_MODELS].filter((m) => !MODEL_NAMES.has(m)),
    [],
  );
  const shown = [...docNames().values()];
  assert.equal(new Set(shown).size, shown.length, "two code names share one plain name");
  assert.ok(
    shown.every((n) => !/[`_]/.test(n)),
    "a plain name still looks like code",
  );
});

test("the real page shows no raw loader name anywhere: preface, intros, Data lines, notes, strip", () => {
  const d = loadResponsibilities();
  const loaders = [...loaderNames()];
  const sections = [...d.offices, ...d.otherSections];
  const text = [
    d.prefaceHtml,
    ...sections.flatMap((s) => [
      s.introHtml,
      ...s.bullets.flatMap((b) => [b.html, b.dataHtml ?? ""]),
      ...s.notes.map((n) => n.html),
      ...officeCoverage(s, d.names).cells.map((c) => c.name),
    ]),
  ];
  for (const t of text)
    for (const l of loaders) assert.ok(!new RegExp(`\\b${l}\\b`).test(t), `${l} shown raw in: ${t}`);
});

test("the preface list is checked and cleaned like any other block", () => {
  const withPreface = (item) => wrap([GOOD]).replace("(issue #1).", "(issue #1).\n\n" + item + "\n");
  assert.throws(
    () => parseOfficeDoc(withPreface("- See [lost]. **Duty** means it."), OPT),
    /unresolved link reference/,
  );
  const d = parseOfficeDoc(withPreface("- **Duty** <!-- secret --> means it."), OPT);
  assert.doesNotMatch(d.prefaceHtml, /secret|<!--/);
  assert.match(d.prefaceHtml, /Duty/);
  const named = parseOfficeDoc(withPreface("- Source `voteview` here."), {
    ...OPT,
    names: new Map([["voteview", "Voteview (Congress roll calls)"]]),
  });
  assert.match(named.prefaceHtml, /Voteview \(Congress roll calls\) here/);
  assert.doesNotMatch(named.prefaceHtml, /<code>voteview/);
});
