// Turns the picked stories into the two message formats. Push bodies can't hold tappable
// links, so the push is the short list and the full digest with links is in the app.

export interface DigestEntry { line: string; url: string; source: string }

const PUSH_MAX = 600;
const SMS_MAX = 640;

export function pushBody(entries: DigestEntry[], language: "en" | "pl"): string {
  const lines: string[] = [];
  let used = 0;
  for (const e of entries) {
    const l = `• ${e.line}`;
    if (used + l.length + 1 > PUSH_MAX - 40) break;
    lines.push(l);
    used += l.length + 1;
  }
  const rest = entries.length - lines.length;
  if (rest > 0) lines.push(language === "pl" ? `+${rest} więcej w Doddy` : `+${rest} more in Doddy`);
  return lines.join("\n");
}

/** As many numbered stories with links as fit in 640 characters (at most 3: SMS costs per segment). */
export function smsBody(entries: DigestEntry[], language: "en" | "pl"): string {
  let body = language === "pl" ? "Wiadomości od Doddy:" : "Doddy news:";
  let n = 0;
  for (const e of entries.slice(0, 3)) {
    const withLink = `\n${n + 1}. ${e.line} ${e.url}`;
    const withoutLink = `\n${n + 1}. ${e.line}`;
    if (body.length + withLink.length <= SMS_MAX) body += withLink;
    else if (body.length + withoutLink.length <= SMS_MAX) body += withoutLink;
    else break;
    n++;
  }
  return body;
}
