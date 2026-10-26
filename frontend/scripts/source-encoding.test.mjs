import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";

// U+FFFD is what a mis-decoded byte becomes (a "·" once shipped as "�" on 192 pages). It never belongs in source.
const FFFD = "\uFFFD";

function* files(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = new URL(e.name + (e.isDirectory() ? "/" : ""), dir);
    if (e.isDirectory()) yield* files(p);
    else yield p;
  }
}

export const withReplacementChar = (text) => text.includes(FFFD);

test("the detector sees a replacement character", () => {
  assert.equal(withReplacementChar(`pay source ${FFFD} how`), true);
  assert.equal(withReplacementChar("pay source · how"), false);
});

test("no frontend/src file contains U+FFFD", () => {
  const bad = [];
  for (const f of files(new URL("../src/", import.meta.url))) {
    if (/\.(png|jpe?g|gif|webp|ico|woff2?|ttf|otf)$/i.test(f.pathname)) continue;
    if (withReplacementChar(readFileSync(f, "utf8"))) bad.push(f.pathname);
  }
  assert.deepEqual(bad, []);
});
