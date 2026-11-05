import { type APIRequestContext, expect, type Page, test } from "@playwright/test";
import { daysAgo, logbookDay } from "./logbookDay.js";

/**
 * The continuity promise, end to end (ADR-600): something made on the iPhone opens on the web,
 * under the same account, with the iPhone vouching for the browser. "The iPhone" here is the
 * app's own HTTP calls (device sign-in, ASK-01's prepare and run, a sign-in code); the browser is
 * a real Chromium against the real backend.
 */

// One fixed device: the test server belongs to the first iPhone that signs in (ADR-563).
const DEVICE_ID = "6f1c2c4e-8b1d-4c39-9a7e-2a4b5c6d7e8f";

async function phone(request: APIRequestContext): Promise<string> {
  const res = await request.post("/v1/session/device", { data: { deviceId: DEVICE_ID } });
  expect(res.status()).toBe(200);
  return (await res.json()).token as string;
}

async function makeDocument(request: APIRequestContext, token: string, title: string): Promise<void> {
  const headers = { authorization: `Bearer ${token}` };
  const args = { kind: "deck", title, request: "Compare five affordable laptops for university" };
  const asked = await request.post("/v1/tools/prepare", { headers, data: { tool: "make_document", arguments: args } });
  expect(asked.status()).toBe(200);
  const { approvalId } = await asked.json();
  const ran = await request.post("/v1/tools/run", { headers, data: { tool: "make_document", arguments: args, timeZone: "Europe/Warsaw", approvalId } });
  expect(ran.status()).toBe(200);
  expect((await ran.json()).document.status).toBe("working");
}

async function code(request: APIRequestContext, token: string): Promise<string> {
  const res = await request.post("/v1/web/link-codes", { headers: { authorization: `Bearer ${token}` }, data: {} });
  expect(res.status()).toBe(200);
  return (await res.json()).code as string;
}

async function logbookSwitch(request: APIRequestContext, token: string, enabled: boolean): Promise<void> {
  const res = await request.put("/v1/web/logbook/state", { headers: { authorization: `Bearer ${token}` }, data: { enabled } });
  expect(res.status()).toBe(200);
}

async function signIn(page: Page, signInCode: string): Promise<void> {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Zaloguj się do Doddy" })).toBeVisible();
  await page.getByLabel("Kod logowania").fill(signInCode.toLowerCase());
  await page.getByRole("button", { name: "Zaloguj się" }).click();
  await expect(page.getByRole("heading", { name: "Jestem." })).toBeVisible();
}

/**
 * The page's rules (CSP) must not block anything the app itself needs, and the page must not
 * throw. A failed request is not a problem in itself: a signed-out page's first session check is
 * a 401 on purpose, and Chromium logs it.
 */
function watchConsole(page: Page): string[] {
  const problems: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error" && !/^Failed to load resource: the server responded with a status of 401/.test(message.text())) problems.push(message.text());
  });
  page.on("pageerror", (error) => problems.push(error.message));
  return problems;
}

test("a deck made on the iPhone is downloaded in the browser, signed in with the iPhone's code", async ({ page, request, context }) => {
  const problems = watchConsole(page);
  const token = await phone(request);
  const title = `Laptops for university ${test.info().project.name}`;
  await makeDocument(request, token, title);

  await signIn(page, await code(request, token));

  // The session cookie can't be read by the page's scripts, and isn't sent cross-site.
  const cookie = (await context.cookies()).find((c) => c.name === "doddy_web");
  expect(cookie?.httpOnly).toBe(true);
  expect(cookie?.sameSite).toBe("Strict");
  expect(await page.evaluate(() => document.cookie)).not.toContain("doddy_web");

  // Home shows the real document; the demo server says it is a demo.
  await expect(page.getByRole("note")).toContainText("Serwer demonstracyjny");
  await expect(page.getByText(`${title}.pptx`).first()).toBeVisible();

  // Documents: download it and check the bytes are the file Doddy made.
  await page.goto("/documents");
  await expect(page.getByRole("heading", { name: "Dokumenty" })).toBeVisible();
  const [download] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: `Pobierz: ${title}.pptx` }).click()]);
  expect(download.suggestedFilename()).toBe(`${title}.pptx`);
  const path = await download.path();
  const { readFile } = await import("node:fs/promises");
  expect((await readFile(path)).toString("utf8")).toBe(`DEMO deck: ${title}`);

  expect(problems).toEqual([]);
});

