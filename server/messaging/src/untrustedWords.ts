// Words that come from someone who is not the user (the other side of a call, the sender of a text, the model's
// answer to such a text) must not reach the user's phone as a tappable link or a number to call or pay, from Doddy's
// own number. This is the one place that makes such words safe to put into a text. Nothing here can prove who wrote
// a text (see docs/implementation/SMS_CHAT.md); it only limits what the words can do once they are in one.

/** What ends a sentence or closes a quote: left outside a link, so "see www.a.pl)." keeps its ")." */
const END = String.raw`[^\s.,;:!?)”"'»]`;
const LABEL = String.raw`[\p{L}\p{M}\p{N}](?:[\p{L}\p{M}\p{N}_-]*[\p{L}\p{M}\p{N}])?`;
const PATH = String.raw`(?:[\/?#](?:\S*${END})?)?`;

/** Something a phone or a mail app turns into a link, as a transcript or a text may write it. */
const LINK = new RegExp([
  // A link with a scheme (any scheme: http, ftp, an app's own), in angle brackets or not, or one starting "www.".
  String.raw`<?(?:[a-z][a-z0-9+.-]{1,31}:\/\/|www\.)\S*${END}>?`,
  // A scheme a phone follows without a double slash: mailto:, tel:, sms:, javascript: ...
  String.raw`(?<![\p{L}\p{N}])(?:mailto|tel|sms|smsto|mms|mmsto|facetime|facetime-audio|callto|skype|sip|sips|geo|maps|whatsapp|tg|webcal|data|javascript|vbscript|file|blob|intent|magnet|bitcoin):\S*${END}>?`,
  // An e-mail address.
  String.raw`(?<![\p{L}\p{N}._%+-])[\p{L}\p{N}._%+-]+@[\p{L}\p{M}\p{N}.-]+\.\p{L}{2,}`,
  // A bare address: any name ending in a dot and two or more letters (.pl, .de, .xyz, .click ...), with a port and a
  // path if it has them. A sentence's own full stop is not followed by a letter, so ordinary text does not match.
  String.raw`(?<![\p{L}\p{M}\p{N}.@_%+-])${LABEL}(?:\.${LABEL})*\.\p{L}{2}[\p{L}\p{M}\p{N}-]*(?::\d{1,5})?${PATH}`,
  // An IPv4 address.
  String.raw`(?<![\p{N}.])\d{1,3}(?:\.\d{1,3}){3}(?![\p{N}])(?::\d{1,5})?${PATH}`,
].join("|"), "giu");

/** A link written as markdown, [label](target): the label's words are kept, the target is not. */
const MARKDOWN_LINK = /\[([^\[\]\n]{0,200})\]\(\s*<?[^\s()]*>?\s*\)/gu;
/** The tags of an HTML link, <a href="...">label</a>: the label's words are kept. */
const ANCHOR_TAG = /<\/?a(?:\s[^>]*)?>/giu;
/** Characters that take no room: a link written with them is still one for a person or a phone to read. */
const INVISIBLE = /[­​-‏‪-‮⁠-⁤﻿]/gu;

/**
 * The text as a link finder should see it, with where each of its characters is in the original: wide letters, other
 * dots and invisible characters are read as the plain ones they stand for, but the text itself is never rewritten.
 */
function seenAs(text: string): { seen: string; from: number[]; to: number[] } {
  let seen = "";
  const from: number[] = [];
  const to: number[] = [];
  let at = 0;
  for (const ch of text) {
    const next = at + ch.length;
    const plain = ch.normalize("NFKC").replace(INVISIBLE, "").replace(/[。｡]/gu, ".");
    for (let k = 0; k < plain.length; k++) { from.push(at); to.push(next); }
    seen += plain;
    at = next;
  }
  return { seen, from, to };
}

/**
 * `text` with every link, web address, e-mail address and link wrapper replaced by `mark` (a markdown link keeps its
 * label). Anything else, the original characters included, is left as it was.
 */
export function withoutLinks(text: string, mark = "…"): string {
  const unwrapped = text.replace(MARKDOWN_LINK, "$1").replace(ANCHOR_TAG, "");
  const { seen, from, to } = seenAs(unwrapped);
  let out = "";
  let pos = 0;
  for (const m of seen.matchAll(LINK)) {
    const end = to[m.index + m[0].length - 1]!;
    if (end <= pos) continue;
    out += unwrapped.slice(pos, Math.max(from[m.index]!, pos)) + mark;
    pos = end;
  }
  return out + unwrapped.slice(pos);
}

/** Six or more digits together, or split by single spaces or hyphens (a phone, card, account or code number). */
const LONG_NUMBER = /\+?\p{Nd}(?:[   -]?\p{Nd}){5,}/gu;

/**
 * The other party's words as a text may quote them: links, web and e-mail addresses and long numbers become "…". They
 * are not the user's words, so nothing they said reaches the user's phone as a tappable link or a number to call or pay.
 */
export function quotableWords(words: string): string {
  return withoutLinks(words).replace(LONG_NUMBER, "…").replace(/\s{2,}/g, " ").trim();
}
