// Build-time warning: exported parquet older than the DuckDB file means `mogov export` was skipped after a build.
import { existsSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

/** Same resolution as src/mogov/config.py: MOGOV_DB, else <MOGOV_DATA_DIR or ../data>/mogov.duckdb. */
export function resolveDbPath(env = process.env, cwd = process.cwd()) {
  if (env.MOGOV_DB) return path.resolve(cwd, env.MOGOV_DB);
  return path.resolve(cwd, env.MOGOV_DATA_DIR ?? path.join("..", "data"), "mogov.duckdb");
}

/** Same default as src/lib/exports/db.ts. */
export function resolveExportsDir(env = process.env, cwd = process.cwd()) {
  return path.resolve(cwd, env.MOGOV_EXPORTS ?? path.join("..", "data", "exports"));
}

function formatAge(ms) {
  const m = Math.round(ms / 60000);
  if (m < 60) return `${m}m`;
  if (m < 2880) return `${(m / 60).toFixed(1)}h`;
  return `${(m / 1440).toFixed(1)}d`;
}

/** Returns the warning text, or null when there is nothing to warn about (including no DuckDB file). */
export function staleExportsWarning(dbPath, exportsDir) {
  if (!existsSync(dbPath) || !existsSync(exportsDir)) return null;
  const dbTime = statSync(dbPath).mtimeMs;
  const stale = readdirSync(exportsDir)
    .filter((f) => f.endsWith(".parquet"))
    .map((f) => ({ f, lag: dbTime - statSync(path.join(exportsDir, f)).mtimeMs }))
    .filter((s) => s.lag > 0);
  if (stale.length === 0) return null;
  return [
    `${stale.length} exported parquet file(s) in ${exportsDir} are older than ${dbPath}:`,
    ...stale.map((s) => `  ${s.f} (${formatAge(s.lag)} older than the DuckDB file)`),
    "The site would be built from stale data. Fix: `uv run mogov export`, then `pnpm build`.",
  ].join("\n");
}

/** Astro integration; astro:build:start fires once per build. */
export default function staleExports() {
  return {
    name: "stale-exports-warning",
    hooks: {
      "astro:build:start": ({ logger }) => {
        const msg = staleExportsWarning(resolveDbPath(), resolveExportsDir());
        if (msg) logger.warn(msg);
      },
    },
  };
}
