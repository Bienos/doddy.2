// How many SMS segments a text will use (research item #4, docs/decisions/2026-11-09-sms-segment-budget.md).
// Twilio bills per segment, and the segment count depends on the encoding, not on the number of characters:
//   - GSM-7 (the 7-bit default alphabet): 160 septets in one segment, 153 per segment when split (7 go to the
//     concatenation header). A few characters (^ { } \ [ ~ ] | € and form feed) are in the extension table and cost
//     two septets (escape + character); an escape pair is never split over two segments.
//   - UCS-2 (UTF-16): chosen for the WHOLE message as soon as one character is outside GSM-7, e.g. any Polish ą ć ę ł ń ó ś ź ż,
//     a curly quote or an emoji. 70 code units in one segment, 67 per segment when split. A character outside the
//     Basic Multilingual Plane (an emoji) is a surrogate pair = 2 code units, and the pair is not split over two segments.
// Source: https://www.twilio.com/docs/glossary/what-sms-character-limit (checked 9 Nov 2026: 160/153 and 70/67; one
// non-GSM character switches the whole message to UCS-2; billing is per segment). Twilio's page does not list the
// extension table or the surrogate rule; they follow 3GPP TS 23.038 and the UTF-16 definition of UCS-2 as carriers use it.
// Twilio's optional "Smart Encoding" (replaces curly quotes etc.) is not assumed: the estimate is the safe, higher one.
// Toll-free US/CA messages carry 152/66 per segment; Doddy texts Polish and EU numbers, so that case is not modelled.
// This is an ESTIMATE; Twilio's own count (num_segments) is the truth and is recorded when it is reported (outbox.ts).
// Pure: no I/O, no logging, no text kept.

export type SmsEncoding = "GSM-7" | "UCS-2";

export interface SegmentEstimate {
  encoding: SmsEncoding;
  /** Septets (GSM-7, an extension character counts 2) or UTF-16 code units (UCS-2). */
  units: number;
  /** 0 for an empty text, otherwise at least 1. */
  segments: number;
}

/** Characters of the GSM 03.38 default alphabet (one septet each). */
const GSM_BASIC = new Set(
  "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà");
/** The extension table: each is an escape plus a septet, so two. */
const GSM_EXTENSION = new Set("\f^{}\\[~]|€");

export const SINGLE_LIMIT = { "GSM-7": 160, "UCS-2": 70 } as const;
export const MULTI_LIMIT = { "GSM-7": 153, "UCS-2": 67 } as const;

/** True when every character is in the GSM-7 default or extension alphabet. */
export function isGsm7(text: string): boolean {
  for (const ch of text) if (!GSM_BASIC.has(ch) && !GSM_EXTENSION.has(ch)) return false;
  return true;
}

/** The size of each character in the encoding, in order. A UCS-2 surrogate pair is one entry of 2 (it is never split). */
function charCosts(text: string, encoding: SmsEncoding): number[] {
  const out: number[] = [];
  for (const ch of text) {
    if (encoding === "GSM-7") out.push(GSM_EXTENSION.has(ch) ? 2 : 1);
    else out.push(ch.length); // 1, or 2 for a character outside the BMP; a lone surrogate iterates as 1
  }
  return out;
}

export function estimateSmsSegments(text: string): SegmentEstimate {
  const encoding: SmsEncoding = isGsm7(text) ? "GSM-7" : "UCS-2";
  const costs = charCosts(text, encoding);
  const units = costs.reduce((a, b) => a + b, 0);
  if (units === 0) return { encoding, units, segments: 0 };
  if (units <= SINGLE_LIMIT[encoding]) return { encoding, units, segments: 1 };
  // Split: pack characters greedily, never breaking one (an extension pair or a surrogate pair) across two segments.
  const room = MULTI_LIMIT[encoding];
  let segments = 1;
  let used = 0;
  for (const c of costs) {
    if (used + c > room) { segments++; used = 0; }
    used += c;
  }
  return { encoding, units, segments };
}

/** The slots a text reserves against a segment cap: its estimated segments, at least 1 (an empty text is not queued). */
export const reservedSegments = (text: string): number => Math.max(1, estimateSmsSegments(text).segments);
