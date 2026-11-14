// Fakes for the voice conversation tests: an in-memory store with the same contract as the Redis one
// (`createVoiceAuthStore`, checked against both in conversations.test.js) and a fake ElevenLabs.
// Not a test itself: the test runner only takes *.test.js.
import assert from "node:assert/strict";
import { VoiceAuthStoreUnavailable } from "../src/voice-auth.js";

/**
 * The conversation part of the store, in memory. `records` maps a record key to its ids (oldest first by score),
 * `owed` maps a record key to what is still owed. `failing` makes every call throw, as an unreachable store does.
 */
export function fakeConversationStore() {
  const records = new Map();
  const owed = new Map();
  const state = { failing: false, failRecording: false };
  const guard = (recording = false) => {
    if (state.failing || (recording && state.failRecording)) throw new VoiceAuthStoreUnavailable();
  };
  const entries = (recordKey) => [...(records.get(recordKey) ?? new Map()).entries()]
    .sort((a, b) => a[1] - b[1] || (a[0] < b[0] ? -1 : 1));
  return {
    records, owed, state,
    async recordConversation(recordKey, id, nowMs, maxEntries) {
      guard(true);
      const set = records.get(recordKey) ?? new Map();
      set.set(id, nowMs);
      records.set(recordKey, set);
      const extra = set.size - maxEntries;
      if (extra > 0) for (const [oldest] of entries(recordKey).slice(0, extra)) set.delete(oldest);
      return Math.max(0, extra);
    },
    async listConversations(recordKey, limit) { guard(); return entries(recordKey).slice(0, limit).map(([id]) => id); },
    async countConversations(recordKey) { guard(); return records.get(recordKey)?.size ?? 0; },
    async addConversations(recordKey, ids, nowMs) {
      guard();
      const set = records.get(recordKey) ?? new Map();
      let added = 0;
      for (const id of ids) if (!set.has(id)) { set.set(id, nowMs); added += 1; }
      if (set.size > 0) records.set(recordKey, set);
      return added;
    },
    async removeConversations(recordKey, ids) {
      guard();
      const set = records.get(recordKey);
      let removed = 0;
      for (const id of ids) if (set?.delete(id)) removed += 1;
      if (set?.size === 0) records.delete(recordKey);
      return removed;
    },
    async markOwed(recordKey, record, nowMs) { guard(); owed.set(recordKey, JSON.stringify({ ...record, since: nowMs })); },
    async clearOwed(recordKey) { guard(); owed.delete(recordKey); },
    async listOwed() {
      guard();
      return [...owed.entries()].map(([recordKey, text]) => ({ recordKey, record: JSON.parse(text) }));
    },
  };
}

export const MAIN_AGENT = "agent_test";
export const TRANSLATOR_AGENT = "agent_8901m787fgppedy9kkvg7memny34";
export const OTHER_AGENT = "agent_not_doddys";

/**
 * A fake ElevenLabs for what the voice server asks of it: the conversation token, the list (filtered by agent and
 * user id, in pages), one conversation and its deletion. `conversations` are `{ id, agent, user }`.
 * Knobs: `deleteFails` / `readBackStillThere` (ids), `readBackStatus` (id → what reading it back answers), `listFails`, `ignoreAgentFilter` (the list answers with other
 * agents' conversations too), `omitConversationId` (the token answer has no id), `pageSize`.
 */
export function fakeElevenLabs({ conversations = [], pageSize = 100, apiKey = "elevenlabs-server-secret" } = {}) {
  const live = new Map(conversations.map((c) => [c.id, { ...c }]));
  const calls = [];
  const knobs = {
    deleteFails: new Set(), readBackStillThere: new Set(), readBackStatus: new Map(), listFails: false, ignoreAgentFilter: false,
    omitConversationId: false, unreachable: false, pageSize, onCall: null,
  };
  let issued = 0;
  const fetch = async (url, init = {}) => {
    const u = new URL(String(url));
    const method = init.method ?? "GET";
    calls.push({ method, path: u.pathname, search: Object.fromEntries(u.searchParams) });
    assert.equal(init.headers?.["xi-api-key"], apiKey, "every call carries the server's key, and only in the header");
    assert.ok(init.signal, "every call has a timeout");
    knobs.onCall?.();
    if (knobs.unreachable) throw new TypeError("network failed");
    if (u.pathname === "/v1/convai/conversation/token") {
      issued += 1;
      const id = `conv_issued_${issued}`;
      live.set(id, { id, agent: u.searchParams.get("agent_id"), user: null });
      return Response.json(knobs.omitConversationId ? { token: `token-${issued}` } : { token: `token-${issued}`, conversation_id: id });
    }
    if (u.pathname === "/v1/convai/conversations" && method === "GET") {
      if (knobs.listFails) return new Response("{}", { status: 500 });
      const agent = u.searchParams.get("agent_id");
      const user = u.searchParams.get("user_id");
      const all = [...live.values()]
        .filter((c) => (knobs.ignoreAgentFilter || !agent || c.agent === agent) && c.user === user)
        .sort((a, b) => (a.id < b.id ? -1 : 1));
      const start = Number(u.searchParams.get("cursor") ?? 0);
      const size = Math.min(Number(u.searchParams.get("page_size") ?? 30), knobs.pageSize);
      const page = all.slice(start, start + size);
      const more = start + size < all.length;
      return Response.json({
        conversations: page.map((c) => ({ agent_id: c.agent, conversation_id: c.id, status: "done" })),
        has_more: more, next_cursor: more ? String(start + size) : null,
      });
    }
    const match = /^\/v1\/convai\/conversations\/([^/]+)$/.exec(u.pathname);
    if (match) {
      const id = decodeURIComponent(match[1]);
      if (method === "DELETE") {
        if (knobs.deleteFails.has(id)) return new Response("{}", { status: 500 });
        return live.delete(id) ? Response.json({}) : new Response("{}", { status: 404 });
      }
      if (method === "GET") {
        if (knobs.readBackStatus.has(id)) return new Response("{}", { status: knobs.readBackStatus.get(id) });
        return live.has(id) || knobs.readBackStillThere.has(id) ? Response.json({ conversation_id: id }) : new Response("{}", { status: 404 });
      }
    }
    return new Response("{}", { status: 400 });
  };
  return {
    fetch, calls, knobs, live,
    /** What the app does after the token: starts the conversation with the user id it was given. */
    start(conversationId, user) { const c = live.get(conversationId); assert.ok(c, "a conversation was issued"); c.user = user; },
    add(conversation) { live.set(conversation.id, { ...conversation }); },
    has(id) { return live.has(id); },
  };
}
