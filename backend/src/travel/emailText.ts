/**
 * Travel, stage 1 (decision 2026-11-11-travel-agent-plan, docs/implementation/TRAVEL.md section 3.10):
 * turn one booking email into the plain text that is read for the booking, with links and secrets gone.
 *
 * Why this exists, from real confirmation emails read on 11 Nov 2026 (the owner's own, used for layout only):
 *  - a Ryanair confirmation is 88 kB of HTML around 4 kB of text; a Wizz Air notice through Gotogate is
 *    markdown-like tables full of 600-character tracking links;
 *  - a Booking.com confirmation carries the booking's PIN ("Please keep your PIN confidential as it can be
 *    used to modify or cancel your booking") and card endings ("•••• 9717", "z końcówką: 4701").
 *
 * So, before anything reads the text: HTML and tables become lines, every link goes (a link in an email is
 * never followed, and drops the main place an instruction could hide), and PINs, card numbers and security
 * codes are replaced by "[removed]". Nothing here calls out; it is pure and tested.
 */

/** The longest text kept for reading. A confirmation's useful part is a few kB; the rest is advertising. */
export const MAX_TRAVEL_TEXT_CHARS = 12_000;

const NAMED_ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", euro: "€", pound: "£", ndash: "–", mdash: "—", hellip: "…",
};

function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, code: string) => {
    if (code.startsWith("#x") || code.startsWith("#X")) return safeCodePoint(parseInt(code.slice(2), 16), whole);
    if (code.startsWith("#")) return safeCodePoint(parseInt(code.slice(1), 10), whole);
    return NAMED_ENTITIES[code.toLowerCase()] ?? whole;
  });
}

function safeCodePoint(n: number, fallback: string): string {
  return Number.isInteger(n) && n > 0 && n <= 0x10ffff ? String.fromCodePoint(n) : fallback;
}

const looksLikeHtml = (s: string) => /<(html|body|table|div|td|p|br|span)\b/i.test(s);

/** HTML, markdown links and tables to plain lines, with no address of any kind left in them. */
export function emailToText(body: string): string {
  let s = body.replace(/\r\n?/g, "\n");
  if (looksLikeHtml(s)) {
    s = s
      .replace(/<!--[\s\S]*?-->/g, " ")
      .replace(/<(style|script|head|title)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, " ")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/(p|div|tr|td|th|li|h[1-6]|table|section)\s*>/gi, "\n")
      .replace(/<[^>]*>/g, " ");
  }
  s = decodeEntities(s);
  s = s
    // [text](address) and [](address): keep the words, drop the address.
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\bhttps?:\/\/[^\s<>"')\]]+/gi, " ")
    .replace(/\bwww\.[^\s<>"')\]]+/gi, " ")
    .replace(/\bmailto:[^\s<>"')\]]+/gi, " ")
    // Markdown tables: cell bars become spaces, separator rows go.
    .replace(/^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$/gm, " ")
    .replace(/\|/g, " ")
    .replace(/[   \t]+/g, " ")
    .replace(/[ ]{2,}/g, " ");
  return s
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join("\n");
}

const REMOVED = "[removed]";

/**
 * PINs, card numbers and security codes go before the text is read or kept anywhere. A pattern that matches
 * too much only costs a word; one that misses leaks a secret, so these lean wide.
 */
export function redactSecrets(text: string): { text: string; removed: number } {
  let removed = 0;
  const swap = (re: RegExp, keep: (m: string, label: string) => string) => {
    text = text.replace(re, (m: string, label: unknown) => {
      removed++;
      return keep(m, typeof label === "string" ? label : "");
    });
  };
  // "PIN: 4928", "PIN code: 5741", "kod PIN 1234", "PIN 1234 (Confidential)"
  swap(/\b((?:kod\s+)?PIN(?:\s*code)?\s*[:#]?\s*)\d{3,8}\b/gi, (_m, label) => `${label}${REMOVED}`);
  // Card numbers written in full or in groups (13–19 digits).
  swap(/\b(?:\d[ -]?){12,18}\d\b/g, () => REMOVED);
  // "•••• 9717", "**** 9717", "xxxx 9717", "XXXX-XXXX-XXXX-9717"
  swap(/(?:[•*xX]{2,}[ -]?){1,4}\d{4}\b/g, () => `•••• ${REMOVED}`);
  // "z końcówką: 4701", "ending in 4701", "ending with 4701", "kończącej się na 4701" (the number may be on the next line)
  swap(/((?:końcówk\p{L}*|kończąc\p{L}*\s+się\s+na|\bending(?:\s+(?:in|with))?|\blast\s+(?:4|four)\s+digits)\s*:?\s*)(\d{4})(?!\d)/giu, (_m, label) => `${label}${REMOVED}`);
  // "CVV 123", "CVC: 123", "security code 123"
  swap(/\b((?:CVV2?|CVC2?|security\s+code)\s*:?\s*)\d{3,4}\b/gi, (_m, label) => `${label}${REMOVED}`);
  return { text, removed };
}

/** The text that is read for a booking: plain, linkless, without secrets, at most MAX_TRAVEL_TEXT_CHARS long. */
export function travelReadableText(body: string): { text: string; removed: number; truncated: boolean } {
  const plain = emailToText(body);
  const { text, removed } = redactSecrets(plain);
  const truncated = text.length > MAX_TRAVEL_TEXT_CHARS;
  return { text: truncated ? text.slice(0, MAX_TRAVEL_TEXT_CHARS) : text, removed, truncated };
}
