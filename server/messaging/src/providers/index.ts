import type { Config } from "../config.js";
import { ApnsPushSender } from "./apns.js";
import { TextCipher } from "../crypto.js";
import { ElevenLabsCallRegistrar } from "./elevenlabs.js";
import { deleteAfterMinutes } from "../providerRecords.js";
import { TwilioClient, TwilioVoiceCaller } from "./twilio.js";
import { ElevenLabsTaskClient, TwilioCallClient } from "./taskCalls.js";
import { GNewsSearch, HttpFeedSource } from "../news/sources.js";
import { callsAvailable } from "../routes/twilioVoice.js";
import { ClaudeDigestWriter, OpenAIDigestWriter } from "../news/writer.js";
import type { TaskCallDeps } from "../taskCalls/context.js";
import { ClaudeResultWriter } from "../taskCalls/writer.js";
import type { ErrandDeps } from "../errands/context.js";
import { ClaudeErrandResearcher } from "../errands/researcher.js";
import type { StudioDeps } from "../studio/context.js";
import { AnthropicStudioApi, parseSkills } from "../studio/model.js";
import { modelLabel } from "../studio/models.js";
import type { AssistantDeps } from "../assistant/deps.js";
import { ClaudeAssistantResponder } from "../assistant/responder.js";
import { PoliteFetcher } from "../deals/fetcher.js";
import type { DealsDeps } from "../deals/service.js";
import { CeidgClient } from "../registry/ceidg.js";
import { AnthropicDealsModel } from "../deals/vision.js";
import { log } from "../log.js";
import { AffiliateLinks } from "../shopping/affiliate.js";
import { SerperOfferSource } from "../shopping/offers.js";
import { RoutingErrandResearcher, ShoppingErrandResearcher } from "../shopping/runner.js";
import type { WatchDeps } from "../watches/context.js";

/**
 * The APNs sender, or undefined. A key that can't be read (APNS_PRIVATE_KEY pasted as the Key ID, or cut short)
 * must not stop the whole server: push stays off, the startup line says `push: false`, and one line says why.
 * Only the error's code is logged, never the key. Exported for the tests.
 */
export function pushSenderFrom(
  apns: Config["apns"],
  make: (c: NonNullable<Config["apns"]>) => ApnsPushSender = (c) => new ApnsPushSender(c),
  report: typeof log = log,
): ApnsPushSender | undefined {
  if (!apns) return undefined;
  try {
    return make(apns);
  } catch (e) {
    const code = (e as { code?: unknown }).code;
    report("push off: APNS_PRIVATE_KEY is not a readable private key; paste the whole .p8 text, from its BEGIN line to its END line", {
      error: typeof code === "string" ? code : "unreadable_key",
    });
    return undefined;
  }
}

