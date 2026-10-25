// Static link checker for a built dist/: every root-relative href/src/data-*-url must live under BASE and
// resolve to a file the way GitHub Pages would serve it. Usage: node scripts/link-check.mjs [dist] [base]
//   e.g. node scripts/link-check.mjs dist /missouri_gov_feed
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Root-relative URLs referenced by attributes in an HTML string (protocol-relative and external excluded). */
export function extractLinks(html) {
  const out = [];
  for (const m of html.matchAll(/\s(?:href|src|data-[a-z-]*url)=("([^"]*)"|'([^']*)')/g)) {
    const v = (m[2] ?? m[3]).trim();
    if (v.startsWith("/") && !v.startsWith("//")) out.push(v);
  }
  return out;
}

/** Map a URL path to the file Pages would serve (exact file, else dir/index.html), or null. */
export function resolveFile(distDir, base, urlPath, exists = existsSync, stat = statSync) {
  const p = decodeURIComponent(urlPath.split(/[?#]/)[0]);
  if (base && p !== base && !p.startsWith(`${base}/`)) return null; // outside the base: 404 on Pages
  const rel = p.slice(base.length).replace(/^\/+/, "");
  for (const c of [rel, path.posix.join(rel, "index.html"), `${rel}.html`]) {
    const f = path.join(distDir, c);
    if (exists(f) && !stat(f).isDirectory()) return f;
  }
  return null;
}

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)],
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dist = path.resolve(process.argv[2] ?? "dist");
  const base = (process.argv[3] ?? "").replace(/\/+$/, "");
  const bad = new Map();
  let n = 0;
  const seen = new Set();
  for (const f of walk(dist).filter((f) => f.endsWith(".html"))) {
    for (const l of extractLinks(readFileSync(f, "utf8"))) {
      n++;
      if (seen.has(l)) continue;
      seen.add(l);
      if (!resolveFile(dist, base, l)) bad.set(l, path.relative(dist, f));
    }
  }
  console.log(`${n} root-relative references, ${seen.size} unique, ${bad.size} broken`);
  for (const [l, from] of [...bad].slice(0, 40)) console.log(`  BROKEN ${l}  (first seen in ${from})`);
  process.exit(bad.size ? 1 : 0);
}
