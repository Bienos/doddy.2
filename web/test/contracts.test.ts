import { describe, expect, test } from "vitest";
import { CurrentSession, DocumentList, ErrorBody, ReceiptList, SessionList, ToolsCatalog } from "../src/api/schemas.js";
import { fixture } from "./fakeServer.js";

/** The server writes these files from its own replies (backend: npm run fixtures:web / fixtures). */
describe("the page reads what the server actually sends", () => {
  test("web sign-in and sessions", () => {
    expect(CurrentSession.parse(fixture("web/session-signed-in")).session.current).toBe(true);
    expect(CurrentSession.parse(fixture("web/session-current")).session.browser).toBe("chrome");
    expect(SessionList.parse(fixture("web/sessions-phone")).sessions[0]?.current).toBe(false);
    expect(ErrorBody.parse(fixture("web/error-code-invalid")).error.code).toBe("unauthenticated");
    expect(ErrorBody.parse(fixture("web/error-signed-out")).error.code).toBe("unauthenticated");
  });

  test("documents in every state", () => {
    expect(DocumentList.parse(fixture("web/documents-empty")).documents).toEqual([]);
    expect(DocumentList.parse(fixture("web/documents-working")).documents.map((d) => d.status)).toEqual(["working", "working"]);
    expect(DocumentList.parse(fixture("web/documents-ready")).documents.map((d) => d.status)).toEqual(["ready", "ready"]);
    expect(DocumentList.parse(fixture("web/documents-interrupted")).documents.map((d) => d.status)).toEqual(["ready", "interrupted", "ready"]);
  });

  test("connected apps and receipts (the iPhone's contract, shared)", () => {
    const catalog = ToolsCatalog.parse(fixture("online-accounts/catalog-gmail-on"));
    expect(catalog.toolkits.find((k) => k.id === "gmail")?.status).toBe("connected");
    ToolsCatalog.parse(fixture("online-accounts/catalog-disconnected"));
    expect(ReceiptList.parse(fixture("online-accounts/receipts")).receipts.length).toBeGreaterThan(0);
  });
});