test("the iPhone signs the browser out, and the browser is out at once", async ({ page, request }) => {
  const token = await phone(request);
  await signIn(page, await code(request, token));
  await page.goto("/settings");
  await expect(page.getByText("Ta przeglądarka")).toBeVisible();

  const listed = await request.get("/v1/web/sessions", { headers: { authorization: `Bearer ${token}` } });
  const sessions = (await listed.json()).sessions as { id: string; createdAt: string }[];
  const newest = sessions.sort((a, b) => b.createdAt.localeCompare(a.createdAt))[0]!;
  const revoked = await request.delete(`/v1/web/sessions/${newest.id}`, { headers: { authorization: `Bearer ${token}` } });
  expect(revoked.status()).toBe(200);

  await page.reload();
  await expect(page.getByRole("heading", { name: "Zaloguj się do Doddy" })).toBeVisible();
});

test("a used code doesn't work twice, and the page says so in Polish", async ({ page, request, browser }) => {
  const token = await phone(request);
  const once = await code(request, token);
  await signIn(page, once);
  const other = await browser.newContext();
  const second = await other.newPage();
  await second.goto("/");
  await second.getByLabel("Kod logowania").fill(once);
  await second.getByRole("button", { name: "Zaloguj się" }).click();
  await expect(second.getByRole("alert")).toContainText("Ten kod nie zadziałał");
  await other.close();
});

