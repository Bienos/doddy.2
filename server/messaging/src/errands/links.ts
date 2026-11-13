// Errand text must not carry a link (security review 4 Nov 2026, ADR-703). The words, brief and priorities go to the
// researcher, and its web fetch can open any address that appears in what it was given. A link in text a model
// wrote is therefore a way to make a page request carry data out, so the create request is refused if any of its text
// holds something shaped like one. A bare domain name ("allegro.pl") stays fine: it names a shop and carries no path.
// The check reads the text the way a browser or a model would, so it first folds look-alike characters and
// percent-escapes; it can't catch every disguise and doesn't try to (spelling a scheme with spaces, say).

/** Zero-width and invisible characters that can be slipped into a scheme or a dot. */
const INVISIBLE = /[\u00AD\u180E\u200B-\u200F\u2060-\u2064\uFEFF]/g;
/** Full stops that URL parsers (UTS 46) treat as a dot but NFKC leaves alone: U+3002 (what U+FF61 folds to). */
const DOT_LIKE = /[\u3002\uFF61]/g;
/** Slashes NFKC leaves alone: fraction slash, division slash, big solidus. */
const SLASH_LIKE = /[\u2044\u2215\u29F8]/g;

const DEFANGED: Array<[string, string]> = [
  ["[.]", "."], ["(.)", "."], ["{.}", "."], ["[dot]", "."], ["(dot)", "."], ["{dot}", "."], ["[:]", ":"], ["(:)", ":"], ["[/]", "/"], ["(/)", "/"],
];

const ESCAPES: Record<string, string> = { "25": "%", "2f": "/", "2e": ".", "3a": ":", "5c": "\\" };
const ENTITIES: Record<string, string> = { sol: "/", period: ".", colon: ":", bsol: "\\" };

/** The text as a parser would see it: look-alikes folded to ASCII, percent-escapes and character entities opened. */
export function foldForLinks(text: string): string {
  let t = text.normalize("NFKC").replace(INVISIBLE, "").replace(DOT_LIKE, ".").replace(SLASH_LIKE, "/");
  for (let i = 0; i < 3; i++) {
    const next = t
      .replace(/%(25|2f|2e|3a|5c)/gi, (_m, h: string) => ESCAPES[h.toLowerCase()]!)
      .replace(/&#(x[0-9a-f]{1,2}|\d{1,3});/gi, (m, n: string) => {
        const code = n[0] === "x" || n[0] === "X" ? parseInt(n.slice(1), 16) : parseInt(n, 10);
        return code >= 0x20 && code < 0x7f ? String.fromCharCode(code) : m;
      })
      .replace(/&(sol|period|colon|bsol);/gi, (_m, name: string) => ENTITIES[name.toLowerCase()]!);
    if (next === t) break;
    t = next;
  }
  // A browser reads a backslash as a slash; and "example[.]com", "example(dot)com", "https[:]//" are links written so a person can still read them.
  t = t.replace(/\\/g, "/");
  for (const [spelled, plain] of DEFANGED) t = t.replace(new RegExp(spelled.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi"), plain);
  return t;
}

const PATTERNS: RegExp[] = [
  // Any scheme followed by two slashes: http://, https://, ftp://, file://, ws://, hxxps:// (backslashes are folded to slashes).
  /[a-z][a-z0-9+.-]*:\/\//i,
  // www. in front of a name.
  /(?:^|[^a-z0-9])www\d{0,3}\./i,
  // Script and data addresses. "data:" alone is a Polish word ("Data: 12.11"), so it needs a media type or a separator.
  /(?:^|[^a-z0-9])(?:javascript|vbscript)\s*:\S/i,
  /(?:^|[^a-z0-9])data:(?:[a-z0-9.+-]+\/[a-z0-9.+-]+|[;,])/i,
  // host.tld followed by a path, a query or a fragment: allegro.pl/oferta, allegro.pl/, evil.example?x=1, a.b.example:8080/x.
  // A bare name (allegro.pl) is not matched. The ending is letters or a punycode one (xn--80asehdb).
  /(?:[\p{L}\p{N}-]+\.)+(?:\p{L}{2,}|xn--[a-z0-9-]{2,})(?::\d{1,5})?(?:\/|[?#]\S)/iu,
  // A dotted IPv4 address, with or without a path ("192.168.0.1/admin", "169.254.169.254").
  /(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?!\d)(?!\.\d)/,
  // An IPv4 address written with hex parts (0x7f.0.0.1).
  /(?<![\w.])0x[0-9a-f]+(?:\.(?:0x[0-9a-f]+|\d+)){3}(?![\w])/i,
  // A markdown link: [text](target) where the target looks like an address or a path.
  /\[[^\]\n]*\]\(\s*<?[^\s()<>]*[/.:#?@][^\s()<>]*/,
  // A bracketed IPv6 address ([::1], [2001:db8::1]).
  /\[(?=[0-9a-f.]*:[0-9a-f.]*:)[0-9a-f:.]{2,45}\]/i,
];

/** True when the text holds something shaped like a link (see the top of this file). */
export function hasLink(text: string): boolean {
  const t = foldForLinks(text);
  return PATTERNS.some((p) => p.test(t));
}

/**
 * The names of the fields of a create request that hold a link, as zod would path them ("words", "priorities.1").
 * Names only, never the text.
 */
export function linkFields(c: { words: string; brief: string; title: string; priorities?: readonly string[] }): string[] {
  const out: string[] = [];
  if (hasLink(c.words)) out.push("words");
  if (hasLink(c.brief)) out.push("brief");
  if (hasLink(c.title)) out.push("title");
  c.priorities?.forEach((p, i) => { if (hasLink(p)) out.push(`priorities.${i}`); });
  return out;
}

/**
 * The same check for any other text a model will read with a web fetch at hand (Studio's topic, audience and
 * details): the names of the fields that hold a link, in the order given. Names only, never the text.
 */
export function textLinkFields(fields: Readonly<Record<string, string | undefined>>): string[] {
  return Object.entries(fields).flatMap(([name, text]) => (text !== undefined && hasLink(text) ? [name] : []));
}
