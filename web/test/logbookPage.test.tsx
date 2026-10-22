import { fireEvent, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { describe, expect, test } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import type { Language } from "../src/i18n/messages.js";
import { fakeServer, fixture } from "./fakeServer.js";

function renderLogbook(language: Language = "en", path = "/logbook") {
  const server = fakeServer({
    "GET /v1/web/session": { body: fixture("web/session-current") },
    "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
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

/** The receipt line with this label, as "Label" + "value" text. */
const receiptLine = (label: string) => within(screen.getByRole("figure")).getByText(label).parentElement?.textContent;

describe("Logbook, At a glance", () => {
  test("it says its numbers are examples, and asks the server for nothing", async () => {
    const { seen } = renderLogbook();
    expect(await screen.findByRole("heading", { level: 1, name: "Logbook" })).toBeInTheDocument();
    expect(screen.getByRole("note")).toHaveTextContent("Example. Made-up numbers, not anyone's usage.");
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(within(nav).getByRole("link", { name: "Logbook Example" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("tab", { name: /At a glance/ })).toHaveAttribute("aria-selected", "true");
    // Only the session check and the page's own health check went to the server.
    expect(seen.map((s) => s.path).sort()).toEqual(["/v1/health", "/v1/web/session"]);
  });

  test("the week is printed as a receipt, from the example's numbers", async () => {
    renderLogbook();
    expect(await screen.findByRole("heading", { level: 2, name: "Your week with Doddy" })).toBeInTheDocument();
    expect(receiptLine("Conversations")).toBe("Conversations28");
    expect(receiptLine("Time talking")).toBe("Time talking1 h 28 min");
    expect(receiptLine("Notes saved")).toBe("Notes saved9");
    expect(receiptLine("Things Doddy did")).toBe("Things Doddy did38");
    expect(receiptLine("right away")).toBe("right away27");
    expect(receiptLine("after your yes")).toBe("after your yes11");
    expect(receiptLine("Asked you first")).toBe("Asked you first15");
    expect(receiptLine("your yes")).toBe("your yes14");
    expect(receiptLine("your no")).toBe("your no1");
    // Couldn't confirm and didn't work are their own lines, never folded into "done".
    expect(receiptLine("Couldn't confirm")).toBe("Couldn't confirm2");
    expect(receiptLine("Didn't work")).toBe("Didn't work1");
    expect(receiptLine("Tasks handed over")).toBe("Tasks handed over3");
  });

  test("the week arrows step through whole weeks to this week so far, and stop at the ends", async () => {
    renderLogbook();
    const label = await screen.findByText("Week 42");
    expect(label.parentElement).toHaveTextContent("12–18 October 2026");
    await userEvent.click(screen.getByRole("button", { name: "Earlier week" }));
    // The stepper and the panel's eyebrow both say which week it is.
    expect(screen.getAllByText("Week 41")).toHaveLength(2);
    await userEvent.click(screen.getByRole("button", { name: "Later week" }));
    await userEvent.click(screen.getByRole("button", { name: "Later week" }));
    expect(screen.getByRole("heading", { level: 2, name: "Your week so far" })).toBeInTheDocument();
    expect(screen.getAllByText("This week so far").length).toBeGreaterThan(0);
    expect(screen.getByRole("button", { name: "Later week" })).toBeDisabled();
    for (let i = 0; i < 12; i += 1) await userEvent.click(screen.getByRole("button", { name: "Earlier week" }));
    expect(screen.getByRole("button", { name: "Earlier week" })).toBeDisabled();
  });

  test("a chart shows the same readout on keyboard focus as on hover", async () => {
    renderLogbook();
    await screen.findByRole("heading", { level: 2, name: "Each day" });
    const group = screen.getByRole("group", { name: "Conversations each day this week" });
    const column = group.querySelector("rect.lb-hit");
    expect(column).not.toBeNull();
    expect(column?.getAttribute("aria-label")).toMatch(/^Monday 12 October: Conversations \d+, Time talking \d+ min$/);
    fireEvent.focus(column as Element);
    const tip = await screen.findByRole("tooltip");
    expect(tip).toHaveTextContent("Monday 12 October");
    expect(within(tip).getByText("Conversations")).toBeInTheDocument();
    fireEvent.blur(column as Element);
    expect(screen.queryByRole("tooltip")).toBeNull();
  });
});

describe("Logbook, Closer look", () => {
  async function openCloser() {
    renderLogbook();
    await userEvent.click(await screen.findByRole("tab", { name: /Closer look/ }));
    return screen.findByRole("heading", { level: 2, name: "Every tool, counted" });
  }

  test("the tab opens with totals, with no comparison with an earlier period", async () => {
    await openCloser();
    expect(screen.getByRole("tab", { name: /Closer look/ })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("button", { name: "30 days" })).toHaveAttribute("aria-pressed", "true");
    for (const label of ["Conversations", "Time talking", "Average conversation", "Notes saved", "Things Doddy did"]) {
      expect(document.querySelector(".lb-kpis")).toHaveTextContent(label);
    }
    // Counts only: no trend words, arrows or percentages-against-before (ADR-306, DOD-10).
    const page = document.body.textContent ?? "";
    expect(page).not.toMatch(/streak|score|vs\.? (last|previous)|compared (to|with)|▲|▼|↑ \d|↓ \d/i);
  });

  test("the period buttons change every number together", async () => {
    await openCloser();
    const conversations = () => document.querySelector(".lb-kpis .lb-kpi-value")?.textContent;
    const thirty = conversations();
    await userEvent.click(screen.getByRole("button", { name: "7 days" }));
    expect(screen.getByRole("button", { name: "7 days" })).toHaveAttribute("aria-pressed", "true");
    expect(document.querySelector(".lb-range")).toHaveTextContent("15–21 October 2026");
    expect(Number(conversations())).toBeLessThan(Number(thirty));
    await userEvent.click(screen.getByRole("button", { name: "90 days" }));
    expect(screen.getByRole("group", { name: "Conversations each week" })).toBeInTheDocument();
    expect(Number(conversations())).toBeGreaterThan(Number(thirty));
  });

  test("the tool table sorts by any column, and a tool that never asks has no 'no'", async () => {
    await openCloser();
    const table = screen.getAllByRole("table")[0] as HTMLElement;
    const names = () => within(table).getAllByRole("row").slice(1).map((r) => within(r).getAllByRole("cell")[0]?.textContent ?? "");
    const times = () => within(table).getAllByRole("row").slice(1).map((r) => Number((within(r).getAllByRole("cell")[2]?.textContent ?? "").replace(/\D/g, "")));
    expect(within(table).getByRole("columnheader", { name: "Times" })).toHaveAttribute("aria-sort", "descending");
    expect(times()).toEqual([...times()].sort((a, b) => b - a));
    await userEvent.click(within(table).getByRole("button", { name: "Tool" }));
    expect(within(table).getByRole("columnheader", { name: "Tool" })).toHaveAttribute("aria-sort", "ascending");
    expect(names()).toEqual([...names()].sort((a, b) => a.localeCompare(b)));
    await userEvent.click(within(table).getByRole("button", { name: "Tool" }));
    expect(within(table).getByRole("columnheader", { name: "Tool" })).toHaveAttribute("aria-sort", "descending");
    // Weather runs without asking, so its "Your no" cell is a dash, not a zero.
    const weather = within(table).getAllByRole("row").find((r) => within(r).queryAllByRole("cell")[0]?.textContent === "Weather") as HTMLElement;
    expect(within(weather).getAllByRole("cell")[4]).toHaveTextContent("–");
  });

  test("every chart has a table twin", async () => {
    await openCloser();
    const before = screen.getAllByRole("table").length;
    expect(screen.getByRole("group", { name: "Conversations each day" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("checkbox", { name: "Show as tables" }));
    expect(screen.queryByRole("group", { name: "Conversations each day" })).toBeNull();
    expect(screen.getAllByRole("table").length).toBeGreaterThan(before + 5);
    expect(screen.getByRole("table", { name: "Conversations each day" })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: "Conversations by weekday and hour (hours with none left out)" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("checkbox", { name: "Show as tables" }));
    expect(screen.getByRole("group", { name: "Conversations each day" })).toBeInTheDocument();
  });

  test("when Doddy asked first, the yes, no, couldn't confirm and didn't work all add up", async () => {
    await openCloser();
    const card = screen.getByRole("heading", { level: 2, name: "When Doddy asked first" }).closest("section") as HTMLElement;
    const line = within(card).getByText(/^Asked first: \d+\. Your yes: \d+\. Your no: \d+\.$/).textContent ?? "";
    const [asked, yes, no] = (line.match(/\d+/g) ?? []).map(Number) as [number, number, number];
    expect(asked).toBe(yes + no);
    const rows = within(card).getAllByRole("listitem").map((li) => Number(li.querySelector("b")?.textContent));
    // Done + couldn't confirm + didn't work = your yes; the last row is your no.
    expect(rows[0]! + rows[1]! + rows[2]!).toBe(yes);
    expect(rows[3]).toBe(no);
  });
});

describe("Logbook, controls and words", () => {
  test("the tabs follow the arrow keys", async () => {
    renderLogbook();
    const glance = await screen.findByRole("tab", { name: /At a glance/ });
    glance.focus();
    await userEvent.keyboard("{ArrowRight}");
    expect(screen.getByRole("tab", { name: /Closer look/ })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("tab", { name: /Closer look/ })).toHaveFocus();
    await userEvent.keyboard("{ArrowLeft}");
    expect(screen.getByRole("tab", { name: /At a glance/ })).toHaveFocus();
  });

  test("download and delete only say what they will do; delete takes two taps", async () => {
    renderLogbook();
    await userEvent.click(await screen.findByRole("button", { name: "Delete everything here" }));
    expect(screen.getByRole("button", { name: "Tap again to delete everything" })).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Tap again to delete everything" }));
    expect(screen.getByRole("status")).toHaveTextContent("Deleting is always free.");
    expect(screen.getByRole("button", { name: "Delete everything here" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Download everything" }));
    expect(screen.getByRole("status")).toHaveTextContent("Downloading and deleting are always free.");
  });

  test("the privacy panel says what is never on the page", async () => {
    renderLogbook();
    const panel = (await screen.findByRole("heading", { level: 2, name: "What Logbook will know" })).closest("section") as HTMLElement;
    expect(within(panel).getByText("Your notes, lists or tags")).toBeInTheDocument();
    expect(within(panel).getByText("Private notes, not even a count")).toBeInTheDocument();
    expect(within(panel).getByText("Off until you turn it on in the app")).toBeInTheDocument();
  });

  test("in Polish: the page, the receipt and the tabs", async () => {
    renderLogbook("pl");
    expect(await screen.findByRole("heading", { level: 1, name: "Dziennik" })).toBeInTheDocument();
    expect(screen.getByRole("note")).toHaveTextContent("Przykład. Wymyślone liczby");
    expect(screen.getByRole("heading", { level: 2, name: "Twój tydzień z Doddym" })).toBeInTheDocument();
    expect(receiptLine("Rozmowy")).toBe("Rozmowy28");
    expect(receiptLine("Czas rozmów")).toBe("Czas rozmów1 godz. 28 min");
    expect(receiptLine("Twoje „nie”")).toBe("Twoje „nie”1");
    expect(screen.getByText("Tydzień 42").parentElement).toHaveTextContent("12–18 października 2026");
    await userEvent.click(screen.getByRole("tab", { name: /Z bliska/ }));
    expect(await screen.findByRole("heading", { level: 2, name: "Każde narzędzie z liczbą użyć" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "30 dni" })).toHaveAttribute("aria-pressed", "true");
  });

  test("a tool the page can't name yet is not an error; every other id in the example has words in both languages", async () => {
    const { MESSAGES } = await import("../src/i18n/messages.js");
    const { TOOL_IDS, TOOLS } = await import("../src/logbook/catalog.js");
    for (const language of ["en", "pl"] as const) {
      for (const id of TOOL_IDS) {
        expect(MESSAGES[language][`logbook.tool.${id}` as const].length, `${language} ${id}`).toBeGreaterThan(0);
        expect(MESSAGES[language][`logbook.app.${TOOLS[id].app}` as const].length).toBeGreaterThan(0);
        expect(MESSAGES[language][`logbook.job.${TOOLS[id].job}` as const].length).toBeGreaterThan(0);
      }
    }
  });
});
