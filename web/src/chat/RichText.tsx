import { Fragment, type ReactNode } from "react";

/**
 * An answer's text with the little formatting the chat asks the model for (ADR-604): paragraphs,
 * "- " and "1. " lists, and **bold**. Everything else stays plain text. It builds React elements
 * from the words, never HTML, so markup or a link in an answer is shown as the characters it is.
 */

type Block = { kind: "p"; lines: string[] } | { kind: "ul"; items: string[] } | { kind: "ol"; items: string[] };

const BULLET = /^\s*[-*•]\s+(.*)$/;
const NUMBERED = /^\s*\d{1,3}[.)]\s+(.*)$/;

export function blocks(text: string): Block[] {
  const out: Block[] = [];
  for (const line of text.replace(/\r\n?/g, "\n").split("\n")) {
    const bullet = BULLET.exec(line);
    const numbered = bullet ? null : NUMBERED.exec(line);
    const last = out[out.length - 1];
    if (bullet) {
      if (last?.kind === "ul") last.items.push(bullet[1]!);
      else out.push({ kind: "ul", items: [bullet[1]!] });
    } else if (numbered) {
      if (last?.kind === "ol") last.items.push(numbered[1]!);
      else out.push({ kind: "ol", items: [numbered[1]!] });
    } else if (line.trim() === "") {
      // A blank line ends a paragraph or a list.
      if (last && !(last.kind === "p" && last.lines.length === 0)) out.push({ kind: "p", lines: [] });
    } else if (last?.kind === "p") {
      last.lines.push(line);
    } else {
      out.push({ kind: "p", lines: [line] });
    }
  }
  return out.filter((b) => (b.kind === "p" ? b.lines.length > 0 : b.items.length > 0));
}

/** `**bold**` inside a line; an unmatched pair stays as typed. */
export function inline(text: string): ReactNode[] {
  const parts = text.split(/(\*\*[^*\n]+\*\*)/g);
  return parts.map((part, i) =>
    part.length > 4 && part.startsWith("**") && part.endsWith("**") ? <strong key={i}>{part.slice(2, -2)}</strong> : <Fragment key={i}>{part}</Fragment>,
  );
}

export function RichText({ text, className }: { text: string; className?: string }) {
  return (
    <div className={className}>
      {blocks(text).map((block, i) =>
        block.kind === "p" ? (
          <p key={i}>
            {block.lines.map((line, j) => (
              <Fragment key={j}>
                {j > 0 ? <br /> : null}
                {inline(line)}
              </Fragment>
            ))}
          </p>
        ) : block.kind === "ul" ? (
          <ul key={i}>
            {block.items.map((item, j) => (
              <li key={j}>{inline(item)}</li>
            ))}
          </ul>
        ) : (
          <ol key={i}>
            {block.items.map((item, j) => (
              <li key={j}>{inline(item)}</li>
            ))}
          </ol>
        ),
      )}
    </div>
  );
}
