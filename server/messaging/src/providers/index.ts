import type { Config } from "../config.js";
import { ApnsPushSender } from "./apns.js";
import { TextCipher } from "../crypto.js";
import { ElevenLabsCallRegistrar } from "./elevenlabs.js";
import { TwilioClient, TwilioVoiceCaller } from "./twilio.js";
import { GNewsSearch, HttpFeedSource } from "../news/sources.js";
import { ClaudeDigestWriter, OpenAIDigestWriter } from "../news/writer.js";

/** Real provider adapters for whatever is configured; anything missing stays undefined. */
export function providersFrom(config: Config) {
  const twilio = config.twilio
    ? new TwilioClient(config.twilio, config.publicBaseUrl && `${config.publicBaseUrl}/webhooks/twilio/status`)
    : undefined;
  const cipher = config.memoryEncryptionKey ? TextCipher.fromBase64(config.memoryEncryptionKey) : undefined;
  return {
    push: config.apns ? new ApnsPushSender(config.apns) : undefined,
    sms: twilio,
    verifier: twilio,
    // Calls (ADR-490): Twilio places Doddy's calls; ElevenLabs connects answered calls to the agent.
    outbound: config.twilio ? new TwilioVoiceCaller(config.twilio) : undefined,
    registrar: config.phoneAgent ? new ElevenLabsCallRegistrar(config.phoneAgent) : undefined,
    cipher,
    news: {
      cipher,
      feeds: new HttpFeedSource(),
      search: config.gnewsApiKey ? new GNewsSearch(config.gnewsApiKey) : undefined,
      // Anthropic first when both keys are set; OpenAI otherwise (ADR-197).
      writer: config.anthropicApiKey ? new ClaudeDigestWriter(config.anthropicApiKey)
        : config.openaiApiKey ? new OpenAIDigestWriter(config.openaiApiKey, { model: config.openaiModel })
        : undefined,
    },
  };
}
