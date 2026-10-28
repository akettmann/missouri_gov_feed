// Post-build check for run-on words: Astro/prettier can drop the whitespace between text and an inline element
// across a line break, so "that is <strong>co-occurrence" ships as "that isco-occurrence". Flags a letter/digit
// glued to an opening inline tag, or a closing inline tag glued to a letter/digit, in dist/**/*.html text.
// Usage: node scripts/run-on-check.mjs [dist]
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const INLINE = "a|strong|em|b|i|code|abbr|mark|cite|q|time|kbd|dfn|var|samp";
// Tags whose contents are not prose (or where glued text is legitimate) are blanked out before scanning.
const OPAQUE = /<(script|style|svg|pre|textarea|title|head)\b[\s\S]*?<\/\1>|<!--[\s\S]*?-->/gi;
const OPEN_AFTER_WORD = new RegExp(String.raw`([\p{L}\p{N}])<(?:${INLINE})(?=[\s>])[^>]*>(?=\S)`, "gu");
// A span is usually a styling hook (sr-only text, an arrow, punctuation), so it only counts when glued to a word and
// its own text starts with a letter or digit: "Mercy<span class="badge">possible match</span>".
const SPAN_AFTER_WORD = /([\p{L}\p{N}])<span(?=[\s>])[^>]*>(?=[\p{L}\p{N}])/gu;
const WORD_AFTER_CLOSE = new RegExp(String.raw`</(?:${INLINE})>([\p{L}\p{N}])`, "gu");

// Intentional glue: add data-glue to the tag (<abbr data-glue>), or list the exact matched text (e.g. "H<abbr>")
// here. Keep this tiny and give a reason.
export const ALLOW = [];

const HINT =
  'add {" "} at the line break in the .astro source (or data-glue on the tag if the glue is intended)';

/** Run-on findings in one HTML string: [{ kind, context }]. */
export function findRunOns(html, allow = ALLOW) {
  const body = html.replace(OPAQUE, (m) => " ".repeat(m.length));
  const out = [];
  for (const [re, kind] of [
    [OPEN_AFTER_WORD, "word<tag"],
    [SPAN_AFTER_WORD, "word<span>word"],
    [WORD_AFTER_CLOSE, "</tag>word"],
  ]) {
    for (const m of body.matchAll(re)) {
      const context = body.slice(Math.max(0, m.index - 30), m.index + m[0].length + 30).replace(/\s+/g, " ");
      if (allow.includes(m[0]) || /\sdata-glue[\s=>]/.test(m[0])) continue;
      out.push({ kind, context, hint: HINT });
    }
  }
  return out;
}

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)],
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dist = path.resolve(process.argv[2] ?? "dist");
  let bad = 0;
  const files = walk(dist).filter((f) => f.endsWith(".html"));
  for (const f of files) {
    for (const r of findRunOns(readFileSync(f, "utf8"))) {
      if (bad++ < 60)
        console.log(`  RUN-ON ${path.relative(dist, f)} [${r.kind}]: ${r.context}  -> ${r.hint}`);
    }
  }
  console.log(`${files.length} pages checked, ${bad} run-on spots`);
  process.exit(bad ? 1 : 0);
}
