// Texting Doddy (docs/implementation/SMS_CHAT.md): a text from a verified number whose owner turned
// "Text with Doddy" on in the app gets one reply by text. Same Claude, prompt and caps as Messages
// (ADR-586): no tools, so a text can't search, send, buy or change anything; no notes, so nothing
// from memory leaves for a phone network. A card Claude would offer (a file, a plan) is not made: the
// reply says it needs the app. Unknown numbers get no reply (no cost, no confirmation the number is
// Doddy's). Nothing the person wrote is stored or logged; the reply is queued encrypted and erased
// once sent, like every other text. One reply per Twilio message id, so a retried webhook never
// answers or counts twice.
import { randomUUID } from "node:crypto";
import type { Db } from "./db.js";
import type { AssistantDeps } from "./assistant/deps.js";
import { LIMITS } from "./assistant/request.js";
import { addTokens, reserve } from "./assistant/usage.js";
import type { TextCipher } from "./crypto.js";
import { enqueue, IdempotencyConflict } from "./outbox.js";

/** Longest reply sent, in characters. Polish letters make a text UCS-2 (67 per part), so 600 is at most 9 parts. */
export const SMS_REPLY_MAX = 600;

export const SMS_CHAT_COPY = {
  more: "… (dalej w aplikacji Doddy)",
  needsApp: "Tę rzecz przygotuję w aplikacji Doddy, w Wiadomościach.",
  limit: "Limit pytań do Doddy'ego na dziś się skończył. Spróbuj jutro.",
  unavailable: "Doddy nie może teraz odpowiedzieć. Spróbuj za chwilę albo napisz w aplikacji.",
  off: "Doddy nie odpowiada teraz na SMS-y. Napisz do niego w aplikacji.",
} as const;

export type SmsChatOutcome = "ignored" | "duplicate" | "answered" | "limit" | "unavailable" | "off";

export interface SmsChatDeps {
  db: Db;
  cipher?: TextCipher;
  assistant?: AssistantDeps;
  log: (msg: string, extra?: object) => void;
}

const MESSAGE_SID = /^(SM|MM)[0-9a-fA-F]{32}$/;

/** Cuts a reply to what one text should carry, on a word boundary when one is near, and says the rest is in the app. */
export function fitSms(text: string, max = SMS_REPLY_MAX): string {
  const chars = [...text.trim()];
  if (chars.length <= max) return chars.join("");
  const room = max - [...SMS_CHAT_COPY.more].length;
  const cut = chars.slice(0, room).join("");
  const space = cut.lastIndexOf(" ");
  return (space > room * 0.7 ? cut.slice(0, space) : cut).trimEnd() + SMS_CHAT_COPY.more;
}

/** Answers one inbound text if its sender turned texting on. Never throws for an expected case. */
export async function handleSmsChat(deps: SmsChatDeps, from: string, body: string, messageSid: string): Promise<SmsChatOutcome> {
  const { db, log } = deps;
  if (!MESSAGE_SID.test(messageSid) || /^\s*$/.test(body)) return "ignored";

  const { rows } = await db.query<{ account_id: string }>(
    `SELECT account_id FROM phone_numbers
     WHERE e164 = $1 AND sms_consent_at IS NOT NULL AND sms_opted_out_at IS NULL AND sms_chat_consent_at IS NOT NULL`,
    [from]);
  const accountId = rows[0]?.account_id;
  if (!accountId) return "ignored";
  // The reply is queued encrypted only; without the key there is no SMS chat (nothing in plain text).
  if (!deps.cipher) return "ignored";

  const key = `sms-chat:${messageSid}`;
  const seen = await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1 AND channel = 'sms' AND idempotency_key = $2",
    [accountId, key]);
  if ((seen.rowCount ?? 0) > 0) return "duplicate";
  // Two deliveries of the same webhook at once can both get here; the key lets only the first reply out.
  const send = async (text: string) => {
    try { await enqueue(db, accountId, ["sms"], text, new Date(), key, { cipher: deps.cipher }); } catch (err) {
      if (!(err instanceof IdempotencyConflict)) throw err;
    }
  };

  const assistant = deps.assistant;
  const responder = assistant?.responder;
  if (!assistant || !assistant.settings.enabled || !responder) {
    await send(SMS_CHAT_COPY.off);
    log("sms chat off", { accountId });
    return "off";
  }

  const reservation = await reserve(db, accountId, {
    perAccount: assistant.settings.dailyPerAccount, perServer: assistant.settings.dailyPerServer,
  });
  if (reservation !== "ok") {
    await send(SMS_CHAT_COPY.limit);
    log("sms chat daily cap reached", { accountId, cap: reservation });
    return "limit";
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), assistant.timeoutMs ?? 45_000);
  try {
    const outcome = await responder.answer({
      schemaVersion: 1, requestId: randomUUID(), sessionId: randomUUID(), locale: "pl",
      userText: [...body.trim()].slice(0, LIMITS.userText).join(""), turns: [], memories: [],
    }, controller.signal);
    if (outcome.usage) await addTokens(db, accountId, outcome.usage).catch(() => {});
    if (outcome.kind !== "ok") {
      await send(SMS_CHAT_COPY.unavailable);
      log("sms chat gave no answer", { accountId, model: responder.model, outcome: outcome.kind });
      return "unavailable";
    }
    const needsApp = outcome.proposal !== undefined || outcome.plan !== undefined;
    const reply = needsApp
      ? fitSms(outcome.answer, SMS_REPLY_MAX - [...SMS_CHAT_COPY.needsApp].length - 2) + "\n\n" + SMS_CHAT_COPY.needsApp
      : fitSms(outcome.answer);
    await send(reply);
    log("sms chat answered", {
      accountId, model: responder.model, card: needsApp, chars: [...reply].length,
      inputTokens: outcome.usage.inputTokens, outputTokens: outcome.usage.outputTokens,
    });
    return "answered";
  } catch (err) {
    await send(SMS_CHAT_COPY.unavailable);
    log("sms chat provider error", { accountId, timedOut: controller.signal.aborted, kind: String((err as { name?: unknown }).name) });
    return "unavailable";
  } finally {
    clearTimeout(timer);
  }
}
