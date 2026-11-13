import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { App } from "../src/App.js";
import { socialStartUrl } from "../src/api/client.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import type { Language } from "../src/i18n/messages.js";
import { readSignInResult } from "../src/pages/SignInPage.js";
import { readLinkResult } from "../src/pages/SettingsPage.js";
import { fakeServer, fixture, signedOut } from "./fakeServer.js";

// ADR-818: Apple and Google on the sign-in page and in Settings, once the server offers them.

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
  "GET /v1/server": { body: { mode: "live" } },
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

  test("an old browser session is asked to sign in again before changing anything", async () => {
    const { seen } = fakeServer({
      ...signedInRoutes,
      "GET /v1/web/sign-in-options": { body: { providers: ["google"] } },
      "GET /v1/web/identities": { body: { identities: [{ id: GOOGLE_ID, provider: "google", linkedAt: "2026-11-03T10:00:00.000Z" }] } },
      [`DELETE /v1/web/identities/${GOOGLE_ID}`]: { status: 422, body: { error: { code: "refused", message: "x" } } },
    });
    renderApp("/settings?link=reauth");
    expect(await screen.findByRole("alert")).toHaveTextContent("needs a fresh sign-in");
    const section = screen.getByRole("heading", { name: "Sign-in methods" }).closest("section")!;
    await userEvent.click(await within(section).findByRole("button", { name: "Unlink: Google" }));
    expect((await within(section).findAllByRole("alert")).at(-1)).toHaveTextContent("needs a fresh sign-in");
    expect(within(section).getByText("Google")).toBeInTheDocument();
    expect(seen.some((s) => s.method === "DELETE")).toBe(true);
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

describe("a new account on the web (owner, 3 Nov 2026)", () => {
  test("with sign-up open, Google and Apple come first, and the code is the other way in", async () => {
    fakeServer({ "GET /v1/web/session": signedOut, "GET /v1/web/sign-in-options": { body: { providers: ["google", "apple"], signup: true } } });
    renderApp();
    expect(
      await screen.findByText("Sign in, or make an account, with Google or Apple. Already use Doddy on your iPhone? A code from it works too."),
    ).toBeInTheDocument();
    const google = screen.getByRole("link", { name: "Continue with Google" });
    const code = screen.getByLabelText("Sign-in code");
    expect(google.compareDocumentPosition(code) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  test("an unlinked Google account is asked first; Create my Doddy account makes it and opens Home", async () => {
    let signedIn = false;
    const { seen } = fakeServer({
      ...signedInRoutes,
      "GET /v1/web/sign-in-options": { body: { providers: ["google"], signup: true } },
      "GET /v1/web/session": () => (signedIn ? { body: fixture("web/session-current") } : signedOut),
      "POST /v1/web/signup": () => {
        signedIn = true;
        return { body: { session: (fixture("web/session-signed-in") as { session: unknown }).session, created: true, provider: "google" } };
      },
    });
    renderApp("/sign-in?signin=new_account&provider=google");
    expect(await screen.findByRole("heading", { name: "Make a Doddy account with Google?" })).toBeInTheDocument();
    expect(screen.getByText(/gives Doddy's sign-in service \(Supabase\) your name and email address/)).toBeInTheDocument();
    expect(seen.some((s) => s.path === "/v1/web/signup")).toBe(false);
    await userEvent.click(screen.getByRole("button", { name: "Create my Doddy account" }));
    expect(await screen.findByRole("heading", { name: "I'm here." })).toBeInTheDocument();
    const post = seen.find((s) => s.path === "/v1/web/signup")!;
    expect(post.method).toBe("POST");
    expect(post.headers["x-doddy-web"]).toBe("1");
  });

  test("an expired sign-in says to choose Google again, and makes nothing", async () => {
    fakeServer({
      "GET /v1/web/session": signedOut,
      "GET /v1/web/sign-in-options": { body: { providers: ["google"], signup: true } },
      "POST /v1/web/signup": { status: 404, body: { error: { code: "not_found", message: "x" } } },
    });
    renderApp("/sign-in?signin=new_account&provider=google", "pl");
    await userEvent.click(await screen.findByRole("button", { name: "Załóż moje konto Doddy" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("To logowanie wygasło");
  });
});

describe("Settings › Delete account", () => {
  test("an account made on the web is deleted here in two steps, and the sign-in page says so", async () => {
    let signedIn = true;
    const { seen } = fakeServer({
      ...signedInRoutes,
      "GET /v1/web/session": () => (signedIn ? { body: fixture("web/session-current") } : signedOut),
      "GET /v1/web/account": { body: { madeOnWeb: true } },
      "POST /v1/web/account/delete": () => {
        signedIn = false;
        return {
          body: {
            complete: true,
            deleted: {},
            remaining: 0,
            onlineAccounts: { removed: ["supabase_auth"], pending: [] },
            kept: [],
            erasedAt: "2026-11-03T10:00:00.000Z",
          },
        };
      },
    });
    renderApp("/settings");
    const section = (await screen.findByRole("heading", { name: "Delete account" })).closest("section")!;
    await userEvent.click(await within(section).findByRole("button", { name: "Delete my Doddy account" }));
    expect(seen.some((s) => s.path === "/v1/web/account/delete")).toBe(false);
    await userEvent.click(within(section).getByRole("button", { name: "Yes, delete everything" }));
    expect(await screen.findByText("Your Doddy account and everything Doddy's server kept for it were deleted.")).toBeInTheDocument();
    expect(seen.find((s) => s.path === "/v1/web/account/delete")?.body).toEqual({ confirm: "delete" });
  });

  test("Keep my account changes nothing, and a removal still owed is said on the sign-in page", async () => {
    const { seen } = fakeServer({
      ...signedInRoutes,
      "GET /v1/web/account": { body: { madeOnWeb: true } },
      "POST /v1/web/account/delete": { body: { complete: false, onlineAccounts: { removed: [], pending: ["supabase_auth"] } } },
    });
    renderApp("/settings");
    const section = (await screen.findByRole("heading", { name: "Delete account" })).closest("section")!;
    await userEvent.click(await within(section).findByRole("button", { name: "Delete my Doddy account" }));
    await userEvent.click(within(section).getByRole("button", { name: "Keep my account" }));
    expect(within(section).getByRole("button", { name: "Delete my Doddy account" })).toBeInTheDocument();
    await userEvent.click(within(section).getByRole("button", { name: "Delete my Doddy account" }));
    await userEvent.click(within(section).getByRole("button", { name: "Yes, delete everything" }));
    expect(await screen.findByText(/isn't confirmed yet; the server keeps trying/)).toBeInTheDocument();
    expect(seen.filter((s) => s.path === "/v1/web/account/delete")).toHaveLength(1);
  });

  test("a web-made account is told how to use it on the iPhone; an iPhone's account isn't", async () => {
    fakeServer({ ...signedInRoutes, "GET /v1/web/account": { body: { madeOnWeb: true } } });
    const first = renderApp("/settings");
    expect(await screen.findByRole("heading", { name: "On your iPhone" })).toBeInTheDocument();
    first.unmount();
    fakeServer({ ...signedInRoutes, "GET /v1/web/account": { body: { madeOnWeb: false } } });
    renderApp("/settings");
    await screen.findByText(/belongs to Doddy on your iPhone/);
    expect(screen.queryByRole("heading", { name: "On your iPhone" })).toBeNull();
  });

  test("an iPhone's account is sent to the iPhone, with no delete button here", async () => {
    fakeServer({ ...signedInRoutes, "GET /v1/web/account": { body: { madeOnWeb: false } } });
    renderApp("/settings");
    const section = (await screen.findByRole("heading", { name: "Delete account" })).closest("section")!;
    expect(within(section).getByText(/belongs to Doddy on your iPhone/)).toBeInTheDocument();
    expect(within(section).queryByRole("button")).toBeNull();
  });

  test("an old sign-in is asked to sign in again; nothing is deleted", async () => {
    fakeServer({
      ...signedInRoutes,
      "GET /v1/web/account": { body: { madeOnWeb: true } },
      "POST /v1/web/account/delete": { status: 422, body: { error: { code: "refused", message: "x" } } },
    });
    renderApp("/settings");
    const section = (await screen.findByRole("heading", { name: "Delete account" })).closest("section")!;
    await userEvent.click(await within(section).findByRole("button", { name: "Delete my Doddy account" }));
    await userEvent.click(within(section).getByRole("button", { name: "Yes, delete everything" }));
    expect(await within(section).findByText(/deleting needs a fresh sign-in/)).toBeInTheDocument();
  });
});

describe("Apple or Google in a small window (auth/popup.ts)", () => {
  // jsdom's own window.close() would tear the test window down: it is never called for real here.
  let close: ReturnType<typeof vi.spyOn>;
  beforeEach(() => {
    window.name = "";
    close = vi.spyOn(window, "close").mockImplementation(() => undefined);
  });
  afterEach(() => {
    cleanup(); // unmount first, so nothing runs against a restored window
    vi.restoreAllMocks();
    window.name = "";
  });
  const fakePopup = () => ({ close: vi.fn(), focus: vi.fn(), closed: false });
  const offered = { "GET /v1/web/sign-in-options": { body: { providers: ["google", "apple"], signup: true } } };

  test("a click opens the small window, this page waits, and Home opens by itself once the server says signed in", async () => {
    let signedIn = false;
    fakeServer({
      ...signedInRoutes,
      ...offered,
      "GET /v1/web/session": () => (signedIn ? { body: fixture("web/session-current") } : signedOut),
    });
    const popup = fakePopup();
    const open = vi.spyOn(window, "open").mockReturnValue(popup as unknown as Window);
    renderApp();
    const apple = await screen.findByRole("link", { name: "Continue with Apple" });
    expect(fireEvent.click(apple)).toBe(false); // the page stays: the link's own navigation is cancelled
    expect(open).toHaveBeenCalledWith("/v1/web/oauth/start?provider=apple", "doddy-signin", expect.stringContaining("popup=yes"));
    expect(await screen.findByText(/Finish signing in with Apple in the window that just opened/)).toBeInTheDocument();
    // The window finished: only the server's answer counts.
    signedIn = true;
    window.dispatchEvent(new Event("focus"));
    expect(await screen.findByRole("heading", { name: "I'm here." })).toBeInTheDocument();
    expect(popup.close).toHaveBeenCalled();
  });

  test("a blocked window falls back to the whole-page redirect", async () => {
    fakeServer({ "GET /v1/web/session": signedOut, ...offered });
    vi.spyOn(window, "open").mockReturnValue(null);
    renderApp();
    const google = await screen.findByRole("link", { name: "Continue with Google" });
    expect(fireEvent.click(google)).toBe(true); // not cancelled: the browser follows the link
    expect(google).toHaveAttribute("href", "/v1/web/oauth/start?provider=google");
    expect(screen.queryByText(/Finish signing in with/)).toBeNull();
  });

  test("a new-tab click keeps its meaning, and Cancel closes the window and stops waiting", async () => {
    fakeServer({ "GET /v1/web/session": signedOut, ...offered });
    const popup = fakePopup();
    const open = vi.spyOn(window, "open").mockReturnValue(popup as unknown as Window);
    renderApp();
    const apple = await screen.findByRole("link", { name: "Continue with Apple" });
    fireEvent.click(apple, { ctrlKey: true });
    expect(open).not.toHaveBeenCalled();
    fireEvent.click(apple);
    await userEvent.click(await screen.findByRole("button", { name: "Cancel" }));
    expect(popup.close).toHaveBeenCalled();
    expect(screen.queryByText(/Finish signing in with/)).toBeNull();
  });

  test("a phone-sized screen keeps the redirect", async () => {
    fakeServer({ "GET /v1/web/session": signedOut, ...offered });
    const open = vi.spyOn(window, "open");
    const width = vi.spyOn(window, "innerWidth", "get").mockReturnValue(390);
    renderApp();
    expect(fireEvent.click(await screen.findByRole("link", { name: "Continue with Apple" }))).toBe(true);
    expect(open).not.toHaveBeenCalled();
    width.mockRestore();
  });

  test("inside the window: signed in shows 'You're signed in' and closes itself; the page behind never shows Home", async () => {
    window.name = "doddy-signin";
    fakeServer({ ...signedInRoutes });
    renderApp();
    expect(await screen.findByRole("heading", { name: "You're signed in." })).toBeInTheDocument();
    expect(close).toHaveBeenCalled();
    expect(screen.queryByRole("heading", { name: "I'm here." })).toBeNull();
  });

  test("inside the window: the server's answer is handed over and the window closes (nothing is made here)", async () => {
    window.name = "doddy-signin";
    const { seen } = fakeServer({ "GET /v1/web/session": signedOut, ...offered });
    renderApp("/sign-in?signin=new_account&provider=apple", "pl");
    expect(await screen.findByText(/Możesz zamknąć to okno\. Odpowiedź czeka/)).toBeInTheDocument();
    expect(close).toHaveBeenCalled();
    expect(screen.queryByRole("button", { name: "Załóż moje konto Doddy" })).toBeNull();
    expect(seen.some((s) => s.path === "/v1/web/signup")).toBe(false);
  });
});
