import { expect, test } from "@playwright/test";
import { daysAgo, logbookDay } from "./logbookDay.js";

/**
 * Screenshots for a person to look at (not a pixel comparison). Run on request:
 * DODDY_SCREENS=<folder> npx playwright test e2e/screens.spec.ts
 */
const out = process.env.DODDY_SCREENS;
test.skip(!out, "set DODDY_SCREENS to a folder to take screenshots");

const DEVICE_ID = "6f1c2c4e-8b1d-4c39-9a7e-2a4b5c6d7e8f";

for (const scheme of ["light", "dark"] as const) {
  test(`screens, ${scheme}`, async ({ page, request }) => {
    await page.emulateMedia({ colorScheme: scheme });
    const project = test.info().project.name;
    const token = (await (await request.post("/v1/session/device", { data: { deviceId: DEVICE_ID } })).json()).token as string;
    const headers = { authorization: `Bearer ${token}` };
    for (const [kind, title] of [["deck", "Laptops for university"], ["text", "Barcelona trip notes"]] as const) {
      const args = { kind, title, request: "For the screenshots" };
      const { approvalId } = await (await request.post("/v1/tools/prepare", { headers, data: { tool: "make_document", arguments: args } })).json();
      await request.post("/v1/tools/run", { headers, data: { tool: "make_document", arguments: args, timeZone: "Europe/Warsaw", approvalId } });
    }
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await page.screenshot({ path: `${out}/${project}-${scheme}-1-sign-in.png`, fullPage: true });
    const code = (await (await request.post("/v1/web/link-codes", { headers, data: {} })).json()).code as string;
    await page.getByLabel("Kod logowania").fill(code);
    await page.getByRole("button", { name: "Zaloguj się" }).click();
    await expect(page.getByRole("heading", { name: "Jestem." })).toBeVisible();
    await expect(page.getByText("Laptops for university.pptx").first()).toBeVisible();
    await page.screenshot({ path: `${out}/${project}-${scheme}-2-home.png`, fullPage: true });
    for (const [path, name] of [["/documents", "3-documents"], ["/apps", "4-apps"], ["/activity", "5-activity"], ["/settings", "6-settings"]] as const) {
      await page.goto(path);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
      await page.waitForLoadState("networkidle");
      await page.screenshot({ path: `${out}/${project}-${scheme}-${name}.png`, fullPage: true });
    }
    // Logbook (ADR-593): off at first, then both tabs with the example's numbers.
    await page.goto("/logbook");
    await expect(page.getByRole("heading", { level: 2, name: "Dziennik jest wyłączony" })).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.screenshot({ path: `${out}/${project}-${scheme}-7-logbook-off.png`, fullPage: true });
    await page.getByRole("button", { name: "Pokaż przykład" }).click();
    await expect(page.getByRole("heading", { level: 2, name: "Twój tydzień z Doddym" })).toBeVisible();
    await page.screenshot({ path: `${out}/${project}-${scheme}-7-logbook-glance.png`, fullPage: true });
    await page.getByRole("tab", { name: /Z bliska/ }).click();
    await expect(page.getByRole("heading", { name: "Każde narzędzie z liczbą użyć" })).toBeVisible();
    await page.screenshot({ path: `${out}/${project}-${scheme}-8-logbook-closer.png`, fullPage: true });
    // Real numbers: nine days the iPhone "sent" (one day missing), then Logbook off again.
    await request.put("/v1/web/logbook/state", { headers, data: { enabled: true } });
    for (const ago of [9, 8, 7, 6, 5, 4, 2, 1, 0]) {
      await request.put(`/v1/web/logbook/days/${daysAgo(ago)}`, { headers, data: logbookDay(daysAgo(ago), 1 + (ago % 4)) });
    }
    await page.goto("/logbook");
    await expect(page.locator(".lb-rc-line").first()).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.screenshot({ path: `${out}/${project}-${scheme}-7-logbook-real.png`, fullPage: true });
    await request.put("/v1/web/logbook/state", { headers, data: { enabled: false } });
    // On a small screen the links are in a sheet under the header.
    if ((page.viewportSize()?.width ?? 1280) < 800) {
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.getByRole("button", { name: "Menu" }).click();
      await page.screenshot({ path: `${out}/${project}-${scheme}-9-menu-open.png` });
    }
  });
}
