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
import type { SmsCaps } from "./config.js";
import { enqueue, IdempotencyConflict, SmsDailyLimit } from "./outbox.js";
import { estimateSmsSegments } from "./smsSegments.js";

/** Longest reply sent, in characters: a ceiling that holds whatever the encoding. The segment budget below is what binds. */
export const SMS_REPLY_MAX = 600;
/**
 * Longest reply sent, in SMS segments (research item #4): Twilio bills per segment, and a Polish text is UCS-2 (67
 * characters a segment once split), so 600 characters was up to 9 segments. 3 segments is about 200 Polish characters,
 * or about 450 characters of plain GSM-7 text. The Polish spelling is never changed to save segments.
 */
export const SMS_REPLY_MAX_SEGMENTS = 3;

export const SMS_CHAT_COPY = {
  // Both tails are plain ASCII on purpose, so a reply that was GSM-7 stays GSM-7. They only say where to ask next: the
  // question and the full answer are not stored (nothing from a text is kept), so the app has no copy to show.
  more: "... (zapytaj dalej w aplikacji Doddy)",
  moreAfterSentence: "(Zapytaj dalej w aplikacji Doddy.)",
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
  /** Texts queued per UTC day, per account and for the server (ADR-704). Default DEFAULT_ABUSE_LIMITS. */
  smsCaps?: SmsCaps;
  /** The most segments a reply may use. Default SMS_REPLY_MAX_SEGMENTS. */
  replySegments?: number;
}

const MESSAGE_SID = /^(SM|MM)[0-9a-fA-F]{32}$/;

export interface FitOptions {
  /** The most SMS segments the whole text (answer, tail and suffix) may use. Default SMS_REPLY_MAX_SEGMENTS. */
  segments?: number;
  /** The most characters (Unicode scalars). Default SMS_REPLY_MAX. */
  maxChars?: number;
  /** Fixed words kept after the answer, whatever is cut (for example the line saying a card is made in the app). */
  suffix?: string;
}

/**
 * Cuts a reply to the segment budget, never changing a letter of what stays: at the last sentence end in the second half,
 * else the last word end in the last 30%, else mid-word, and says where to ask for the rest. The text is measured in
 * segments with the encoding it really has (smsSegments.ts), so a reply without Polish letters may be longer than one
 * with them. The result, tail and suffix included, never exceeds the budget.
 */
export function fitSms(text: string, opts: FitOptions = {}): string {
  const segments = opts.segments ?? SMS_REPLY_MAX_SEGMENTS;
  const maxChars = opts.maxChars ?? SMS_REPLY_MAX;
  const suffix = opts.suffix ?? "";
  const chars = [...text.trim()];
  const fits = (s: string) => [...s].length <= maxChars && estimateSmsSegments(s).segments <= segments;
  const whole = chars.join("") + suffix;
  if (fits(whole)) return whole;
  // The largest head that still fits with the tail; adding characters never lowers the count, so this is a binary search.
  const head = (k: number) => chars.slice(0, k).join("");
  let lo = 0;
  let hi = chars.length;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (fits(head(mid).trimEnd() + " " + SMS_CHAT_COPY.more + suffix)) lo = mid; else hi = mid - 1;
  }
  const k = lo;
  const isSpace = (c: string | undefined) => c === undefined || /\s/.test(c);
  // A sentence end at or before k (the next character, in the whole text, is a space or the end).
  let sentence = -1;
  for (let i = k - 1; i >= 0; i--) {
    if ((chars[i] === "." || chars[i] === "!" || chars[i] === "?") && isSpace(chars[i + 1])) { sentence = i + 1; break; }
  }
  if (sentence > k * 0.5) {
    const out = head(sentence).trimEnd() + " " + SMS_CHAT_COPY.moreAfterSentence + suffix;
    if (fits(out)) return out;
  }
  const cut = head(k);
  const space = cut.search(/\s\S*$/);
  const base = space > cut.length * 0.7 && !isSpace(chars[k]) ? cut.slice(0, space) : cut;
  return base.trimEnd() + " " + SMS_CHAT_COPY.more + suffix;
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
  const send = async (text: string, idempotencyKey = key) => {
    try { await enqueue(db, accountId, ["sms"], text, new Date(), idempotencyKey, { cipher: deps.cipher, smsCaps: deps.smsCaps }); } catch (err) {
      if (err instanceof SmsDailyLimit) {
        // The day's cap on texts is reached (ADR-704): no reply goes out, and the webhook still answers normally.
        log("sms chat reply not queued; daily text cap reached", { accountId, scope: err.scope });
      } else if (!(err instanceof IdempotencyConflict)) {
        throw err;
      }
    }
  };
  // "Off" and "limit" are said once a (UTC) day, the day the cap counts in, not once per text:
  // an auto-reply or a flood of texts would otherwise get a paid text back for every one.
  const today = new Date().toISOString().slice(0, 10);

  const assistant = deps.assistant;
  const responder = assistant?.responder;
  if (!assistant || !assistant.settings.enabled || !responder) {
    await send(SMS_CHAT_COPY.off, `sms-chat-off:${today}`);
    log("sms chat off", { accountId });
    return "off";
  }

  const reservation = await reserve(db, accountId, {
    perAccount: assistant.settings.dailyPerAccount, perServer: assistant.settings.dailyPerServer,
    newAccountPool: assistant.settings.dailyForNewAccounts, newAccountHours: assistant.settings.newAccountHours,
  });
  if (reservation !== "ok") {
    await send(SMS_CHAT_COPY.limit, `sms-chat-limit:${today}`);
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
    const segments = deps.replySegments ?? SMS_REPLY_MAX_SEGMENTS;
    const reply = needsApp
      ? fitSms(outcome.answer, { segments, suffix: "\n\n" + SMS_CHAT_COPY.needsApp })
      : fitSms(outcome.answer, { segments });
    await send(reply);
    const est = estimateSmsSegments(reply);
    log("sms chat answered", {
      accountId, model: responder.model, card: needsApp, chars: [...reply].length, segments: est.segments, encoding: est.encoding,
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
