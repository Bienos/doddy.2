import type { Config } from "../config.js";
import { ApnsPushSender } from "./apns.js";
import { TextCipher } from "../crypto.js";
import { ElevenLabsOutboundCaller, ElevenLabsTokenIssuer } from "./elevenlabs.js";
import { TwilioClient } from "./twilio.js";
import { GNewsSearch, HttpFeedSource } from "../news/sources.js";
import { ClaudeDigestWriter } from "../news/writer.js";

/** Real provider adapters for whatever is configured; anything missing stays undefined. */
export function providersFrom(config: Config) {
  const twilio = config.twilio
    ? new TwilioClient(config.twilio, config.publicBaseUrl && `${config.publicBaseUrl}/webhooks/twilio/status`)
    : undefined;
  return {
    push: config.apns ? new ApnsPushSender(config.apns) : undefined,
    sms: twilio,
    verifier: twilio,
    voice: config.elevenLabs ? new ElevenLabsTokenIssuer(config.elevenLabs) : undefined,
    outbound: config.phoneAgent ? new ElevenLabsOutboundCaller(config.phoneAgent) : undefined,
    cipher: config.memoryEncryptionKey ? TextCipher.fromBase64(config.memoryEncryptionKey) : undefined,
    news: {
      feeds: new HttpFeedSource(),
      search: config.gnewsApiKey ? new GNewsSearch(config.gnewsApiKey) : undefined,
      writer: config.anthropicApiKey ? new ClaudeDigestWriter(config.anthropicApiKey) : undefined,
    },
  };
}
