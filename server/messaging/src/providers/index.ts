import type { Config } from "../config.js";
import { ApnsPushSender } from "./apns.js";
import { TextCipher } from "../crypto.js";
import { ElevenLabsOutboundCaller } from "./elevenlabs.js";
import { TwilioClient } from "./twilio.js";
import { ElevenLabsTaskClient, TwilioCallClient } from "./taskCalls.js";
import { GNewsSearch, HttpFeedSource } from "../news/sources.js";
import { ClaudeDigestWriter, OpenAIDigestWriter } from "../news/writer.js";
import type { TaskCallDeps } from "../taskCalls/context.js";
import { ClaudeResultWriter } from "../taskCalls/writer.js";
import type { ErrandDeps } from "../errands/context.js";
import { ClaudeErrandResearcher } from "../errands/researcher.js";

/** Real provider adapters for whatever is configured; anything missing stays undefined. */
export function providersFrom(config: Config) {
  const twilio = config.twilio
    ? new TwilioClient(config.twilio, config.publicBaseUrl && `${config.publicBaseUrl}/webhooks/twilio/status`)
    : undefined;
  const cipher = config.memoryEncryptionKey ? TextCipher.fromBase64(config.memoryEncryptionKey) : undefined;
  const push = config.apns ? new ApnsPushSender(config.apns) : undefined;
  const t = config.taskCalls;
  const taskCalls: TaskCallDeps | undefined = t ? {
    telephony: new TwilioCallClient(t.twilioAccountSid, t.twilioAuthToken),
    voice: new ElevenLabsTaskClient(t.elevenLabsApiKey),
    config: t,
    settings: config.taskCallSettings,
    // Optional: points at the answer and writes the card's summary (Anthropic only; ADR-504).
    writer: config.anthropicApiKey ? new ClaudeResultWriter(config.anthropicApiKey) : undefined,
    liveActivity: push ? {
      update: async (token, env, state, end) => { await push.sendLiveActivity({ deviceToken: token, environment: env }, state, end); },
    } : undefined,
  } : undefined;
  // Errands (ADR-570): a researcher only with an Anthropic key and the switch on. Without
  // MEMORY_ENCRYPTION_KEY the routes answer 503 errands_disabled whatever is set here.
  const es = config.errandSettings;
  const errands: ErrandDeps = {
    settings: es,
    researcher: es.enabled && config.anthropicApiKey
      ? new ClaudeErrandResearcher(config.anthropicApiKey, { model: es.model, effort: es.effort })
      : undefined,
  };
  return {
    push,
    sms: twilio,
    verifier: twilio,
    outbound: config.phoneAgent ? new ElevenLabsOutboundCaller(config.phoneAgent) : undefined,
    cipher,
    taskCalls,
    errands,
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
