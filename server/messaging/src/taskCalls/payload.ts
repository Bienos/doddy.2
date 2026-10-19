// The compiled payload of a call case (ADR-501): everything Twilio and ElevenLabs will receive,
// built once when the brief is created. The user approves its digest; the dial and answer code send
// these stored values and nothing else, so a deploy between approval and the call can't change
// what is said or who is called.
import type { RecordingNotice } from "../config.js";
import { hmacSha256, type TextCipher } from "../crypto.js";
import type { Brief, FactKind } from "./brief.js";
import { GRACE_SECS, RING_SECS } from "./hours.js";
import { callbackLine, factLines, forbiddenList, openingLine } from "./opening.js";
import { formatPolish, type DestinationKind } from "./phone.js";

/** The variables the task-call agent receives; its prompt may use exactly these (plus doddy_attempt). */
export interface AgentVariables {
  doddy_opening_line: string;
  doddy_question: string;
  doddy_principal: string;
  doddy_callee: string;
  doddy_goal: string;
  doddy_facts: string;
  doddy_callback_line: string;
  doddy_max_minutes: string;
}
export const AGENT_VARIABLE_NAMES = [
  "doddy_opening_line", "doddy_question", "doddy_principal", "doddy_callee", "doddy_goal", "doddy_facts",
  "doddy_callback_line", "doddy_max_minutes",
] as const satisfies readonly (keyof AgentVariables)[];
/** Added at answer time so the post-call webhook can be matched to the attempt. Not in the prompt. */
export const ATTEMPT_VARIABLE = "doddy_attempt";

export interface CallPayload {
  format: 1;
  caseId: string;
  kind: "ask";
  language: "pl";
  display: {
    callee: { name: string; phone: string; destinationKind: DestinationKind; source: Brief["callee"]["source"]; sourceLabel: string | null };
    principal: { name: string; genitive: string };
    goal: string;
    question: string;
    facts: { kind: FactKind; text: string }[];
    forbidden: string[];
    notice: RecordingNotice;
    maxDurationSecs: number;
  };
  twilio: { to: string; from: string; timeLimitSecs: number; timeoutSecs: number; record: false };
  agent: { variables: AgentVariables };
}

export interface CompileInput {
  caseId: string;
  brief: Brief;
  destination: { e164: string; kind: DestinationKind };
  fromNumber: string;
  notice: RecordingNotice;
}

export function compilePayload({ caseId, brief, destination, fromNumber, notice }: CompileInput): CallPayload {
  const g = brief.principal.genitive;
  const question = /[?？]$/.test(brief.question) ? brief.question : `${brief.question}?`;
  const facts = brief.facts.map((f) => ({ kind: f.kind, text: f.text }));
  return {
    format: 1,
    caseId,
    kind: "ask",
    language: "pl",
    display: {
      callee: {
        name: brief.callee.name, phone: formatPolish(destination.e164), destinationKind: destination.kind,
        source: brief.callee.source, sourceLabel: brief.callee.sourceLabel ?? null,
      },
      principal: { name: brief.principal.name, genitive: g },
      goal: brief.goal,
      question,
      facts,
      forbidden: forbiddenList(g, facts.map((f) => f.kind)),
      notice,
      maxDurationSecs: brief.maxDurationSecs,
    },
    twilio: {
      to: destination.e164,
      from: fromNumber,
      timeLimitSecs: brief.maxDurationSecs + GRACE_SECS,
      timeoutSecs: RING_SECS,
      record: false,
    },
    agent: {
      variables: {
        doddy_opening_line: openingLine(g, notice, question),
        doddy_question: question,
        doddy_principal: g,
        doddy_callee: brief.callee.name,
        doddy_goal: brief.goal,
        doddy_facts: factLines(facts),
        doddy_callback_line: callbackLine(g),
        doddy_max_minutes: String(Math.round(brief.maxDurationSecs / 60)),
      },
    },
  };
}

/** JSON with object keys sorted at every level: the same payload always gives the same bytes. */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  const o = value as Record<string, unknown>;
  return `{${Object.keys(o).filter((k) => o[k] !== undefined).sort().map((k) => `${JSON.stringify(k)}:${canonicalJson(o[k])}`).join(",")}}`;
}

/** Keys for one purpose each, derived from MEMORY_ENCRYPTION_KEY. */
export interface CaseKeys { digest: Buffer; destination: Buffer; callerPhone: Buffer }
export const caseKeys = (cipher: TextCipher): CaseKeys => ({
  digest: cipher.derivedKey("call-payload-digest"),
  destination: cipher.derivedKey("call-destination"),
  callerPhone: cipher.derivedKey("call-caller-phone"),
});

/** HMAC, not a bare hash, so a digest can't be used to guess a short brief's contents. */
export const payloadDigest = (keys: CaseKeys, payload: CallPayload) => hmacSha256(keys.digest, canonicalJson(payload));
export const destinationHash = (keys: CaseKeys, e164: string) => hmacSha256(keys.destination, e164);
export const callerPhoneHash = (keys: CaseKeys, e164: string) => hmacSha256(keys.callerPhone, e164);
export const payloadAad = (accountId: string, caseId: string) => `${accountId}:call-case:${caseId}`;

/** What the brief card shows: built from the payload itself, so the card is what will be sent. */
export function previewOf(payload: CallPayload, digest: Buffer, approvableUntil: Date) {
  const d = payload.display;
  return {
    caseId: payload.caseId,
    digest: digest.toString("hex"),
    approvableUntil: approvableUntil.toISOString(),
    callee: d.callee,
    principal: d.principal,
    goal: d.goal,
    openingLine: payload.agent.variables.doddy_opening_line,
    question: d.question,
    facts: d.facts,
    forbidden: d.forbidden,
    callbackLine: payload.agent.variables.doddy_callback_line,
    maxDurationSecs: d.maxDurationSecs,
    notice: d.notice,
    recordsAudio: false,
  };
}
