import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import type { Deps } from "../app.js";
import { findSession, PIN_MAX_ATTEMPTS, pinLockMinutes, sameSecret, type Session } from "../calls.js";
import { verifyPin } from "../crypto.js";
import { inTransaction } from "../db.js";
import { memoryCopyOn, quotedMemory, saveNote, searchMemoryCopy } from "../inbox.js";
import { canPush, enqueue } from "../outbox.js";

// The phone agent's tools, called by ElevenLabs during phone calls. All require the shared tool
// secret. (Calls themselves start at routes/twilioVoice.ts since ADR-490.)
// Tool replies are always HTTP 200 with a `status` the agent's prompt knows how to say aloud;
// they never contain memories unless the caller proved the PIN on this call.

const pinBody = z.object({ pin: z.string().max(16) });
const searchBody = z.object({ query: z.string().min(1).max(300) });
const noteBody = z.object({ text: z.string().trim().min(1).max(1000) });

export const elevenLabsRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;

  function authorized(req: FastifyRequest, reply: FastifyReply): boolean {
    if (!deps.toolSecret) {
      void reply.code(503).send({ error: "not_configured" });
      return false;
    }
    const header = req.headers["x-doddy-tool-secret"];
    if (!sameSecret(deps.toolSecret, typeof header === "string" ? header : undefined)) {
      void reply.code(401).send({ error: "unauthorized" });
      return false;
    }
    return true;
  }

  async function session(req: FastifyRequest): Promise<Session | undefined> {
    const header = req.headers["x-doddy-session"];
    return findSession(db, typeof header === "string" ? header : undefined);
  }

  app.post("/webhooks/elevenlabs/tools/verify-pin", async (req, reply) => {
    if (!authorized(req, reply)) return;
    const s = await session(req);
    if (!s) return { status: "not_recognised" };
    const body = pinBody.safeParse(req.body);
    if (!body.success) return { status: "wrong_pin", attemptsLeft: null };
    const pin = body.data.pin.replace(/\D/g, "");

    return inTransaction(db, async (c) => {
      const { rows } = await c.query<{ pin_hash: string | null; attempts: number; locks: number; locked: boolean; minutes: number | null }>(
        `SELECT pin_hash, pin_failed_attempts AS attempts, pin_lock_count AS locks, pin_locked_until > now() AS locked,
                ceil(extract(epoch FROM pin_locked_until - now()) / 60)::int AS minutes
         FROM call_settings WHERE account_id = $1 FOR UPDATE`, [s.accountId]);
      const st = rows[0];
      if (!st?.pin_hash) return { status: "no_pin_set" };
      if (st.locked) return { status: "locked", minutes: st.minutes };
      if (await verifyPin(pin, st.pin_hash)) {
        await c.query("UPDATE call_settings SET pin_failed_attempts = 0, pin_lock_count = 0, pin_locked_until = NULL WHERE account_id = $1", [s.accountId]);
        await c.query("UPDATE call_sessions SET pin_verified_at = now() WHERE id = $1", [s.id]);
        return { status: "verified" };
      }
      const attempts = st.attempts + 1;
      const lock = attempts >= PIN_MAX_ATTEMPTS;
      const minutes = pinLockMinutes(st.locks);
      await c.query(
        `UPDATE call_settings SET pin_failed_attempts = $2,
           pin_lock_count = pin_lock_count + CASE WHEN $3 THEN 1 ELSE 0 END,
           pin_locked_until = CASE WHEN $3 THEN now() + make_interval(mins => $4) ELSE pin_locked_until END
         WHERE account_id = $1`,
        [s.accountId, lock ? 0 : attempts, lock, minutes]);
      if (lock && deps.push && await canPush(c, s.accountId)) {
        // Tell the owner: someone may be guessing their PIN. No caller number in the text.
        await enqueue(c, s.accountId, ["push"],
          `Someone entered a wrong Doddy PIN ${PIN_MAX_ATTEMPTS} times on a phone call. PIN entry is locked for ${minutes >= 60 ? `${minutes / 60} h` : `${minutes} min`}. If it wasn't you, change your PIN in Doddy.`,
          new Date(), `pin-lock:${s.accountId}:${st.locks + 1}:${Date.now()}`, { cipher: deps.cipher });
      }
      return lock ? { status: "locked", minutes } : { status: "wrong_pin", attemptsLeft: PIN_MAX_ATTEMPTS - attempts };
    });
  });

  app.post("/webhooks/elevenlabs/tools/search-memories", async (req, reply) => {
    if (!authorized(req, reply)) return;
    const s = await session(req);
    if (!s) return { status: "not_recognised" };
    if (!s.pinVerified) return { status: "pin_required" };
    const body = searchBody.safeParse(req.body);
    if (!body.success) return { status: "no_match" };
    if (!deps.cipher || !await memoryCopyOn(db, s.accountId)) return { status: "memory_off" };
    const hits = await searchMemoryCopy(db, deps.cipher, s.accountId, body.data.query);
    if (hits.length === 0) return { status: "no_match" };
    return { status: "ok", results: hits.map(quotedMemory) };
  });

  app.post("/webhooks/elevenlabs/tools/save-note", async (req, reply) => {
    if (!authorized(req, reply)) return;
    const s = await session(req);
    if (!s) return { status: "not_recognised" };
    // A caller ID can be faked, so even notes need the PIN.
    if (!s.pinVerified) return { status: "pin_required" };
    if (!deps.cipher) return { status: "unavailable" };
    const body = noteBody.safeParse(req.body);
    if (!body.success) return { status: "empty" };
    const { rows: call } = await db.query<{ conversation_id: string | null }>(
      "SELECT c.conversation_id FROM call_sessions s LEFT JOIN calls c ON c.id = s.call_id WHERE s.id = $1", [s.id]);
    const id = await saveNote(db, deps.cipher, s.accountId, body.data.text, "call", call[0]?.conversation_id ?? null);
    if (!id) return { status: "inbox_full" };
    // The notification never contains the note itself.
    if (deps.push && await canPush(db, s.accountId)) {
      await enqueue(db, s.accountId, ["push"], "Doddy took a note on your call. Open Doddy to confirm it.", new Date(), `call-note:${id}`, { cipher: deps.cipher });
    }
    return { status: "saved_for_confirmation" };
  });
};
