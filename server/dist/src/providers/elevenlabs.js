import { ProviderError } from "./types.js";
/**
 * Issues a short-lived conversation token for the Doddy agent so the app never holds the
 * ElevenLabs API key. The agent must have authentication turned on for this to matter.
 */
export class ElevenLabsTokenIssuer {
    config;
    timeoutMs;
    constructor(config, timeoutMs = 10_000) {
        this.config = config;
        this.timeoutMs = timeoutMs;
    }
    async conversationToken() {
        const url = new URL("https://api.elevenlabs.io/v1/convai/conversation/token");
        url.searchParams.set("agent_id", this.config.agentId);
        const res = await fetch(url, {
            headers: { "xi-api-key": this.config.apiKey },
            signal: AbortSignal.timeout(this.timeoutMs),
        });
        if (!res.ok)
            throw new ProviderError("elevenlabs_token", res.status);
        const json = (await res.json());
        if (!json.token)
            throw new ProviderError("elevenlabs_token_missing", res.status);
        return json.token;
    }
}
/** Outbound calls through the Twilio number imported into ElevenLabs (native integration). */
export class ElevenLabsOutboundCaller {
    config;
    timeoutMs;
    constructor(config, timeoutMs = 15_000) {
        this.config = config;
        this.timeoutMs = timeoutMs;
    }
    async placeCall(toE164, dynamicVariables) {
        let res;
        try {
            res = await fetch("https://api.elevenlabs.io/v1/convai/twilio/outbound-call", {
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
        }
        catch {
            // The call may already be ringing; never retry automatically.
            return { kind: "unknown", code: "elevenlabs_network" };
        }
        const json = (await res.json().catch(() => ({})));
        if (res.ok && json.success)
            return { kind: "accepted", conversationId: json.conversation_id, callSid: json.callSid };
        return { kind: "rejected", code: `elevenlabs_${res.status}` };
    }
}
//# sourceMappingURL=elevenlabs.js.map