// The recap of an S2 call (ADR-684): built in code from the call's transcript and the notes it left. A
// model, if configured, may only write the summary, the next step, and point at the lines where something
// was settled or where Doddy said it can't do something. Every pointer is checked against the transcript
// here: its quote must be words from that line, or the item is dropped. Notes come from the database (only
// `save_note` creates them, and only after it answered saved_for_confirmation), never from the model.
import { z } from "zod";

export type Speaker = "doddy" | "caller";
export interface Line { speaker: Speaker; text: string; atSecs: number | null }

/** One thing pointed at in the transcript: a short description, and words copied from that line. */
export interface Pointer { text: string; line: number; quote: string }

export interface RecapNote { id: string; text: string; createdAt: string }

export type SummaryNote =
  | "no_writer" | "writer_failed" | "daily_limit" | "save_claim" | "empty_call" | "transcript_unreadable" | "unusable_summary";

export interface CallRecap {
  format: 1;
  callId: string;
  direction: "inbound" | "outbound";
  startedAt: string | null;
  durationSecs: number | null;
  /** Null when no model wrote one; `summaryNote` says why. */
  summary: string | null;
  summaryBy: "doddy_model" | "rules";
  summaryNote: SummaryNote | null;
  /** The language the summary is in (two letters), when the model wrote one. */
  language: string | null;
  agreed: Pointer[];
  couldNotDo: Pointer[];
  /** Notes Doddy took on this call. They wait in the call-notes inbox until the user saves them. */
  notes: RecapNote[];
  nextStep: string | null;
  transcript: Line[];
  /** How many of the model's pointers were dropped because they didn't match the transcript. */
  droppedPointers: number;
  builtAt: string;
}

/** What the optional model step gets and may say. Everything it says is checked before use. */
export interface RecapWriterInput {
  direction: "inbound" | "outbound";
  lines: { line: number; speaker: Speaker; text: string }[];
  tools: { line: number; name: string }[];
}
export interface RecapWriterOutput {
  summary: string;
  language: string;
  agreed: Pointer[];
  couldNotDo: Pointer[];
  nextStep: string | null;
  usage?: { inputTokens: number; outputTokens: number };
}
export interface RecapWriter {
  readonly model: string;
  write(input: RecapWriterInput): Promise<RecapWriterOutput>;
}

export const LIMITS = {
  lines: 400, lineChars: 1500, summaryChars: 400, itemChars: 200, quoteChars: 300, nextStepChars: 200, items: 5,
} as const;

// ---------- the post-call payload ----------

const turn = z.object({
  role: z.string(),
  message: z.string().nullable().optional(),
  time_in_call_secs: z.number().nullable().optional(),
  tool_calls: z.array(z.object({ tool_name: z.string().nullable().optional() }).passthrough()).nullable().optional(),
}).passthrough();

/** The parts of ElevenLabs' post-call payload this uses. Unknown fields are ignored and never stored. */
export const phoneConversationSchema = z.object({
  agent_id: z.string(),
  conversation_id: z.string().min(1).max(128),
  transcript: z.array(turn).default([]),
  metadata: z.object({
    call_duration_secs: z.number().nullable().optional(),
    start_time_unix_secs: z.number().nullable().optional(),
    phone_call: z.object({ call_sid: z.string().max(64).nullable().optional() }).passthrough().nullable().optional(),
  }).passthrough().default({}),
}).passthrough();
export type PhoneConversation = z.infer<typeof phoneConversationSchema>;

/** What is stored (encrypted) until the recap is built: only the turns, their tools, and the call's times. */
export interface StoredInput {
  turns: { role: "doddy" | "caller"; text: string; atSecs: number | null; tools: string[] }[];
  durationSecs: number | null;
  startUnix: number | null;
}

export function storedInputFrom(conv: PhoneConversation): StoredInput {
  return {
    turns: conv.transcript.slice(0, LIMITS.lines * 2).map((t) => ({
      role: t.role === "agent" ? "doddy" : "caller",
      text: typeof t.message === "string" ? t.message.slice(0, LIMITS.lineChars * 2) : "",
      atSecs: typeof t.time_in_call_secs === "number" ? t.time_in_call_secs : null,
      tools: (t.tool_calls ?? []).map((x) => x.tool_name ?? "").filter(Boolean).slice(0, 10),
    })),
    durationSecs: typeof conv.metadata.call_duration_secs === "number" ? conv.metadata.call_duration_secs : null,
    startUnix: typeof conv.metadata.start_time_unix_secs === "number" ? conv.metadata.start_time_unix_secs : null,
  };
}

// ---------- transcript ----------

/** Digit runs, with the spaces, dashes and dots people say between digits. */
const DIGITS = /\d(?:[\s.\-–]*\d)*/g;
export const PIN_MASK = "••••";

/**
 * The transcript as lines with text, and the tools Doddy called (by line). The caller's PIN is masked:
 * in the caller's turns before each `verify_pin` call (back to Doddy's previous spoken line), every digit run
 * becomes ••••, so the PIN reaches neither the model nor the recap.
 */
