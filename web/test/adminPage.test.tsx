import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, test } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import { fakeServer, fixture } from "./fakeServer.js";

/** The admin dashboard (decision 2026-11-09-usage-counts-on-by-default): the owner's own page, counts only. */

const TOMEK = "00000000-0000-4000-8000-00000000000b";
const notFound = { status: 404, body: { error: { code: "not_found", message: "Not found." } } };

function renderAdmin(path = "/admin", routes: Record<string, unknown> = {}, language: "en" | "pl" = "en") {
  const server = fakeServer({
    "GET /v1/web/session": { body: fixture("web/session-current") },
    "GET /v1/server": { body: { mode: "live" } },
    "GET /v1/web/owner": { body: fixture("web/owner-flag") },
    "GET /v1/web/owner/overview": { body: fixture("web/owner-overview") },
    "GET /v1/web/owner/accounts": { body: fixture("web/owner-accounts") },
    [`GET /v1/web/owner/accounts/${TOMEK}/logbook`]: { body: fixture("web/owner-account-logbook") },
    ...(routes as Record<string, { body: unknown }>),
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

const tab = (name: string) => screen.findByRole("tab", { name });

// jsdom has no scrolling; the page scrolls to the top when a tab opens.
beforeEach(() => {
  window.scrollTo = (() => {}) as typeof window.scrollTo;
});

describe("the admin dashboard", () => {
  test("is its own page, not the workspace: no workspace menu, one header, counts only, reads only", async () => {
    const { seen } = renderAdmin();
    expect(await screen.findByText("Doddy Admin")).toBeInTheDocument();
    expect(screen.getByText("Counts only: no words, notes or audio exist here.")).toBeInTheDocument();
    expect(screen.queryByRole("navigation", { name: "Workspace" })).toBeNull();
    expect(screen.getByRole("link", { name: "Back to Doddy" })).toHaveAttribute("href", "/");
    await screen.findByRole("heading", { level: 2, name: "Needs attention" });
    expect(seen.filter((s) => s.method !== "GET")).toEqual([]);
  });

  test("the overview: the numbers, the line chart with its table twin, the attention list and the funnel", async () => {
    renderAdmin();
    const kpis = await screen.findByRole("list", { name: "Overview" });
    const kpi = (label: string) => within(kpis).getByText(label).closest("li") as HTMLElement;
    expect(kpi("Accounts")).toHaveTextContent("4");
    expect(kpi("Accounts")).toHaveTextContent("Apple 2");
    expect(kpi("Active today")).toHaveTextContent("1");
    expect(kpi("Active in 7 days")).toHaveTextContent("3");
    expect(kpi("Conversations")).toHaveTextContent("72");
    expect(kpi("Activation")).toHaveTextContent("75%");
    expect(kpi("Activation")).toHaveTextContent("3 of 4 new accounts used Doddy within a week");

    const chart = screen.getByRole("heading", { level: 2, name: "Accounts using Doddy, each day" }).closest("section") as HTMLElement;
    expect(within(chart).getByRole("img", { name: /Accounts using Doddy, each day/ })).toBeInTheDocument();
    await userEvent.click(within(chart).getByRole("button", { name: "Table" }));
    const rows = within(chart).getAllByRole("row");
    expect(rows).toHaveLength(31); // header + 30 days
    expect(within(chart).getByRole("button", { name: "Chart" })).toHaveAttribute("aria-pressed", "true");

    const attention = screen.getByRole("heading", { level: 2, name: "Needs attention" }).closest("section") as HTMLElement;
    expect(within(attention).getByText(/of the 4 new accounts used Doddy within a week/)).toBeInTheDocument();
    expect(within(attention).getAllByText("Good").length).toBeGreaterThan(0); // the level is words too, never color alone

    const funnel = screen.getByRole("heading", { level: 2, name: "How many accounts stay active" }).closest("section") as HTMLElement;
    expect(within(funnel).getByText("All accounts")).toBeInTheDocument();
    expect(within(funnel).getByText("Active today")).toBeInTheDocument();
  });

  test("users: search, the filters and a sparkline for each account", async () => {
    renderAdmin();
    await userEvent.click(await tab("Users"));
    const table = await screen.findByRole("table");
    expect(within(table).getAllByRole("row")).toHaveLength(5); // header + 4
    expect(within(table).getAllByRole("img", { name: /Last 14 days/ })).toHaveLength(4);
    expect(screen.getByText("4 of 4 accounts")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: /Never used/ }));
    expect(within(screen.getByRole("table")).getAllByRole("row")).toHaveLength(2);
    expect(within(screen.getByRole("table")).getByText("x7k2p9q4@privaterelay.appleid.com")).toBeInTheDocument();
    expect(screen.getByText("1 of 4 accounts")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: /Everyone/ }));
    await userEvent.type(screen.getByRole("searchbox", { name: "Search by email or name" }), "tomek");
    expect(within(screen.getByRole("table")).getAllByRole("row")).toHaveLength(2);
    await userEvent.clear(screen.getByRole("searchbox"));
    await userEvent.type(screen.getByRole("searchbox"), "nobody@nowhere");
    expect(screen.getByText("No accounts match.")).toBeInTheDocument();
  });

  test("an account opens its own days in a drawer that Escape closes", async () => {
    renderAdmin();
    await userEvent.click(await tab("Users"));
    await userEvent.click(await screen.findByRole("button", { name: "tomek@example.com" }));
    const drawer = await screen.findByRole("dialog");
    expect(within(drawer).getByRole("heading", { level: 2, name: "tomek@example.com" })).toBeInTheDocument();
    expect(within(drawer).getByText(/Tomek Nowak/)).toBeInTheDocument();
    expect(await within(drawer).findByRole("heading", { level: 2, name: "Conversations each day" })).toBeInTheDocument();
    expect(within(drawer).getByText(/Account id: 00000000-0000-4000-8000-00000000000b/)).toBeInTheDocument();
    expect(within(drawer).getByRole("button", { name: "Close" })).toHaveFocus();
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  test("tools: every tool as a bar with a glyph legend, the trouble filter and the table", async () => {
    renderAdmin();
    await userEvent.click(await tab("Tools"));
    const card = (await screen.findByRole("heading", { level: 2, name: "Does it work? Every tool, by result" })).closest("section") as HTMLElement;
    for (const label of ["Done", "Said no", "Not sure", "Didn't work"]) expect(within(card).getByText(label)).toBeInTheDocument();
    expect(within(card).getAllByText(/\d+ uses/).length).toBeGreaterThan(3);
    const before = within(card).getAllByText(/\d+ uses/).length;
    await userEvent.click(screen.getByRole("button", { name: "Only tools with 20% trouble or more" }));
    expect(within(card).queryAllByText(/\d+ uses/).length).toBeLessThan(before);
    await userEvent.click(within(card).getByRole("button", { name: "Table" }));
    expect(within(card).getByRole("columnheader", { name: "Didn't work" })).toBeInTheDocument();
  });

  test("conversations: when people talk (with a number grid twin), how long, how they end, languages and tasks", async () => {
    renderAdmin();
    await userEvent.click(await tab("Conversations"));
    const heat = (await screen.findByRole("heading", { level: 2, name: "When people talk to Doddy" })).closest("section") as HTMLElement;
    expect(within(heat).getByRole("img", { name: "When people talk to Doddy" })).toBeInTheDocument();
    await userEvent.click(within(heat).getByRole("button", { name: "Table" }));
    expect(within(heat).getAllByRole("row")).toHaveLength(8); // hours + 7 weekdays
    expect(screen.getByRole("heading", { level: 2, name: "How long conversations last" })).toBeInTheDocument();
    expect(screen.getByText("The connection dropped")).toBeInTheDocument();
    const languages = screen.getByRole("heading", { level: 2, name: "Languages" }).closest("section") as HTMLElement;
    expect(within(languages).getByText("PL")).toBeInTheDocument();
    expect(within(languages).getByText("EN")).toBeInTheDocument();
    expect(screen.getByText("Tasks handed over to Doddy")).toBeInTheDocument();
  });

  test("growth: new accounts, sign-in methods with one color each, activation and the weekly cohorts", async () => {
    renderAdmin();
    await userEvent.click(await tab("Growth"));
    expect(await screen.findByRole("heading", { level: 2, name: "New accounts each day" })).toBeInTheDocument();
    const methods = screen.getByRole("heading", { level: 2, name: "How accounts sign in" }).closest("section") as HTMLElement;
    expect(within(methods).getByText("Apple")).toBeInTheDocument();
    expect(within(methods).getByText("Google")).toBeInTheDocument();
    expect(within(methods).getByText("Email")).toBeInTheDocument();
    const cohorts = screen.getByRole("heading", { level: 2, name: "Weekly cohorts" }).closest("section") as HTMLElement;
    expect(within(cohorts).getAllByRole("row")).toHaveLength(9); // header + 8 weeks
    expect(within(cohorts).getByRole("columnheader", { name: "+1 wk" })).toBeInTheDocument();
    expect(within(cohorts).getByText("2026-09-28")).toBeInTheDocument();
    // Nobody in the fixture joined 28 days ago, so week 4 has no one to judge yet: a dash, never 0%.
    expect(within(cohorts).getByRole("columnheader", { name: "Value in week 4" })).toBeInTheDocument();
    const firstWeek = within(cohorts).getByRole("row", { name: /^2026-09-28/ });
    expect(within(firstWeek).getAllByRole("cell").at(-1)).toHaveTextContent("—");
  });

  test("growth: tasks that worked out each week, per account, with the guardrails and what the number leaves in", async () => {
    renderAdmin();
    await userEvent.click(await tab("Growth"));
    const value = (await screen.findByRole("heading", { level: 2, name: "Tasks that worked out" })).closest("section") as HTMLElement;
    expect(within(value).getByText(/not only changes Doddy confirmed/)).toBeInTheDocument();
    expect(within(value).getByText("This week so far")).toBeInTheDocument();
    expect(within(value).getAllByRole("row")).toHaveLength(9); // header + 8 weeks
    const now = within(value).getByRole("row", { name: /^2026-10-19 \(so far\)/ });
    expect(within(now).getAllByRole("cell").map((c) => c.textContent)).toEqual(["3", "13", "4.3", "100%", "7%", "0%", "0%", "22%"]);
    for (const name of ["Not sure", "Didn't work", "Undone", "Said no"]) expect(within(value).getByRole("columnheader", { name })).toBeInTheDocument();

    const first = screen.getByRole("heading", { level: 2, name: "From the first task that worked out" }).closest("section") as HTMLElement;
    expect(within(first).getAllByRole("row")).toHaveLength(9);
    expect(within(first).queryByRole("columnheader", { name: "Joined" })).toBeNull();
    const row = within(first).getByRole("row", { name: /^2026-09-28/ });
    // Size, then weeks +1 to +3 after the first task, then the four weeks still to come as blanks.
    expect(within(row).getAllByRole("cell").map((c) => c.textContent)).toEqual(["1", "100%", "100%", "100%", "", "", "", ""]);
  });

  test("growth in Polish: the new sections have their Polish words", async () => {
    renderAdmin("/admin", {}, "pl");
    await userEvent.click(await tab("Wzrost"));
    expect(await screen.findByRole("heading", { level: 2, name: "Zadania, które wyszły" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { level: 2, name: "Od pierwszego zadania, które wyszło" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Wartość w 4. tygodniu" })).toBeInTheDocument();
  });

  test("changing the period asks the server for that period (and keeps the page on screen meanwhile)", async () => {
    const { fetchMock } = renderAdmin();
    await screen.findByRole("heading", { level: 2, name: "Needs attention" });
    const asked = () => fetchMock.mock.calls.map((c) => String(c[0])).filter((u) => u.includes("/v1/web/owner/overview"));
    expect(asked()).toEqual(["/v1/web/owner/overview?days=30"]);
    await userEvent.selectOptions(screen.getByRole("combobox", { name: "Period" }), "7");
    await waitFor(() => expect(asked()).toEqual(["/v1/web/owner/overview?days=30", "/v1/web/owner/overview?days=7"]));
    expect(fetchMock.mock.calls.map((c) => String(c[0]))).toContain("/v1/web/owner/accounts?days=7");
  });

  test("the Insights open the place that has the details, with the filter set", async () => {
    renderAdmin("/admin", {
      "GET /v1/web/owner/accounts": {
        body: (() => {
          const list = fixture("web/owner-accounts") as { accounts: { logbook: string }[] };
          return { ...list, accounts: list.accounts.map((a, i) => (i === 2 ? { ...a, logbook: "off", lastActiveDay: null } : a)) };
        })(),
      },
    });
    const attention = (await screen.findByRole("heading", { level: 2, name: "Needs attention" })).closest("section") as HTMLElement;
    const off = within(attention).getByText(/Logbook is off, so their use isn't counted: 1 accounts/).closest("li") as HTMLElement;
    await userEvent.click(within(off).getByRole("button"));
    expect(await screen.findByRole("tab", { name: "Users", selected: true })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Logbook off/ })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByText("1 of 4 accounts")).toBeInTheDocument();
  });

  test("the attention list shows the first six findings and keeps the rest behind one button", async () => {
    const overview = fixture("web/owner-overview") as { logbook: { totals: { tools: Record<string, unknown> } } };
    const tools = Object.fromEntries(Array.from({ length: 8 }, (_, i) => [`broken_tool_${i}`, { done: 4, declined: 0, unsure: 0, failed: 6, undone: 0 }]));
    overview.logbook.totals.tools = tools;
    renderAdmin("/admin", { "GET /v1/web/owner/overview": { body: overview } });
    const attention = (await screen.findByRole("heading", { level: 2, name: "Needs attention" })).closest("section") as HTMLElement;
    expect(within(attention).getAllByRole("listitem")).toHaveLength(6);
    await userEvent.click(within(attention).getByRole("button", { name: /Show all \d+/ }));
    expect(within(attention).getAllByRole("listitem").length).toBeGreaterThan(6);
    expect(within(attention).getByText(/broken_tool_7 doesn't work out 60% of the time \(10 uses\)/)).toBeInTheDocument();
    await userEvent.click(within(attention).getByRole("button", { name: "Show fewer" }));
    expect(within(attention).getAllByRole("listitem")).toHaveLength(6);
  });

  test("in Polish", async () => {
    renderAdmin("/admin", {}, "pl");
    expect(await screen.findByRole("heading", { level: 2, name: "Wymaga uwagi" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Użytkownicy" })).toBeInTheDocument();
    expect(screen.getByText("Same liczby: nie ma tu słów, notatek ani dźwięku.")).toBeInTheDocument();
  });

  test("someone who isn't an owner is sent back to Home, and sees nothing of it", async () => {
    renderAdmin("/admin", { "GET /v1/web/owner": notFound, "GET /v1/web/owner/overview": notFound, "GET /v1/web/owner/accounts": notFound });
    const nav = await screen.findByRole("navigation", { name: "Workspace" });
    expect(within(nav).queryByRole("link", { name: "Admin" })).toBeNull();
    expect(screen.queryByText("Doddy Admin")).toBeNull();
  });

  test("a sign-in older than the panel allows is asked to sign in again, and no account is shown", async () => {
    const refused = { status: 422, body: { error: { code: "refused", message: "For safety, the owner panel opens only within 15 minutes of signing in. Sign out, sign in again, then open it." } } };
    const { seen } = renderAdmin("/admin", {
      "GET /v1/web/owner/overview": refused,
      "GET /v1/web/owner/accounts": refused,
      "DELETE /v1/web/session": { body: { signedOut: true } },
    });
    expect(await screen.findByRole("alert")).toHaveTextContent("For safety, the owner panel opens only within 15 minutes of signing in.");
    expect(screen.queryByRole("heading", { level: 2, name: "Needs attention" })).toBeNull();
    expect(screen.queryByText("tomek@example.com")).toBeNull();
    expect(screen.getByRole("link", { name: "Back to Doddy" })).toHaveAttribute("href", "/");
    await userEvent.click(screen.getByRole("button", { name: "Sign out" }));
    expect(await screen.findByRole("heading", { name: "Sign in to Doddy" })).toBeInTheDocument();
    expect(seen.filter((s) => s.method === "DELETE").map((s) => s.path)).toEqual(["/v1/web/session"]);
  });

  test("the same, in Polish", async () => {
    const refused = { status: 422, body: { error: { code: "refused", message: "x" } } };
    renderAdmin("/admin", { "GET /v1/web/owner/overview": refused, "GET /v1/web/owner/accounts": refused }, "pl");
    expect(await screen.findByRole("alert")).toHaveTextContent("Dla bezpieczeństwa panel właściciela otwiera się tylko w ciągu 15 minut od zalogowania.");
    expect(screen.getByRole("button", { name: "Wyloguj się" })).toBeInTheDocument();
  });

  test("an owner finds the dashboard in the menu; nobody else does", async () => {
    renderAdmin("/");
    const nav = await screen.findByRole("navigation", { name: "Workspace" });
    expect(await within(nav).findByRole("link", { name: "Admin" })).toHaveAttribute("href", "/admin");
  });
});
