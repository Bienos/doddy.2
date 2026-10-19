// Provider adapters for call cases: Twilio places and steers the call; ElevenLabs is the voice.
// Same rule as the rest of the server: an answer we didn't get is "unknown", never success, and
// nothing that may have reached a provider is retried automatically. Error messages from
// providers are never logged or returned (Twilio's echo the number); only status and error codes.
import { z } from "zod";

// ---------- Twilio ----------

export interface CreateCallParams {
  to: string; from: string;
  url: string; fallbackUrl: string; statusCallback: string;
  timeLimitSecs: number; timeoutSecs: number;
}
export type CallCreateOutcome =
  | { kind: "accepted"; sid: string }
  | { kind: "rejected"; code: string }
  | { kind: "unknown"; code: string };
export type CallUpdateOutcome =
  | { kind: "ok" }
  | { kind: "not_in_progress" }
  | { kind: "rejected"; code: string }
  | { kind: "unknown"; code: string };
export interface CallRecord { status: string; durationSecs: number | null; price: string | null; priceUnit: string | null }
export interface CallUpdate { twiml?: string; status?: "completed" | "canceled"; timeLimitSecs?: number }
export type CallFetchOutcome = { kind: "ok"; call: CallRecord } | { kind: "not_found" } | { kind: "error"; code: string };

export interface TaskTelephony {
  readonly accountSid: string;
  createCall(p: CreateCallParams): Promise<CallCreateOutcome>;
  /** Redirect a live call to new TwiML, end it (completed; canceled while ringing), or change its time limit. */
  updateCall(sid: string, p: CallUpdate): Promise<CallUpdateOutcome>;
  fetchCall(sid: string): Promise<CallFetchOutcome>;
}

export class TwilioCallClient implements TaskTelephony {
  private readonly auth: string;

  constructor(readonly accountSid: string, authToken: string, private readonly timeoutMs = 10_000,
    private readonly baseURL = "https://api.twilio.com") {
    this.auth = "Basic " + Buffer.from(`${accountSid}:${authToken}`).toString("base64");
  }

  private url(path: string) { return `${this.baseURL}/2010-04-01/Accounts/${this.accountSid}${path}`; }

