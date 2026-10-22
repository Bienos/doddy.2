import { render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, test, vi } from "vitest";
import { App } from "../src/App.js";
import { SessionProvider } from "../src/auth/session.js";
import { I18nProvider } from "../src/i18n/i18n.js";
import { fakeServer, fixture } from "./fakeServer.js";

/** The day the Doddy app can send notes and conversations and has the switches: the flag is flipped here, not in the pages. */
vi.mock("../src/memory/config.js", () => ({ MEMORY_ENABLED: true, IPHONE_SYNCS_MEMORY: true }));

describe("Memory once the iPhone can send it", () => {
  test("the menu loses its Soon marker, and the off card tells where the switch is", async () => {
    fakeServer({
      "GET /v1/web/session": { body: fixture("web/session-current") },
      "GET /v1/health": { body: { status: "ok", mode: "live", api: "v1", capabilities: [] } },
      "GET /v1/web/memory": { body: fixture("web/memory-off") },
    });
    render(
      <I18nProvider initial="en">
        <SessionProvider>
          <MemoryRouter initialEntries={["/memory"]}>
            <App />
          </MemoryRouter>
        </SessionProvider>
      </I18nProvider>,
    );
    const card = (await screen.findByRole("heading", { level: 2, name: "Nothing is kept on Doddy's server" })).closest("section") as HTMLElement;
    expect(card).toHaveTextContent("Turn it on in Doddy on your iPhone: Settings › Doddy on the web › Memory.");
    expect(card).not.toHaveTextContent("isn't built");
    const nav = screen.getByRole("navigation", { name: "Workspace" });
    expect(within(nav).getByRole("link", { name: "Memory" })).toHaveAttribute("aria-current", "page");
    expect(within(nav).getByRole("link", { name: "Ask Doddy" })).toBeInTheDocument();
  });
});
