import type { PhoneAgentConfig } from "../config.js";
import { connectTwiml } from "../voiceTwiml.js";
import type { CallRegistrar, RegisterOutcome } from "./types.js";

/**
 * Connects an answered Twilio call to the "Doddy (phone)" agent with ElevenLabs register-call
 * (ADR-490): the number stays on Doddy's Twilio account and this server decides who reaches the
 * agent. The call's variables, including the secret__ session key, travel in
 * conversation_initiation_client_data, as they did with ElevenLabs' own outbound-call API.
 */
export class ElevenLabsCallRegistrar implements CallRegistrar {
  constructor(
    private readonly config: PhoneAgentConfig,
    // Twilio waits 15 s for the voice webhook; leave room for the fixed sentence if this fails.
    private readonly timeoutMs = 5_000,
    private readonly baseURL = "https://api.elevenlabs.io",
  ) {}

  async register(call: Parameters<CallRegistrar["register"]>[0]): Promise<RegisterOutcome> {
    let res: Response;
    try {
      res = await fetch(`${this.baseURL}/v1/convai/twilio/register-call`, {
        method: "POST",
        headers: { "xi-api-key": this.config.apiKey, "content-type": "application/json" },
        body: JSON.stringify({
          agent_id: this.config.agentId,
          from_number: call.from,
          to_number: call.to,
          direction: call.direction,
          conversation_initiation_client_data: { dynamic_variables: call.variables },
        }),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch {
      return { kind: "failed", code: "elevenlabs_network" };
    }
    if (!res.ok) return { kind: "failed", code: `elevenlabs_${res.status}` };
    const twiml = connectTwiml(await res.text().catch(() => ""), res.headers.get("content-type"));
    return twiml ? { kind: "twiml", twiml } : { kind: "failed", code: "elevenlabs_bad_twiml" };
  }
}
