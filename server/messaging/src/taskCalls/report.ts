import type { Line, Outcome } from "./result.js";

export const FACT_KINDS = ["answer", "person", "organization", "date", "time", "price", "location", "condition", "commitment", "open_question", "follow_up"] as const;
export type FactKind = typeof FACT_KINDS[number];
export interface CandidateFact { kind: FactKind; value: string; line: number; quote: string; uncertain: boolean }
export interface EvidenceFact {
  kind: FactKind; value: string; certainty: "reported" | "uncertain";
  evidence: { line: number; atSecs: number | null; quote: string };
}
export interface CallReport {
  format: 1;
  objective: string;
  domain: "appointment" | "restaurant" | "support" | "general";
  outcome: Outcome;
  facts: EvidenceFact[];
  verification: { method: "verbatim_callee_evidence"; accepted: number; rejected: number; uncoveredLines: number[] };
}

const clean = (s: string) => s.normalize("NFKC").trim();
const fold = (s: string) => clean(s).normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
const uncertainWords = /\b(maybe|perhaps|might|may be|possibly|probably|not sure|cannot confirm|can't confirm|only if|provided that|chyba|moze|prawdopodobnie|nie wiem|nie jestem pew\w*|nie moge potwierdzic|pod warunkiem|jezeli)\b/;

/** A second, deterministic pass: model prose is never proof. Each value must occur inside an exact
 * excerpt of the cited callee line. No assistant line, invented date, guessed currency conversion,
 * or unstated agreement survives this pass. "reported" records what was said, not a provider booking receipt.
 */
export function buildCallReport(objective: string, outcome: Outcome, transcript: readonly Line[], proposed: readonly CandidateFact[] = []): CallReport {
  const facts: EvidenceFact[] = [];
  const seen = new Set<string>();
  let rejected = Math.max(0, proposed.length - 16);
  for (const fact of proposed.slice(0, 16)) {
    const line = Number.isInteger(fact.line) && fact.line >= 0 ? transcript[fact.line] : undefined;
    const quote = typeof fact.quote === "string" ? clean(fact.quote) : "";
    const value = typeof fact.value === "string" ? clean(fact.value) : "";
    if (!FACT_KINDS.includes(fact.kind) || !line || line.speaker !== "callee" || !quote || quote.length > 300
        || !value || value.length > 200 || !line.text.includes(quote) || !quote.includes(value)) {
      rejected++;
      continue;
    }
    // A date's presence is not an agreement. This deliberately rejects ambiguous, negated and conditional
    // commitments; ordinary availability belongs under answer/date/condition instead.
    if (fact.kind === "commitment" && (!/\b(confirmed|confirm|agreed|booked|reserved|potwierdzam|potwierdzamy|potwierdzone|zarezerwowane|umowione)\b/.test(fold(line.text))
        || uncertainWords.test(fold(line.text)) || /\b(not|never|no|nie)\b|\?/.test(fold(line.text)))) {
      rejected++;
      continue;
    }
    const key = JSON.stringify([fact.kind, value, fact.line]);
    if (seen.has(key)) continue;
    seen.add(key);
    facts.push({ kind: fact.kind, value,
      // Read uncertainty from the entire line, so quoting only "Friday" cannot remove "maybe".
      certainty: fact.uncertain || uncertainWords.test(fold(line.text)) ? "uncertain" : "reported",
      evidence: { line: fact.line, atSecs: line.atSecs, quote } });
  }
  const title = clean(objective).slice(0, 360);
  const subject = fold(title);
  const domain = /dent|appointment|wizy|lekar|termin/.test(subject) ? "appointment"
    : /restaurant|restaur|stolik|table|dinner|kolac/.test(subject) ? "restaurant"
    : /support|complaint|reklamac|obslug/.test(subject) ? "support" : "general";
  // Numeric details omitted from the structured findings need review. This is a conservative coverage
  // signal, not a claim that code can prove every semantically important detail was extracted.
  const uncoveredLines = transcript.flatMap((line, index) => {
    if (line.speaker !== "callee") return [];
    const tokens = line.text.match(/\d+(?:[:.,/]\d+)*/g) ?? [];
    const represented = facts.filter((f) => f.evidence.line === index).map((f) => f.value).join(" ");
    return tokens.some((token) => !represented.includes(token)) ? [index] : [];
  }).slice(0, 24);
  return { format: 1, objective: title, domain, outcome, facts,
    verification: { method: "verbatim_callee_evidence", accepted: facts.length, rejected, uncoveredLines } };
}

/** Preserve a source excerpt as the summary only when the entire proposed summary is actually spoken.
 * This deliberately does not pretend to solve semantic entailment or certify a free-form model paragraph.
 */
export function groundedNarrative(text: string | undefined, transcript: readonly Line[]): string | undefined {
  if (!text?.trim()) return undefined;
  const candidate = clean(text);
  return candidate.length <= 300 && transcript.some((l) => l.speaker === "callee" && l.text.includes(candidate)) ? candidate : undefined;
}
