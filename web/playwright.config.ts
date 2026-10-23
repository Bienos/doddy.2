import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end: the real backend (mock providers, in-memory database, device sign-in on) serves the
 * built web app on one origin, exactly as in production (ADR-600). The test plays the iPhone with
 * the same HTTP calls the app makes. Build both first: `npm run build` here and in backend/.
 */
const PORT = Number(process.env.DODDY_E2E_PORT ?? 8799);
const ORIGIN = `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: "e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [["list"]],
  timeout: 60_000,
  use: {
    baseURL: ORIGIN,
    trace: "off",
    ...(process.env.PLAYWRIGHT_CHROMIUM ? { launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM } } : {}),
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] } },
    { name: "phone-size", use: { ...devices["Pixel 7"] } },
  ],
  webServer: {
    command: "node dist/src/server.js",
    cwd: "../backend",
    url: `${ORIGIN}/v1/health`,
    reuseExistingServer: false,
    timeout: 60_000,
    env: {
      DODDY_MODE: "mock",
      DODDY_ENV: "test",
      DODDY_AUTH_MODE: "signed",
      // A throwaway key for this test server only (32 bytes of 7s); never a real key.
      DODDY_SESSION_SIGNING_KEY: Buffer.alloc(32, 7).toString("base64"),
      DODDY_DEVICE_SIGNUP: "first-device",
      DODDY_HOST: "127.0.0.1",
      DODDY_PORT: String(PORT),
      DODDY_DB_PATH: ":memory:",
      DODDY_WEB_ORIGIN: ORIGIN,
      DODDY_WEB_DIST: "../web/dist",
      // Every test signs in from 127.0.0.1; the real default is 10 per quarter hour.
      DODDY_WEB_SIGNIN_TRIES_PER_CLIENT: "200",
    },
  },
});
