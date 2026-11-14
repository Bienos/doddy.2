import type { Db } from "./db.js";
import { inTransaction } from "./db.js";
import type { TextCipher } from "./crypto.js";
import { returnServerSlot, takeServerSlot } from "./serverUsage.js";
import { caseKeys, destinationHash } from "./taskCalls/payload.js";

// Call-backs (decision 2026-11-09-call-backs-and-contact-calls, owner; limits in 2026-11-12-call-back-limits): someone
// Doddy called on a user's behalf who calls Doddy's number back is put through to that user's verified number. Doddy's
// number is the caller ID the user sees, so the caller never learns the user's number. Nothing is recorded. Only numbers
// Doddy dialled for a user have a route; every other stranger still hears the fixed line.
//
// A route is one number and one account, and it lasts `callbackRouteDays` (7) after Doddy last dialled that number for
// that account. A call is put through only when exactly one account has a fresh route to the caller's number (two users
// who called the same place can't tell which of them it wants, so neither gets it), that account's user has calls on,
// Twilio's caller-ID attestation (if it sends one) is A-level, and the route's and the server's caps for the day allow
// it. Otherwise the caller hears one short line and the call ends. The forwarded call lasts at most 15 minutes.

type Q = Pick<Db, "query">;

/** The longest a forwarded call-back may last (Twilio `<Dial timeLimit>`, seconds). */
export const CALLBACK_MAX_SECS = 15 * 60;

/**
 * Written in the same transaction that claims a task call for dialling, so a call placed always leaves its route. Every
 * account that dialled the number gets its own row, calls on or off, so a call-back can tell when it is ambiguous; only
 * a user with calls on is ever put through. A newer dial renews the account's route; an older one never moves it back.
 */
export async function rememberCallbackRoute(c: Q, destination: Buffer, accountId: string, at: Date): Promise<void> {
  await c.query(
    `INSERT INTO callback_routes (destination_hash, account_id, last_dialed_at) VALUES ($1, $2, $3)
     ON CONFLICT (destination_hash, account_id) DO UPDATE SET last_dialed_at = EXCLUDED.last_dialed_at
     WHERE callback_routes.last_dialed_at <= EXCLUDED.last_dialed_at`,
    [destination, accountId, at]);
}

/** Routes past their days go; run by the worker's hourly tidy. Expired ones are never used before that either. */
export async function pruneCallbackRoutes(db: Q, days: number, now: Date = new Date()): Promise<number> {
  const r = await db.query(
    "DELETE FROM callback_routes WHERE last_dialed_at <= $1::timestamptz - make_interval(days => $2)", [now, days]);
  return r.rowCount ?? 0;
}

/**
 * Twilio's `StirVerstat` on an incoming call (https://www.twilio.com/docs/voice/trusted-calling-with-shakenstir, read
 * 12 Nov 2026): present only when the call carries a SHAKEN PASSporT, so calls from Polish numbers normally have none.
 * Values: `TN-Validation-Passed-A|B|C`, `TN-Validation-Failed-A|B|C`, each also with `-Passthrough` or `-Diverted`, plus
 * `No-TN-Validation` and `TN-Validation-Failed`. A-level means the caller's provider vouches that the caller may use
 * that number. With one sent, only A (signed by the caller's own provider, or passed through unchanged) is put through:
 * B and C don't vouch for the number, failed ones are suspect, and a diverted call's attestation is the diverting
 * provider's. None sent is allowed, since that is the normal case outside the US and Canada.
 */
export function attestationAllowsForward(stirVerstat: string | undefined): boolean {
  if (!stirVerstat) return true;
  return stirVerstat === "TN-Validation-Passed-A" || stirVerstat === "TN-Validation-Passed-A-Passthrough";
}

export interface CallbackLimits {
  routeDays: number;
  forwardsPerRouteDay: number;
  /** The server's daily cap of calls put through (shared with calls to the phone agent). */
  serverPerDay: number;
}

export type CallbackRefusal = "shared_number" | "calls_off" | "not_attested" | "route_limit" | "server_limit";
export type CallbackDecision =
  | { kind: "none" }
  | { kind: "refused"; reason: CallbackRefusal }
  | { kind: "forward"; target: string };

/**
 * Whether a call from `caller` is put through, and to which verified number. The caller is matched by the keyed hash
 * only. `none`: no fresh route (the caller hears the stranger's line). A user whose number is gone, or is the caller's
 * own, has calls off, or is one of several with a fresh route is never put through.
 */
