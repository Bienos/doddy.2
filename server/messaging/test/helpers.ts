import { readFileSync } from "node:fs";
import { enforceDbGate } from "./dbGate.js";
import { buildApp, type Deps } from "../src/app.js";
import { DEFAULT_TASK_CALL_SETTINGS, type TaskCallSettings } from "../src/config.js";
import { createPool, migrate, type Db } from "../src/db.js";
import { TextCipher } from "../src/crypto.js";
import { twilioSignature } from "../src/providers/twilio.js";
import type {
  CallCreateOutcome, CallFetchOutcome, CallRecord, CallUpdate, CallUpdateOutcome, CreateCallParams, ElConversation,
  RegisterOutcome as ElRegisterOutcome, TaskTelephony, TaskVoice,
} from "../src/providers/taskCalls.js";
import type {
  CallOutcome, CallRegistrar, DeleteOutcome, OutboundCall, OutboundCaller, PhoneVerifier, PushData, PushSender, PushTarget, RecordDeleter,
  RegisterOutcome, SendOutcome, SmsSender, VerifyCheck,
} from "../src/providers/types.js";
import type { BriefInput } from "../src/taskCalls/brief.js";
import type { ResultWriter } from "../src/taskCalls/context.js";

export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
// In CI a missing database fails the run (throws here); locally it skips with one warning line.
enforceDbGate();
export const dbSkip = TEST_DATABASE_URL ? false : "TEST_DATABASE_URL not set (needs a disposable Postgres database)";

/**
 * Refuses a database that isn't plainly a disposable test one (engineering audit, 7 Nov 2026): freshDb
 * drops its whole public schema, so a TEST_DATABASE_URL pasted from a real service would wipe it. The
 * database's name must end in `_test` or `-test`, or be `test`, as CI's `doddy_test` does.
 */
