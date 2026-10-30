import assert from "node:assert/strict";
import { test } from "node:test";
import {
  asOfText,
  escapeHtml,
  footnotesInOrder,
  longDate,
  orderVersions,
  statusLabel,
  statuteBodyHtml,
  statutePath,
  statutePaths,
  NOT_LOADED,
  introText,
  versionNames,
} from "../src/lib/statuteText.ts";

test("blank lines make paragraphs and a single newline is a line break", () => {
  assert.equal(
    statuteBodyHtml("1.010. Title. — 1. First.\n\n2. Second\n(1) one\n(2) two"),
    "<p>1.010. Title. — 1. First.</p>\n<p>2. Second<br>\n(1) one<br>\n(2) two</p>",
  );
});

test("a subsection list stays text, in order, with no list markup added", () => {
  const html = statuteBodyHtml("(1) apples;\n(2) pears;\n(3) plums.");
  assert.equal(html, "<p>(1) apples;<br>\n(2) pears;<br>\n(3) plums.</p>");
  assert.doesNotMatch(html, /<[ou]l>/);
});

test("tab-separated lines become a table, prose around it stays prose (143.011 shape)", () => {
  const html = statuteBodyHtml(
    "Rates:\n\nIf the income is:\tThe tax is:\nNot over $1,000\t1 1/2%\n\nThe end.",
  );
  assert.equal(
    html,
    '<p>Rates:</p>\n<div class="statute-table-wrap" tabindex="0" role="region" aria-label="Table in the statute text"><table class="statute-table"><tbody>\n' +
      "<tr><td>If the income is:</td><td>The tax is:</td></tr>\n" +
      "<tr><td>Not over $1,000</td><td>1 1/2%</td></tr>\n</tbody></table></div>\n<p>The end.</p>",
  );
});

test("prose lines and tab rows in one block do not merge", () => {
  const html = statuteBodyHtml("lead-in\na\tb\ntrailer");
  assert.equal(
    html,
    '<p>lead-in</p>\n<div class="statute-table-wrap" tabindex="0" role="region" aria-label="Table in the statute text"><table class="statute-table"><tbody>\n<tr><td>a</td><td>b</td></tr>\n</tbody></table></div>\n<p>trailer</p>',
  );
});

