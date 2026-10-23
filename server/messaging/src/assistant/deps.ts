import type { AssistantSettings } from "../config.js";
import type { AssistantResponder } from "./responder.js";

/** What Messages needs (ADR-586): the switches and caps, and the responder (an Anthropic key). Without a
 * responder or with the switch off, the route answers 503 notConfigured. */
export interface AssistantDeps {
  settings: AssistantSettings;
  responder?: AssistantResponder;
  /** How long one model call may take before the route answers timeout. Default 45 s. */
  timeoutMs?: number;
}
