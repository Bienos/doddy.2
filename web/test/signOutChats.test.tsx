import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { describe, expect, test } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import { ChatContext } from "../src/memory/schema.js";
import { fakeServer, fixture, signedOut } from "./fakeServer.js";

/**
 * The chats kept in this browser (localStorage, never on the server) go whenever the sign-in ends,
 * by whichever road it ends (ADR-604, ADR-715): Sign out, a Sign out that finds the server already
 * agrees, Settings, and a session that ended while a page was in use. Each test checks the stored
 * copy itself, not only the screen, because that copy is what a later visitor to this browser could read.
 */

const STORAGE_KEY = "doddy.web.chats.v1";
const current = fixture("web/session-current") as { session: { id: string } };
const SESSION_ID = current.session.id;
const SLOW = { timeout: 5_000 };

const keepAChat = () =>
  window.localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({ owner: SESSION_ID, threads: [{ id: "t1", title: "Something private", createdAt: 1, updatedAt: 1, turns: [{ role: "user", text: "Something private", at: 1 }] }] }),
  );
const stored = () => window.localStorage.getItem(STORAGE_KEY);

type Routes = Parameters<typeof fakeServer>[0];
function renderAt(path: string, routes: Routes) {
  const server = fakeServer({
    "GET /v1/web/session": { body: current },
    "GET /v1/server": { body: { mode: "live" } },
    "GET /v1/web/chat/context": { body: ChatContext.parse(fixture("web/chat-context")) },
    "GET /v1/web/documents": { body: fixture("web/documents-ready") },
    "GET /v1/web/sessions": { body: { sessions: [current.session] } },
    ...routes,
  });
  render(
    <I18nProvider initial="en">
      <SessionProvider>
        <MemoryRouter initialEntries={[path]}>
          <App />
        </MemoryRouter>
      </SessionProvider>
    </I18nProvider>,
  );
  return server;
}

const signInPage = () => screen.findByRole("heading", { name: "Sign in to Doddy" }, SLOW);

describe("the chats kept in this browser go with the sign-in, by every road it can end", () => {
  test("a message the server answers 'signed out' to ends the visit and takes the kept chats with it", async () => {
    let asked = 0;
    renderAt("/chat", {
      "POST /v1/web/chat": () => (++asked === 1 ? { body: { text: "Kept.", sources: [], usage: { inputTokens: 1, outputTokens: 1 } } } : signedOut),
    });
    const say = async (text: string) => {
      await userEvent.type(await screen.findByRole("textbox", { name: "Message Doddy" }, SLOW), text);
      await userEvent.click(screen.getByRole("button", { name: "Send" }));
    };
    await say("Remember this");
    await screen.findByText("Kept.", undefined, SLOW);
    await waitFor(() => expect(stored()).toContain("Remember this"), SLOW);

    await say("And now?");
    await signInPage();
    expect(stored()).toBeNull();
  });

  test("a page whose own request is answered 'signed out' takes the kept chats with it", async () => {
    keepAChat();
    renderAt("/apps", { "GET /v1/tools": signedOut });
    await signInPage();
    expect(stored()).toBeNull();
  });

  test("Sign out removes them even when the server says the session had already ended", async () => {
    keepAChat();
    renderAt("/documents", { "DELETE /v1/web/session": signedOut });
    await userEvent.click(await screen.findByRole("button", { name: "Sign out" }, SLOW));
    await signInPage();
    expect(stored()).toBeNull();
  });

  test("signing this browser out in Settings removes them", async () => {
    keepAChat();
    renderAt("/settings", { "DELETE /v1/web/session": { body: { signedOut: true } } });
    expect(await screen.findByText("This browser", undefined, SLOW)).toBeInTheDocument();
    expect(stored()).not.toBeNull();
    await userEvent.click(screen.getByRole("button", { name: /^Sign out of this browser/ }));
    await signInPage();
    expect(stored()).toBeNull();
  });

  test("a Sign out the server could not be reached for changes nothing: still signed in, the chats are still there", async () => {
    keepAChat();
    renderAt("/documents", { "DELETE /v1/web/session": new TypeError("Failed to fetch") });
    await userEvent.click(await screen.findByRole("button", { name: "Sign out" }, SLOW));
    expect(await screen.findByRole("alert", undefined, SLOW)).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Sign in to Doddy" })).toBeNull();
    expect(stored()).toContain("Something private");
    expect(screen.getByRole("button", { name: "Sign out" })).toBeEnabled();
  });
});