export async function callbackDecision(
  db: Db, cipher: TextCipher, caller: string, stirVerstat: string | undefined, limits: CallbackLimits, now: Date,
): Promise<CallbackDecision> {
  if (!/^\+[1-9][0-9]{6,14}$/.test(caller)) return { kind: "none" };
  const hash = destinationHash(caseKeys(cipher), caller);
  const { rows } = await db.query<{ account_id: string; e164: string | null; calls_on: boolean }>(
    `SELECT r.account_id, p.e164, coalesce(s.inbound_enabled, false) AS calls_on
     FROM callback_routes r
     LEFT JOIN phone_numbers p ON p.account_id = r.account_id
     LEFT JOIN call_settings s ON s.account_id = r.account_id
     WHERE r.destination_hash = $1 AND r.last_dialed_at > $2::timestamptz - make_interval(days => $3)
     LIMIT 2`, [hash, now, limits.routeDays]);
  if (rows.length === 0) return { kind: "none" };
  if (rows.length > 1) return { kind: "refused", reason: "shared_number" };
  const route = rows[0]!;
  if (!route.e164 || route.e164 === caller) return { kind: "none" };
  if (!route.calls_on) return { kind: "refused", reason: "calls_off" };
  if (!attestationAllowsForward(stirVerstat)) return { kind: "refused", reason: "not_attested" };

  // The server's slot first, then the route's: a route over its day gives the slot back, and a full server leaves the
  // route's count as it was. One transaction, so parallel calls can't both take the last one.
  const day = now.toISOString().slice(0, 10);
  const reason = await inTransaction(db, async (c): Promise<CallbackRefusal | undefined> => {
    if (!(await takeServerSlot(c, "inbound_calls", limits.serverPerDay, day))) return "server_limit";
    const taken = await c.query(
      `UPDATE callback_routes SET forwards = CASE WHEN forwards_day = $3::date THEN forwards + 1 ELSE 1 END, forwards_day = $3::date
       WHERE destination_hash = $1 AND account_id = $2 AND (forwards_day IS DISTINCT FROM $3::date OR forwards < $4)`,
      [hash, route.account_id, day, limits.forwardsPerRouteDay]);
    if ((taken.rowCount ?? 0) === 0) {
      await returnServerSlot(c, "inbound_calls", day);
      return "route_limit";
    }
    return undefined;
  });
  return reason ? { kind: "refused", reason } : { kind: "forward", target: route.e164 };
}

const escapeXml = (s: string) => s.replace(/[<>&"']/g, (ch) => `&#${ch.charCodeAt(0)};`);

/** What the caller hears: Doddy says it's an AI and that it is connecting them, then the user's phone rings. */
export function forwardTwiml(target: string, callerId: string, doneUrl: string): string {
  return '<?xml version="1.0" encoding="UTF-8"?><Response>'
    + '<Say language="pl-PL" voice="Polly.Ola-Neural">Tu Doddy, wirtualny asystent. Łączę z osobą, w której imieniu dzwonił Doddy.</Say>'
    + '<Say language="en-US" voice="Polly.Joanna">This is Doddy, a virtual assistant. Connecting you to the person Doddy called for.</Say>'
    + `<Dial callerId="${escapeXml(callerId)}" timeout="25" timeLimit="${CALLBACK_MAX_SECS}" record="do-not-record" action="${escapeXml(doneUrl)}">`
    + `<Number>${escapeXml(target)}</Number></Dial></Response>`;
}

/** After the dial: a call that wasn't answered tells the caller so and ends; an answered one just ends. */
export function forwardDoneTwiml(dialStatus: string): string {
  if (dialStatus === "completed" || dialStatus === "answered") return '<?xml version="1.0" encoding="UTF-8"?><Response><Hangup/></Response>';
  return '<?xml version="1.0" encoding="UTF-8"?><Response>'
    + '<Say language="pl-PL" voice="Polly.Ola-Neural">Nie udało się połączyć. Ta osoba zobaczy, że dzwoniono. Do usłyszenia.</Say>'
    + '<Say language="en-US" voice="Polly.Joanna">The call couldn\'t be connected. They will see that you called. Goodbye.</Say>'
    + "<Hangup/></Response>";
}
