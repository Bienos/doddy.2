import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { describe, expect, test, vi } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { blocks } from "../src/chat/RichText.js";
import { suggestionsFor } from "../src/chat/suggestions.js";
import { dayGroup, loadThreads, MAX_THREADS, saveThreads, type Thread, titleFor } from "../src/chat/threads.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import type { Language } from "../src/i18n/messages.js";
import { ChatContext } from "../src/memory/schema.js";
import { fakeServer, fixture } from "./fakeServer.js";

/**
 * The chat (ADR-604): ChatGPT's layout in Doddy's colours, wired to POST /v1/web/chat. Every
 * answer is the server's (here, its own fixtures); the list of chats lives in this browser only.
 */

type Routes = Parameters<typeof fakeServer>[0];
const SESSION_ID = (fixture("web/session-current") as { session: { id: string } }).session.id;
const STORAGE_KEY = "doddy.web.chats.v1";

const context = (patch: Partial<ChatContext> = {}): ChatContext => ({ ...ChatContext.parse(fixture("web/chat-context")), ...patch });
const reply = (text: string, sources: unknown[] = []) => ({ body: { text, sources, usage: { inputTokens: 1, outputTokens: 1 } } });

function renderAt(path: string, routes: Routes, language: Language = "en") {
  const server = fakeServer({
    "GET /v1/web/session": { body: fixture("web/session-current") },
    "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
    "GET /v1/web/chat/context": { body: context() },
    ...routes,
  });
  render(
    <I18nProvider initial={language}>
      <SessionProvider>
        <MemoryRouter initialEntries={[path]}>
          <App />
        </MemoryRouter>
      </SessionProvider>
    </I18nProvider>,
  );
  return server;
}

const box = () => screen.findByRole("textbox", { name: "Message Doddy" });
async function say(text: string) {
  await userEvent.type(await box(), text);
  await userEvent.click(screen.getByRole("button", { name: "Send" }));
}

