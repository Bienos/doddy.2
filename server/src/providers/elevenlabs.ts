import type { ElevenLabsConfig } from "../config.js";
import { ProviderError, type VoiceTokenIssuer } from "./types.js";

/**
 * Issues a short-lived conversation token for the Doddy agent so the app never holds the
 * ElevenLabs API key. The agent must have authentication turned on for this to matter.
 */
export class ElevenLabsTokenIssuer implements VoiceTokenIssuer {
  constructor(private readonly config: ElevenLabsConfig, private readonly timeoutMs = 10_000) {}

  async conversationToken(): Promise<string> {
    const url = new URL("https://api.elevenlabs.io/v1/convai/conversation/token");
    url.searchParams.set("agent_id", this.config.agentId);
    const res = await fetch(url, {
      headers: { "xi-api-key": this.config.apiKey },
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!res.ok) throw new ProviderError("elevenlabs_token", res.status);
    const json = (await res.json()) as { token?: string };
    if (!json.token) throw new ProviderError("elevenlabs_token_missing", res.status);
    return json.token;
  }
}
