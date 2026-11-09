import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { describe, expect, test } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import { toolRows } from "../src/owner/schema.js";
import { fakeServer, fixture } from "./fakeServer.js";

/** The owner panel (decision 2026-11-09-usage-counts-on-by-default): owners only, counts only. */

/** The server's own replies (backend: npm run fixtures:owner). */
const overview = fixture("web/owner-overview") as { directory: boolean; accounts: unknown };
const TOMEK = "00000000-0000-4000-8000-00000000000b";

function renderOwner(routes: Record<string, unknown> = {}) {
  const server = fakeServer({
    "GET /v1/web/session": { body: fixture("web/session-current") },
    "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
    "GET /v1/web/owner": { body: fixture("web/owner-flag") },
    "GET /v1/web/owner/overview": { body: overview },
    "GET /v1/web/owner/accounts": { body: fixture("web/owner-accounts") },
    [`GET /v1/web/owner/accounts/${TOMEK}/logbook`]: { body: fixture("web/owner-account-logbook") },
    ...(routes as Record<string, { body: unknown }>),
  });
  render(
    <I18nProvider initial="en">
      <SessionProvider>
        <MemoryRouter initialEntries={["/owner"]}>
          <App />
        </MemoryRouter>
      </SessionProvider>
    </I18nProvider>,
  );
  return server;
}

describe("the owner panel", () => {
  test("shows totals, sign-in methods, tools that fail and every account, from reads only", async () => {
    const { seen } = renderOwner();
    expect(await screen.findByRole("heading", { level: 1, name: "Everyone's Doddy" })).toBeInTheDocument();
    const tiles = await screen.findByRole("list", { name: "Everyone's Doddy" });
    expect(within(tiles).getByText("Accounts").previousSibling).toHaveTextContent("2");
    expect(within(tiles).getByText("Conversations").previousSibling).toHaveTextContent("6");
    expect(within(tiles).getByText("Minutes talking").previousSibling).toHaveTextContent("15");

    const tools = screen.getByRole("heading", { level: 2, name: "What Doddy did, by tool" }).closest("section") as HTMLElement;
    const weather = within(tools).getByText("get_weather").closest("tr") as HTMLElement;
    expect(weather).toHaveTextContent("33%");

    const list = screen.getByRole("heading", { level: 2, name: "Accounts" }).closest("section") as HTMLElement;
    expect(await within(list).findByText("tomek@example.com")).toBeInTheDocument();
    expect(within(list).getByText("google")).toBeInTheDocument();

    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(await within(nav).findByRole("link", { name: "Owner" })).toHaveAttribute("aria-current", "page");
    expect(seen.filter((s) => s.method !== "GET")).toEqual([]);
  });

  test("one account's own days open from the list", async () => {
    renderOwner();
    const list = (await screen.findByRole("heading", { level: 2, name: "Accounts" })).closest("section") as HTMLElement;
    const tomek = (await within(list).findByText("tomek@example.com")).closest("tr") as HTMLElement;
    await userEvent.click(within(tomek).getByRole("button", { name: "Open" }));
    expect(await screen.findByRole("heading", { level: 1, name: "tomek@example.com" })).toBeInTheDocument();
    expect(await screen.findByRole("heading", { level: 2, name: "Each day" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "All accounts" }));
    expect(await screen.findByRole("heading", { level: 1, name: "Everyone's Doddy" })).toBeInTheDocument();
  });

  test("without Supabase's account list it says so", async () => {
    renderOwner({ "GET /v1/web/owner/overview": { body: { ...overview, directory: false, accounts: { total: null, byMethod: {}, newByDay: [] } } } });
    expect(await screen.findByText(/can't read the account list from Supabase/)).toBeInTheDocument();
  });

  test("someone who isn't an owner has no menu entry, and the address shows the server's no", async () => {
    renderOwner({ "GET /v1/web/owner": { status: 404, body: { error: { code: "not_found", message: "Not found." } } }, "GET /v1/web/owner/overview": { status: 404, body: { error: { code: "not_found", message: "Not found." } } } });
    expect(await screen.findByRole("heading", { level: 1, name: "Everyone's Doddy" })).toBeInTheDocument();
    expect(await screen.findAllByRole("alert")).not.toHaveLength(0);
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(within(nav).queryByRole("link", { name: "Owner" })).toBeNull();
  });

  test("tools are listed most used first, with how often they didn't work out", () => {
    const rows = toolRows({ a_tool: { done: 1, declined: 0, unsure: 0, failed: 0, undone: 0 }, b_tool: { done: 2, declined: 0, unsure: 1, failed: 1, undone: 0 }, unused: { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 } });
    expect(rows.map((r) => r.tool)).toEqual(["b_tool", "a_tool"]);
    expect(rows[0]!.failRate).toBe(0.5);
  });
});
