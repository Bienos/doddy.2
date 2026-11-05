import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { describe, expect, test, vi } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import { fakeServer, fixture } from "./fakeServer.js";

/** The day the Doddy app can send Logbook and has the switch for it: the flag is flipped here, not in the page. */
vi.mock("../src/logbook/config.js", () => ({ LOGBOOK_ENABLED: true, IPHONE_SENDS_LOGBOOK: true }));

function renderLogbook(path = "/logbook") {
  fakeServer({
    "GET /v1/web/session": { body: fixture("web/session-current") },
    "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
    "GET /v1/web/logbook": { body: fixture("web/logbook-off") },
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
}

describe("Logbook once the iPhone can send it", () => {
  test("the menu entry loses its Example marker, and the off card tells where the switch is", async () => {
    renderLogbook();
    const card = (await screen.findByRole("heading", { level: 2, name: "Logbook is off" })).closest("section") as HTMLElement;
    expect(card).toHaveTextContent("Turn it on in Doddy on your iPhone: Settings › Doddy on the web.");
    expect(card).not.toHaveTextContent("isn't built");
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(within(nav).getByRole("link", { name: "Logbook" })).toHaveAttribute("aria-current", "page");
  });

  test("the example stops saying the iPhone half is missing", async () => {
    renderLogbook();
    await userEvent.click(await screen.findByRole("button", { name: "Show an example" }));
    expect(screen.getByRole("note")).toHaveTextContent("Example. Made-up numbers, not anyone's usage.");
    expect(screen.getByRole("note")).not.toHaveTextContent("isn't built");
  });
});
