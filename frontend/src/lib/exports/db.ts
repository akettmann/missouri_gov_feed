// Build-time reader for data/exports/*.parquet (written by `uv run mogov export --format parquet`).
import { existsSync, statSync } from "node:fs";
import path from "node:path";
import { DuckDBInstance, type DuckDBConnection } from "@duckdb/node-api";
import { assertNoMissingColumns, REQUIRED_COLUMNS } from "./requiredColumns.ts";

/** MOGOV_EXPORTS overrides the default `<repo>/data/exports`; builds run from frontend/ (pnpm scripts). */
export const EXPORTS_DIR = path.resolve(
  process.env.MOGOV_EXPORTS ?? path.join(process.cwd(), "..", "data", "exports"),
);

export function exportPath(table: string): string {
  return path.join(EXPORTS_DIR, `${table}.parquet`).replaceAll("\\", "/");
}

export function hasExport(table: string): boolean {
  return existsSync(exportPath(table));
}

export function exportedAt(table: string): Date | null {
  return hasExport(table) ? statSync(exportPath(table)).mtime : null;
}

let conn: Promise<DuckDBConnection> | undefined;

function connection(): Promise<DuckDBConnection> {
  conn ??= DuckDBInstance.create(":memory:").then((db) => db.connect());
  return conn;
}

const checked = new Map<string, Promise<string[]>>();

/** Column names of an export file, read once per table. */
function exportColumns(table: string): Promise<string[]> {
  let cols = checked.get(table);
  if (!cols) {
    cols = connection()
      .then((c) =>
        c.runAndReadAll(
          `select column_name from (describe select * from read_parquet('${exportPath(table)}'))`,
        ),
      )
      .then((r) => r.getRowObjectsJson().map((row) => String(row.column_name)));
    checked.set(table, cols);
    // Do not keep a failed lookup for the process lifetime: `astro dev` must recover after a re-export.
    cols.catch(() => checked.delete(table));
  }
  return cols;
}

/** Fails with a re-export message when an export that exists lacks columns REQUIRED_COLUMNS declares. */
async function assertExportsCurrent(tables: string[]): Promise<void> {
  const actual: Record<string, string[]> = {};
  for (const t of tables) if (t in REQUIRED_COLUMNS && hasExport(t)) actual[t] = await exportColumns(t);
  assertNoMissingColumns(actual);
}

/**
 * Run SQL where `{table}` placeholders become read_parquet('<exports>/table.parquet').
 * Cast DATE/DECIMAL/BIGINT in the SQL so rows come back as plain JSON-safe values.
 * Values that vary go in `params` (bound to `?` placeholders), never into the SQL text.
 */
export async function query<T>(sql: string, params?: (string | number)[]): Promise<T[]> {
  const used = [...new Set([...sql.matchAll(/\{(\w+)\}/g)].map((m) => m[1]))];
  await assertExportsCurrent(used);
  const resolved = sql.replace(/\{(\w+)\}/g, (_, t: string) => {
    if (!hasExport(t)) {
      throw new Error(`missing export ${exportPath(t)}; run \`uv run mogov export --format parquet\``);
    }
    return `read_parquet('${exportPath(t)}')`;
  });
  try {
    const reader = await (await connection()).runAndReadAll(resolved, params);
    return reader.getRowObjectsJson() as unknown as T[];
  } catch (e) {
    throw await explainBinderError(e, used);
  }
}

/**
 * Catch-all for tables REQUIRED_COLUMNS does not list: a binder error naming a column that one of the
 * exports in this SQL lacks is a stale export, so say so. Otherwise it is a real SQL bug: rethrow as is.
 */
async function explainBinderError(e: unknown, tables: string[]): Promise<unknown> {
  const m = /Binder Error: .*?(?:Referenced column|Column) "(\w+)"/s.exec(
    e instanceof Error ? e.message : "",
  );
  if (!m) return e;
  const stale: Record<string, string[]> = {};
  for (const t of tables) {
    if (!hasExport(t)) continue;
    const cols = await exportColumns(t).catch(() => null);
    if (cols && !cols.includes(m[1])) stale[t] = [m[1]];
  }
  try {
    assertNoMissingColumns(Object.fromEntries(Object.keys(stale).map((t) => [t, []])), stale);
  } catch (staleError) {
    return staleError;
  }
  return e;
}
