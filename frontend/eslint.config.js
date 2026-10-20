import js from "@eslint/js";
import astro from "eslint-plugin-astro";
import { defineConfig } from "eslint/config";
import globals from "globals";
import tseslint from "typescript-eslint";

export default defineConfig(
  { ignores: ["dist/", ".astro/", "node_modules/"] },
  js.configs.recommended,
  tseslint.configs.recommended,
  astro.configs.recommended,
  {
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
    rules: {
      // `const { drop: _drop, ...keep } = obj` is how we omit a field
      "@typescript-eslint/no-unused-vars": ["error", { varsIgnorePattern: "^_", ignoreRestSiblings: true }],
    },
  },
);
