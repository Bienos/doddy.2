import type { AssistantSettings } from "../config.js";
import type { AssistantResponder } from "./responder.js";
import type { RecapWriter } from "./recap.js";

/** What Messages needs (ADR-586): the switches and caps, and the responder (an Anthropic key). Without a
 * responder or with the switch off, the route answers 503 notConfigured. */
export interface AssistantDeps {
  settings: AssistantSettings;
  responder?: AssistantResponder;
  /** Conversation recaps (decision 2026-11-09-conversation-recaps): same key, switch and caps as Messages. */
  recapWriter?: RecapWriter;
  /** How long one model call may take before the route answers timeout. Default 45 s. */
  timeoutMs?: number;
}
