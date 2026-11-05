import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, test, vi } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import type { Language } from "../src/i18n/messages.js";
import { fakeServer, fixture } from "./fakeServer.js";

type Routes = Parameters<typeof fakeServer>[0];

function renderAt(path: string, routes: Routes, language: Language = "en") {
  const server = fakeServer({
    "GET /v1/web/session": { body: fixture("web/session-current") },
    "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
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

const kept: Routes = {
  "GET /v1/web/memory": { body: fixture("web/memory-overview") },
  "GET /v1/web/memory/notes": { body: fixture("web/memory-notes") },
  "GET /v1/web/memory/conversations": { body: fixture("web/memory-conversations") },
  "GET /v1/web/memory/conversations/00000000-0000-4000-8000-0000000000c1": { body: fixture("web/memory-conversation") },
};

afterEach(() => vi.useRealTimers());

describe("Memory", () => {
  test("nothing kept: one calm card that doesn't point at an app switch that isn't built", async () => {
    renderAt("/memory", { "GET /v1/web/memory": { body: fixture("web/memory-off") } });
    const card = (await screen.findByRole("heading", { level: 2, name: "Nothing is kept on Doddy's server" })).closest("section") as HTMLElement;
    expect(card).toHaveTextContent("can't send notes and conversations yet");
    expect(document.body).not.toHaveTextContent("Settings › Doddy on the web");
    expect(screen.queryByRole("tablist")).toBeNull();
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(within(nav).getByRole("link", { name: "Memory Soon" })).toHaveAttribute("aria-current", "page");
  });

  test("what is kept: the summary, the notes newest first, each with when, how and its type", async () => {
    renderAt("/memory", kept);
    expect(await screen.findByText("3 notes · 1 conversations")).toBeInTheDocument();
    await screen.findByText("Dentist on Friday at 9");
    const items = [...document.querySelectorAll<HTMLElement>(".memory-list > li")];
    expect(items.map((li) => li.querySelector(".memory-note-text")?.textContent)).toEqual(["Anna's birthday is 14 March", "Dentist on Friday at 9", "Zaproszenie od Łukasza na sobotę"]);
    expect(items[0]).toHaveTextContent("By voice");
    expect(items[0]).toHaveTextContent("Fact");
    expect(screen.getByText(/Your iPhone last sent/)).toBeInTheDocument();
  });

  test("searching sends the words in the body, never in the address", async () => {
    const { seen } = renderAt("/memory", { ...kept, "POST /v1/web/memory/notes/search": { body: fixture("web/memory-notes-search") } });
    await screen.findByText("Dentist on Friday at 9");
    await userEvent.type(screen.getByRole("searchbox", { name: "Search your notes" }), "Anna");
    await waitFor(() => expect(screen.queryByText("Dentist on Friday at 9")).toBeNull());
    expect(await screen.findByText("Anna's birthday is 14 March")).toBeInTheDocument();
    const search = seen.filter((s) => s.method === "POST" && s.path === "/v1/web/memory/notes/search");
    expect(search.length).toBeGreaterThan(0);
    expect(search.at(-1)?.body).toMatchObject({ q: "Anna" });
    expect(seen.every((s) => !s.path.includes("Anna"))).toBe(true);
    expect(search.at(-1)?.headers["x-doddy-web"]).toBe("1");
  });

  test("a search with no match says so, and 'show more' appends the next page", async () => {
    let calls = 0;
    renderAt("/memory", {
      ...kept,
      "GET /v1/web/memory/notes": () => {
        calls += 1;
        const base = fixture("web/memory-notes") as { notes: { id: string; text: string }[] };
        return calls === 1
          ? { body: { ...base, notes: base.notes.slice(0, 1), total: 3, nextOffset: 1 } }
          : { body: { ...base, notes: base.notes.slice(1), total: 3, nextOffset: null } };
      },
    });
    await screen.findByText("Anna's birthday is 14 March");
    expect(screen.queryByText("Dentist on Friday at 9")).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Show more" }));
    expect(await screen.findByText("Dentist on Friday at 9")).toBeInTheDocument();
    expect(screen.getByText("Anna's birthday is 14 March")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Show more" })).toBeNull();
  });

  test("items the server couldn't read are counted in words, not hidden silently", async () => {
    renderAt("/memory", { ...kept, "GET /v1/web/memory/notes": { body: { ...(fixture("web/memory-notes") as object), unreadable: 2 } } });
    expect(await screen.findByText(/2 items can't be read with the key this server has now/)).toBeInTheDocument();
  });

  test("conversations: a preview, then the whole thing with who said what", async () => {
    renderAt("/memory#conversations", kept);
    expect(await screen.findByText("Kiedy są urodziny Anny?")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Read" }));
    expect(await screen.findByText("Urodziny Anny są 14 marca.")).toBeInTheDocument();
    expect(screen.getByText("Urodziny Anny są 14 marca.").closest("li")).toHaveTextContent("Doddy");
    expect(screen.getAllByText("You").length).toBeGreaterThan(0);
    await userEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(screen.queryByText("Urodziny Anny są 14 marca.")).toBeNull();
  });

  test("deleting one conversation asks first, tells that the iPhone keeps its copy, and says Deleted only after the server answers", async () => {
    const { seen } = renderAt("/memory#conversations", {
      ...kept,
      "DELETE /v1/web/memory/conversations/00000000-0000-4000-8000-0000000000c1": { body: fixture("web/memory-conversation-deleted") },
    });
    await screen.findByText("Kiedy są urodziny Anny?");
    await userEvent.click(screen.getByRole("button", { name: "Read" }));
    await userEvent.click(await screen.findByRole("button", { name: "Delete this conversation" }));
    expect(screen.getByRole("alert")).toHaveTextContent("Your iPhone keeps its own copy.");
    expect(seen.filter((s) => s.method === "DELETE")).toHaveLength(0);
    await userEvent.click(screen.getByRole("button", { name: "Yes, delete" }));
    expect(await screen.findByText("Deleted from Doddy's server.")).toBeInTheDocument();
    expect(screen.queryByText("Kiedy są urodziny Anny?")).toBeNull();
    const deleted = seen.find((s) => s.method === "DELETE");
    expect(deleted?.headers["x-doddy-web"]).toBe("1");
  });

  test("a kind that is off says so in its tab", async () => {
    renderAt("/memory#conversations", { ...kept, "GET /v1/web/memory": { body: { ...(fixture("web/memory-overview") as object), conversations: false } } });
    expect(await screen.findByText("Conversations aren't being kept. Turn them on in the Doddy app.")).toBeInTheDocument();
  });

  test("delete everything takes two taps; 'Deleted' is said after the server answers, and the page goes back to nothing kept", async () => {
    let gone = false;
    const { seen } = renderAt("/memory", {
      ...kept,
      "GET /v1/web/memory": () => ({ body: fixture(gone ? "web/memory-off" : "web/memory-overview") }),
      "DELETE /v1/web/memory": () => {
        gone = true;
        return { body: { notes: false, conversations: false, deletedNotes: 3, deletedConversations: 1 } };
      },
    });
    await userEvent.click(await screen.findByRole("button", { name: "Delete everything here" }));
    expect(seen.filter((s) => s.method === "DELETE")).toHaveLength(0);
    await userEvent.click(screen.getByRole("button", { name: "Tap again to delete everything" }));
    expect(await screen.findByRole("heading", { level: 2, name: "Nothing is kept on Doddy's server" })).toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent("Deleted. 3 notes and 1 conversations removed. Your iPhone will stop sending.");
  });

  test("a refused delete says so in words and leaves everything where it was", async () => {
    renderAt("/memory", { ...kept, "DELETE /v1/web/memory": { status: 500, body: { error: { code: "internal", message: "boom" } } } });
    await userEvent.click(await screen.findByRole("button", { name: "Delete everything here" }));
    await userEvent.click(screen.getByRole("button", { name: "Tap again to delete everything" }));
    expect(await screen.findByRole("status")).toHaveTextContent("Something went wrong on Doddy's server. Nothing was changed.");
    expect(screen.getByText("Anna's birthday is 14 March")).toBeInTheDocument();
  });

  test("download everything saves the server's file", async () => {
    const saved: string[] = [];
    Object.assign(URL, { createObjectURL: vi.fn(() => "blob:memory"), revokeObjectURL: vi.fn() });
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) {
      saved.push(this.download);
    });
    const { seen } = renderAt("/memory", { ...kept, "GET /v1/web/memory/export": { blob: new Blob(["{}"], { type: "application/json" }) } });
    await userEvent.click(await screen.findByRole("button", { name: "Download everything" }));
    expect(await screen.findByRole("status")).toHaveTextContent("Saved everything Doddy's server keeps for you as a file.");
    expect(seen.some((s) => s.path === "/v1/web/memory/export")).toBe(true);
    expect(saved).toHaveLength(1);
    expect(saved[0]).toMatch(/^doddy-memory-\d{4}-\d{2}-\d{2}\.json$/);
    click.mockRestore();
  });

  test("the server can't be reached: an error and a way to try again, never an empty list", async () => {
    let calls = 0;
    renderAt("/memory", { ...kept, "GET /v1/web/memory": () => (++calls === 1 ? new Error("offline") : { body: fixture("web/memory-overview") }) });
    expect(await screen.findByRole("alert")).toHaveTextContent("couldn't be reached");
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByText("3 notes · 1 conversations")).toBeInTheDocument();
  });

  test("the privacy panel says it is text only, that the server can read it, and who else reads the best matches", async () => {
    renderAt("/memory", kept);
    const panel = (await screen.findByRole("heading", { level: 2, name: "What Doddy's server keeps" })).closest("section") as HTMLElement;
    expect(panel).toHaveTextContent("Text only");
    expect(panel).toHaveTextContent("Never audio");
    expect(panel).toHaveTextContent("Doddy's server can read it");
    expect(panel).toHaveTextContent("Claude (made by Anthropic)");
    expect(panel).toHaveTextContent("kept 1 year".replace("kept", "Conversations are kept"));
  });

  test("in Polish: the page, the tabs and the off card", async () => {
    renderAt("/memory", { "GET /v1/web/memory": { body: fixture("web/memory-off") } }, "pl");
    expect(await screen.findByRole("heading", { level: 1, name: "Pamięć" })).toBeInTheDocument();
    expect(await screen.findByRole("heading", { level: 2, name: "Na serwerze Doddy’ego nic nie jest przechowywane" })).toBeInTheDocument();
    expect(document.body).toHaveTextContent("tej części aplikacji Doddy jeszcze nie ma");
  });
});
