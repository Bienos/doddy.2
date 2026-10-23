import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import type { Language } from "../src/i18n/messages.js";
import { fakeServer, fixture } from "./fakeServer.js";

type Routes = Parameters<typeof fakeServer>[0];

/**
 * The page with a fake server. By default Logbook is off on the server and the test opens the
 * example (#example), so the long-standing checks of the charts run on the seeded example week.
 */
function renderLogbook(language: Language = "en", path = "/logbook#example", routes: Routes = {}) {
  const server = fakeServer({
    "GET /v1/web/session": { body: fixture("web/session-current") },
    "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
    "GET /v1/web/logbook": { body: fixture("web/logbook-off") },
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

/** The receipt line with this label, as "Label" + "value" text. */
const receiptLine = (label: string) => within(screen.getByRole("figure")).getByText(label).parentElement?.textContent;

describe("Logbook, At a glance", () => {
  test("the example says its numbers are made up, and sends the server nothing but the read", async () => {
    const { seen } = renderLogbook();
    expect(await screen.findByRole("heading", { level: 1, name: "Logbook" })).toBeInTheDocument();
    expect(screen.getByRole("note")).toHaveTextContent("Example. Made-up numbers, not anyone's usage.");
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(within(nav).getByRole("link", { name: "Logbook Example" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("tab", { name: /At a glance/ })).toHaveAttribute("aria-selected", "true");
    // The session check, the health check and the Logbook read: no writes.
    await waitFor(() => expect(seen.map((s) => `${s.method} ${s.path}`).sort()).toEqual(["GET /v1/health", "GET /v1/web/logbook", "GET /v1/web/session"]));
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
    // The first week starts mid-week (23 July) and is the last stop.
    for (let i = 0; i < 13; i += 1) await userEvent.click(screen.getByRole("button", { name: "Earlier week" }));
    expect(screen.getByRole("button", { name: "Earlier week" })).toBeDisabled();
    expect(screen.getAllByText("Week 30").length).toBeGreaterThan(0);
    expect(screen.queryByText("This week so far")).toBeNull();
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
    // A year is as far as Logbook keeps; the example only has 13 weeks, so it shows all of them.
    const ninety = conversations();
    await userEvent.click(screen.getByRole("button", { name: "1 year" }));
    expect(screen.getByRole("button", { name: "1 year" })).toHaveAttribute("aria-pressed", "true");
    expect(Number(conversations())).toBeGreaterThanOrEqual(Number(ninety));
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
    expect(within(panel).getByText("The text of your notes, lists or tags")).toBeInTheDocument();
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

// ---------------------------------------------------------------- real numbers and their states

const VIEW = fixture("web/logbook-view") as { updatedAt: string; days: { day: string }[] };
const serves = (name: string, status = 200): Routes => ({ "GET /v1/web/logbook": { status, body: fixture(`web/${name}`) } });

describe("Logbook, the numbers the iPhone sent", () => {
  beforeEach(() => {
    // The fixtures' clock is 22 Oct 2026; only the date is faked so waiting still works.
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-22T12:00:00Z"));
  });
  afterEach(() => vi.useRealTimers());

  test("the days from the server are what the receipt prints, with no example banner", async () => {
    renderLogbook("en", "/logbook", serves("logbook-view"));
    expect(await screen.findByRole("heading", { level: 2, name: "Your week so far" })).toBeInTheDocument();
    // 4 + 1 + 3 conversations on 20, 21 and 22 October in the fixture.
    expect(receiptLine("Conversations")).toBe("Conversations8");
    expect(screen.queryByText("Example.")).toBeNull();
    expect(screen.queryByRole("note")).toBeNull();
    expect(document.querySelector(".lb-fresh")).toHaveTextContent("Your iPhone last sent numbers");
    expect(document.querySelector(".lb-fresh")).not.toHaveTextContent("Example");
  });

  test("the page reads with the web app's own header and sends nothing else", async () => {
    const { seen } = renderLogbook("en", "/logbook", serves("logbook-view"));
    await screen.findByRole("heading", { level: 2, name: "Your week so far" });
    const read = seen.find((s) => s.path === "/v1/web/logbook");
    expect(read?.method).toBe("GET");
    expect(read?.credentials).toBe("same-origin");
    expect(seen.filter((s) => s.method !== "GET")).toEqual([]);
  });

  test("Logbook off: one calm card that never sends anyone to a switch that isn't built, and an example on request", async () => {
    renderLogbook("en", "/logbook");
    expect(await screen.findByRole("heading", { level: 2, name: "Logbook is off" })).toBeInTheDocument();
    const card = screen.getByRole("heading", { level: 2, name: "Logbook is off" }).closest("section") as HTMLElement;
    expect(card).toHaveTextContent("can't send Logbook yet");
    expect(document.body).not.toHaveTextContent("Settings › Doddy on the web");
    expect(screen.queryByRole("tablist")).toBeNull();

    await userEvent.click(within(card).getByRole("button", { name: "Show an example" }));
    expect(screen.getByRole("note")).toHaveTextContent("Example. Made-up numbers, not anyone's usage. Your real Logbook needs a Doddy update on your iPhone that isn't built yet.");
    expect(receiptLine("Conversations")).toBe("Conversations28");
    await userEvent.click(screen.getByRole("button", { name: "Back to my Logbook" }));
    expect(screen.getByRole("heading", { level: 2, name: "Logbook is off" })).toBeInTheDocument();
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("Logbook on with nothing sent yet says so, without zeros or an empty chart", async () => {
    renderLogbook("en", "/logbook", serves("logbook-empty"));
    expect(await screen.findByRole("heading", { level: 2, name: "Nothing counted yet" })).toBeInTheDocument();
    expect(document.body).toHaveTextContent("Logbook is on. The first days appear here after your iPhone sends them.");
    expect(screen.queryByRole("tablist")).toBeNull();
    expect(screen.queryByRole("figure")).toBeNull();
  });

  test("the server can't be reached: an error and a way to try again, never zeros", async () => {
    let calls = 0;
    renderLogbook("en", "/logbook", {
      "GET /v1/web/logbook": () => (++calls === 1 ? new Error("offline") : { body: fixture("web/logbook-view") }),
    });
    expect(await screen.findByRole("alert")).toHaveTextContent("couldn't be reached");
    expect(screen.queryByRole("figure")).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByRole("heading", { level: 2, name: "Your week so far" })).toBeInTheDocument();
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("a reply the page can't read is an error, not half-shown data", async () => {
    const bad = structuredClone(fixture("web/logbook-view")) as { days: Record<string, unknown>[] };
    bad.days[0] = { ...bad.days[0], transcript: "buy milk" };
    renderLogbook("en", "/logbook", { "GET /v1/web/logbook": { body: bad } });
    expect(await screen.findByRole("alert")).toHaveTextContent("can't read");
    expect(screen.queryByRole("figure")).toBeNull();
    expect(document.body).not.toHaveTextContent("buy milk");
  });

  test("two days without anything from the iPhone: said once, with the date, without guilt", async () => {
    vi.setSystemTime(new Date("2026-10-26T09:00:00Z"));
    renderLogbook("en", "/logbook", serves("logbook-view"));
    expect(await screen.findByRole("note")).toHaveTextContent(/^Your iPhone last sent counts on 22 Oct 2026\. Open Doddy to update\.$/);
    vi.setSystemTime(new Date("2026-10-23T09:00:00Z"));
  });

  test("a recent send shows no such note", async () => {
    vi.setSystemTime(new Date("2026-10-23T09:00:00Z"));
    renderLogbook("en", "/logbook", serves("logbook-view"));
    await screen.findByRole("heading", { level: 2, name: "Your week so far" });
    expect(screen.queryByRole("note")).toBeNull();
  });

  test("delete takes two taps, then the server deletes; 'Deleted' is said only after it answers, and the page empties", async () => {
    let afterDelete = false;
    const { seen } = renderLogbook("en", "/logbook", {
      "GET /v1/web/logbook": () => ({ body: fixture(afterDelete ? "web/logbook-empty" : "web/logbook-view") }),
      "DELETE /v1/web/logbook": () => {
        afterDelete = true;
        return { body: fixture("web/logbook-deleted") };
      },
    });
    await userEvent.click(await screen.findByRole("button", { name: "Delete everything here" }));
    expect(seen.filter((s) => s.method === "DELETE")).toHaveLength(0);
    expect(screen.queryByText(/Deleted/)).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Tap again to delete everything" }));
    expect(await screen.findByRole("heading", { level: 2, name: "Nothing counted yet" })).toBeInTheDocument();
    const deleted = seen.filter((s) => s.method === "DELETE");
    expect(deleted).toHaveLength(1);
    expect(deleted[0]?.path).toBe("/v1/web/logbook");
    expect(deleted[0]?.headers["x-doddy-web"]).toBe("1");
    expect(screen.getByRole("status")).toHaveTextContent("Deleted. 3 days removed from Doddy's server.");
  });

  test("a delete the server refuses says so in words and leaves the numbers where they were", async () => {
    renderLogbook("en", "/logbook", {
      ...serves("logbook-view"),
      "DELETE /v1/web/logbook": { status: 500, body: { error: { code: "internal", message: "boom" } } },
    });
    await userEvent.click(await screen.findByRole("button", { name: "Delete everything here" }));
    await userEvent.click(screen.getByRole("button", { name: "Tap again to delete everything" }));
    expect(await screen.findByRole("status")).toHaveTextContent("Something went wrong on Doddy's server. Nothing was changed.");
    expect(screen.queryByText(/^Deleted/)).toBeNull();
    expect(receiptLine("Conversations")).toBe("Conversations8");
  });

  test("download everything saves the server's file", async () => {
    const saved: { name: string; url: string }[] = [];
    const createObjectURL = vi.fn(() => "blob:logbook");
    Object.assign(URL, { createObjectURL, revokeObjectURL: vi.fn() });
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) {
      saved.push({ name: this.download, url: this.href });
    });
    const { seen } = renderLogbook("en", "/logbook", {
      ...serves("logbook-view"),
      "GET /v1/web/logbook/export": { blob: new Blob(["{}"], { type: "application/json" }) },
    });
    await userEvent.click(await screen.findByRole("button", { name: "Download everything" }));
    expect(await screen.findByRole("status")).toHaveTextContent("Saved everything stored for your Logbook as a file.");
    expect(seen.some((s) => s.path === "/v1/web/logbook/export")).toBe(true);
    expect(saved).toEqual([{ name: "doddy-logbook-2026-10-22.json", url: "blob:logbook" }]);
    click.mockRestore();
  });

  test("Download CSV saves one row per day of the period shown: counts and dates only", async () => {
    const blobs: Blob[] = [];
    Object.assign(URL, { createObjectURL: vi.fn((blob: Blob) => (blobs.push(blob), "blob:csv")), revokeObjectURL: vi.fn() });
    const names: string[] = [];
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) {
      names.push(this.download);
    });
    renderLogbook("en", "/logbook", serves("logbook-view"));
    await userEvent.click(await screen.findByRole("tab", { name: /Closer look/ }));
    await userEvent.click(await screen.findByRole("button", { name: "Download CSV" }));
    expect(await screen.findByRole("status")).toHaveTextContent("Saved the numbers shown as a CSV file.");
    expect(names).toEqual(["doddy-logbook-2026-10-20-to-2026-10-22.csv"]);
    const text = await new Promise<string>((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.readAsText(blobs[0] as Blob);
    });
    const [header, ...rows] = text.trim().split("\r\n");
    expect(header).toMatch(/^day,conversations,seconds_talking,/);
    expect(rows.map((r) => r.split(",")[0])).toEqual(["2026-10-20", "2026-10-21", "2026-10-22"]);
    expect(rows.map((r) => r.split(",")[1])).toEqual(["4", "1", "3"]);
    for (const row of rows) expect(row).toMatch(/^[0-9,-]+$/);
    click.mockRestore();
  });

  test("in Polish: the off card and its example", async () => {
    renderLogbook("pl", "/logbook");
    expect(await screen.findByRole("heading", { level: 2, name: "Dziennik jest wyłączony" })).toBeInTheDocument();
    expect(document.body).toHaveTextContent("tej części aplikacji Doddy jeszcze nie ma");
    await userEvent.click(screen.getByRole("button", { name: "Pokaż przykład" }));
    expect(screen.getByRole("note")).toHaveTextContent("Przykład. Wymyślone liczby, nie czyjeś użycie.");
    expect(screen.getByRole("button", { name: "Wróć do mojego Dziennika" })).toBeInTheDocument();
  });
});
