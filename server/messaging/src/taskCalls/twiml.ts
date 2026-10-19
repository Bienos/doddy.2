// TwiML for task calls. Every document is built here with escaping; nothing is spliced as text.
// ElevenLabs' register-call TwiML is parsed and accepted only in the one shape we expect (a single
// <Connect><Stream> to an ElevenLabs host), then rebuilt with live transcription in front of it.
import { XMLParser } from "fast-xml-parser";

const escapeXml = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");

type Attrs = Record<string, string | number | boolean | undefined>;

export function el(name: string, attrs: Attrs = {}, children: string | string[] = []): string {
  const a = Object.entries(attrs).filter(([, v]) => v !== undefined).map(([k, v]) => ` ${k}="${escapeXml(String(v))}"`).join("");
  const inner = Array.isArray(children) ? children.join("") : escapeXml(children);
  return inner ? `<${name}${a}>${inner}</${name}>` : `<${name}${a}/>`;
}

const doc = (...children: string[]) => `<?xml version="1.0" encoding="UTF-8"?>${el("Response", {}, children)}`;

export interface SayVoice { voice: string; language: "pl-PL" }
const say = (text: string, v: SayVoice) => el("Say", { language: v.language, voice: v.voice }, text);

/** A fixed Polish sentence, then hang up. Used for the apology, the goodbye and refusals. */
export const sayAndHangUp = (text: string, v: SayVoice) => doc(say(text, v), el("Hangup"));
export const hangUp = () => doc(el("Hangup"));

export const LIVE_TRANSCRIPTION_NAME = "doddy-live";

export interface AgentStream { url: string; attributes: Record<string, string>; parameters: { name: string; value: string }[] }

/** Accepts only `<Response><Connect><Stream url="wss://…elevenlabs.io/…">(<Parameter/>)*</Stream></Connect></Response>`. */
export function parseAgentTwiml(xml: string): AgentStream | undefined {
  let tree: unknown;
  try {
    tree = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "@_", parseAttributeValue: false, parseTagValue: false, trimValues: true })
      .parse(xml, true);
  } catch {
    return undefined;
  }
  const root = (tree as Record<string, unknown>)?.Response;
  if (!isObject(root) || !onlyKeys(root, ["Connect"])) return undefined;
  const connect = root.Connect;
  if (!isObject(connect) || !onlyKeys(connect, ["Stream"])) return undefined;
  const stream = connect.Stream;
  if (!isObject(stream) || !onlyKeys(stream, ["Parameter"])) return undefined;
  const url = stream["@_url"];
  if (typeof url !== "string" || !isElevenLabsSocket(url)) return undefined;
  const attributes: Record<string, string> = {};
  for (const [k, v] of Object.entries(stream)) {
    if (!k.startsWith("@_") || k === "@_url") continue;
    const name = k.slice(2);
    // Only plain attribute names with text values; ElevenLabs' own status callbacks are dropped.
    if (!/^[A-Za-z]{1,40}$/.test(name) || typeof v !== "string" || /^statusCallback/i.test(name)) return undefined;
    attributes[name] = v;
  }
  const raw = stream.Parameter === undefined ? [] : Array.isArray(stream.Parameter) ? stream.Parameter : [stream.Parameter];
  const parameters: { name: string; value: string }[] = [];
  for (const p of raw) {
    if (!isObject(p) || !onlyKeys(p, []) || typeof p["@_name"] !== "string" || typeof p["@_value"] !== "string") return undefined;
    if (Object.keys(p).some((k) => k !== "@_name" && k !== "@_value")) return undefined;
    parameters.push({ name: p["@_name"], value: p["@_value"] });
  }
  return { url, attributes, parameters };
}

function isElevenLabsSocket(url: string): boolean {
  try {
    const u = new URL(url);
    return u.protocol === "wss:" && (u.hostname === "elevenlabs.io" || u.hostname.endsWith(".elevenlabs.io")) && !u.username && !u.password;
  } catch {
    return false;
  }
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
/** Child elements (non-attribute keys) are only the allowed ones. */
const onlyKeys = (o: Record<string, unknown>, allowed: string[]) =>
  Object.keys(o).every((k) => k.startsWith("@_") || allowed.includes(k));

export interface AnswerUrls { transcription: string; connectEnded: string }

/** Live transcription of both sides, then the agent's stream; nothing after it but hanging up. */
export function agentAnswerTwiml(stream: AgentStream, urls: AnswerUrls): string {
  return doc(
    el("Start", {}, [el("Transcription", {
      name: LIVE_TRANSCRIPTION_NAME, track: "both_tracks", languageCode: "pl-PL", transcriptionEngine: "google",
      partialResults: false, inboundTrackLabel: "callee", outboundTrackLabel: "doddy",
      statusCallbackUrl: urls.transcription, statusCallbackMethod: "POST",
    })]),
    el("Connect", { action: urls.connectEnded, method: "POST" }, [
      el("Stream", { url: stream.url, ...stream.attributes }, stream.parameters.map((p) => el("Parameter", { name: p.name, value: p.value }))),
    ]),
    el("Hangup"),
  );
}

/** The callee's call when the user takes over: stop listening, say so, join the user in a conference. */
export function calleeHandoverTwiml(text: string, v: SayVoice, conference: string, statusUrl: string): string {
  return doc(
    el("Stop", {}, [el("Transcription", { name: LIVE_TRANSCRIPTION_NAME })]),
    say(text, v),
    el("Dial", {}, [conferenceNoun(conference, statusUrl)]),
    el("Hangup"),
  );
}

/** The user's leg: "Naciśnij 1, aby przejąć rozmowę." Nothing joins until they do. */
export function takeoverPromptTwiml(text: string, v: SayVoice, digitsUrl: string): string {
  return doc(el("Gather", { numDigits: 1, timeout: 8, action: digitsUrl, method: "POST", actionOnEmptyResult: true }, [say(text, v)]));
}

export const userJoinTwiml = (conference: string, statusUrl: string) => doc(el("Dial", {}, [conferenceNoun(conference, statusUrl)]), el("Hangup"));

function conferenceNoun(name: string, statusUrl: string): string {
  return el("Conference", {
    beep: false, startConferenceOnEnter: true, endConferenceOnExit: true, waitUrl: "",
    statusCallback: statusUrl, statusCallbackEvent: "start end join leave", statusCallbackMethod: "POST",
  }, name);
}
