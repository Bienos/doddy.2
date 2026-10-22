import { AppError } from "../errors.js";
import type { Route } from "../web/routes.js";
import type { MemoryChat } from "./chat.js";
import { MEMORY_CONVERSATION_MAX_BODY_BYTES, MEMORY_NOTES_MAX_BODY_BYTES, NotesSearchBody, refuse } from "./contract.js";
import type { MemoryService } from "./service.js";

/**
 * The `/v1/web/memory…` and `/v1/web/chat` routes (ADR-595), added to the web router. Who may call:
 *  - the iPhone's own session writes (switches, notes, conversations): a browser can never put
 *    anything on the server or switch keeping on;
 *  - the browser or the iPhone reads, downloads and deletes, and asks the chat. A cookie request
 *    that changes something passes the same-origin check in the router.
 * Every call is for the caller's own user id, taken from the session and never from the request.
 */

const ID = "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})";

/** `?limit=` and `?offset=` as whole numbers in range, or a 400. Words to search for are never taken from the address. */
function page(req: { url?: string | undefined }, maxLimit = 100): { limit: number; offset: number } {
  const params = new URL(req.url ?? "/", "http://doddy.invalid").searchParams;
  const number = (name: string, fallback: number, min: number, max: number) => {
    const raw = params.get(name);
    if (raw === null) return fallback;
    if (!/^\d{1,6}$/.test(raw)) throw new AppError("invalid_request");
    const value = Number(raw);
    if (value < min || value > max) throw new AppError("invalid_request");
    return value;
  };
  if (params.has("q")) throw new AppError("invalid_request", { message: "Search with POST /v1/web/memory/notes/search, not in the address." });
  return { limit: number("limit", 50, 1, maxLimit), offset: number("offset", 0, 0, 100_000) };
}

export function memoryRoutes({ service, chat }: { service: MemoryService; chat: MemoryChat }): Route[] {
  return [
    {
      method: "GET",
      pattern: /^\/v1\/web\/memory$/,
      template: "GET /v1/web/memory",
      access: "either",
      run: async ({ caller }) => ({ status: 200, body: await service.overview(caller!.userId) }),
    },
    {
      method: "DELETE",
      pattern: /^\/v1\/web\/memory$/,
      template: "DELETE /v1/web/memory",
      access: "either",
      // Deletes everything kept and switches both off; the iPhone's next send is refused and it stops.
      run: async ({ caller }) => ({ status: 200, body: await service.deleteAll(caller!.userId) }),
    },
    {
      method: "PUT",
      pattern: /^\/v1\/web\/memory\/state$/,
      template: "PUT /v1/web/memory/state",
      access: "phone",
      run: async ({ caller, body }) => ({ status: 200, body: await service.setState(caller!.userId, body) }),
    },
    {
      method: "PUT",
      pattern: /^\/v1\/web\/memory\/notes$/,
      template: "PUT /v1/web/memory/notes",
      access: "phone",
      maxBodyBytes: MEMORY_NOTES_MAX_BODY_BYTES,
      run: async ({ caller, body }) => ({ status: 200, body: await service.replaceNotes(caller!.userId, body) }),
    },
    {
      method: "PUT",
      pattern: new RegExp(`^/v1/web/memory/conversations/${ID}$`),
      template: "PUT /v1/web/memory/conversations/:id",
      access: "phone",
      maxBodyBytes: MEMORY_CONVERSATION_MAX_BODY_BYTES,
      run: async ({ caller, params, body }) => ({ status: 200, body: await service.putConversation(caller!.userId, params[0]!, body) }),
    },
    {
      method: "GET",
      pattern: /^\/v1\/web\/memory\/notes$/,
      template: "GET /v1/web/memory/notes",
      access: "either",
      run: async ({ caller, req }) => {
        const { limit, offset } = page(req);
        return { status: 200, body: await service.listNotes(caller!.userId, { limit, offset }) };
      },
    },
    {
      method: "POST",
      pattern: /^\/v1\/web\/memory\/notes\/search$/,
      template: "POST /v1/web/memory/notes/search",
      access: "either",
      run: async ({ caller, body }) => {
        const parsed = NotesSearchBody.safeParse(body);
        if (!parsed.success) return refuse(parsed.error);
        return { status: 200, body: await service.searchNotes(caller!.userId, { q: parsed.data.q, limit: parsed.data.limit ?? 30, offset: parsed.data.offset ?? 0 }) };
      },
    },
    {
      method: "GET",
      pattern: /^\/v1\/web\/memory\/conversations$/,
      template: "GET /v1/web/memory/conversations",
      access: "either",
      run: async ({ caller, req }) => {
        const { limit, offset } = page(req);
        return { status: 200, body: await service.listConversations(caller!.userId, { limit, offset }) };
      },
    },
    {
      method: "GET",
      pattern: new RegExp(`^/v1/web/memory/conversations/${ID}$`),
      template: "GET /v1/web/memory/conversations/:id",
      access: "either",
      run: async ({ caller, params }) => ({ status: 200, body: await service.getConversation(caller!.userId, params[0]!) }),
    },
    {
      method: "DELETE",
      pattern: new RegExp(`^/v1/web/memory/conversations/${ID}$`),
      template: "DELETE /v1/web/memory/conversations/:id",
      access: "either",
      run: async ({ caller, params }) => ({ status: 200, body: await service.deleteConversation(caller!.userId, params[0]!) }),
    },
    {
      method: "GET",
      pattern: /^\/v1\/web\/memory\/export$/,
      template: "GET /v1/web/memory/export",
      access: "either",
      run: async ({ caller, now }) => {
        const everything = await service.exportAll(caller!.userId);
        const bytes = Buffer.from(`${JSON.stringify({ exportedAt: now.toISOString(), ...everything }, null, 2)}\n`, "utf8");
        return { status: 200, file: { name: `doddy-memory-${now.toISOString().slice(0, 10)}.json`, mime: "application/json", bytes } };
      },
    },
    {
      method: "POST",
      pattern: /^\/v1\/web\/chat$/,
      template: "POST /v1/web/chat",
      access: "either",
      run: async ({ caller, body }) => ({ status: 200, body: await chat.answer(caller!.userId, body) }),
    },
  ];
}