test("keyboard and small screens: skip link, focus on the heading, menu, no sideways scroll", async ({ page, request }) => {
  const token = await phone(request);
  await signIn(page, await code(request, token));
  const narrow = (page.viewportSize()?.width ?? 1280) < 800;
  if (narrow) {
    const menu = page.getByRole("button", { name: "Menu" });
    await expect(menu).toHaveAttribute("aria-expanded", "false");
    await menu.click();
    await expect(menu).toHaveAttribute("aria-expanded", "true");
  }
  await page.getByRole("link", { name: "Połączone aplikacje" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Połączone aplikacje" })).toBeFocused();
  const sideways = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(sideways).toBeLessThanOrEqual(0);

  // A fresh visit: focus starts at the top, so the first Tab reaches the skip link.
  await page.goto("/activity");
  await expect(page.getByRole("heading", { level: 1, name: "Co zrobił Doddy" })).toBeVisible();
  await expect(page.getByRole("heading", { level: 1 })).not.toBeFocused();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "Przejdź do treści" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#main$/);
});

test("the page's own security headers are in place", async ({ request }) => {
  const res = await request.get("/documents");
  expect(res.status()).toBe(200);
  const csp = res.headers()["content-security-policy"] ?? "";
  expect(csp).toContain("script-src 'self'");
  expect(csp).toContain("frame-ancestors 'none'");
  expect(res.headers()["x-frame-options"]).toBe("DENY");
});

test("Logbook opens from the menu: off at first, an example on request, under the page's own security rules", async ({ page, request }) => {
  const problems = watchConsole(page);
  const token = await phone(request);
  await logbookSwitch(request, token, false);
  await signIn(page, await code(request, token));

  // The menu on a small screen is a sheet; on a wide one the links are in the header.
  const narrow = (page.viewportSize()?.width ?? 1280) < 800;
  if (narrow) await page.getByRole("button", { name: "Menu" }).click();
  await page.getByRole("link", { name: /Dziennik/ }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Dziennik" })).toBeFocused();
  await expect(page).toHaveURL(/\/logbook$/);
  // Nothing has been sent: the page says Logbook is off, and offers an example instead of zeros.
  await expect(page.getByRole("heading", { level: 2, name: "Dziennik jest wyłączony" })).toBeVisible();
  await expect(page.locator(".lb-rc-line")).toHaveCount(0);
  await page.getByRole("button", { name: "Pokaż przykład" }).click();
  // The example says its numbers are made up, and the week's receipt is drawn.
  await expect(page.getByRole("note").filter({ hasText: "Przykład." })).toContainText("Wymyślone liczby");
  await expect(page.getByRole("heading", { level: 2, name: "Twój tydzień z Doddym" })).toBeVisible();
  await expect(page.locator(".lb-rc-line").first()).toContainText("Rozmowy");
  await expect(page.locator("svg[aria-label='Rozmowy w poszczególne dni tygodnia'] rect.lb-hit")).toHaveCount(7);

  // The charts really are drawn with the sizes the CSP allows: no inline style attribute is in the markup.
  expect(await page.evaluate(() => [...document.querySelectorAll("[style]")].filter((el) => !(el instanceof SVGElement) && el.getAttribute("style")?.includes("{")).length)).toBe(0);

  // Closer look: every chart, the sortable table, the heatmap with its 168 cells.
  await page.getByRole("tab", { name: /Z bliska/ }).click();
  await expect(page.getByRole("heading", { name: "Każde narzędzie z liczbą użyć" })).toBeVisible();
  await expect(page.locator("svg[aria-label='Rozmowy według dnia tygodnia i godziny'] rect.lb-cell")).toHaveCount(168);
  await page.getByRole("button", { name: "90 dni" }).click();
  await expect(page.getByRole("img", { name: "Rozmowy tydzień po tygodniu" }).or(page.locator("svg[aria-label='Rozmowy tydzień po tygodniu']"))).toBeVisible();
  await page.getByRole("checkbox", { name: "Pokaż jako tabele" }).check();
  await expect(page.getByRole("table", { name: "Rozmowy tydzień po tygodniu" })).toBeVisible();

  // A tooltip follows the pointer over a column and goes away.
  await page.getByRole("checkbox", { name: "Pokaż jako tabele" }).uncheck();
  const column = page.locator("svg[aria-label='Rozmowy tydzień po tygodniu'] rect.lb-hit").nth(3);
  // The tooltip drops on scroll (it is fixed to the window); scroll the column into view first.
  await column.scrollIntoViewIfNeeded();
  await page.waitForTimeout(150);
  await column.hover();
  await expect(page.getByRole("tooltip")).toContainText("Rozmowy");
  await page.mouse.move(2, 2);
  await expect(page.getByRole("tooltip")).toHaveCount(0);

  const sideways = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(sideways).toBeLessThanOrEqual(0);
  // No CSP violation, no failed request, no error in the console.
  expect(problems).toEqual([]);
});

test("Logbook shows what the iPhone sent, downloads it, and deletes it when asked", async ({ page, request }) => {
  const problems = watchConsole(page);
  const token = await phone(request);
  const headers = { authorization: `Bearer ${token}` };
  await logbookSwitch(request, token, true);

  // The iPhone sends three days; one with a word where a number belongs is refused whole.
  for (const [ago, n] of [[2, 4], [1, 1], [0, 3]] as const) {
    const sent = await request.put(`/v1/web/logbook/days/${daysAgo(ago)}`, { headers, data: logbookDay(daysAgo(ago), n) });
    expect(sent.status()).toBe(200);
  }
  const refused = await request.put(`/v1/web/logbook/days/${daysAgo(0)}`, { headers, data: { ...logbookDay(daysAgo(0), 3), transcript: "buy milk" } });
  expect(refused.status()).toBe(400);
  expect(await refused.text()).not.toContain("buy milk");

  await signIn(page, await code(request, token));
  await page.goto("/logbook");
  await expect(page.getByRole("heading", { level: 1, name: "Dziennik" })).toBeVisible();
  // Real numbers: no example banner, the receipt adds up what was sent (4 + 1 + 3), and the week can start mid-week.
  await expect(page.locator(".lb-rc-line").first()).toContainText("Rozmowy");
  await expect(page.locator(".lb-rc-line").first().locator("dd")).toHaveText("8");
  await expect(page.getByRole("note").filter({ hasText: "Przykład." })).toHaveCount(0);

  // Download everything: the server's own file.
  const [file] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "Pobierz wszystko" }).click()]);
  expect(file.suggestedFilename()).toMatch(/^doddy-logbook-\d{4}-\d{2}-\d{2}\.json$/);
  const saved = JSON.parse(await (await import("node:fs/promises")).readFile((await file.path()) as string, "utf8"));
  expect(saved.enabled).toBe(true);
  expect(saved.days).toHaveLength(3);
  expect(JSON.stringify(saved)).not.toContain("buy milk");

  // The numbers shown, as CSV, from Closer look.
  await page.getByRole("tab", { name: /Z bliska/ }).click();
  const [csv] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "Pobierz CSV" }).click()]);
  expect(csv.suggestedFilename()).toBe(`doddy-logbook-${daysAgo(2)}-to-${daysAgo(0)}.csv`);

  // A browser can read and delete but not write: its own cookie can't send a day or switch Logbook.
  const cookieWrite = await page.evaluate(async (day) => {
    const res = await fetch(`/v1/web/logbook/state`, { method: "PUT", headers: { "content-type": "application/json", "x-doddy-web": "1" }, body: JSON.stringify({ enabled: false }) });
    return { status: res.status, day };
  }, daysAgo(0));
  expect(cookieWrite.status).toBe(401);

  // Delete takes two taps, then the server answers and the page says how many days went.
  await page.getByRole("button", { name: "Usuń wszystko stąd" }).click();
  await page.getByRole("button", { name: "Dotknij ponownie, by usunąć wszystko" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Usunięto." })).toContainText("3");
  await expect(page.getByRole("heading", { level: 2, name: "Nic jeszcze nie policzono" })).toBeVisible();

  const sideways = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(sideways).toBeLessThanOrEqual(0);
  expect(problems).toEqual([]);
  await logbookSwitch(request, token, false);
});

