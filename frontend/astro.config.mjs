// @ts-check
import { defineConfig } from "astro/config";
import staleExports from "./scripts/stale-exports.mjs";

// Fully static: every page and per-official JSON is prerendered from data/exports/*.parquet at build time.
export default defineConfig({
  output: "static",
  site: process.env.PUBLIC_SITE_URL,
  integrations: [staleExports()],
  trailingSlash: "ignore",
  build: { format: "directory" },
  vite: {
    // native addon; must be loaded by Node at build time, never bundled
    ssr: { external: ["@duckdb/node-api"] },
  },
});
