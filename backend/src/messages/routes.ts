import type { Route } from "../web/routes.js";
import { THREAD_MAX_BODY_BYTES } from "./contract.js";
import type { ThreadService } from "./service.js";

/**
 * `/v1/web/messages`: the iPhone sends its Messages thread and deletes the copy; the browser and the iPhone read it.
 * A browser can never put anything here or delete it: the thread lives on the iPhone, and deleting only the copy
 * from a browser would come back at the iPhone's next send. Every call is for the caller's own user id.
 */
export function threadRoutes(service: ThreadService): Route[] {
  return [
    {
      method: "PUT",
      pattern: /^\/v1\/web\/messages$/,
      template: "PUT /v1/web/messages",
      access: "phone",
      maxBodyBytes: THREAD_MAX_BODY_BYTES,
      run: async ({ caller, body }) => ({ status: 200, body: await service.replace(caller!.userId, body) }),
    },
    {
      method: "GET",
      pattern: /^\/v1\/web\/messages$/,
      template: "GET /v1/web/messages",
      access: "either",
      run: async ({ caller }) => ({ status: 200, body: await service.read(caller!.userId) }),
    },
    {
      method: "DELETE",
      pattern: /^\/v1\/web\/messages$/,
      template: "DELETE /v1/web/messages",
      access: "phone",
      run: async ({ caller }) => ({ status: 200, body: await service.deleteAll(caller!.userId) }),
    },
  ];
}
