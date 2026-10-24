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
import type { AssistantDeps } from "../assistant/deps.js";
import { ClaudeAssistantResponder } from "../assistant/responder.js";
import { PoliteFetcher } from "../deals/fetcher.js";
import type { DealsDeps } from "../deals/service.js";
import { AnthropicDealsModel } from "../deals/vision.js";
import { log } from "../log.js";
import { AffiliateLinks } from "../shopping/affiliate.js";
import { SerperOfferSource } from "../shopping/offers.js";
import { RoutingErrandResearcher, ShoppingErrandResearcher } from "../shopping/runner.js";

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
  // One polite fetcher (robots.txt, DoddyBot user agent, blocks never worked around) for the shop pages
  // of shopping errands and for the leaflets (ADR-608, ADR-609).
  const fetcher = new PoliteFetcher();
  const es = config.errandSettings;
  const ss = config.shoppingSettings;
  // Shopping errands (ADR-607) go to the shopping runner; the rest to the research runner, as before.
  const errands: ErrandDeps = {
    settings: es,
    researcher: es.enabled && config.anthropicApiKey
      ? new RoutingErrandResearcher(
        new ClaudeErrandResearcher(config.anthropicApiKey, { model: es.model, effort: es.effort }),
        new ShoppingErrandResearcher(config.anthropicApiKey, {
          offers: new SerperOfferSource(ss.serperApiKey), fetcher,
          maxOfferSearches: ss.maxOfferSearches, maxPageChecks: ss.maxPageChecks,
          affiliate: new AffiliateLinks(ss.affiliateRules),
        }, { model: ss.model, effort: ss.effort, premiumModel: ss.premiumModel, premiumAccountIds: ss.premiumAccountIds }))
      : undefined,
  };
  // Leaflets (ADR-609): without an Anthropic key, Dino and Rossmann still answer from their own data
  // and Biedronka and Lidl come back failed.
  const ds = config.dealsSettings;
  const deals: DealsDeps = {
    settings: ds,
    fetcher,
    model: ds.enabled && config.anthropicApiKey ? new AnthropicDealsModel(config.anthropicApiKey, { model: ds.visionModel }) : undefined,
    log,
  };
  // Messages (ADR-586): a responder only with an Anthropic key and the switch on; otherwise the route
  // answers 503 notConfigured.
  const as = config.assistantSettings;
  const assistant: AssistantDeps = {
    settings: as,
    responder: as.enabled && config.anthropicApiKey
      ? new ClaudeAssistantResponder(config.anthropicApiKey, { model: as.model, effort: as.effort })
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
    assistant,
    deals,
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