describe("an empty chat", () => {
  test("Doddy asks what he can help with, offers questions he can answer, and the menu leads here", async () => {
    renderAt("/chat", {});
    expect(await screen.findByRole("heading", { level: 1, name: "Chat with Doddy" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { level: 2, name: "What can I help with?" })).toBeInTheDocument();
    const offered = within(screen.getByRole("list", { name: "What can I help with?" }));
    // The fixture keeps notes and a conversation, but Logbook has no days: no usage questions yet.
    await waitFor(() => expect(offered.getAllByRole("button").map((b) => b.textContent)).toEqual(["What's in my notes for this week?", "What did we talk about last time?", "Which apps do I have connected?", "What do you know about my account?"]));
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(within(nav).getByRole("link", { name: "Chat" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByText(/Chats are kept only in this browser/)).toBeInTheDocument();
  });

  test("“What I can see” lists each part in words, from what the server says", async () => {
    renderAt("/chat", { "GET /v1/web/chat/context": { body: context({ apps: { connected: ["Gmail", "Notion"], available: 6 }, documents: { count: 2 }, activity: { count: 0, lastAt: null } }) } });
    await userEvent.click(await screen.findByRole("button", { name: "What I can see" }));
    const panel = (await screen.findByRole("heading", { level: 2, name: "What Doddy reads for this chat" })).parentElement as HTMLElement;
    const row = (name: string) => within(panel).getByText(name).closest("div") as HTMLElement;
    expect(row("Notes")).toHaveTextContent("3 on Doddy's server");
    expect(row("Conversations")).toHaveTextContent("1 on Doddy's server");
    expect(row("Logbook")).toHaveTextContent("On, no days sent yet");
    expect(row("Connected apps")).toHaveTextContent("Gmail, Notion");
    expect(row("Documents")).toHaveTextContent("2 from the last 7 days");
    expect(row("Activity")).toHaveTextContent("None yet");
    expect(panel).toHaveTextContent("he changes and sends nothing");
    await userEvent.keyboard("{Escape}");
    expect(screen.queryByRole("heading", { level: 2, name: "What Doddy reads for this chat" })).toBeNull();
  });

  test("with Logbook's days in, the offered questions are about how you use Doddy", () => {
    const withDays = context({ logbook: { enabled: true, days: 12, updatedAt: "2026-10-22T10:00:00.000Z" } });
    expect(suggestionsFor(withDays).slice(0, 3)).toEqual(["chat.suggest.week", "chat.suggest.when", "chat.suggest.how"]);
    expect(suggestionsFor(undefined)).toEqual(["chat.suggest.apps", "chat.suggest.account"]);
  });

  test("a server without a chat model says so, and offers no box to type in", async () => {
    renderAt("/chat", { "GET /v1/web/chat/context": { body: context({ ready: false }) } });
    expect(await screen.findByText(/The chat isn't switched on for this server yet/)).toBeInTheDocument();
    expect(await box()).toBeDisabled();
    expect(screen.queryByRole("list", { name: "What can I help with?" })).toBeNull();
  });

  test("the old Ask Doddy address opens the chat", async () => {
    renderAt("/ask", {});
    expect(await screen.findByRole("heading", { level: 1, name: "Chat with Doddy" })).toBeInTheDocument();
  });
});

describe("talking", () => {
  test("a message goes with the web app's own request, and the answer shows with the sources it cites", async () => {
    const { seen } = renderAt("/chat", { "POST /v1/web/chat": { body: fixture("web/chat-reply") } });
    await say("When is Anna's birthday?");
    expect(await screen.findByText("DEMO: here is what your saved note says.")).toBeInTheDocument();
    const sent = seen.find((s) => s.path === "/v1/web/chat");
    expect(sent?.method).toBe("POST");
    expect(sent?.headers["x-doddy-web"]).toBe("1");
    expect(sent?.body).toMatchObject({ message: "When is Anna's birthday?", history: [], locale: "en" });
    const zone = (sent?.body as { timeZone?: string }).timeZone;
    expect(zone === undefined || /^[A-Za-z]/.test(zone)).toBe(true);
    // The person's message is a bubble; the box is empty again.
    expect(screen.getByText("When is Anna's birthday?", { selector: ".chat-bubble" })).toBeInTheDocument();
    expect(await box()).toHaveValue("");
    const sources = screen.getByText("Sources (1)");
    await userEvent.click(sources);
    expect(within(sources.closest("details") as HTMLElement).getByText("Anna's birthday is 14 March")).toBeInTheDocument();
  });

  test("an answer from the account links to the page it came from", async () => {
    renderAt("/chat", { "POST /v1/web/chat": reply("You talked **4 times** this week:\n- 3 by voice\n- 1 typed", [{ kind: "account", part: "logbook" }, { kind: "account", part: "apps" }]) });
    await say("How much did we talk this week?");
    const strong = await screen.findByText("4 times");
    expect(strong.tagName).toBe("STRONG");
    expect(screen.getByText("3 by voice").tagName).toBe("LI");
    const sources = screen.getByText("Sources (2)").closest("details") as HTMLElement;
    expect(sources).toHaveTextContent("Logbook · Connected apps");
    await userEvent.click(screen.getByText("Sources (2)"));
    const links = within(sources).getAllByRole("link", { name: "Open" });
    expect(links.map((a) => a.getAttribute("href"))).toEqual(["/logbook", "/apps"]);
  });

  test("an answer is shown as text, never as markup or a link", async () => {
    renderAt("/chat", { "POST /v1/web/chat": reply("<img src=x onerror=alert(1)> https://evil.example/steal **<b>x</b>**", [{ kind: "note", id: "x", text: "<b>bold</b>", capturedAt: null }]) });
    await say("hi there");
    expect(await screen.findByText(/<img src=x onerror=alert\(1\)>/)).toBeInTheDocument();
    expect(document.querySelector("img[src='x']")).toBeNull();
    expect(document.querySelector("a[href*='evil']")).toBeNull();
    expect(document.querySelector(".chat-text b")).toBeNull();
  });

  test("the next message carries the turns so far, at most ten, as plain text", async () => {
    let n = 0;
    const { seen } = renderAt("/chat", { "POST /v1/web/chat": () => reply(`Answer ${++n}`) });
    for (let i = 1; i <= 7; i += 1) {
      await say(`Question ${i}?`);
      await screen.findByText(`Answer ${i}`);
    }
    const bodies = seen.filter((s) => s.path === "/v1/web/chat").map((s) => s.body as { history: { role: string; text: string }[] });
    expect(bodies[0]?.history).toEqual([]);
    expect(bodies[1]?.history).toEqual([{ role: "user", text: "Question 1?" }, { role: "assistant", text: "Answer 1" }]);
    expect(bodies[6]?.history).toHaveLength(10);
    expect(bodies[6]?.history[0]).toEqual({ role: "user", text: "Question 2?" });
    expect(bodies[6]?.history.at(-1)).toEqual({ role: "assistant", text: "Answer 6" });
  });

  test("Enter sends, Shift+Enter makes a new line", async () => {
    const { seen } = renderAt("/chat", { "POST /v1/web/chat": reply("Got it.") });
    const input = await box();
    await userEvent.type(input, "line one{Shift>}{Enter}{/Shift}line two");
    expect(input).toHaveValue("line one\nline two");
    await userEvent.keyboard("{Enter}");
    expect(await screen.findByText("Got it.")).toBeInTheDocument();
    expect(seen.filter((s) => s.path === "/v1/web/chat").map((s) => (s.body as { message: string }).message)).toEqual(["line one\nline two"]);
  });

  test("a suggestion is sent as the first message", async () => {
    const { seen } = renderAt("/chat", { "POST /v1/web/chat": reply("Gmail.") });
    await userEvent.click(await screen.findByRole("button", { name: "Which apps do I have connected?" }));
    expect(await screen.findByText("Gmail.")).toBeInTheDocument();
    expect((seen.find((s) => s.path === "/v1/web/chat")?.body as { message: string }).message).toBe("Which apps do I have connected?");
  });

  test("a failed message says why in words and can be asked again with the same turns", async () => {
    let calls = 0;
    const { seen } = renderAt("/chat", {
      "POST /v1/web/chat": () => (++calls === 1 ? { status: 429, body: { error: { code: "quota_exceeded", message: "x" } } } : { body: fixture("web/chat-reply") }),
    });
    await say("When is Anna's birthday?");
    expect(await screen.findByRole("alert")).toHaveTextContent("Today's question limit was reached. Try again tomorrow.");
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByText("DEMO: here is what your saved note says.")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).toBeNull();
    const asked = seen.filter((s) => s.path === "/v1/web/chat").map((s) => s.body as { message: string; history: unknown[] });
    expect(asked.map((b) => b.message)).toEqual(["When is Anna's birthday?", "When is Anna's birthday?"]);
    expect(asked[1]?.history).toEqual([]);
  });

  test("Stop ends the wait; the question stays and can be asked again", async () => {
    const { fetchMock } = renderAt("/chat", {});
    const answered = fetchMock.getMockImplementation()!;
    let hang = true;
    fetchMock.mockImplementation(async (input, init = {}) => {
      if (String(input).endsWith("/v1/web/chat") && hang) {
        return new Promise<Response>((_, reject) => init.signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError"))));
      }
      if (String(input).endsWith("/v1/web/chat")) return new Response(JSON.stringify(reply("Here it is.").body), { status: 200 });
      return answered(input, init);
    });
    await say("A slow one?");
    expect(await screen.findByRole("status")).toHaveTextContent("Doddy is writing…");
    await userEvent.click(screen.getByRole("button", { name: "Stop" }));
    expect(await screen.findByText("Answer stopped.")).toBeInTheDocument();
    hang = false;
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByText("Here it is.")).toBeInTheDocument();
  });

  test("Answer again asks the last question once more and replaces the answer", async () => {
    let n = 0;
    const { seen } = renderAt("/chat", { "POST /v1/web/chat": () => reply(`Take ${++n}`) });
    await say("Tell me something");
    await screen.findByText("Take 1");
    await userEvent.click(screen.getByRole("button", { name: "Answer again" }));
    expect(await screen.findByText("Take 2")).toBeInTheDocument();
    expect(screen.queryByText("Take 1")).toBeNull();
    const asked = seen.filter((s) => s.path === "/v1/web/chat").map((s) => s.body as { message: string; history: unknown[] });
    expect(asked[1]).toMatchObject({ message: "Tell me something", history: [] });
  });

  test("a chat whose session ended signs the page out", async () => {
    renderAt("/chat", { "POST /v1/web/chat": { status: 401, body: fixture("web/error-signed-out") } });
    await say("Hello?");
    expect(await screen.findByRole("button", { name: "Sign in" })).toBeInTheDocument();
  });

  test("in Polish: the page, the box and the button", async () => {
    renderAt("/chat", {}, "pl");
    expect(await screen.findByRole("heading", { level: 1, name: "Czat z Doddym" })).toBeInTheDocument();
    expect(await screen.findByRole("textbox", { name: "Napisz do Doddy’ego" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Wyślij" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { level: 2, name: "W czym mogę pomóc?" })).toBeInTheDocument();
  });
});

describe("the list of chats", () => {
  test("a chat is listed under Today by its first question, and New chat starts an empty one", async () => {
    renderAt("/chat", { "POST /v1/web/chat": reply("Gmail and Notion.") });
    await say("Which apps do I have connected?");
    await screen.findByText("Gmail and Notion.");
    const list = screen.getByRole("complementary", { name: "Your chats" });
    const today = within(list).getByRole("region", { name: "Today" });
    const open = within(today).getByRole("button", { name: "Which apps do I have connected?" });
    expect(open).toHaveAttribute("aria-current", "true");

    await userEvent.click(within(list).getByRole("button", { name: "New chat" }));
    expect(screen.getByRole("heading", { level: 2, name: "What can I help with?" })).toBeInTheDocument();
    expect(screen.queryByText("Gmail and Notion.")).toBeNull();

    await userEvent.click(open);
    expect(await screen.findByText("Gmail and Notion.")).toBeInTheDocument();
  });

  test("chats are kept in this browser for this sign-in, and come back on the next visit", async () => {
    renderAt("/chat", { "POST /v1/web/chat": reply("Kept.") });
    await say("Remember this chat");
    await screen.findByText("Kept.");
    await waitFor(() => expect(window.localStorage.getItem(STORAGE_KEY)).toContain("Remember this chat"));
    const saved = JSON.parse(window.localStorage.getItem(STORAGE_KEY)!) as { owner: string; threads: Thread[] };
    expect(saved.owner).toBe(SESSION_ID);
    expect(saved.threads[0]?.turns.map((t) => t.role)).toEqual(["user", "doddy"]);
    expect(loadThreads(SESSION_ID)[0]?.title).toBe("Remember this chat");
  });

  test("another sign-in's chats are deleted, never shown", async () => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ owner: "someone-else", threads: [{ id: "t1", title: "Their secret", createdAt: 1, updatedAt: 1, turns: [{ role: "user", text: "Their secret", at: 1 }] }] }));
    renderAt("/chat", {});
    await screen.findByRole("heading", { level: 1, name: "Chat with Doddy" });
    expect(screen.queryByText("Their secret")).toBeNull();
    expect(window.localStorage.getItem(STORAGE_KEY)).toBeNull();
  });

  test("one chat can be deleted, or all of them after a confirmation", async () => {
    let n = 0;
    renderAt("/chat", { "POST /v1/web/chat": () => reply(`Answer ${++n}`) });
    await say("First chat");
    await screen.findByText("Answer 1");
    const list = screen.getByRole("complementary", { name: "Your chats" });
    await userEvent.click(within(list).getByRole("button", { name: "New chat" }));
    await say("Second chat");
    await screen.findByText("Answer 2");

    await userEvent.click(within(list).getByRole("button", { name: "Delete chat “First chat”" }));
    expect(within(list).queryByRole("button", { name: "First chat" })).toBeNull();
    expect(within(list).getByRole("button", { name: "Second chat" })).toBeInTheDocument();

    await userEvent.click(within(list).getByRole("button", { name: "Delete all chats" }));
    await userEvent.click(within(list).getByRole("button", { name: "Delete" }));
    expect(within(list).queryByRole("button", { name: "Second chat" })).toBeNull();
    expect(screen.getByText("Your chats will show up here.")).toBeInTheDocument();
    expect(window.localStorage.getItem(STORAGE_KEY)).toBeNull();
  });

  test("signing out deletes the chats kept in this browser", async () => {
    renderAt("/chat", { "POST /v1/web/chat": reply("Bye."), "DELETE /v1/web/session": { body: { signedOut: true } } });
    await say("Something private");
    await screen.findByText("Bye.");
    await waitFor(() => expect(window.localStorage.getItem(STORAGE_KEY)).not.toBeNull());
    await userEvent.click(screen.getByRole("button", { name: "Sign out" }));
    expect(await screen.findByRole("button", { name: "Sign in" })).toBeInTheDocument();
    expect(window.localStorage.getItem(STORAGE_KEY)).toBeNull();
  });
});

describe("the pieces", () => {
  test("formatting: paragraphs, both kinds of list and bold; nothing else", () => {
    expect(blocks("One\ntwo\n\n- a\n- b\n\n1. x\n2) y\nafter")).toEqual([
      { kind: "p", lines: ["One", "two"] },
      { kind: "ul", items: ["a", "b"] },
      { kind: "ol", items: ["x", "y"] },
      { kind: "p", lines: ["after"] },
    ]);
    expect(blocks("\n\n")).toEqual([]);
  });

  test("a chat's title is its first question on one line, cut to fit", () => {
    expect(titleFor("  How   much\ndid we talk? ")).toBe("How much did we talk?");
    const long = titleFor("x".repeat(80));
    expect([...long]).toHaveLength(48);
    expect(long.endsWith("…")).toBe(true);
  });

  test("chats are grouped by the person's own days", () => {
    const now = new Date(2026, 9, 22, 10, 0).getTime();
    const at = (days: number, hour = 9) => new Date(2026, 9, 22 - days, hour, 0).getTime();
    expect([at(0, 0), at(1, 23), at(3), at(12), at(45)].map((t) => dayGroup(t, now))).toEqual(["today", "yesterday", "week", "month", "older"]);
  });

  test("saving keeps the newest chats, and keeps going when the browser's storage is full", () => {
    const thread = (n: number): Thread => ({ id: `t${n}`, title: `T${n}`, createdAt: n, updatedAt: n, turns: [{ role: "user", text: `q${n}`, at: n }] });
    expect(saveThreads("me", Array.from({ length: MAX_THREADS + 5 }, (_, i) => thread(i)))).toBe(true);
    const kept = loadThreads("me");
    expect(kept).toHaveLength(MAX_THREADS);
    expect(kept[0]?.id).toBe(`t${MAX_THREADS + 4}`);

    const setItem = vi.spyOn(Storage.prototype, "setItem");
    let tries = 0;
    setItem.mockImplementation(function (this: Storage) {
      tries += 1;
      if (tries < 3) throw new DOMException("full", "QuotaExceededError");
    });
    expect(saveThreads("me", [thread(1), thread(2), thread(3), thread(4)])).toBe(true);
    expect(tries).toBe(3);
    setItem.mockImplementation(() => {
      throw new DOMException("blocked", "SecurityError");
    });
    expect(saveThreads("me", [thread(1)])).toBe(false);
  });
});