export function transcriptFrom(input: StoredInput): { lines: Line[]; tools: { line: number; name: string }[] } {
  const turns = input.turns.map((t) => ({ ...t }));
  for (let i = 0; i < turns.length; i++) {
    if (turns[i]!.role !== "doddy" || !turns[i]!.tools.includes("verify_pin")) continue;
    for (let j = i - 1; j >= 0; j--) {
      const t = turns[j]!;
      if (t.role === "doddy" && t.text.trim()) break;
      if (t.role === "caller") t.text = t.text.replace(DIGITS, PIN_MASK);
    }
  }
  const lines: Line[] = [];
  const tools: { line: number; name: string }[] = [];
  for (const t of turns) {
    const text = t.text.replace(/\s+/g, " ").trim().slice(0, LIMITS.lineChars);
    // A tool call belongs to the line Doddy says next (or the last one, at the end).
    for (const name of t.tools) tools.push({ line: text ? lines.length : Math.max(0, lines.length - 1), name });
    if (!text) continue;
    if (lines.length >= LIMITS.lines) break;
    lines.push({ speaker: t.role, text, atSecs: t.atSecs });
  }
  return { lines, tools: tools.filter((t) => t.line < Math.max(1, lines.length)) };
}

// ---------- checks ----------

/**
 * A claim that something was saved, stored or remembered. The recap lists notes itself, from the database;
 * the summary must not say anything was saved (only a confirmed note becomes a memory, in the app).
 */
const SAVE_CLAIM = /(?<!\p{L})(saved|stored|remembered|zapisa(?:ł|ła|łem|łam|ło|no|ne|ny|na|li|ły)|zapamięta(?:ł|ła|łem|łam|no|ne|ny|na|li|ły)|zachowa(?:ł|ła|no|ne|ny|na))(?!\p{L})/iu;
export const claimsSaving = (s: string) => SAVE_CLAIM.test(s);

const fold = (s: string) => s.normalize("NFKC").toLocaleLowerCase("pl").replace(/\s+/g, " ").trim();
const clean = (s: string | null | undefined, max: number) => {
  const t = (s ?? "").replace(/\s+/g, " ").trim();
  return t && t.length <= max ? t : null;
};

/** Keeps a pointer only when its line exists (and is Doddy's, if `doddyOnly`) and its quote is words from it. */
function checkPointers(items: Pointer[], lines: Line[], doddyOnly: boolean): { kept: Pointer[]; dropped: number } {
  const kept: Pointer[] = [];
  let dropped = 0;
  for (const item of items) {
    const line = lines[item.line];
    const text = clean(item.text, LIMITS.itemChars);
    const quote = clean(item.quote, LIMITS.quoteChars);
    const ok = Number.isInteger(item.line) && line && text && quote && (!doddyOnly || line.speaker === "doddy")
      && fold(line.text).includes(fold(quote)) && !claimsSaving(text) && kept.length < LIMITS.items;
    if (ok) kept.push({ text, line: item.line, quote });
    else dropped++;
  }
  return { kept, dropped };
}

export interface RecapFacts {
  callId: string;
  direction: "inbound" | "outbound";
  input: StoredInput | null;
  notes: RecapNote[];
  now: Date;
}

/** Builds the recap from the facts and, when there is one, the model's proposal. */
export function buildRecap(f: RecapFacts, writer: RecapWriterOutput | null, rulesReason: SummaryNote | null): CallRecap {
  const { lines } = f.input ? transcriptFrom(f.input) : { lines: [] as Line[] };
  const base: CallRecap = {
    format: 1,
    callId: f.callId,
    direction: f.direction,
    startedAt: f.input?.startUnix != null ? new Date(f.input.startUnix * 1000).toISOString() : null,
    durationSecs: f.input?.durationSecs ?? null,
    summary: null,
    summaryBy: "rules",
    summaryNote: rulesReason ?? (f.input ? "no_writer" : "transcript_unreadable"),
    language: null,
    agreed: [],
    couldNotDo: [],
    notes: f.notes,
    nextStep: null,
    transcript: lines,
    droppedPointers: 0,
    builtAt: f.now.toISOString(),
  };
  if (!writer) return base;
  const summary = clean(writer.summary, LIMITS.summaryChars);
  if (!summary) return { ...base, summaryNote: "unusable_summary" };
  if (claimsSaving(summary)) return { ...base, summaryNote: "save_claim" };
  const agreed = checkPointers(writer.agreed ?? [], lines, false);
  const couldNotDo = checkPointers(writer.couldNotDo ?? [], lines, true);
  const next = clean(writer.nextStep, LIMITS.nextStepChars);
  return {
    ...base,
    summary,
    summaryBy: "doddy_model",
    summaryNote: null,
    language: /^[a-z]{2}$/.test(writer.language ?? "") ? writer.language : null,
    agreed: agreed.kept,
    couldNotDo: couldNotDo.kept,
    nextStep: next && !claimsSaving(next) ? next : null,
    droppedPointers: agreed.dropped + couldNotDo.dropped,
  };
}

/** True when the caller said nothing: there is nothing to summarise. */
export const callerSpoke = (input: StoredInput) => transcriptFrom(input).lines.some((l) => l.speaker === "caller");
