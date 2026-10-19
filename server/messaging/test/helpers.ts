import { readFileSync } from "node:fs";
import { buildApp, type Deps } from "../src/app.js";
import { DEFAULT_TASK_CALL_SETTINGS, type TaskCallSettings } from "../src/config.js";
import { createPool, migrate, type Db } from "../src/db.js";
import { TextCipher } from "../src/crypto.js";
import type {
  CallCreateOutcome, CallFetchOutcome, CallRecord, CallUpdate, CallUpdateOutcome, CreateCallParams, ElConversation,
  RegisterOutcome, TaskTelephony, TaskVoice,
} from "../src/providers/taskCalls.js";
import type {
  CallOutcome, OutboundCaller, PhoneVerifier, PushSender, PushTarget, SendOutcome, SmsSender, VerifyCheck,
} from "../src/providers/types.js";
import type { BriefInput } from "../src/taskCalls/brief.js";
import type { ResultWriter } from "../src/taskCalls/context.js";

export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
export const dbSkip = TEST_DATABASE_URL ? false : "TEST_DATABASE_URL not set (needs a disposable Postgres database)";

/** Wipes the test database's public schema and re-applies migrations. */
export async function freshDb(): Promise<Db> {
  const db = createPool(TEST_DATABASE_URL!);
  await db.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
  await migrate(db);
  return db;
}

// Test doubles stand in for Apple/Twilio only; database, HTTP layer and dispatcher are real.
export class FakePush implements PushSender {
  sent: { target: PushTarget; body: string }[] = [];
  next: SendOutcome[] = [];
  async send(target: PushTarget, alert: { body: string }, messageId: string): Promise<SendOutcome> {
    this.sent.push({ target, body: alert.body });
    return this.next.shift() ?? { kind: "accepted", providerId: messageId };
  }
}

export class FakeSms implements SmsSender {
  sent: { to: string; body: string }[] = [];
  next: SendOutcome[] = [];
  async send(to: string, body: string): Promise<SendOutcome> {
    this.sent.push({ to, body });
    return this.next.shift() ?? { kind: "accepted", providerId: `SM${this.sent.length}` };
  }
}

export class FakeVerifier implements PhoneVerifier {
  started: string[] = [];
  async start(to: string) { this.started.push(to); }
  async check(_to: string, code: string): Promise<VerifyCheck> {
    return code === "123456" ? "approved" : code === "000000" ? "expired_or_missing" : "wrong_code";
  }
}

export class FakeOutbound implements OutboundCaller {
  calls: { to: string; variables: Record<string, string> }[] = [];
  next: CallOutcome[] = [];
  async placeCall(to: string, variables: Record<string, string>): Promise<CallOutcome> {
    this.calls.push({ to, variables });
    return this.next.shift() ?? { kind: "accepted", conversationId: `conv_${this.calls.length}`, callSid: "CA1" };
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

const TASK_PROMPT = readFileSync(new URL("../../../../voice-agent/task-call/instructions.md", import.meta.url), "utf8").trim();

/** The live agent as the spec says it must be (shape read from a real agent on 2026-10-18). */
export function compliantAgent(): Record<string, unknown> {
  return {
    agent_id: TASK_AGENT_ID,
    conversation_config: {
      asr: { user_input_audio_format: "ulaw_8000" },
      tts: { agent_output_audio_format: "ulaw_8000", model_id: "eleven_flash_v2_5" },
      conversation: { max_duration_seconds: 330 },
      agent: {
        first_message: "{{doddy_opening_line}}", language: "pl", disable_first_message_interruptions: true,
        prompt: {
          prompt: TASK_PROMPT, tool_ids: [], knowledge_base: [], mcp_server_ids: [], native_mcp_server_ids: [],
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
  nextRegister: RegisterOutcome[] = [];
  conversations = new Map<string, ElConversation>();
  deleted: string[] = [];
  agent: unknown = compliantAgent();
  agentReads = 0;
  async registerCall(p: { agentId: string; from: string; to: string; variables: Record<string, string> }): Promise<RegisterOutcome> {
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
  async getAgent(): Promise<unknown> {
    this.agentReads++;
    return this.agent;
  }
}

export interface TaskTestOptions { settings?: Partial<TaskCallSettings>; writer?: ResultWriter; start?: string }

/** The real app with task calls on, fake providers and a clock the test moves. */
export async function taskTestApp(db: Db, opts: TaskTestOptions = {}) {
  const telephony = new FakeTelephony();
  const voice = new FakeVoice();
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
      },
    },
    taskCallLog: (msg, extra) => logs.push({ msg, extra }),
  });
  return { ...base, telephony, voice, clock, settings, logs };
}

export async function testApp(db: Db, extra: Partial<Deps> = {}) {
  const push = new FakePush();
  const sms = new FakeSms();
  const verifier = new FakeVerifier();
  const outbound = new FakeOutbound();
  const app = await buildApp({
    db, push, sms, verifier, outbound, cipher: testCipher, toolSecret: TOOL_SECRET, doddyPhoneNumber: "+48221234567",
    twilioAuthToken: TWILIO_TOKEN, publicBaseUrl: BASE_URL, logger: false, ...extra,
  });
  return { app, push, sms, verifier, outbound };
}
