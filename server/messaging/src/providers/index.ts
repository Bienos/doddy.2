import type { Config } from "../config.js";
import { ApnsPushSender } from "./apns.js";
import { TextCipher } from "../crypto.js";
import { ClaudeTextReplyWriter } from "./claudeReplies.js";
import { ElevenLabsCallRegistrar } from "./elevenlabs.js";
import { deleteAfterMinutes } from "../providerRecords.js";
import { TwilioClient, TwilioVoiceCaller } from "./twilio.js";
import { GNewsSearch, HttpFeedSource } from "../news/sources.js";
import { callsAvailable } from "../routes/twilioVoice.js";
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
    // Replies to the user's texts: Claude only (owner decision 7), never the OpenAI fallback.
    replyWriter: config.anthropicApiKey
      ? new ClaudeTextReplyWriter({ apiKey: config.anthropicApiKey, model: config.textReplyModel }) : undefined,
    // Doddy's message and call records at Twilio are deleted this long after they are final.
    deleter: twilio,
    deleteAfterMinutes: deleteAfterMinutes(config.twilioRecordDeleteAfterHours),
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

/**
 * What the worker needs to place scheduled calls (ADR-495), only when calls are fully set up (the
 * same test as the API's). Without it a due call fails, and the user is told, instead of ringing
 * into a call nobody can answer.
 */
export function scheduledCallsFrom(config: Config, providers: ReturnType<typeof providersFrom>) {
  const ready = callsAvailable({
    ...providers, toolSecret: config.toolSecret, twilioAuthToken: config.twilio?.authToken,
    publicBaseUrl: config.publicBaseUrl, doddyPhoneNumber: config.doddyPhoneNumber,
  }).outbound;
  return ready
    ? { outbound: providers.outbound, doddyPhoneNumber: config.doddyPhoneNumber, publicBaseUrl: config.publicBaseUrl, quietHours: config.quietHours }
    : undefined;
}
