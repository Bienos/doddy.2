// Money for shopping (docs/implementation/SHOPPING.md): always integer minor units (grosze) with an ISO
// currency code, never floating point. Parsing accepts the ways Polish shops and Google Shopping write
// prices ("1 899,00 zł", "1.899,00 zł", "1899 zł", "PLN 1,899.00", "1 899 zł"); formatting writes the
// app's Polish form "1 899,00 zł" (no-break space) or "PLN 1,899.00" for English.

export interface Money { minor: number; currency: string }

const NBSP = " ";
const CURRENCY_WORDS: Array<[RegExp, string]> = [
  [/\b(zł|zl|złotych|złote|złoty|pln)\b/iu, "PLN"],
  [/(zł)/iu, "PLN"],
  [/€|\beur\b/iu, "EUR"],
  [/\$|\busd\b/iu, "USD"],
];

/** The currency a price text names, or undefined. Polish shops write "zł". */
export function currencyOf(text: string): string | undefined {
  for (const [re, code] of CURRENCY_WORDS) if (re.test(text)) return code;
  return undefined;
}

/**
 * The amount in a price text as minor units, or undefined when there isn't exactly one readable
 * amount. Separators: a comma or dot followed by exactly two digits at the end is the decimal mark;
 * spaces, no-break spaces and the other mark group thousands.
 */
export function parseAmount(text: string): number | undefined {
  // A minus sign before the number is never a price.
  if (/[-−]\s*\d/u.test(text)) return undefined;
  const numbers = text.match(/\d[\d\s  .,']*\d|\d/gu);
  if (!numbers || numbers.length !== 1) return undefined;
  let s = numbers[0].replace(/[\s  ']/gu, "");
  let decimals = "00";
  const m = /^(.*)[.,](\d{1,2})$/u.exec(s);
  if (m && m[1] !== undefined && m[2] !== undefined && !/[.,]\d{3}$/u.test(s)) {
    s = m[1];
    decimals = m[2].padEnd(2, "0");
  }
  s = s.replace(/[.,]/gu, "");
  if (!/^\d{1,9}$/u.test(s)) return undefined;
  const minor = Number(s) * 100 + Number(decimals);
  return Number.isSafeInteger(minor) && minor > 0 ? minor : undefined;
}

/** "1 899,00 zł" → {minor: 189900, currency: "PLN"}. `fallbackCurrency` when the text names none. */
export function parseMoney(text: string, fallbackCurrency?: string): Money | undefined {
  const minor = parseAmount(text);
  const currency = currencyOf(text) ?? fallbackCurrency;
  return minor !== undefined && currency ? { minor, currency } : undefined;
}

/** A number from structured data (schema.org `price`: 1899, "1899.00", "1899,00") as minor units. */
export function amountFromData(value: unknown): number | undefined {
  if (typeof value === "number") {
    if (!Number.isFinite(value) || value <= 0) return undefined;
    const minor = Math.round(value * 100);
    return Number.isSafeInteger(minor) ? minor : undefined;
  }
  if (typeof value !== "string") return undefined;
  const t = value.trim();
  if (/^\d+([.,]\d{1,2})?$/u.test(t)) {
    const [whole = "", frac = ""] = t.split(/[.,]/u);
    const minor = Number(whole) * 100 + Number(frac.padEnd(2, "0") || "0");
    return Number.isSafeInteger(minor) && minor > 0 ? minor : undefined;
  }
  return parseAmount(t);
}

function group(n: number, sep: string): string {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/gu, sep);
}

/** "1 899,00 zł" for pl (no-break spaces), "PLN 1,899.00" otherwise. */
export function formatMoney(m: Money, language: string): string {
  const whole = Math.floor(m.minor / 100);
  const frac = String(m.minor % 100).padStart(2, "0");
  if (language === "pl") {
    const unit = m.currency === "PLN" ? "zł" : m.currency;
    return `${group(whole, NBSP)},${frac}${NBSP}${unit}`;
  }
  return `${m.currency} ${group(whole, ",")}.${frac}`;
}

/**
 * Every money amount a text states, in minor units: a number next to a currency word or sign
 * ("1 899 zł", "PLN 1,899.00", "300 zł"). Used to drop model-written sentences that state an amount
 * the code can't back (SHOPPING.md, code rules).
 */
export function moneyMentions(text: string): number[] {
  const out: number[] = [];
  const num = String.raw`\d{1,3}(?:[\s  .,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?`;
  const after = new RegExp(String.raw`(${num})\s*(?:zł|zl\b|pln\b|złotych|złote|złoty|€|eur\b|usd\b|\$)`, "giu");
  const before = new RegExp(String.raw`(?:pln|eur|usd|\$|€)\s*(${num})`, "giu");
  for (const re of [after, before]) {
    for (const m of text.matchAll(re)) {
      const a = m[1] ? parseAmount(m[1]) : undefined;
      if (a !== undefined) out.push(a);
    }
  }
  return out;
}
