import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { existsSync, rmSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { stripTrailingSlash, withBase } from "../src/lib/basePath.ts";
import { extractLinks, resolveFile } from "./link-check.mjs";
import {
  checkLimits,
  normalizeBase,
  PAGES_BRANCH,
  pagesTarget,
  parseArgs,
  pushUrl,
  redactUrl,
  repoFromRemote,
  withTempDir,
} from "./pages-config.mjs";

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
  assert.equal(repoFromRemote("ssh://git@github.com/a/b"), "a/b");
  assert.equal(repoFromRemote("https://user:tok@github.com/a/b.git"), "a/b");
});

test("repoFromRemote anchors the host and rejects dot names", () => {
  assert.equal(repoFromRemote("https://evil.example/github.com/x/y.git"), null);
  assert.equal(repoFromRemote("C:/x/github.com/a/b"), null);
  assert.equal(repoFromRemote("/home/me/github.com:a/b"), null);
  assert.equal(repoFromRemote("https://evil.example/x@github.com/a/b"), null);
  assert.equal(repoFromRemote("https://github.com/a/.."), null);
  assert.equal(repoFromRemote("https://github.com/../b"), null);
  assert.throws(() => pagesTarget("a/.."));
});

test("withTempDir removes the dir and exits 130 on SIGINT, unless keep", () => {
  for (const keep of [false, true]) {
    const proc = new EventEmitter();
    const exits = [];
    let made;
    withTempDir(
      "mogov-sigint-",
      (dir) => {
        made = dir;
        proc.emit("SIGINT");
        assert.equal(existsSync(dir), keep);
      },
      { keep, proc, exit: (c) => exits.push(c) },
    );
    assert.deepEqual(exits, [130]);
    assert.equal(proc.listenerCount("SIGINT"), 0);
    if (keep) rmSync(made, { recursive: true, force: true });
  }
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
    allowDirty: false,
    keep: false,
    remote: "origin",
  });
  assert.equal(parseArgs(["--dry-run", "--skip-build"]).opts.dryRun, true);
  assert.equal(parseArgs(["--remote", "up"]).opts.remote, "up");
  assert.deepEqual(parseArgs(["--dry-runn"]).errors, ["unknown argument --dry-runn"]);
  assert.equal(parseArgs(["--remote"]).errors.length, 1);
});

test("parseArgs rejects every way of choosing a branch (gh-pages is the only target)", () => {
  assert.equal(PAGES_BRANCH, "gh-pages");
  const attempts = [["--branch", "main"], ["--branch=main"], ["--branch"], ["--branch", "gh-pages"]];
  for (const argv of attempts) assert.ok(parseArgs(argv).errors.length > 0, argv.join(" "));
  assert.equal("branch" in parseArgs([]).opts, false);
  assert.equal(parseArgs(["--keep", "--allow-dirty"]).opts.keep, true);
});

test("pushUrl and redactUrl", () => {
  assert.equal(pushUrl("a/b"), "https://github.com/a/b.git");
  assert.equal(redactUrl("https://user:tok@github.com/a/b.git"), "https://***@github.com/a/b.git");
  assert.equal(redactUrl("git@github.com:a/b.git"), "git@github.com:a/b.git");
});

test("withTempDir removes the dir after success and after a throw, unless keep", () => {
  let seen;
  withTempDir("mogov-test-", (d) => (seen = d));
  assert.equal(existsSync(seen), false);
  const failing = (d) => {
    seen = d;
    throw new Error("git failed");
  };
  assert.throws(() => withTempDir("mogov-test-", failing), /git failed/);
  assert.equal(existsSync(seen), false);
  withTempDir("mogov-test-", (d) => (seen = d), { keep: true });
  assert.equal(existsSync(seen), true);
  rmSync(seen, { recursive: true, force: true });
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

test("resolveFile: a file that exists only under the wrong prefix is not found", () => {
  // the file sits at dist/b/a/index.html, so the link /b/a/ (base /b) looks for dist/a/... and must miss
  const files = new Set([path.join("dist", "b", "a", "index.html")]);
  const exists = (f) => files.has(f);
  const stat = () => ({ isDirectory: () => false });
  assert.equal(resolveFile("dist", "/b", "/b/a/", exists, stat), null);
  assert.ok(resolveFile("dist", "", "/b/a/", exists, stat));
});
