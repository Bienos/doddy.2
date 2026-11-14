/**
 * The checks that tie every value read from a booking email to the words of that email
 * (DOD-02, DOD-08; docs/implementation/TRAVEL.md section 6). The reader is asked to give each date, time
 * and amount twice: as a value and exactly as written. A value is kept only if the "as written" words are
 * in the email and mean that value when this code reads them. A name, a code or a reference is kept only
 * if it is in the email. Nothing here trusts the reader; nothing here calls out.
 */

/** Case, accents' composed form and runs of white space don't matter when looking for words in an email. */
export function normalizeForSearch(s: string): string {
  return s.normalize("NFKC").toLocaleLowerCase("pl").replace(/\s+/g, " ").trim();
}

/** True when `needle` (non-empty after normalizing) appears in `haystack`. */
export function appearsIn(haystack: string, needle: string | null | undefined): boolean {
  if (typeof needle !== "string") return false;
  const n = normalizeForSearch(needle);
  return n.length > 0 && normalizeForSearch(haystack).includes(n);
}

// ---------------------------------------------------------------- dates

const MONTHS: Record<string, number> = {};
const addMonths = (names: string[][]) => names.forEach((list, i) => list.forEach((name) => { MONTHS[name] = i + 1; }));
addMonths([
  ["january", "jan", "styczeń", "styczen", "stycznia", "sty"],
  ["february", "feb", "luty", "lutego", "lut"],
  ["march", "mar", "marzec", "marca"],
  ["april", "apr", "kwiecień", "kwiecien", "kwietnia", "kwi"],
  ["may", "maj", "maja"],
  ["june", "jun", "czerwiec", "czerwca", "cze"],
  ["july", "jul", "lipiec", "lipca", "lip"],
  ["august", "aug", "sierpień", "sierpien", "sierpnia", "sie"],
  ["september", "sep", "sept", "wrzesień", "wrzesien", "września", "wrzesnia", "wrz"],
  ["october", "oct", "październik", "pazdziernik", "października", "pazdziernika", "paź", "paz"],
  ["november", "nov", "listopad", "listopada", "lis"],
  ["december", "dec", "grudzień", "grudzien", "grudnia", "gru"],
]);

const pad = (n: number) => String(n).padStart(2, "0");

function isRealDate(y: number, m: number, d: number): boolean {
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}

const fullYear = (y: number) => (y < 100 ? 2000 + y : y);

/**
 * What a date "as written" can mean, as ISO dates. European order only (08/12/2026 is 8 December); a date
 * without a year may be in the email's year or the next one. Unreadable words give an empty list.
 */
export function readDate(asWritten: string, emailYear: number): string[] {
  const s = normalizeForSearch(asWritten).replace(/[,.]+$/g, "");
  const out = new Set<string>();
  const add = (y: number, m: number, d: number) => { if (isRealDate(y, m, d)) out.add(`${y}-${pad(m)}-${pad(d)}`); };
  const addYearless = (m: number, d: number) => { add(emailYear, m, d); add(emailYear + 1, m, d); };

  let g: RegExpMatchArray | null;
  if ((g = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/))) add(Number(g[1]), Number(g[2]), Number(g[3]));
  else if ((g = s.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{2}|\d{4})$/))) add(fullYear(Number(g[3])), Number(g[2]), Number(g[1]));
  else if ((g = s.match(/^(\d{1,2})[./-](\d{1,2})$/))) addYearless(Number(g[2]), Number(g[1]));
  else {
    // Words: an optional weekday, then day and month in either order, then an optional year.
    // "Sunday, 29 March 2026", "Fri, 30 Oct 26", "02/Apr/2026", "1 lis", "Oct 30, 2026".
    const words = s.replace(/[,/.-]+/g, " ").split(" ").filter(Boolean);
    const monthWords = words.filter((w) => MONTHS[w] !== undefined);
    const fourDigit = words.filter((w) => /^\d{4}$/.test(w));
    const short = words.filter((w) => /^\d{1,2}$/.test(w));
    const month = monthWords.length === 1 ? MONTHS[monthWords[0]!] : undefined;
    let day: number | undefined, year: number | undefined;
    if (fourDigit.length === 1 && short.length === 1) { day = Number(short[0]); year = Number(fourDigit[0]); }
    else if (fourDigit.length === 0 && short.length === 2) { day = Number(short[0]); year = fullYear(Number(short[1])); }
    else if (fourDigit.length === 0 && short.length === 1) day = Number(short[0]);
    if (day !== undefined && month !== undefined) {
      if (year !== undefined) add(year, month, day);
      else addYearless(month, day);
    }
  }
  return [...out];
}

