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

test("spans are styling hooks and may touch text", () => {
  assert.deepEqual(findRunOns('<a>roll call<span aria-hidden="true">↗</span></a>'), []);
});

test("script, style, svg and pre contents are ignored", () => {
  assert.deepEqual(findRunOns("<script>if (a<b && c<a) {}</script><pre>x<a>y</a>z</pre>"), []);
  assert.deepEqual(findRunOns("<svg><text>a<a>b</a>c</text></svg>"), []);
});

test("an allowlisted context passes, others still fail", () => {
  const html = `<p>H<abbr>2</abbr>O</p><p>${"filler text ".repeat(8)}</p><p>that is<strong>x</strong></p>`;
  assert.equal(findRunOns(html, []).length, 3);
  const r = findRunOns(html, ["H<abbr>"]);
  assert.equal(r.length, 1);
  assert.match(r[0].context, /that is<strong>/);
});
