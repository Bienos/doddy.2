import { type APIRequestContext, expect, type Page, test } from "@playwright/test";

/**
 * The continuity promise, end to end (ADR-579): something made on the iPhone opens on the web,
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