  async createCall(p: CreateCallParams): Promise<CallCreateOutcome> {
    const form = new URLSearchParams({
      To: p.to, From: p.from, Url: p.url, Method: "POST", FallbackUrl: p.fallbackUrl, FallbackMethod: "POST",
      StatusCallback: p.statusCallback, StatusCallbackMethod: "POST",
      Timeout: String(p.timeoutSecs), TimeLimit: String(p.timeLimitSecs), Record: "false",
    });
    for (const e of ["initiated", "ringing", "answered", "completed"]) form.append("StatusCallbackEvent", e);
    let res: Response;
    try {
      res = await fetch(this.url("/Calls.json"), {
        method: "POST", headers: { authorization: this.auth, "content-type": "application/x-www-form-urlencoded" },
        body: form, signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch {
      return { kind: "unknown", code: "twilio_network" }; // the call may already be ringing
    }
    const json = (await res.json().catch(() => ({}))) as { sid?: string; code?: number };
    if (res.status === 201 && typeof json.sid === "string" && /^CA[0-9a-f]{32}$/.test(json.sid)) return { kind: "accepted", sid: json.sid };
    if (res.status >= 500 || res.status === 408 || res.status === 429) return { kind: "unknown", code: `twilio_${json.code ?? res.status}` };
    return { kind: "rejected", code: `twilio_${json.code ?? res.status}` };
  }

  async updateCall(sid: string, p: CallUpdate): Promise<CallUpdateOutcome> {
    const form = new URLSearchParams();
    if (p.twiml) form.set("Twiml", p.twiml);
    if (p.status) form.set("Status", p.status);
    if (p.timeLimitSecs) form.set("TimeLimit", String(p.timeLimitSecs));
    let res: Response;
    try {
      res = await fetch(this.url(`/Calls/${sid}.json`), {
        method: "POST", headers: { authorization: this.auth, "content-type": "application/x-www-form-urlencoded" },
        body: form, signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch {
      return { kind: "unknown", code: "twilio_network" };
    }
    if (res.status === 200) return { kind: "ok" };
    const json = (await res.json().catch(() => ({}))) as { code?: number };
    // 21220: the call is not in progress (already ended), so it can't be redirected.
    if (json.code === 21220 || res.status === 404) return { kind: "not_in_progress" };
    if (res.status >= 500 || res.status === 429) return { kind: "unknown", code: `twilio_${json.code ?? res.status}` };
    return { kind: "rejected", code: `twilio_${json.code ?? res.status}` };
  }

  async fetchCall(sid: string): Promise<CallFetchOutcome> {
    let res: Response;
    try {
      res = await fetch(this.url(`/Calls/${sid}.json`), { headers: { authorization: this.auth }, signal: AbortSignal.timeout(this.timeoutMs) });
    } catch {
      return { kind: "error", code: "twilio_network" };
    }
    if (res.status === 404) return { kind: "not_found" };
    if (res.status !== 200) return { kind: "error", code: `twilio_${res.status}` };
    const j = (await res.json().catch(() => ({}))) as { status?: string; duration?: string | null; price?: string | null; price_unit?: string | null };
    return {
      kind: "ok",
      call: {
        status: typeof j.status === "string" ? j.status : "unknown",
        durationSecs: j.duration != null && /^\d+$/.test(j.duration) ? Number(j.duration) : null,
        price: typeof j.price === "string" ? j.price : null,
        priceUnit: typeof j.price_unit === "string" ? j.price_unit : null,
      },
    };
  }
}

// ---------- ElevenLabs ----------

const turn = z.object({
  role: z.string(),
  message: z.string().nullable().optional(),
  time_in_call_secs: z.number().nullable().optional(),
  tool_calls: z.array(z.object({ tool_name: z.string().nullable().optional() }).passthrough()).nullable().optional(),
}).passthrough();

/** The parts of a conversation (GET or post-call webhook) we use. Unknown fields are ignored. */
export const conversationSchema = z.object({
  agent_id: z.string(),
  conversation_id: z.string().min(1).max(128),
  status: z.string().optional(),
  transcript: z.array(turn).default([]),
  metadata: z.object({
    call_duration_secs: z.number().nullable().optional(),
    cost: z.number().nullable().optional(),
    termination_reason: z.string().nullable().optional(),
    start_time_unix_secs: z.number().nullable().optional(),
  }).passthrough().default({}),
  conversation_initiation_client_data: z.object({
    dynamic_variables: z.record(z.string(), z.unknown()).nullable().optional(),
  }).passthrough().nullable().optional(),
}).passthrough();
export type ElConversation = z.infer<typeof conversationSchema>;

export type RegisterOutcome = { kind: "ok"; twiml: string } | { kind: "failed"; code: string };

export interface TaskVoice {
  registerCall(p: { agentId: string; from: string; to: string; variables: Record<string, string> }): Promise<RegisterOutcome>;
  getConversation(id: string): Promise<{ kind: "ok"; conversation: ElConversation } | { kind: "not_found" } | { kind: "error"; code: string }>;
  deleteConversation(id: string): Promise<"deleted" | "not_found" | "error">;
  /** Conversations of one agent that started before a time, newest first (one page). */
  listConversations(agentId: string, startedBeforeUnix: number): Promise<{ id: string; startUnix: number }[] | "error">;
  getAgent(agentId: string): Promise<unknown | "error">;
}

export class ElevenLabsTaskClient implements TaskVoice {
  constructor(private readonly apiKey: string, private readonly timeoutMs = 10_000, private readonly baseURL = "https://api.elevenlabs.io") {}

  private request(method: string, path: string, body?: unknown, timeoutMs = this.timeoutMs): Promise<Response> {
    return fetch(`${this.baseURL}${path}`, {
      method,
      headers: { "xi-api-key": this.apiKey, ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeoutMs),
    });
  }

  async registerCall(p: { agentId: string; from: string; to: string; variables: Record<string, string> }): Promise<RegisterOutcome> {
    let res: Response;
    try {
      // Runs while the callee waits after picking up: a short limit, then the spoken apology.
      res = await this.request("POST", "/v1/convai/twilio/register-call", {
        agent_id: p.agentId, from_number: p.from, to_number: p.to, direction: "outbound",
        conversation_initiation_client_data: { dynamic_variables: p.variables },
      }, 5_000);
    } catch {
      return { kind: "failed", code: "elevenlabs_network" };
    }
    if (!res.ok) return { kind: "failed", code: `elevenlabs_${res.status}` };
    const text = await res.text().catch(() => "");
    // Documented as TwiML; some clients see it as a JSON-encoded string.
    let twiml = text.trim();
    if (twiml.startsWith("\"")) {
      try { twiml = String(JSON.parse(twiml)); } catch { return { kind: "failed", code: "elevenlabs_unreadable" }; }
    }
    if (!twiml.includes("<Response")) return { kind: "failed", code: "elevenlabs_unreadable" };
    return { kind: "ok", twiml };
  }

  async getConversation(id: string) {
    let res: Response;
    try {
      res = await this.request("GET", `/v1/convai/conversations/${encodeURIComponent(id)}`);
    } catch {
      return { kind: "error" as const, code: "elevenlabs_network" };
    }
    if (res.status === 404) return { kind: "not_found" as const };
    if (!res.ok) return { kind: "error" as const, code: `elevenlabs_${res.status}` };
    const parsed = conversationSchema.safeParse(await res.json().catch(() => undefined));
    return parsed.success ? { kind: "ok" as const, conversation: parsed.data } : { kind: "error" as const, code: "elevenlabs_unreadable" };
  }

  async deleteConversation(id: string): Promise<"deleted" | "not_found" | "error"> {
    try {
      const res = await this.request("DELETE", `/v1/convai/conversations/${encodeURIComponent(id)}`);
      if (res.ok) return "deleted";
      if (res.status === 404) return "not_found";
      return "error";
    } catch {
      return "error";
    }
  }

  async listConversations(agentId: string, startedBeforeUnix: number) {
    try {
      const q = new URLSearchParams({ agent_id: agentId, page_size: "100", call_start_before_unix: String(startedBeforeUnix) });
      const res = await this.request("GET", `/v1/convai/conversations?${q}`);
      if (!res.ok) return "error" as const;
      const j = (await res.json().catch(() => ({}))) as { conversations?: { conversation_id?: unknown; start_time_unix_secs?: unknown }[] };
      return (j.conversations ?? []).flatMap((c) =>
        typeof c.conversation_id === "string" && typeof c.start_time_unix_secs === "number"
          ? [{ id: c.conversation_id, startUnix: c.start_time_unix_secs }] : []);
    } catch {
      return "error" as const;
    }
  }

  async getAgent(agentId: string): Promise<unknown | "error"> {
    try {
      const res = await this.request("GET", `/v1/convai/agents/${encodeURIComponent(agentId)}`);
      return res.ok ? await res.json() : "error";
    } catch {
      return "error";
    }
  }
}
