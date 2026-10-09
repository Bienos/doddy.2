import { GatewayError } from "./errors.mjs";

const MAX_ANSWER_SCALARS = 2000;

/**
 * Parses the model reply and checks its citations against the note ids that were actually sent.
 * A citation to any id outside that set fails the whole reply (docs/architecture/AI_RUNTIME.md).
 */
export function verifyModelReply(rawText, submittedNoteIds) {
  let parsed;
  try {
    parsed = JSON.parse(rawText);
  } catch {
    throw new GatewayError("invalidResponse");
  }

  if (!parsed || typeof parsed !== "object") throw new GatewayError("invalidResponse");
  if (typeof parsed.answer !== "string") throw new GatewayError("invalidResponse");
  if (!Array.isArray(parsed.citedIds) || !parsed.citedIds.every((id) => typeof id === "string")) {
    throw new GatewayError("invalidResponse");
  }

  const allowed = new Set(submittedNoteIds);
  if (parsed.citedIds.some((id) => !allowed.has(id))) throw new GatewayError("invalidCitations");

  const answer = [...parsed.answer].slice(0, MAX_ANSWER_SCALARS).join("");
  return { answer, citedIds: [...new Set(parsed.citedIds)] };
}
