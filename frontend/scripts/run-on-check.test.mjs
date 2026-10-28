import assert from "node:assert/strict";
import { test } from "node:test";
import { findRunOns } from "./run-on-check.mjs";

test("a word glued to an opening inline tag fails", () => {
  const r = findRunOns("<p>that is<strong>co-occurrence</strong>, not causation</p>");
  assert.equal(r.length, 1);
  assert.equal(r[0].kind, "word<tag");
});

test("every inline tag with attributes is caught, digits count as words", () => {
  assert.equal(findRunOns("<p>keeps a<code data-astro-cid-x>match_confidence</code></p>").length, 1);
  assert.equal(findRunOns('<p>try<a href="/" class="x">searching</a></p>').length, 1);
  assert.equal(findRunOns("<p>in 2024<em>only</em></p>").length, 1);
});

test("a closing inline tag glued to a word fails", () => {
  const r = findRunOns("<p><strong>co-occurrence</strong>not causation</p>");
  assert.equal(r.length, 1);
  assert.equal(r[0].kind, "</tag>word");
});

test("correctly spaced text passes", () => {
  assert.deepEqual(findRunOns("<p>that is <strong>co-occurrence</strong> not causation</p>"), []);
  assert.deepEqual(findRunOns("<p>that is\n<strong>co-occurrence</strong>\nnot</p>"), []);
});

test("punctuation next to a tag is not a run-on", () => {
  assert.deepEqual(findRunOns("<p>(<a href='/'>x</a>), <strong>y</strong>'s, <code>z</code>.</p>"), []);
});

test("a tag whose content starts with a space already separates the words", () => {
  assert.deepEqual(findRunOns('<a>EPA record<span class="sr-only"> for X</span></a>'), []);
  assert.deepEqual(findRunOns("<p>word<em> spaced</em></p>"), []);
});

test("a span whose text starts with a letter or digit glued to a word fails", () => {
  const r = findRunOns('<td>Mercy<span class="badge">possible match</span></td>');
  assert.equal(r.length, 1);
  assert.equal(r[0].kind, "word<span>word");
  assert.match(r[0].hint, /\{" "\}/);
  assert.equal(
    findRunOns(`<li>HIGH PRAIRIE<span
 class="badge"
>same brand</span></li>`).length,
    1,
  );
});

test("spans that are sr-only, arrows, punctuation-led or spaced pass", () => {
  assert.deepEqual(findRunOns('<a>roll call<span aria-hidden="true">↗</span></a>'), []);
  assert.deepEqual(findRunOns('<a>EPA record<span class="sr-only"> for X</span></a>'), []);
  assert.deepEqual(findRunOns('<li>Site<span class="muted">, Main St</span></li>'), []);
  assert.deepEqual(findRunOns('<li>Site<span class="muted"> · NAICS</span></li>'), []);
  assert.deepEqual(findRunOns('<td>Mercy <span class="badge">possible match</span></td>'), []);
});

test("HTML comments are skipped", () => {
  assert.deepEqual(findRunOns("<!-- a<strong>b</strong>c --><p>ok</p>"), []);
});

test("script, style, svg and pre contents are ignored", () => {
  assert.deepEqual(findRunOns("<script>if (a<b && c<a) {}</script><pre>x<a>y</a>z</pre>"), []);
  assert.deepEqual(findRunOns("<svg><text>a<a>b</a>c</text></svg>"), []);
});

test("an allowlisted match or data-glue passes, others still fail", () => {
  const html = `<p>H<abbr>2</abbr>O</p><p>that is<strong>x</strong></p>`;
  assert.equal(findRunOns(html, []).length, 3);
  const r = findRunOns(html, ["H<abbr>", "</abbr>O"]);
  assert.equal(r.length, 1);
  assert.match(r[0].context, /that is<strong>/);
  assert.deepEqual(findRunOns("<p>H<abbr data-glue>2</abbr> O</p>", []), []);
});
