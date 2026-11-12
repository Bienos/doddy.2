// Linear-time reading of fetched HTML and feed text. A regex such as `/<[^>]*x[^>]*>/g` or
// `/<x>([\s\S]*?)<\/x>/g` starts again at every "<" and reads on to the end of the input each time it
// fails, so a page with many "<" and no ">" took seconds per 100 KB. These helpers find the same tags
// and elements with searches that only move forward.

/** The first match of `needle` (a string, or a global regex) at or after `from`: its index and end, or undefined. */
export function findFrom(text: string, needle: string | RegExp, from: number): { index: number; end: number } | undefined {
  if (typeof needle === "string") {
    const i = text.indexOf(needle, from);
    return i < 0 ? undefined : { index: i, end: i + needle.length };
  }
  if (!needle.global) throw new Error("findFrom needs a global regex");
  needle.lastIndex = from;
  const m = needle.exec(text);
  return m ? { index: m.index, end: m.index + m[0].length } : undefined;
}

/**
 * `findFrom` for a run of searches in one text, each from a point at or after the one before. An answer the last
 * search already covers is reused, so searches that move forward read the text once in all.
 */
export function forwardFinder(text: string, needle: string | RegExp): (from: number) => { index: number; end: number } | undefined {
  let lastFrom = Number.POSITIVE_INFINITY;
  let last: { index: number; end: number } | undefined;
  return (from) => {
    if (from >= lastFrom && (!last || last.index >= from)) return last;
    lastFrom = from;
    last = findFrom(text, needle, from);
    return last;
  };
}

/** `s.replace(/<[^>]*>/g, by)`, in linear time. */
export function stripTags(s: string, by = " "): string {
  let out = "";
  let at = 0;
  for (;;) {
    const lt = s.indexOf("<", at);
    if (lt < 0) break;
    const gt = s.indexOf(">", lt + 1);
    if (gt < 0) break; // no ">" after this "<", so no later "<" starts a tag either
    out += s.slice(at, lt) + by;
    at = gt + 1;
  }
  return at === 0 ? s : out + s.slice(at);
}

export interface StartTag {
  /** Where the tag's "<" is. */
  index: number;
  /** Just past its ">". */
  end: number;
  /** The tag, "<" to ">". */
  text: string;
}

/**
 * The first start tag at or after `from`: a match of `open` (a global regex for the tag's beginning, such as
 * `/<form\b/gi`, or `/</g` for any tag) up to the first ">" after it. This is what `/<form\b[^>]*>/gi` finds from
 * `from`. When no ">" follows, no later tag can end either, so the answer is undefined at once.
 */
export function nextStartTag(html: string, open: RegExp, from = 0): StartTag | undefined {
  const start = findFrom(html, open, from);
  if (!start) return undefined;
  const gt = html.indexOf(">", start.end);
  if (gt < 0) return undefined;
  return { index: start.index, end: gt + 1, text: html.slice(start.index, gt + 1) };
}

/**
 * Every start tag `open` finds, in order: the matches of `/<form\b[^>]*>/gi` for `/<form\b/gi`. Filtering them
 * with a test on the tag gives the matches of `/<form\b[^>]*ATTR[^>]*>/gi` when ATTR can't contain ">": a tag
 * whose text fails the test has no later "<form" inside it that could pass.
 */
export function* startTags(html: string, open: RegExp, from = 0): Generator<StartTag> {
  for (let tag = nextStartTag(html, open, from); tag; tag = nextStartTag(html, open, tag.end)) yield tag;
}

export interface Element {
  tag: StartTag;
  /** The text between the start tag and `close`. */
  content: string;
  /** Just past `close`. */
  end: number;
}

/**
 * The elements whose start tag `open` finds and `accept` passes, each with its content up to the first `close`
 * after the start tag: the matches of `/<x\b[^>]*ATTR[^>]*>([\s\S]*?)<\/x>/g`. When a start tag has no `close`
 * after it, none of the later ones has either, so the scan stops there.
 */
export function* elements(
  html: string, open: RegExp, close: string | RegExp, accept: (tag: StartTag) => boolean = () => true,
): Generator<Element> {
  const closeAt = forwardFinder(html, close);
  let from = 0;
  for (;;) {
    const tag = nextStartTag(html, open, from);
    if (!tag) return;
    if (!accept(tag)) { from = tag.end; continue; }
    const c = closeAt(tag.end);
    if (!c) return;
    yield { tag, content: html.slice(tag.end, c.index), end: c.end };
    from = c.end;
  }
}

/** The first of `elements`, or undefined. */
export function firstElement(html: string, open: RegExp, close: string | RegExp, accept?: (tag: StartTag) => boolean): Element | undefined {
  for (const e of elements(html, open, close, accept)) return e;
  return undefined;
}

export interface Span {
  /** Where `open` starts. */
  index: number;
  /** Just past `open`. */
  contentStart: number;
  /** Where `close` starts. */
  contentEnd: number;
  /** Just past `close`. */
  end: number;
}

/**
 * The first `open` (a string or global regex) at or after `from` and the first `close` after it: what
 * `/OPEN([\s\S]*?)CLOSE/` finds when OPEN matches one way only. Undefined when either is missing (a later `open`
 * has no `close` after it either).
 */
export function spanAt(text: string, open: string | RegExp, close: string | RegExp, from = 0): Span | undefined {
  const o = findFrom(text, open, from);
  if (!o) return undefined;
  const c = findFrom(text, close, o.end);
  return c ? { index: o.index, contentStart: o.end, contentEnd: c.index, end: c.end } : undefined;
}

/** Every span `spanAt` finds, each search starting past the last span: the matches of `/OPEN[\s\S]*?CLOSE/g`. */
export function* spans(text: string, open: string | RegExp, close: string | RegExp): Generator<Span> {
  for (let s = spanAt(text, open, close); s; s = spanAt(text, open, close, s.end)) yield s;
}

/** `text.replace(/OPEN[\s\S]*?CLOSE/g, by)`, in linear time. */
export function replaceSpans(text: string, open: string | RegExp, close: string | RegExp, by: string): string {
  let out = "";
  let at = 0;
  for (const s of spans(text, open, close)) {
    out += text.slice(at, s.index) + by;
    at = s.end;
  }
  return at === 0 ? text : out + text.slice(at);
}

/**
 * Cuts `text` to `max` characters. A tag the cut splits ("<a href=…" with its ">" past the cut) is dropped with
 * everything after it, so it can't show up as text.
 */
export function capHtml(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const open = cut.indexOf("<", cut.lastIndexOf(">") + 1);
  return open < 0 ? cut : cut.slice(0, open);
}
