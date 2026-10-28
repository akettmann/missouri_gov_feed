// Reads the reference docs and the loader list from the repo at build time (cwd is frontend/).
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
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

export const readDoc = (name: string) => readFileSync(path.join(repo, "docs/reference", name), "utf8");

export function loadResponsibilities(): OfficeDoc {
  return parseOfficeDoc(readDoc("office_responsibilities.md"), {
    requireData: true,
    loaders: loaderNames(),
    models: DOC_MODELS,
  });
}
