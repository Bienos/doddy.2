import { render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, test } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import { fakeServer, fixture } from "./fakeServer.js";

function renderAt(path: string) {
  return render(
    <I18nProvider initial="en">
      <SessionProvider>
        <MemoryRouter initialEntries={[path]}>
          <App />
        </MemoryRouter>
      </SessionProvider>
    </I18nProvider>,
  );
}

const thread = {
  syncedAt: "2026-10-28T08:00:00.000Z",
  messages: [
    { id: "00000000-0000-4000-8000-000000000001", sender: "user", text: "Kiedy są urodziny Anny?", createdAt: "2026-10-28T07:58:00.000Z", delivery: "sent" },
    { id: "00000000-0000-4000-8000-000000000002", sender: "doddy", text: "14 marca.", createdAt: "2026-10-28T07:58:05.000Z" },
    { id: "00000000-0000-4000-8000-000000000003", sender: "user", text: "Co to?", createdAt: "2026-10-28T07:59:00.000Z", delivery: "failed", hasPhoto: true },
    { id: "00000000-0000-4000-8000-000000000004", sender: "doddy", text: "Plan bety", createdAt: "2026-10-28T07:59:30.000Z", file: { name: "Plan bety", kind: "deck" } },
  ],
};

describe("Messages from the iPhone", () => {
  test("shows the thread read only, says a photo was not kept and names a file", async () => {
    fakeServer({ "GET /v1/web/session": { body: fixture("web/session-current") }, "GET /v1/web/messages": { body: thread } });
    renderAt("/messages");
    const list = await screen.findByRole("list", { name: "Messages" });
    const items = within(list).getAllByRole("listitem");
    expect(items).toHaveLength(4);
    expect(items[0]).toHaveTextContent("Kiedy są urodziny Anny?");
    expect(items[0]).toHaveClass("from-you");
    expect(items[1]).toHaveClass("from-doddy");
    expect(items[2]).toHaveTextContent("Photo (not kept)");
    expect(items[2]).toHaveTextContent("No answer");
    expect(items[3]).toHaveTextContent("File: Plan bety");
    // Read only: nothing to type into, nothing to delete.
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(screen.queryByRole("button", { name: /delete/i })).toBeNull();
  });

  test("before the iPhone sends anything, it says so", async () => {
    fakeServer({ "GET /v1/web/session": { body: fixture("web/session-current") }, "GET /v1/web/messages": { body: { messages: [], syncedAt: null } } });
    renderAt("/messages");
    expect(await screen.findByText(/Nothing yet\. Write to Doddy in Messages/)).toBeInTheDocument();
  });
});
