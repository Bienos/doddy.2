import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { describe, expect, test } from "vitest";
import { App } from "../src/App.js";
import { socialStartUrl } from "../src/api/client.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import type { Language } from "../src/i18n/messages.js";
import { readSignInResult } from "../src/pages/SignInPage.js";
import { readLinkResult } from "../src/pages/SettingsPage.js";
import { fakeServer, fixture, signedOut } from "./fakeServer.js";

// ADR-700: Apple and Google on the sign-in page and in Settings, once the server offers them.

function renderApp(path = "/", language: Language = "en") {
  return render(
    <I18nProvider initial={language}>
      <SessionProvider>
        <MemoryRouter initialEntries={[path]}>
          <App />
        </MemoryRouter>
      </SessionProvider>
    </I18nProvider>,
  );
}

const GOOGLE_ID = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const signedInRoutes = {
  "GET /v1/web/session": { body: fixture("web/session-current") },
  "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
  "GET /v1/web/documents": { body: fixture("web/documents-ready") },
  "GET /v1/tools": { body: fixture("online-accounts/catalog-gmail-on") },
  "GET /v1/tools/receipts": { body: fixture("online-accounts/receipts") },
  "GET /v1/web/sessions": { body: fixture("web/sessions-phone") },
};

describe("the sign-in page", () => {
  test("an older server (no options route) shows the code only", async () => {
    fakeServer({ "GET /v1/web/session": signedOut });
    renderApp();
    expect(await screen.findByLabelText("Sign-in code")).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("link", { name: /Continue with/ })).toBeNull());
  });

  test("offered buttons are whole-page links to the server's start, next to the code", async () => {
    fakeServer({ "GET /v1/web/session": signedOut, "GET /v1/web/sign-in-options": { body: { providers: ["google", "apple", "facebook"] } } });
    renderApp();
    const google = await screen.findByRole("link", { name: "Continue with Google" });
    expect(google).toHaveAttribute("href", "/v1/web/oauth/start?provider=google");
    expect(screen.getByRole("link", { name: "Continue with Apple" })).toHaveAttribute("href", "/v1/web/oauth/start?provider=apple");
    expect(screen.queryByRole("link", { name: /facebook/i })).toBeNull();
    // The code still works the same way.
    expect(screen.getByLabelText("Sign-in code")).toBeInTheDocument();
  });

  test("in Polish", async () => {
    fakeServer({ "GET /v1/web/session": signedOut, "GET /v1/web/sign-in-options": { body: { providers: ["google"] } } });
    renderApp("/", "pl");
    expect(await screen.findByRole("link", { name: "Kontynuuj z Google" })).toBeInTheDocument();
  });

  test("a Google account linked to nobody is explained, and a code then opens Home, not a missing page", async () => {
    let signedIn = false;
    fakeServer({
      ...signedInRoutes,
      "GET /v1/web/sign-in-options": { body: { providers: ["google"] } },
      "GET /v1/web/session": () => (signedIn ? { body: fixture("web/session-current") } : signedOut),
      "POST /v1/web/session": () => {
        signedIn = true;
        return { body: fixture("web/session-signed-in") };
      },
    });
    renderApp("/sign-in?signin=not_linked&provider=google");
    expect(await screen.findByRole("alert")).toHaveTextContent("This Google account isn't linked to a Doddy account yet");
    await userEvent.type(screen.getByLabelText("Sign-in code"), "K7QM-4XPA");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
    expect(await screen.findByRole("heading", { name: "I'm here." })).toBeInTheDocument();
  });

  test("only the server's known results are read from the address", () => {
    expect(readSignInResult("?signin=canceled&provider=apple")).toEqual({ result: "canceled", provider: "apple" });
    expect(readSignInResult("?signin=<script>")).toBeNull();
    expect(readSignInResult("?signin=failed&provider=evil")).toEqual({ result: "failed", provider: null });
    expect(readLinkResult("?link=taken&provider=google")).toEqual({ result: "taken", provider: "google" });
    expect(readLinkResult("?link=whatever")).toBeNull();
    expect(socialStartUrl("google", "link")).toBe("/v1/web/oauth/start?provider=google&intent=link");
  });
});

describe("Settings › Sign-in methods", () => {
  test("hidden when the server offers no Apple or Google", async () => {
    fakeServer({ ...signedInRoutes });
    renderApp("/settings");
    expect(await screen.findByRole("heading", { name: "Signed-in browsers" })).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("heading", { name: "Sign-in methods" })).toBeNull());
  });

  test("lists what is linked, offers the rest, and unlinks from the web app with its header", async () => {
    let identities = [{ id: GOOGLE_ID, provider: "google", linkedAt: "2026-11-03T10:00:00.000Z" }];
    const { seen } = fakeServer({
      ...signedInRoutes,
      "GET /v1/web/sign-in-options": { body: { providers: ["google", "apple"] } },
      "GET /v1/web/identities": () => ({ body: { identities } }),
      [`DELETE /v1/web/identities/${GOOGLE_ID}`]: () => {
        identities = [];
        return { body: { unlinked: true } };
      },
    });
    renderApp("/settings");
    const section = (await screen.findByRole("heading", { name: "Sign-in methods" })).closest("section")!;
    await within(section).findByText("Google");
    expect(within(section).getByRole("link", { name: "Link Apple" })).toHaveAttribute("href", "/v1/web/oauth/start?provider=apple&intent=link");
    expect(within(section).queryByRole("link", { name: "Link Google" })).toBeNull();
    await userEvent.click(within(section).getByRole("button", { name: "Unlink: Google" }));
    expect(await within(section).findByRole("link", { name: "Link Google" })).toBeInTheDocument();
    const del = seen.find((s) => s.method === "DELETE");
    expect(del?.headers["x-doddy-web"]).toBe("1");
    expect(within(section).getByText("Nothing linked yet: you sign in with a code from your iPhone.")).toBeInTheDocument();
  });

  test("says how linking went: taken by another account is an alert, nothing merged", async () => {
    fakeServer({
      ...signedInRoutes,
      "GET /v1/web/sign-in-options": { body: { providers: ["google"] } },
      "GET /v1/web/identities": { body: { identities: [] } },
    });
    renderApp("/settings?link=taken&provider=google");
    expect(await screen.findByRole("alert")).toHaveTextContent("already linked to another Doddy account");
  });

  test("a finished link is a status line", async () => {
    fakeServer({
      ...signedInRoutes,
      "GET /v1/web/sign-in-options": { body: { providers: ["google"] } },
      "GET /v1/web/identities": { body: { identities: [{ id: GOOGLE_ID, provider: "google", linkedAt: "2026-11-03T10:00:00.000Z" }] } },
    });
    renderApp("/settings?link=linked&provider=google", "pl");
    expect(await screen.findByText("Google jest połączone. Następnym razem wybierz Kontynuuj z Google na stronie logowania.")).toBeInTheDocument();
  });
});
