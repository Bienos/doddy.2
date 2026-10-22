import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

/**
 * Doddy Web is served by backend/ (ADR-579), so in production the API is the same origin.
 * In development the Vite server forwards /v1 to a local backend started with
 * DODDY_WEB_ORIGIN=http://127.0.0.1:5173 (see web/README.md); Origin and cookies pass through.
 */
export default defineConfig({
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: { "/v1": { target: process.env.DODDY_API ?? "http://127.0.0.1:8787", changeOrigin: false } },
  },
  build: {
    outDir: "dist",
    assetsDir: "assets",
    sourcemap: false,
    // The page's CSP allows scripts from this origin only; no inline module-preload helper.
    modulePreload: { polyfill: false },
  },
  test: {
    environment: "jsdom",
    include: ["test/**/*.test.{ts,tsx}"],
    setupFiles: ["test/setup.ts"],
    restoreMocks: true,
  },
});