/** Real provider adapters for whatever is configured; anything missing stays undefined. */
export function providersFrom(config: Config) {
  const twilio = config.twilio
    ? new TwilioClient(config.twilio, config.publicBaseUrl && `${config.publicBaseUrl}/webhooks/twilio/status`)
    : undefined;
  const cipher = config.memoryEncryptionKey ? TextCipher.fromBase64(config.memoryEncryptionKey) : undefined;
  const push = pushSenderFrom(config.apns);
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
    smsCaps: { perAccount: config.limits.smsPerAccountDay, perServer: config.limits.smsPerServerDay },
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
        new ClaudeErrandResearcher(config.anthropicApiKey, { model: es.model, effort: es.effort, budget: es.budget }),
        new ShoppingErrandResearcher(config.anthropicApiKey, {
          offers: new SerperOfferSource(ss.serperApiKey), fetcher,
          maxOfferSearches: ss.maxOfferSearches, maxPageChecks: ss.maxPageChecks,
          affiliate: new AffiliateLinks(ss.affiliateRules),
          budget: es.budget,
        }, { model: ss.model, effort: ss.effort, premiumModel: ss.premiumModel, premiumAccountIds: ss.premiumAccountIds, budget: es.budget }))
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
    // ADR-666: the same partner rules as shopping errands (ADR-612), added after the picks.
    further: { shops: config.dealsSearchShops, affiliate: new AffiliateLinks(ss.affiliateRules) },
    // ADR-668: the same rules for the offers' own pages (a shop's product page), after the picks.
    affiliate: new AffiliateLinks(ss.affiliateRules),
  };
  // Price watches (shopping stage 2): the same polite fetcher reads the pages; no model and no other key is
  // involved. Without MEMORY_ENCRYPTION_KEY or WATCHES_ENABLED=1 the routes answer 503 watches_disabled.
  const watches: WatchDeps = { settings: config.watchSettings, fetcher };
  // Messages (ADR-586): a responder only with an Anthropic key and the switch on; otherwise the route
  // answers 503 notConfigured.
  const as = config.assistantSettings;
  const assistant: AssistantDeps = {
    settings: as,
    responder: as.enabled && config.anthropicApiKey
      ? new ClaudeAssistantResponder(config.anthropicApiKey, { model: as.model, effort: as.effort })
      : undefined,
  };
  // Studio (ADR-740): the model API only with an Anthropic key, the switch on (STUDIO_ENABLED, default 0) and Doddy's
  // skills. The key is read from the server's environment only (rule 6): nothing here or in the app holds one.
  const sts = config.studioSettings;
  const skills = parseSkills(sts.skills);
  const studio: StudioDeps = {
    settings: sts,
    api: sts.enabled && config.anthropicApiKey && skills.length
      ? new AnthropicStudioApi(config.anthropicApiKey, {
        models: sts.models, modelLabel: modelLabel(sts.models), skills, maxSearches: sts.maxSearches, maxFetches: sts.maxFetches,
        blockedDomains: sts.blockedDomains, taskBudgetTokens: sts.taskBudgetTokens,
      })
      : undefined,
  };
  return {
    push,
    sms: twilio,
    // Deletes phone-agent conversations queued at account deletion when task calls (and their worker) are off.
    phoneAgentVoice: config.phoneAgent ? new ElevenLabsTaskClient(config.phoneAgent.apiKey) : undefined,
    verifier: twilio,
    // Calls (ADR-750): Twilio places Doddy's calls; ElevenLabs connects answered calls to the agent.
    outbound: config.twilio ? new TwilioVoiceCaller(config.twilio) : undefined,
    registrar: config.phoneAgent ? new ElevenLabsCallRegistrar(config.phoneAgent) : undefined,
    cipher,
    taskCalls,
    errands,
    studio,
    assistant,
    deals,
    // ADR-685: CEIDG only with the owner's token; the route answers 503 registry_disabled otherwise.
    ceidg: config.ceidg ? new CeidgClient(config.ceidg) : undefined,
    watches,
    // Doddy's message and call records at Twilio are deleted this long after they are final (ADR-753).
    deleter: twilio,
    deleteAfterMinutes: deleteAfterMinutes(config.twilioRecordDeleteAfterHours),
    // Account, verification, text and call caps and the allowed countries (ADR-702, ADR-704): the web service and the
    // worker read the same settings.
    limits: config.limits,
    news: {
      cipher,
      smsCaps: { perAccount: config.limits.smsPerAccountDay, perServer: config.limits.smsPerServerDay },
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
 * What the worker needs to place scheduled calls (ADR-754), only when calls are fully set up (the
 * same test as the API's). Without it a due call fails, and the user is told, instead of ringing
 * into a call nobody can answer.
 */
export function scheduledCallsFrom(config: Config, providers: ReturnType<typeof providersFrom>) {
  const ready = callsAvailable({
    ...providers, toolSecret: config.toolSecret, twilioAuthToken: config.twilio?.authToken,
    publicBaseUrl: config.publicBaseUrl, doddyPhoneNumber: config.doddyPhoneNumber,
  }).outbound;
  return ready
    ? {
      outbound: providers.outbound, doddyPhoneNumber: config.doddyPhoneNumber, publicBaseUrl: config.publicBaseUrl,
      quietHours: config.quietHours, limits: config.limits,
    }
    : undefined;
}
