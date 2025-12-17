// ESLint flat config for Vue 3 + TypeScript
import js from "@eslint/js";
import vue from "eslint-plugin-vue";
import vueParser from "vue-eslint-parser";
import tseslint from "typescript-eslint";
import globals from "globals";

export default [
  // Ignore build artifacts and dependencies
  { ignores: ["dist", "node_modules"] },

  // Base JS recommended rules
  js.configs.recommended,

  // Global language options
  {
    files: ["**/*.{js,cjs,mjs,ts,tsx,vue}"],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: "module",
      globals: globals.browser,
    },
  },

  // TypeScript recommended rules (non type-aware for speed/setup simplicity)
  ...tseslint.configs.recommended,

  // Vue 3 recommended rules (with SFC parser)
  ...vue.configs["flat/recommended"],
  // Ensure .vue files use Vue parser and TS inside <script>
  {
    files: ["**/*.vue"],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        // Use TS parser inside <script lang="ts">
        parser: tseslint.parser,
        ecmaVersion: 2023,
        sourceType: "module",
        extraFileExtensions: [".vue"],
      },
    },
    rules: {
      // Allow single-word component names (common for views)
      "vue/multi-word-component-names": "off",
    },
  },

  // Project-specific tweaks
  {
    files: ["**/*.{ts,tsx,vue}"],
    rules: {
      // So linting does not fail builds initially
      "@typescript-eslint/no-explicit-any": "warn",
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      "vue/no-dupe-keys": "warn",
    },
  },

  // Allow common patterns in Vite's env typings
  {
    files: ["src/vite-env.d.ts"],
    rules: {
      "@typescript-eslint/no-empty-object-type": "off",
      "@typescript-eslint/no-explicit-any": "off",
    },
  },

  // Node.js globals for build scripts
  {
    files: ["scripts/**/*.js"],
    languageOptions: {
      globals: globals.node,
    },
  },
];
