import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// Unit tests only: pure utils and composables, run against jsdom so the composables that read
// `window.location` and `localStorage` at import time load. No component mounting (yet) — that
// would need @vue/test-utils and the Vue plugin here.
export default defineConfig({
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.ts"],
    restoreMocks: true,
    unstubGlobals: true,
  },
});
