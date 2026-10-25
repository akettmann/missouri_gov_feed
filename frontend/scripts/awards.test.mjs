import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import { test } from "node:test";
import { streakMarker } from "../src/lib/format.ts";

test("streakMarker shows X<n> with a spoken label from 2 years", () => {
  assert.deepEqual(streakMarker(3), { text: "X3", label: "3 qualifying years in a row" });
  assert.deepEqual(streakMarker(2), { text: "X2", label: "2 qualifying years in a row" });
});

test("streakMarker is absent for a single year, lifetime rows (null) and missing values", () => {
  assert.equal(streakMarker(1), null);
  assert.equal(streakMarker(null), null);
  assert.equal(streakMarker(undefined), null);
});

test("awards page renders the streak marker as aria-hidden text plus visually hidden spoken text", () => {
  // Astro pages can't be rendered from node:test, so pin the markup in source. aria-label on a generic
  // element is prohibited, so the spoken text must be real (sr-only) text instead.
  const page = readFileSync(new URL("../src/pages/awards.astro", import.meta.url), "utf8");
  assert.match(page, /<span aria-hidden="true">\{marker\.text\}<\/span>/);
  assert.match(page, /<span class="sr-only">\{marker\.label\}<\/span>/);
  assert.doesNotMatch(page, /aria-label/);
  assert.equal(page.match(/streakMarker\(/g).length, 1, "compute the marker once per entry");
  const css = readFileSync(new URL("../src/styles/global.css", import.meta.url), "utf8");
  assert.match(css, /\.sr-only\s*\{[^}]*clip-path/);
});
