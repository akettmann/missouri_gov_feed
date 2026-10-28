// Reads the reference docs and the loader list from the repo at build time (cwd is frontend/).
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { Lexer, type Tokens } from "marked";
import { parseOfficeDoc, type OfficeDoc } from "./officeDoc.ts";

const repo = path.resolve(process.cwd(), "..");

/** Loader names = src/mogov/loaders/*.py modules, the same names the `source:` labels use. */
export const loaderNames = (): Set<string> =>
  new Set(
    readdirSync(path.join(repo, "src/mogov/loaders"))
      .filter((f) => f.endsWith(".py") && !f.startsWith("_"))
      .map((f) => f.replace(/\.py$/, "")),
  );

/** Code names a Data clause may mention that are dbt models, not sources. */
export const DOC_MODELS: ReadonlySet<string> = new Set(["fct_judicial_retention"]);

/** Plain names for researched sources that have no loader yet, so no row in docs/sources.md. */
export const CANDIDATE_NAMES: ReadonlyMap<string, string> = new Map([
  ["mo_sos_business", "Missouri Secretary of State business filings"],
  ["mo_sos_rules", "Missouri Secretary of State rules filings"],
]);

/** Plain names for the dbt models a Data clause may name. */
export const MODEL_NAMES: ReadonlyMap<string, string> = new Map([
  ["fct_judicial_retention", "judicial retention results"],
]);

/**
 * Reader-facing source names, read from the Summary table of docs/sources.md (its "Source" column), so the
 * doc stays the one place the names live. Two loaders with the same source name are told apart by the title of
 * their own section ("## loader: title"), or by the first item of their "Data it provides" cell. A trailing "(domain.tld)" is dropped: it is a web address, not a name.
 */
export function sourceNames(markdown: string): Map<string, string> {
  const tokens = new Lexer().lex(markdown);
  const titles = new Map<string, string>();
  for (const t of tokens) {
    const m =
      t.type === "heading" && (t as Tokens.Heading).depth === 2
        ? /^(\w+): (.+)$/.exec((t as Tokens.Heading).text)
        : null;
    if (m) titles.set(m[1], m[2]);
  }
  const table = tokens.find(
    (t): t is Tokens.Table => t.type === "table" && (t as Tokens.Table).header[0]?.text === "Loader",
  );
  if (!table) throw new Error("docs/sources.md: no Summary table starting with a Loader column");
  const rows = table.rows.map((r) => ({
    loader: r[0].text.replace(/`/g, ""),
    name: r[1].text.replace(/\s*\([a-z0-9.-]+\.(?:gov|com|org)\)$/i, ""),
    data: titles.get(r[0].text.replace(/`/g, "")) ?? r[2].text.split(",")[0].trim(),
  }));
  const counts = new Map<string, number>();
  rows.forEach((r) => counts.set(r.name, (counts.get(r.name) ?? 0) + 1));
  return new Map(rows.map((r) => [r.loader, counts.get(r.name)! > 1 ? `${r.name}: ${r.data}` : r.name]));
}

export const readSourcesDoc = () => readFileSync(path.join(repo, "docs/sources.md"), "utf8");

/** Every code name the office docs may show by a plain name. */
export const docNames = (): Map<string, string> =>
  new Map([...sourceNames(readSourcesDoc()), ...CANDIDATE_NAMES, ...MODEL_NAMES]);

export const readDoc = (name: string) => readFileSync(path.join(repo, "docs/reference", name), "utf8");

export function loadResponsibilities(): OfficeDoc {
  return parseOfficeDoc(readDoc("office_responsibilities.md"), {
    requireData: true,
    loaders: loaderNames(),
    models: DOC_MODELS,
    names: docNames(),
  });
}