/** "2026-12-08" from words in the email, or null when the words aren't there or don't mean that date. */
export function groundDate(text: string, ev: { iso: string; asWritten: string } | null | undefined, emailYear: number): string | null {
  if (!ev || !/^\d{4}-\d{2}-\d{2}$/.test(ev.iso)) return null;
  if (!appearsIn(text, ev.asWritten)) return null;
  return readDate(ev.asWritten, emailYear).includes(ev.iso) ? ev.iso : null;
}

// ---------------------------------------------------------------- times

/** "14:00" when the email says 14:00 (or 14.00, or 2:00 PM), otherwise null. */
export function groundTime(text: string, value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const g = value.match(/^(\d{1,2}):(\d{2})$/);
  if (!g) return null;
  const h = Number(g[1]), m = Number(g[2]);
  if (h > 23 || m > 59) return null;
  const hh = pad(h), mm = pad(m);
  const t = normalizeForSearch(text);
  const forms = [`${hh}:${mm}`, `${h}:${mm}`, `${hh}.${mm}`, `${h}.${mm}`];
  if (h >= 12) {
    const h12 = h === 12 ? 12 : h - 12;
    forms.push(`${h12}:${mm} pm`, `${h12}:${mm}pm`);
  } else {
    const h12 = h === 0 ? 12 : h;
    forms.push(`${h12}:${mm} am`, `${h12}:${mm}am`);
  }
  // A digit right before or after means it is part of another number ("114:00", "14:005").
  return forms.some((f) => new RegExp(`(^|[^0-9])${f.replace(/[.]/g, "\\.")}($|[^0-9])`).test(t)) ? `${hh}:${mm}` : null;
}

// ---------------------------------------------------------------- money

const CURRENCY_SIGNS: [RegExp, string][] = [
  [/€|\beur\b|\beuro?\b/i, "EUR"],
  [/zł|\bpln\b/i, "PLN"],
  [/£|\bgbp\b/i, "GBP"],
  [/\$|\busd\b/i, "USD"],
  [/\bchf\b/i, "CHF"],
  [/\bczk\b|kč/i, "CZK"],
  [/\btry\b|₺/i, "TRY"],
  [/\bhuf\b|\bft\b/i, "HUF"],
];

/** The amount in "€ 1,234.50", "296.50 PLN", "1 234,50 zł" as "1234.50", or null when it isn't one number. */
export function readAmount(asWritten: string): string | null {
  const digits = asWritten.match(/\d[\d\s.,]*\d|\d/g);
  if (!digits || digits.length !== 1) return null;
  let n = digits[0]!.replace(/\s/g, "");
  const lastSep = Math.max(n.lastIndexOf("."), n.lastIndexOf(","));
  if (lastSep >= 0 && n.length - lastSep - 1 === 2) {
    n = n.slice(0, lastSep).replace(/[.,]/g, "") + "." + n.slice(lastSep + 1);
  } else {
    // No decimal part: every separator groups thousands ("1,234", "1.234") or nothing.
    n = n.replace(/[.,]/g, "");
  }
  if (!/^\d+(\.\d{2})?$/.test(n)) return null;
  const [whole, cents = "00"] = n.split(".");
  return `${String(Number(whole))}.${cents}`;
}

export function readCurrency(asWritten: string): string | null {
  const found = CURRENCY_SIGNS.filter(([re]) => re.test(asWritten)).map(([, code]) => code);
  return found.length === 1 ? found[0]! : null;
}

export interface Money { amount: string; currency: string }

/** The amount and currency, if the email says exactly that ("as written" is in it and reads the same). */
export function groundMoney(text: string, ev: { amount: string; currency: string; asWritten: string } | null | undefined): Money | null {
  if (!ev || !appearsIn(text, ev.asWritten)) return null;
  const amount = readAmount(ev.asWritten);
  const currency = readCurrency(ev.asWritten);
  const claimed = readAmount(ev.amount);
  if (!amount || !currency || amount !== claimed || currency !== ev.currency.toUpperCase()) return null;
  return { amount, currency };
}
