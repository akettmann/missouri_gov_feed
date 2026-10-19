// Build-time reader for data/exports/*.parquet (written by `uv run mogov export --format parquet`).
import { existsSync, statSync } from "node:fs";
import path from "node:path";
import { DuckDBInstance, type DuckDBConnection } from "@duckdb/node-api";

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

/**
 * Run SQL where `{table}` placeholders become read_parquet('<exports>/table.parquet').
 * Cast DATE/DECIMAL/BIGINT in the SQL so rows come back as plain JSON-safe values.
 */
export async function query<T>(sql: string): Promise<T[]> {
  const resolved = sql.replace(/\{(\w+)\}/g, (_, t: string) => {
    if (!hasExport(t)) {
      throw new Error(`missing export ${exportPath(t)}; run \`uv run mogov export --format parquet\``);
    }
    return `read_parquet('${exportPath(t)}')`;
  });
  const reader = await (await connection()).runAndReadAll(resolved);
  return reader.getRowObjectsJson() as unknown as T[];
}
