import assert from "node:assert/strict";
import { test } from "node:test";
import { valueLinkLine } from "../src/lib/compareLink.ts";

// the smallest document stand-in the builder needs
class Node_ {
  constructor(tag) {
    this.tag = tag;
    this.attrs = {};
    this.children = [];
    this.textContent = "";
    this.className = "";
  }
  append(...kids) {
    this.children.push(...kids);
  }
  setAttribute(k, v) {
    this.attrs[k] = v;
  }
}
const doc = { createElement: (t) => new Node_(t) };

test("compare source link hides the arrow from screen readers and carries the context as sr-only text", () => {
  const line = valueLinkLine(doc, { text: "Pay", href: "https://x.test/", context: "(House pay)" });
  assert.equal(line.className, "small");
  const a = line.children[0];
  assert.equal(a.tag, "a");
  assert.equal(a.href, "https://x.test/");
  assert.equal(a.rel, "noopener noreferrer");
  assert.equal(a.target, "_blank");
  const [space, ctx, arrow] = a.children;
  assert.equal(space, " ");
  assert.equal(ctx.className, "sr-only");
  assert.equal(ctx.textContent, "(House pay)");
  assert.equal(arrow.textContent, "↗");
  assert.equal(arrow.attrs["aria-hidden"], "true");
});

test("compare source link without context has no sr-only span", () => {
  const a = valueLinkLine(doc, { text: "Pay", href: "/p" }).children[0];
  assert.equal(a.children.length, 1);
  assert.equal(a.children[0].attrs["aria-hidden"], "true");
});
