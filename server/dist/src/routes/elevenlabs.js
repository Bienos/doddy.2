import { randomUUID } from "node:crypto";
import { z } from "zod";
import { findSession, MAX_PENDING_NOTES, openSession, PIN_LOCK_MINUTES, PIN_MAX_ATTEMPTS, sameSecret, variablesFor, } from "../calls.js";
import { verifyPin } from "../crypto.js";
import { inTransaction } from "../db.js";
import { searchMemories } from "../memorySearch.js";
import { canPush, enqueue } from "../outbox.js";
// Endpoints called by ElevenLabs during phone calls. All require the shared tool secret.
// Tool replies are always HTTP 200 with a `status` the agent's prompt knows how to say aloud;
// they never contain memories unless the caller proved the PIN on this call.
const startBody = z.object({
    caller_id: z.string().max(32).optional(),
    called_number: z.string().max(32).optional(),
    call_sid: z.string().max(64).optional(),
    conversation_id: z.string().max(128).optional(),
});
const pinBody = z.object({ pin: z.string().max(16) });
const searchBody = z.object({ query: z.string().min(1).max(300) });
const noteBody = z.object({ text: z.string().trim().min(1).max(1000) });
export const elevenLabsRoutes = (deps) => async (app) => {
    const { db } = deps;
    function authorized(req, reply) {
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
    async function session(req) {
        const header = req.headers["x-doddy-session"];
        return findSession(db, typeof header === "string" ? header : undefined);
    }
    // Conversation initiation webhook for inbound Twilio calls. Runs while the phone rings, so
    // it must answer quickly and always answer: a failure here would drop the call.
    app.post("/webhooks/elevenlabs/call-start", async (req, reply) => {
        if (!authorized(req, reply))
            return;
        const respond = (dynamic_variables) => reply.send({ type: "conversation_initiation_client_data", dynamic_variables });
        const body = startBody.safeParse(req.body);
        if (!body.success || !body.data.caller_id)
            return respond(variablesFor("unknown", "inbound"));
        try {
            const { rows } = await db.query(`SELECT p.account_id, s.inbound_enabled FROM phone_numbers p
         LEFT JOIN call_settings s ON s.account_id = p.account_id WHERE p.e164 = $1`, [body.data.caller_id]);
            const row = rows[0];
            if (!row)
                return respond(variablesFor("unknown", "inbound"));
            if (!row.inbound_enabled)
                return respond(variablesFor("calls_off", "inbound"));
            const callId = randomUUID();
            await db.query(`INSERT INTO calls (id, account_id, direction, status, conversation_id, call_sid)
         VALUES ($1, $2, 'inbound', 'started', $3, $4)`, [callId, row.account_id, body.data.conversation_id ?? null, body.data.call_sid ?? null]);
            return respond(await openSession(db, row.account_id, callId, "inbound"));
        }
        catch (err) {
            req.log.error({ err: { message: err.message } }, "call-start failed");
            return respond(variablesFor("unavailable", "inbound"));
        }
    });
    app.post("/webhooks/elevenlabs/tools/verify-pin", async (req, reply) => {
        if (!authorized(req, reply))
            return;
        const s = await session(req);
        if (!s)
            return { status: "not_recognised" };
        const body = pinBody.safeParse(req.body);
        if (!body.success)
            return { status: "wrong_pin", attemptsLeft: null };
        const pin = body.data.pin.replace(/\D/g, "");
        return inTransaction(db, async (c) => {
            const { rows } = await c.query(`SELECT pin_hash, pin_failed_attempts AS attempts, pin_locked_until > now() AS locked,
                ceil(extract(epoch FROM pin_locked_until - now()) / 60)::int AS minutes
         FROM call_settings WHERE account_id = $1 FOR UPDATE`, [s.accountId]);
            const st = rows[0];
            if (!st?.pin_hash)
                return { status: "no_pin_set" };
            if (st.locked)
                return { status: "locked", minutes: st.minutes };
            if (await verifyPin(pin, st.pin_hash)) {
                await c.query("UPDATE call_settings SET pin_failed_attempts = 0, pin_locked_until = NULL WHERE account_id = $1", [s.accountId]);
                await c.query("UPDATE call_sessions SET pin_verified_at = now() WHERE id = $1", [s.id]);
                return { status: "verified" };
            }
            const attempts = st.attempts + 1;
            const lock = attempts >= PIN_MAX_ATTEMPTS;
            await c.query(`UPDATE call_settings SET pin_failed_attempts = $2,
           pin_locked_until = CASE WHEN $3 THEN now() + make_interval(mins => $4) ELSE pin_locked_until END
         WHERE account_id = $1`, [s.accountId, lock ? 0 : attempts, lock, PIN_LOCK_MINUTES]);
            return lock ? { status: "locked", minutes: PIN_LOCK_MINUTES } : { status: "wrong_pin", attemptsLeft: PIN_MAX_ATTEMPTS - attempts };
        });
    });
    app.post("/webhooks/elevenlabs/tools/search-memories", async (req, reply) => {
        if (!authorized(req, reply))
            return;
        const s = await session(req);
        if (!s)
            return { status: "not_recognised" };
        if (!s.pinVerified)
            return { status: "pin_required" };
        const body = searchBody.safeParse(req.body);
        if (!body.success)
            return { status: "no_match" };
        const { rows: st } = await db.query("SELECT memory_copy_enabled_at IS NOT NULL AS on FROM call_settings WHERE account_id = $1", [s.accountId]);
        if (!st[0]?.on || !deps.cipher)
            return { status: "memory_off" };
        const cipher = deps.cipher;
        const { rows } = await db.query("SELECT memory_id, ciphertext, captured_at FROM memory_copies WHERE account_id = $1", [s.accountId]);
        const memories = rows.map((r) => ({
            id: r.memory_id,
            text: cipher.decrypt(r.ciphertext, `${s.accountId}:memory:${r.memory_id}`),
            capturedAt: r.captured_at,
        }));
        const hits = searchMemories(memories, body.data.query);
        if (hits.length === 0)
            return { status: "no_match" };
        return {
            status: "ok",
            results: hits.map((h) => ({ text: h.text, saved: h.capturedAt ? h.capturedAt.toISOString().slice(0, 10) : "date unknown" })),
        };
    });
    app.post("/webhooks/elevenlabs/tools/save-note", async (req, reply) => {
        if (!authorized(req, reply))
            return;
        const s = await session(req);
        if (!s)
            return { status: "not_recognised" };
        // A caller ID can be faked, so even notes need the PIN.
        if (!s.pinVerified)
            return { status: "pin_required" };
        if (!deps.cipher)
            return { status: "unavailable" };
        const body = noteBody.safeParse(req.body);
        if (!body.success)
            return { status: "empty" };
        const { rows } = await db.query("SELECT count(*)::int AS n FROM call_notes WHERE account_id = $1", [s.accountId]);
        if ((rows[0]?.n ?? 0) >= MAX_PENDING_NOTES)
            return { status: "inbox_full" };
        const id = randomUUID();
        const { rows: call } = await db.query("SELECT c.conversation_id FROM call_sessions s LEFT JOIN calls c ON c.id = s.call_id WHERE s.id = $1", [s.id]);
        await db.query(`INSERT INTO call_notes (id, account_id, key_version, ciphertext, conversation_id) VALUES ($1, $2, $3, $4, $5)`, [id, s.accountId, deps.cipher.keyVersion, deps.cipher.encrypt(body.data.text, `${s.accountId}:note:${id}`),
            call[0]?.conversation_id ?? null]);
        // The notification never contains the note itself.
        if (deps.push && await canPush(db, s.accountId)) {
            await enqueue(db, s.accountId, ["push"], "Doddy took a note on your call. Open Doddy to confirm it.", new Date(), `call-note:${id}`);
        }
        return { status: "saved_for_confirmation" };
    });
};
//# sourceMappingURL=elevenlabs.js.map