import type { PhoneAgentConfig } from "../config.js";
import { ProviderError, type CallOutcome, type OutboundCaller } from "./types.js";

/** Outbound calls through the Twilio number imported into ElevenLabs (native integration). */
export class ElevenLabsOutboundCaller implements OutboundCaller {
  constructor(
    private readonly config: PhoneAgentConfig,
    private readonly timeoutMs = 15_000,
    private readonly baseURL = "https://api.elevenlabs.io",
  ) {}

  async placeCall(toE164: string, dynamicVariables: Record<string, string>): Promise<CallOutcome> {
    let res: Response;
    try {
      res = await fetch(`${this.baseURL}/v1/convai/twilio/outbound-call`, {
        method: "POST",
        headers: { "xi-api-key": this.config.apiKey, "content-type": "application/json" },
        body: JSON.stringify({
          agent_id: this.config.agentId,
          agent_phone_number_id: this.config.phoneNumberId,
          to_number: toE164,
          conversation_initiation_client_data: { dynamic_variables: dynamicVariables },
        }),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch {
      // The call may already be ringing; never retry automatically.
      return { kind: "unknown", code: "elevenlabs_network" };
    }
    const json = (await res.json().catch(() => ({}))) as { success?: boolean; conversation_id?: string; callSid?: string };
    if (res.ok && json.success) return { kind: "accepted", conversationId: json.conversation_id, callSid: json.callSid };
    // A gateway error or timeout can arrive after the call is already ringing: unknown, not failed.
    if (res.status >= 500 || res.status === 408) return { kind: "unknown", code: `elevenlabs_${res.status}` };
    return { kind: "rejected", code: `elevenlabs_${res.status}` };
  }
}
