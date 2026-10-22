import { describe, expect, test } from "vitest";
import { api, ApiError } from "../src/api/client.js";
import { fakeServer, fixture } from "./fakeServer.js";

describe("the API client", () => {
  test("sends the web app's header, same-origin credentials and JSON, never a token", async () => {
    const { seen } = fakeServer({ "POST /v1/web/session": { body: fixture("web/session-signed-in") } });
    const session = await api.signIn("ABCD-EFGH");
    expect(session.current).toBe(true);
    expect(seen[0]).toMatchObject({ method: "POST", path: "/v1/web/session", body: { code: "ABCD-EFGH" }, credentials: "same-origin" });
    expect(seen[0]?.headers["x-doddy-web"]).toBe("1");
    expect(seen[0]?.headers["content-type"]).toBe("application/json");
    expect(seen[0]?.headers.authorization).toBeUndefined();
  });

  test("server errors keep their code, message and retry time", async () => {
    fakeServer({ "GET /v1/web/documents": { status: 429, body: { error: { code: "rate_limited", message: "Slow down.", correlationId: "x", retryAfterSeconds: 120 } } } });
    const error = await api.documents().catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ code: "rate_limited", status: 429, retryAfterSeconds: 120, message: "Slow down." });
  });

  test("an unknown error code or a non-JSON error is a generic server error", async () => {
    fakeServer({ "GET /v1/tools": { status: 503, body: { error: { code: "live_not_configured", message: "Not set up." } } }, "GET /v1/tools/receipts": { status: 500, raw: "<html>" } });
    expect(await api.catalog().catch((e: ApiError) => e.code)).toBe("server");
    expect(await api.receipts().catch((e: ApiError) => e.code)).toBe("server");
  });

  test("a reply that doesn't match the contract is refused, not half-shown", async () => {
    fakeServer({ "GET /v1/web/documents": { body: { documents: [{ id: 1 }] } }, "GET /v1/web/sessions": { raw: "not json" } });
    expect(await api.documents().catch((e: ApiError) => e.code)).toBe("unreadable");
    expect(await api.sessions().catch((e: ApiError) => e.code)).toBe("unreadable");
  });

  test("no connection is a network error", async () => {
    fakeServer({ "GET /v1/web/session": new TypeError("Failed to fetch") });
    expect(await api.session().catch((e: ApiError) => e.code)).toBe("network");
  });
});
