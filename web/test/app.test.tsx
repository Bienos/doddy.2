import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, test, vi } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import type { Language } from "../src/i18n/messages.js";
import { canonicalCode } from "../src/pages/SignInPage.js";
import { fakeServer, fixture, signedOut } from "./fakeServer.js";

function renderApp(path = "/", language?: Language) {
  return render(
    <I18nProvider {...(language ? { initial: language } : {})}>
      <SessionProvider>
        <MemoryRouter initialEntries={[path]}>
          <App />
        </MemoryRouter>
      </SessionProvider>
    </I18nProvider>,
  );
}

const signedInRoutes = {
  "GET /v1/web/session": { body: fixture("web/session-current") },
  "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
  "GET /v1/web/documents": { body: fixture("web/documents-ready") },
  "GET /v1/tools": { body: fixture("online-accounts/catalog-gmail-on") },
  "GET /v1/tools/receipts": { body: fixture("online-accounts/receipts") },
  "GET /v1/web/sessions": { body: fixture("web/sessions-phone") },
};

afterEach(() => {
  vi.useRealTimers();
});

describe("signing in", () => {
  test("Polish by default; a malformed code is caught before anything is sent", async () => {
    const { seen } = fakeServer({ "GET /v1/web/session": signedOut });
    renderApp();
    expect(await screen.findByRole("heading", { name: "Zaloguj się do Doddy" })).toBeInTheDocument();
    expect(document.documentElement.lang).toBe("pl");
    await userEvent.type(screen.getByLabelText("Kod logowania"), "ABC");
    await userEvent.click(screen.getByRole("button", { name: "Zaloguj się" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Kod ma osiem liter i cyfr");
    expect(seen.filter((s) => s.method === "POST")).toEqual([]);
  });

  test("a good code signs in and opens Home; only working sections are in the menu", async () => {
    let signedIn = false;
    const { seen } = fakeServer({
      ...signedInRoutes,
      "GET /v1/web/session": () => (signedIn ? { body: fixture("web/session-current") } : signedOut),
      "POST /v1/web/session": () => {
        signedIn = true;
        return { body: fixture("web/session-signed-in") };
      },
    });
    renderApp("/", "en");
    await userEvent.type(await screen.findByLabelText("Sign-in code"), "k7qm 4xpa");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
    expect(await screen.findByRole("heading", { name: "I'm here." })).toBeInTheDocument();
    expect(seen.find((s) => s.method === "POST")?.body).toEqual({ code: "K7QM-4XPA" });
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    // Logbook is there with example numbers only, and the menu says so (ADR-602).
    expect(within(nav).getAllByRole("link").map((a) => a.textContent)).toEqual(["Home", "Messages Soon", "Documents", "Connected apps", "Activity", "Logbook Example", "Memory Soon", "Ask Doddy Soon", "Settings"]);
    // Nothing pretends: no chat box, no memories, no tasks.
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(screen.getByRole("heading", { name: "Not on the web yet" })).toBeInTheDocument();
  });

  test("a refused code says so in the page's language", async () => {
    fakeServer({ "GET /v1/web/session": signedOut, "POST /v1/web/session": { status: 401, body: fixture("web/error-code-invalid") } });
    renderApp("/", "pl");
    await userEvent.type(await screen.findByLabelText("Kod logowania"), "ABCD-EFGH");
    await userEvent.click(screen.getByRole("button", { name: "Zaloguj się" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Ten kod nie zadziałał");
  });

  test("too many tries tells how long to wait", async () => {
    fakeServer({
      "GET /v1/web/session": signedOut,
      "POST /v1/web/session": { status: 429, body: { error: { code: "rate_limited", message: "x", correlationId: "c", retryAfterSeconds: 900 } } },
    });
    renderApp("/", "en");
    await userEvent.type(await screen.findByLabelText("Sign-in code"), "ABCD-EFGH");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Wait about 15 min");
  });

  test("the server unreachable is said plainly, with a retry", async () => {
    fakeServer({ "GET /v1/web/session": new TypeError("Failed to fetch") });
    renderApp("/", "en");
    expect(await screen.findByRole("alert")).toHaveTextContent("couldn't be reached");
    expect(screen.getByRole("button", { name: "Try again" })).toBeInTheDocument();
  });

  test("typed codes are tidied the way the server reads them", () => {
    expect(canonicalCode(" k7qm-4xpa ")).toBe("K7QM-4XPA");
    expect(canonicalCode("K7QM4XPA")).toBe("K7QM-4XPA");
    expect(canonicalCode("K7QM-4XP0")).toBeNull();
    expect(canonicalCode("K7QM-4XPAA")).toBeNull();
  });
});

describe("the workspace", () => {
  test("documents: real statuses, an interrupted one never shown as being made", async () => {
    fakeServer({ ...signedInRoutes, "GET /v1/web/documents": { body: fixture("web/documents-interrupted") } });
    renderApp("/documents", "en");
    expect(await screen.findByRole("heading", { name: "Documents" })).toBeInTheDocument();
    expect(await screen.findByText("Mechanics price check.pdf")).toBeInTheDocument();
    expect(screen.getByText(/Stopped: Doddy's server restarted/)).toBeInTheDocument();
    expect(screen.queryByText("Being made")).toBeNull();
    // Only ready files can be downloaded.
    expect(screen.getAllByRole("button", { name: /^Download: / }).map((b) => b.getAttribute("aria-label"))).toEqual([
      "Download: Barcelona trip notes.md",
      "Download: Laptops for university.pptx",
    ]);
    expect(screen.getByText(/keeps each one for 7 days/)).toBeInTheDocument();
  });

  test("while something is being made, the list asks the server again every ten seconds", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    let calls = 0;
    fakeServer({
      ...signedInRoutes,
      "GET /v1/web/documents": () => {
        calls++;
        return { body: fixture(calls === 1 ? "web/documents-working" : "web/documents-ready") };
      },
    });
    renderApp("/documents", "en");
    expect(await screen.findAllByText("Being made")).toHaveLength(2);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10_000);
    });
    await waitFor(() => expect(screen.getAllByText("Ready")).toHaveLength(2));
    const after = calls;
    await act(async () => {
      await vi.advanceTimersByTimeAsync(30_000);
    });
    expect(calls).toBe(after);
  });

  test("download saves the file through the browser; a failure is said, with the reason", async () => {
    const created = vi.fn(() => "blob:doddy");
    vi.stubGlobal("URL", Object.assign(URL, { createObjectURL: created, revokeObjectURL: vi.fn() }));
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
    const docs = fixture("web/documents-ready") as { documents: { id: string }[] };
    fakeServer({
      ...signedInRoutes,
      [`GET /v1/web/documents/${docs.documents[0]!.id}/file`]: { blob: new Blob(["notes"]) },
      [`GET /v1/web/documents/${docs.documents[1]!.id}/file`]: { status: 404, body: { error: { code: "not_found", message: "x", correlationId: "c" } } },
    });
    renderApp("/documents", "en");
    const buttons = await screen.findAllByRole("button", { name: /^Download: / });
    await userEvent.click(buttons[0]!);
    await waitFor(() => expect(click).toHaveBeenCalledTimes(1));
    expect(created).toHaveBeenCalledTimes(1);
    await userEvent.click(buttons[1]!);
    expect(await screen.findByRole("alert")).toHaveTextContent("Couldn't download Laptops for university.pptx");
  });

  test("activity: an unknown outcome is labelled unknown, never done", async () => {
    fakeServer({
      ...signedInRoutes,
      "GET /v1/tools/receipts": {
        body: {
          receipts: [
            { operationId: "11111111-1111-4111-8111-111111111111", operation: "write", toolkit: "gmail", tool: "send_email", timestamp: "2026-10-22T10:00:00.000Z", mode: "live", status: "outcome_unknown", summary: "Sent? Gmail didn't answer.", errorCode: "provider_timeout", providerReference: null },
          ],
        },
      },
    });
    renderApp("/activity", "en");
    expect(await screen.findByText("Sent? Gmail didn't answer.")).toBeInTheDocument();
    expect(screen.getByText(/^Unknown: check the app itself/)).toBeInTheDocument();
    expect(screen.queryByText("Done")).toBeNull();
  });

  test("a session that ends mid-visit returns to sign-in and says why", async () => {
    fakeServer({ ...signedInRoutes, "GET /v1/tools": signedOut });
    renderApp("/apps", "en");
    expect(await screen.findByRole("heading", { name: "Sign in to Doddy" })).toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent("You're signed out");
  });

  test("settings: this browser is marked, and signing it out returns to sign-in", async () => {
    const current = fixture("web/session-current") as { session: object };
    let out = false;
    fakeServer({
      ...signedInRoutes,
      "GET /v1/web/session": () => (out ? signedOut : { body: current }),
      "GET /v1/web/sessions": { body: { sessions: [current.session] } },
      "DELETE /v1/web/session": () => {
        out = true;
        return { body: { signedOut: true } };
      },
    });
    renderApp("/settings", "en");
    expect(await screen.findByText("This browser")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /^Sign out of this browser/ }));
    expect(await screen.findByRole("heading", { name: "Sign in to Doddy" })).toBeInTheDocument();
  });

  test("a demo server says so on every page", async () => {
    fakeServer({ ...signedInRoutes, "GET /v1/health": { body: { status: "ok", mode: "mock", api: "v1", capabilities: [] } } });
    renderApp("/", "en");
    expect(await screen.findByRole("note")).toHaveTextContent("Demo server");
  });

  test("an unknown address shows a page, not a blank screen", async () => {
    fakeServer(signedInRoutes);
    renderApp("/chat", "en");
    expect(await screen.findByRole("heading", { name: "This page doesn't exist" })).toBeInTheDocument();
  });
});