export function assertDisposableTestDatabase(url: string): void {
  let name = "";
  try {
    name = decodeURIComponent(new URL(url).pathname.replace(/^\//, ""));
  } catch {
    name = "";
  }
  if (!/(^|[_-])test$/i.test(name)) {
    throw new Error(`TEST_DATABASE_URL must name a disposable database whose name ends in _test (it names "${name || "no database"}"): the tests drop its public schema`);
  }
}

/** Wipes the test database's public schema and re-applies migrations. */
export async function freshDb(): Promise<Db> {
  assertDisposableTestDatabase(TEST_DATABASE_URL!);
  const db = createPool(TEST_DATABASE_URL!);
  await db.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
  await migrate(db);
  return db;
}

// Test doubles stand in for Apple/Twilio only; database, HTTP layer and dispatcher are real.
export class FakePush implements PushSender {
  sent: { target: PushTarget; body: string; data?: PushData }[] = [];
  next: SendOutcome[] = [];
  async send(target: PushTarget, alert: { body: string }, messageId: string, data?: PushData): Promise<SendOutcome> {
    this.sent.push({ target, body: alert.body, ...(data ? { data } : {}) });
    return this.next.shift() ?? { kind: "accepted", providerId: messageId };
  }
}

export class FakeSms implements SmsSender {
  sent: { to: string; body: string }[] = [];
  next: SendOutcome[] = [];
  /** Twilio's message list for any number; undefined means Twilio couldn't be asked. */
  recent: { sid: string; body: string; createdAt: Date; status: string }[] | undefined = [];
  lookups: string[] = [];
  async send(to: string, body: string): Promise<SendOutcome> {
    this.sent.push({ to, body });
    return this.next.shift() ?? { kind: "accepted", providerId: `SM${this.sent.length}` };
  }
  async recentMessagesTo(to: string) {
    this.lookups.push(to);
    return this.recent;
  }
}

export class FakeVerifier implements PhoneVerifier {
  started: string[] = [];
  async start(to: string) { this.started.push(to); }
  async check(_to: string, code: string): Promise<VerifyCheck> {
    return code === "123456" ? "approved" : code === "000000" ? "expired_or_missing" : "wrong_code";
  }
}

/** Stands in for Twilio's Calls API. */
export class FakeOutbound implements OutboundCaller {
  calls: OutboundCall[] = [];
  next: CallOutcome[] = [];
  /** Twilio's CallSid is unique in the table (migration 017): tests that share a database and place calls from several
   * fakes give each its own prefix. The call-flow tests rely on the default "CAout" + the call's number. */
  constructor(private readonly prefix = "CAout") {}
  async placeCall(call: OutboundCall): Promise<CallOutcome> {
    this.calls.push(call);
    return this.next.shift() ?? { kind: "accepted", callSid: `${this.prefix}${this.calls.length}` };
  }
}

export const CONNECT_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="wss://agent.example.test"/></Connect></Response>';

/** Stands in for ElevenLabs register-call: records each call it is asked to connect. */
export class FakeRegistrar implements CallRegistrar {
  calls: Parameters<CallRegistrar["register"]>[0][] = [];
  next: RegisterOutcome[] = [];
  async register(call: Parameters<CallRegistrar["register"]>[0]): Promise<RegisterOutcome> {
    this.calls.push(call);
    return this.next.shift() ?? { kind: "twiml", twiml: CONNECT_TWIML };
  }
}

/** Stands in for Twilio's DELETE on a message or call record. */
export class FakeDeleter implements RecordDeleter {
  deleted: { kind: string; sid: string }[] = [];
  next: DeleteOutcome[] = [];
  async deleteRecord(kind: "message" | "call", sid: string): Promise<DeleteOutcome> {
    this.deleted.push({ kind, sid });
    return this.next.shift() ?? { kind: "deleted" };
  }
}

export const TOOL_SECRET = "test-tool-secret-0123456789";
export const testCipher = new TextCipher(Buffer.alloc(32, 7));

export const TWILIO_TOKEN = "test-auth-token";
export const BASE_URL = "https://doddy.example.test";

// ---------- task calls ----------

export const VALID_PESEL = "44051401359";

export function sampleBrief(over: Partial<BriefInput> = {}): BriefInput {
  return {
    kind: "ask",
    callee: { name: "Serwis Laptop", phone: "+48 22 123 45 67", source: "contacts", sourceLabel: "Serwis Laptop Mokotów" },
    principal: { name: "Anna", genitive: "Anny" },
    goal: "Dowiedzieć się, czy laptop oddany do naprawy jest gotowy do odbioru.",
    question: "Czy laptop z serwisu jest gotowy",
    facts: [{ kind: "reference", text: "Numer zlecenia 12345" }, { kind: "device", text: "Lenovo ThinkPad, oddany 10 października" }],
    ...over,
  };
}


export const TASK_ACCOUNT_SID = "AC" + "a".repeat(32);
export const TASK_AUTH_TOKEN = "task-auth-token";
export const TASK_AGENT_ID = "agent_task_test";
/** The booking agent's id in tests (decision 2026-11-12-book-agent). */
export const TASK_BOOK_AGENT_ID = "agent_task_book_test";
/** The order agent's id in tests (decision 2026-11-12-food-by-phone). */
export const TASK_ORDER_AGENT_ID = "agent_task_order_test";
export const EL_WEBHOOK_SECRET = "el-webhook-secret-0123456789";
export const DODDY_FROM = "+48221112233";
export const sidFor = (n: number) => "CA" + n.toString(16).padStart(32, "0");
// One counter for every fake: call SIDs are unique across apps sharing a test database.
let sidCounter = 0;

/** Stands in for Twilio's Calls API; records every request. */
export class FakeTelephony implements TaskTelephony {
  readonly accountSid = TASK_ACCOUNT_SID;
  created: CreateCallParams[] = [];
  updates: { sid: string; update: CallUpdate }[] = [];
  nextCreate: CallCreateOutcome[] = [];
  nextUpdate: CallUpdateOutcome[] = [];
  records = new Map<string, CallRecord>();
  async createCall(p: CreateCallParams): Promise<CallCreateOutcome> {
    this.created.push(p);
    return this.nextCreate.shift() ?? { kind: "accepted", sid: sidFor(++sidCounter) };
  }
  async updateCall(sid: string, update: CallUpdate): Promise<CallUpdateOutcome> {
    this.updates.push({ sid, update });
    return this.nextUpdate.shift() ?? { kind: "ok" };
  }
  async fetchCall(sid: string): Promise<CallFetchOutcome> {
    const r = this.records.get(sid);
    return r ? { kind: "ok", call: r } : { kind: "not_found" };
  }
}

export const EL_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response><Connect>'
  + '<Stream url="wss://api.elevenlabs.io/v1/convai/conversation/twilio?agent_id=agent_task_test">'
  + '<Parameter name="conversation_id" value="conv_live_1"/></Stream></Connect></Response>';

export const TASK_PROMPT = readFileSync(new URL("../../../../voice-agent/task-call/instructions.md", import.meta.url), "utf8").trim();
export const ORDER_PROMPT = readFileSync(new URL("../../../../voice-agent/task-call-order/instructions.md", import.meta.url), "utf8").trim();
export const BOOK_PROMPT = readFileSync(new URL("../../../../voice-agent/task-call-book/instructions.md", import.meta.url), "utf8").trim();

/** The live agent as the spec says it must be (shape read from a real agent on 2026-10-18). */
export function compliantAgent(prompt = TASK_PROMPT, agentId = TASK_AGENT_ID): Record<string, unknown> {
  return {
    agent_id: agentId,
    conversation_config: {
      asr: { user_input_audio_format: "ulaw_8000" },
      tts: { agent_output_audio_format: "ulaw_8000", model_id: "eleven_flash_v2_5" },
      conversation: { max_duration_seconds: 330 },
      agent: {
        first_message: "{{doddy_opening_line}}", language: "pl", disable_first_message_interruptions: true,
        prompt: {
          prompt, tool_ids: [], knowledge_base: [], mcp_server_ids: [], native_mcp_server_ids: [],
          built_in_tools: {
            end_call: { type: "system", name: "end_call", params: { system_tool_type: "end_call" } },
            voicemail_detection: { type: "system", name: "voicemail_detection", params: { system_tool_type: "voicemail_detection" } },
          },
        },
      },
    },
    platform_settings: {
      overrides: {
        conversation_config_override: { agent: { first_message: false, language: false, prompt: { prompt: false } }, tts: { voice_id: false } },
        custom_llm_extra_body: false, enable_conversation_initiation_client_data_from_webhook: false,
      },
      privacy: { record_voice: false, retention_days: 1 },
      auth: { enable_auth: true },
    },
  };
}

/** Stands in for ElevenLabs: register-call, conversations, the agent. */
export class FakeVoice implements TaskVoice {
  registered: { agentId: string; from: string; to: string; variables: Record<string, string> }[] = [];
  nextRegister: ElRegisterOutcome[] = [];
  conversations = new Map<string, ElConversation>();
  deleted: string[] = [];
  agent: unknown = compliantAgent();
  agentReads = 0;
  async registerCall(p: { agentId: string; from: string; to: string; variables: Record<string, string> }): Promise<ElRegisterOutcome> {
    this.registered.push(p);
    return this.nextRegister.shift() ?? { kind: "ok", twiml: EL_TWIML };
  }
  async getConversation(id: string) {
    const c = this.conversations.get(id);
    return c ? { kind: "ok" as const, conversation: c } : { kind: "not_found" as const };
  }
  async deleteConversation(id: string): Promise<"deleted" | "not_found" | "error"> {
    if (!this.conversations.has(id)) return "not_found";
    this.conversations.delete(id);
    this.deleted.push(id);
    return "deleted";
  }
  async listConversations(_agentId: string, before: number) {
    return [...this.conversations.values()]
      .filter((c) => (c.metadata.start_time_unix_secs ?? 0) < before)
      .map((c) => ({ id: c.conversation_id, startUnix: c.metadata.start_time_unix_secs ?? 0 }));
  }
  /** Per-agent answers (the booking agent); any other id gets `agent`. */
  agentsById = new Map<string, unknown>();
  async getAgent(agentId?: string): Promise<unknown> {
    this.agentReads++;
    return (agentId && this.agentsById.get(agentId)) ?? this.agent;
  }
}

export interface TaskTestOptions {
  settings?: Partial<TaskCallSettings>; writer?: ResultWriter; start?: string;
  /** Sets up the booking agent too, answering with this prompt (decision 2026-11-12-book-agent). */
  bookAgentPrompt?: string;
  /** Sets up the order agent too, answering with this prompt (decision 2026-11-12-food-by-phone). */
  orderAgentPrompt?: string;
}

/** The real app with task calls on, fake providers and a clock the test moves. */
export async function taskTestApp(db: Db, opts: TaskTestOptions = {}) {
  const telephony = new FakeTelephony();
  const voice = new FakeVoice();
  if (opts.bookAgentPrompt !== undefined) voice.agentsById.set(TASK_BOOK_AGENT_ID, compliantAgent(opts.bookAgentPrompt, TASK_BOOK_AGENT_ID));
  if (opts.orderAgentPrompt !== undefined) voice.agentsById.set(TASK_ORDER_AGENT_ID, compliantAgent(opts.orderAgentPrompt, TASK_ORDER_AGENT_ID));
  // Monday 19 Oct 2026, 11:00 in Warsaw.
  const clock = { now: new Date(opts.start ?? "2026-10-19T09:00:00Z") };
  const settings: TaskCallSettings = {
    ...DEFAULT_TASK_CALL_SETTINGS, ...opts.settings,
    limits: { ...DEFAULT_TASK_CALL_SETTINGS.limits, ...opts.settings?.limits },
    prices: { elevenLabsUsdPerCredit: 0.0001, transcriptionUsdPerMin: 0.05, ...opts.settings?.prices },
  };
  const logs: { msg: string; extra?: object }[] = [];
  const base = await testApp(db, {
    taskCalls: {
      telephony, voice, settings, writer: opts.writer, now: () => clock.now,
      config: {
        twilioAccountSid: TASK_ACCOUNT_SID, twilioAuthToken: TASK_AUTH_TOKEN, fromNumber: DODDY_FROM,
        elevenLabsApiKey: "test", agentId: TASK_AGENT_ID, webhookSecret: EL_WEBHOOK_SECRET,
        ...(opts.bookAgentPrompt !== undefined ? { bookAgentId: TASK_BOOK_AGENT_ID } : {}),
        ...(opts.orderAgentPrompt !== undefined ? { orderAgentId: TASK_ORDER_AGENT_ID } : {}),
      },
    },
    taskCallLog: (msg, extra) => logs.push({ msg, extra }),
    // Call-back routes are dated by the dial's clock, so the call-back that follows reads the same clock.
    now: () => clock.now,
  });
  return { ...base, telephony, voice, clock, settings, logs };
}

export async function testApp(db: Db, extra: Partial<Deps> = {}) {
  const push = new FakePush();
  const sms = new FakeSms();
  const verifier = new FakeVerifier();
  const outbound = new FakeOutbound();
  const registrar = new FakeRegistrar();
  const app = await buildApp({
    db, push, sms, verifier, outbound, registrar, cipher: testCipher, toolSecret: TOOL_SECRET,
    doddyPhoneNumber: DODDY_NUMBER, twilioAuthToken: TWILIO_TOKEN, publicBaseUrl: BASE_URL, logger: false,
    // The tests of other features make dozens of accounts from the one test address in a single database, so the
    // daily account cap per address (50 in production, ADR-702) would be a hidden limit on how many tests a file may
    // have. The tests of that cap pass their own `limits`.
    limits: { accountsPerIpDay: 100_000 },
    // Anonymous accounts are off by default (ANONYMOUS_ACCOUNTS, decision 2026-11-08-required-account). The tests of other
    // features make their accounts with `POST /v1/accounts`, so they keep the switch on; the tests of the switch itself
    // pass `anonymousAccounts: false` (test/accountQuotas.test.ts).
    anonymousAccounts: true,
    ...extra,
  });
  return { app, push, sms, verifier, outbound, registrar };
}

export const DODDY_NUMBER = "+48221234567";

/** A webhook request signed the way Twilio signs it (form body, X-Twilio-Signature). */
export function twilioRequest(url: string, form: Record<string, string>,
  signature = twilioSignature(TWILIO_TOKEN, BASE_URL + url, form)) {
  return {
    method: "POST" as const, url, payload: new URLSearchParams(form).toString(),
    headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": signature },
  };
}