test("Memory and Ask Doddy: what the iPhone keeps on the server is read, searched, asked about, downloaded and deleted", async ({ page, request }) => {
  const problems = watchConsole(page);
  const token = await phone(request);
  const headers = { authorization: `Bearer ${token}` };
  const put = (path: string, data: unknown) => request.put(path, { headers, data });
  const note = (n: number, text: string) => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, text, source: "explicit_voice", capturedAt: new Date(Date.now() - n * 86_400_000).toISOString() });

  // Off first: the page says nothing is kept, and the server refuses anything the iPhone sends.
  expect((await put("/v1/web/memory/state", { notes: false, conversations: false })).status()).toBe(200);
  expect((await put("/v1/web/memory/notes", { items: [note(1, "Anna's birthday is 14 March")] })).status()).toBe(403);
  await signIn(page, await code(request, token));
  await page.goto("/memory");
  await expect(page.getByRole("heading", { level: 2, name: "Na serwerze Doddy’ego nic nie jest przechowywane" })).toBeVisible();
  await expect(page.getByRole("heading", { level: 2, name: "Na serwerze Doddy’ego nic nie jest przechowywane" })).toBeVisible();

  // The iPhone turns both on and sends two notes and a conversation.
  expect((await put("/v1/web/memory/state", { notes: true, conversations: true })).status()).toBe(200);
  expect((await put("/v1/web/memory/notes", { items: [note(1, "Anna's birthday is 14 March"), note(2, "Dentist on Friday at 9")] })).status()).toBe(200);
  const talk = "00000000-0000-4000-8000-0000000000c1";
  const started = new Date(Date.now() - 3_600_000).toISOString();
  expect(
    (await put(`/v1/web/memory/conversations/${talk}`, {
      startedAt: started,
      endedAt: new Date().toISOString(),
      language: "pl",
      endedBy: "you",
      turns: [
        { role: "user", text: "Kiedy są urodziny Anny?" },
        { role: "doddy", text: "Urodziny Anny są 14 marca." },
      ],
    })).status(),
  ).toBe(200);

  await page.goto("/memory");
  await expect(page.getByText("Anna's birthday is 14 March")).toBeVisible();
  await expect(page.getByText("Dentist on Friday at 9")).toBeVisible();
  await page.getByRole("searchbox", { name: "Szukaj w notatkach" }).fill("dentist");
  await expect(page.getByText("Anna's birthday is 14 March")).toHaveCount(0);
  await expect(page.getByText("Dentist on Friday at 9")).toBeVisible();

  // Conversations: read in full.
  await page.getByRole("tab", { name: "Rozmowy" }).click();
  await page.getByRole("button", { name: "Czytaj" }).click();
  await expect(page.getByText("Urodziny Anny są 14 marca.")).toBeVisible();

  // A browser's own cookie can read but never write: it can't send a note or switch keeping on.
  const refused = await page.evaluate(async () => {
    const res = await fetch("/v1/web/memory/notes", { method: "PUT", headers: { "content-type": "application/json", "x-doddy-web": "1" }, body: JSON.stringify({ items: [] }) });
    return res.status;
  });
  expect(refused).toBe(401);

  // The chat (ADR-604; the demo model answers and cites the first thing it was given: a note here).
  await page.goto("/chat");
  await page.getByRole("textbox", { name: "Napisz do Doddy’ego" }).fill("Kiedy są urodziny Anny?");
  await page.getByRole("button", { name: "Wyślij", exact: true }).click();
  await expect(page.getByText(/^DEMO:/)).toBeVisible();
  await page.getByText(/Źródła \(/).click();
  await expect(page.locator(".chat-sources li").first()).toBeVisible();

  // Download everything: the server's own file, with the switches, notes and conversations.
  await page.goto("/memory");
  const [file] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "Pobierz wszystko" }).click()]);
  expect(file.suggestedFilename()).toMatch(/^doddy-memory-\d{4}-\d{2}-\d{2}\.json$/);
  const saved = JSON.parse(await (await import("node:fs/promises")).readFile((await file.path()) as string, "utf8"));
  expect(saved.switches).toEqual({ notes: true, conversations: true });
  expect(saved.notes).toHaveLength(2);
  expect(saved.conversations[0].turns).toHaveLength(2);

  // Delete everything: two taps, then both are off and the iPhone's next send is refused.
  await page.getByRole("button", { name: "Usuń wszystko stąd" }).click();
  await page.getByRole("button", { name: "Dotknij ponownie, by usunąć wszystko" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Usunięto." })).toContainText("Notatki: 2");
  await expect(page.getByRole("heading", { level: 2, name: "Na serwerze Doddy’ego nic nie jest przechowywane" })).toBeVisible();
  expect((await put("/v1/web/memory/notes", { items: [note(1, "Anna's birthday is 14 March")] })).status()).toBe(403);

  const sideways = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(sideways).toBeLessThanOrEqual(0);
  expect(problems).toEqual([]);
});

