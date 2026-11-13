import type { Db } from "./db.js";
import type { TextCipher } from "./crypto.js";
import { caseKeys, destinationHash } from "./taskCalls/payload.js";

// Call-backs (decision 2026-11-09-call-backs-and-contact-calls, owner): someone Doddy called on a user's behalf who
// calls Doddy's number back is put through to that user's verified number. Doddy's number is the caller ID the user
// sees, so the caller never learns the user's number. Nothing is recorded. Only numbers Doddy dialled for a user
// have a route; every other stranger still hears the fixed line.

type Q = Pick<Db, "query">;

/** Written in the same transaction that claims a task call for dialling, so a call placed always leaves its route. */
export async function rememberCallbackRoute(c: Q, destination: Buffer, accountId: string, at: Date): Promise<void> {
  await c.query(
    `INSERT INTO callback_routes (destination_hash, account_id, last_dialed_at) VALUES ($1, $2, $3)
     ON CONFLICT (destination_hash) DO UPDATE SET account_id = EXCLUDED.account_id, last_dialed_at = EXCLUDED.last_dialed_at
     WHERE callback_routes.last_dialed_at <= EXCLUDED.last_dialed_at`,
    [destination, accountId, at]);
}

/**
 * The verified number of the user Doddy last called this caller for, or undefined. The caller is matched by the
 * keyed hash only. A user whose number is gone, or whose number is the caller's own, gets no forwarded call.
 */
export async function callbackTarget(db: Q, cipher: TextCipher, caller: string): Promise<string | undefined> {
  if (!/^\+[1-9][0-9]{6,14}$/.test(caller)) return undefined;
  const { rows: [row] } = await db.query<{ e164: string }>(
    `SELECT p.e164 FROM callback_routes r JOIN phone_numbers p ON p.account_id = r.account_id
     WHERE r.destination_hash = $1`, [destinationHash(caseKeys(cipher), caller)]);
  if (!row || row.e164 === caller) return undefined;
  return row.e164;
}

const escapeXml = (s: string) => s.replace(/[<>&"']/g, (ch) => `&#${ch.charCodeAt(0)};`);

/** What the caller hears: Doddy says it's an AI and that it is connecting them, then the user's phone rings. */
export function forwardTwiml(target: string, callerId: string, doneUrl: string): string {
  return '<?xml version="1.0" encoding="UTF-8"?><Response>'
    + '<Say language="pl-PL" voice="Polly.Ola-Neural">Tu Doddy, wirtualny asystent. Łączę z osobą, w której imieniu dzwonił Doddy.</Say>'
    + '<Say language="en-US" voice="Polly.Joanna">This is Doddy, a virtual assistant. Connecting you to the person Doddy called for.</Say>'
    + `<Dial callerId="${escapeXml(callerId)}" timeout="25" record="do-not-record" action="${escapeXml(doneUrl)}">`
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