test("HTML-looking text is escaped, in paragraphs, table cells and footnotes' helper", () => {
  const html = statuteBodyHtml("<script>alert(\"x\")</script> & 'q'\n\n<b>a</b>\t<i>b</i>");
  assert.ok(!html.includes("<script"));
  assert.ok(!html.includes("<b>") && !html.includes("<i>"));
  assert.match(html, /&lt;script&gt;alert\(&quot;x&quot;\)&lt;\/script&gt; &amp; &#39;q&#39;/);
  assert.match(html, /<td>&lt;b&gt;a&lt;\/b&gt;<\/td><td>&lt;i&gt;b&lt;\/i&gt;<\/td>/);
  assert.equal(escapeHtml("a&b"), "a&amp;b");
});

test("empty or missing text (repealed sections) renders nothing", () => {
  assert.equal(statuteBodyHtml(""), "");
  assert.equal(statuteBodyHtml(null), "");
  assert.equal(statuteBodyHtml(undefined), "");
});

test("each status has its own label and dates", () => {
  const base = { is_current: false, effective_date: null, ended_date: null, transferred_to: null };
  assert.deepEqual(
    statusLabel({ ...base, status: "in force", is_current: true, effective_date: "2015-08-28" }),
    { label: "In force", detail: "In force since August 28, 2015.", transferredTo: null },
  );
  assert.equal(statusLabel({ ...base, status: "in force" }).label, "In force (earlier version)");
  assert.deepEqual(statusLabel({ ...base, status: "not yet effective", effective_date: "2026-11-12" }), {
    label: "Not yet effective",
    detail: "Takes effect November 12, 2026.",
    transferredTo: null,
  });
  const contingent = statusLabel({ ...base, status: "contingent" });
  assert.equal(contingent.label, "Contingent");
  assert.doesNotMatch(contingent.detail, /2099/);
  assert.equal(
    statusLabel({ ...base, status: "repealed", ended_date: "1975-09-28" }).detail,
    "Repealed September 28, 1975.",
  );
  assert.equal(statusLabel({ ...base, status: "repealed" }).detail, "Repealed; the Revisor gives no date.");
  const moved = statusLabel({
    ...base,
    status: "transferred",
    ended_date: "2010-01-01",
    transferred_to: "9.9",
  });
  assert.equal(moved.detail, "Transferred January 1, 2010 to section 9.9.");
  assert.equal(moved.transferredTo, "9.9");
  assert.equal(
    statusLabel({ ...base, status: "historical", effective_date: "1978-08-13" }).label,
    "Historical",
  );
});

test("footnotes print in the Revisor's order whatever order they arrive in", () => {
  const fs = [3, 1, 2].map((n) => ({ footnote_number: n, footnote_text: `n${n}`, is_history_note: n === 1 }));
  assert.deepEqual(
    footnotesInOrder(fs).map((f) => f.footnote_text),
    ["n1", "n2", "n3"],
  );
  assert.equal(fs[0].footnote_text, "n3", "input is not mutated");
});

test("versions: current first, then not yet effective, contingent, earlier; ties end on bid", () => {
  const v = (bid, status, is_current, effective_date) => ({ bid, status, is_current, effective_date });
  const order = orderVersions([
    v(9, "repealed", false, null),
    v(8, "in force", false, "1999-05-06"),
    v(7, "contingent", false, null),
    v(6, "not yet effective", false, "2027-01-01"),
    v(5, "in force", true, "2014-08-28"),
    v(4, "in force", true, "2014-08-28"),
    v(3, "in force", false, "2001-01-01"),
  ]).map((x) => x.bid);
  assert.deepEqual(order, [4, 5, 6, 7, 3, 8, 9]);
});

test("dates and as-of wording: pipeline publish time, never 'copied on'", () => {
  assert.equal(longDate("2026-10-26 04:32:00.815865-05"), "October 26, 2026");
  assert.equal(longDate(null), "");
  const t = asOfText("2026-10-26 04:32:00-05");
  assert.match(t, /Our pipeline published this page's data on October 26, 2026\./);
  assert.match(t, /up to 180 days/);
  assert.doesNotMatch(t, /copied/i);
  assert.doesNotMatch(asOfText(null), /published this page/);
});

test("section page path keeps the id as is", () => {
  assert.equal(statutePath("400.3-505"), "/statutes/400.3-505/");
});

test("statutePaths: one page per section, or the single not-loaded page without exports", () => {
  assert.deepEqual(statutePaths(true, [{ section_id: "1.010" }, { section_id: "1.020" }]), [
    { params: { section: "1.010" } },
    { params: { section: "1.020" } },
  ]);
  assert.deepEqual(statutePaths(false, []), [{ params: { section: NOT_LOADED } }]);
});

test("versions get distinct headings and distinct link context", () => {
  const v = (status, is_current, effective_date) => ({
    status,
    is_current,
    effective_date,
    ended_date: null,
    transferred_to: null,
  });
  const n = versionNames([
    v("in force", true, "2020-08-28"),
    v("in force", true, "2020-08-28"),
    v("historical", false, "2010-08-28"),
  ]);
  assert.equal(new Set(n.map((x) => x.heading)).size, 3);
  assert.equal(new Set(n.map((x) => x.context)).size, 3);
  assert.equal(n[0].heading, "In force (version 1 of 2)");
  assert.equal(n[2].context, "(Historical, August 28, 2010)");
});

test("repeal-only pages make no word-for-word claim and count no versions", () => {
  assert.doesNotMatch(introText([{ status: "repealed" }]), /word for word|versions/);
  assert.match(introText([{ status: "in force" }, { status: "repealed" }]), /word for word/);
  assert.doesNotMatch(introText([{ status: "in force" }, { status: "repealed" }]), /versions of/);
  assert.match(
    introText([{ status: "in force" }, { status: "historical" }, { status: "repealed" }]),
    /2 versions/,
  );
});
