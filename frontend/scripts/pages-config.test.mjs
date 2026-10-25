import assert from "node:assert/strict";
import path from "node:path";
import { test } from "node:test";
import { stripTrailingSlash, withBase } from "../src/lib/basePath.ts";
import { extractLinks, resolveFile } from "./link-check.mjs";
import { checkLimits, normalizeBase, pagesTarget, parseArgs, repoFromRemote } from "./pages-config.mjs";

test("withBase prefixes absolute paths and tolerates the root base", () => {
  assert.equal(withBase("/", "/officials/a/"), "/officials/a/");
  assert.equal(withBase("/missouri_gov_feed/", "/officials/a/"), "/missouri_gov_feed/officials/a/");
  assert.equal(withBase("/missouri_gov_feed", "/find/"), "/missouri_gov_feed/find/");
  assert.equal(stripTrailingSlash("/"), "");
});

test("normalizeBase", () => {
  assert.equal(normalizeBase(undefined), undefined);
  assert.equal(normalizeBase(""), undefined);
  assert.equal(normalizeBase("/"), undefined);
  assert.equal(normalizeBase("missouri_gov_feed"), "/missouri_gov_feed");
  assert.equal(normalizeBase("/missouri_gov_feed/"), "/missouri_gov_feed");
  assert.throws(() => normalizeBase("C:/Program Files/Git/missouri_gov_feed")); // MSYS-mangled
});

test("pagesTarget: project site vs user site, and bad input", () => {
  assert.deepEqual(pagesTarget("akettmann/missouri_gov_feed"), {
    site: "https://akettmann.github.io",
    base: "/missouri_gov_feed",
    url: "https://akettmann.github.io/missouri_gov_feed/",
  });
  assert.equal(pagesTarget("akettmann/akettmann.github.io").base, undefined);
  assert.equal(pagesTarget("akettmann/akettmann.github.io").url, "https://akettmann.github.io/");
  assert.throws(() => pagesTarget("nope"));
});

test("repoFromRemote handles https and ssh", () => {
  assert.equal(
    repoFromRemote("https://github.com/akettmann/missouri_gov_feed.git"),
    "akettmann/missouri_gov_feed",
  );
  assert.equal(
    repoFromRemote("git@github.com:akettmann/missouri_gov_feed.git"),
    "akettmann/missouri_gov_feed",
  );
  assert.equal(repoFromRemote("https://example.com/x/y"), null);
});

test("checkLimits flags oversize files and sites", () => {
  const MB = 1048576;
  const ok = checkLimits([
    { path: "a", size: 3 * MB },
    { path: "b", size: MB },
  ]);
  assert.deepEqual(ok.problems, []);
  assert.equal(ok.totalBytes, 4 * MB);
  assert.equal(ok.largest.path, "a");
  assert.equal(checkLimits([{ path: "big.csv", size: 100 * MB }]).problems.length, 1);
  const tiny = { siteBytes: 50 * MB, fileBytes: 100 * MB };
  assert.equal(checkLimits([{ path: "a", size: 60 * MB }], tiny).problems.length, 1);
});

test("parseArgs", () => {
  assert.deepEqual(parseArgs([]).opts, {
    dryRun: false,
    skipBuild: false,
    allowStale: false,
    remote: "origin",
    branch: "gh-pages",
  });
  assert.equal(parseArgs(["--dry-run", "--skip-build"]).opts.dryRun, true);
  assert.equal(parseArgs(["--remote", "up"]).opts.remote, "up");
  assert.deepEqual(parseArgs(["--dry-runn"]).errors, ["unknown argument --dry-runn"]);
  assert.equal(parseArgs(["--remote"]).errors.length, 1);
});

test("extractLinks keeps only root-relative references", () => {
  const html = `<a href="/a/">x</a><a href='/b.csv'>y</a><img src="//cdn/x.png"><a href="https://e.com/">z</a>
    <a href="rel/">r</a><article data-bundle-url="/o/x.json"></article>`;
  assert.deepEqual(extractLinks(html), ["/a/", "/b.csv", "/o/x.json"]);
});

test("resolveFile enforces the base and Pages-style index resolution", () => {
  const files = new Set([path.join("dist", "a", "index.html"), path.join("dist", "x.csv")]);
  const exists = (f) => files.has(f);
  const stat = () => ({ isDirectory: () => false });
  assert.ok(resolveFile("dist", "/b", "/b/a/", exists, stat));
  assert.ok(resolveFile("dist", "/b", "/b/x.csv#frag", exists, stat));
  assert.equal(resolveFile("dist", "/b", "/a/", exists, stat), null); // missing base
  assert.equal(resolveFile("dist", "/b", "/xa/", exists, stat), null); // wrong prefix of the same length
  assert.equal(resolveFile("dist", "/b", "/bb/a/", exists, stat), null);
  assert.equal(resolveFile("dist", "/b", "/b/nope/", exists, stat), null);
  assert.ok(resolveFile("dist", "", "/a/", exists, stat));
});