test("the chat: with nothing kept it answers from the account, keeps the chat in the list, and fits a phone", async ({ page, request }) => {
  const problems = watchConsole(page);
  const token = await phone(request);
  await request.put("/v1/web/memory/state", { headers: { authorization: `Bearer ${token}` }, data: { notes: false, conversations: false } });
  await logbookSwitch(request, token, true);
  for (const day of [daysAgo(0), daysAgo(1)]) {
    expect((await request.put(`/v1/web/logbook/days/${day}`, { headers: { authorization: `Bearer ${token}` }, data: logbookDay(day, 2) })).status()).toBe(200);
  }
  await signIn(page, await code(request, token));
  await page.getByRole("link", { name: "Napisz do Doddy’ego" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Czat z Doddym" })).toBeFocused();
  await expect(page.getByRole("heading", { level: 2, name: "W czym mogę pomóc?" })).toBeVisible();

  // What it can see: Logbook's two days, nothing kept, nothing connected.
  await page.getByRole("button", { name: "Co widzę" }).click();
  const panel = page.locator(".chat-sees");
  await expect(panel).toContainText("Liczniki z 2 dni");
  await expect(panel).toContainText("Nic nie jest połączone");
  const box = (await panel.boundingBox())!;
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.keyboard.press("Escape");

  // A usage question is offered because Logbook has days; the demo model cites Logbook, and the source links there.
  await page.getByRole("button", { name: "Ile rozmawialiśmy w tym tygodniu?" }).click();
  await expect(page.getByText("DEMO: here is what your account's logbook shows.")).toBeVisible(); // the demo model's own English
  await page.getByText(/Źródła \(1\)/).click();
  await expect(page.locator(".chat-sources").getByRole("link", { name: "Otwórz" })).toHaveAttribute("href", "/logbook");

  // The chat is in the list, and it is still there after a reload (this browser only).
  if (await page.getByRole("button", { name: "Pokaż czaty" }).isVisible()) await page.getByRole("button", { name: "Pokaż czaty" }).click();
  await expect(page.getByRole("complementary", { name: "Twoje czaty" }).getByRole("button", { name: "Ile rozmawialiśmy w tym tygodniu?", exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("heading", { level: 1, name: "Czat z Doddym" })).toBeVisible();
  if (await page.getByRole("button", { name: "Pokaż czaty" }).isVisible()) await page.getByRole("button", { name: "Pokaż czaty" }).click();
  await expect(page.getByRole("complementary", { name: "Twoje czaty" }).getByRole("button", { name: "Ile rozmawialiśmy w tym tygodniu?", exact: true })).toBeVisible();

  const sideways = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(sideways).toBeLessThanOrEqual(0);
  expect(problems).toEqual([]);
  await logbookSwitch(request, token, false);
});
