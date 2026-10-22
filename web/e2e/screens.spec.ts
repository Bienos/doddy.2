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
    // Memory and Ask Doddy (ADR-595): off, then with notes and a conversation, then a chat answer.
    await page.goto("/memory");
    await expect(page.getByRole("heading", { level: 2, name: "Na serwerze Doddy’ego nic nie jest przechowywane" })).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.screenshot({ path: `${out}/${project}-${scheme}-7-memory-off.png`, fullPage: true });
    await request.put("/v1/web/memory/state", { headers, data: { notes: true, conversations: true } });
    const keptNote = (n: number, text: string) => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, text, source: n % 2 ? "explicit_voice" : "explicit_text", kind: n === 1 ? "fact" : undefined, capturedAt: new Date(Date.now() - n * 86_400_000).toISOString() });
    await request.put("/v1/web/memory/notes", {
      headers,
      data: { items: [keptNote(1, "Anna's birthday is 14 March"), keptNote(2, "Dentist on Friday at 9"), keptNote(3, "Zaproszenie od Łukasza na sobotę, trzeba przynieść wino"), keptNote(4, "Passport expires in June: renew it before the trip")] },
    });
    await request.put("/v1/web/memory/conversations/00000000-0000-4000-8000-0000000000c1", {
      headers,
      data: {
        startedAt: new Date(Date.now() - 7_200_000).toISOString(),
        endedAt: new Date(Date.now() - 7_000_000).toISOString(),
        language: "pl",
        endedBy: "you",
        turns: [
          { role: "user", text: "Kiedy są urodziny Anny?" },
          { role: "doddy", text: "Urodziny Anny są 14 marca." },
          { role: "user", text: "Dzięki, dodaj prezent do listy." },
        ],
      },
    });
    await page.goto("/memory");
    await expect(page.getByText("Anna's birthday is 14 March")).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.screenshot({ path: `${out}/${project}-${scheme}-8-memory-notes.png`, fullPage: true });
    await page.getByRole("tab", { name: "Rozmowy" }).click();
    await page.getByRole("button", { name: "Czytaj" }).click();
    await expect(page.getByText("Urodziny Anny są 14 marca.")).toBeVisible();
    await page.screenshot({ path: `${out}/${project}-${scheme}-8-memory-conversation.png`, fullPage: true });
    await page.goto("/ask");
    await page.getByRole("textbox", { name: "Twoje pytanie" }).fill("Kiedy są urodziny Anny?");
    await page.getByRole("button", { name: "Zapytaj", exact: true }).click();
    await expect(page.getByText(/^DEMO:/)).toBeVisible();
    await page.getByText(/Z Twoich notatek i rozmów \(/).click();
    await page.screenshot({ path: `${out}/${project}-${scheme}-8-ask.png`, fullPage: true });
    await request.put("/v1/web/memory/state", { headers, data: { notes: false, conversations: false } });
    // On a small screen the links are in a sheet under the header.
    if ((page.viewportSize()?.width ?? 1280) < 800) {
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.getByRole("button", { name: "Menu" }).click();
      await page.screenshot({ path: `${out}/${project}-${scheme}-9-menu-open.png` });
    }
  });
}
