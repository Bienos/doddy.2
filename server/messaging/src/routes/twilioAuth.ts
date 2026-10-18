import type { FastifyReply, FastifyRequest } from "fastify";
import type { Deps } from "../app.js";
import { isValidTwilioSignature } from "../providers/twilio.js";

export type TwilioForm = Record<string, string | string[] | undefined>;

export const formValue = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";

/**
 * Rejects anything not signed by Twilio (403), and answers 503 when the server can't check
 * signatures (no auth token or public URL); for calls, Twilio then plays the number's fallback.
 * Returns the form fields of a valid request.
 */
export function verifiedTwilioForm(
  deps: Pick<Deps, "twilioAuthToken" | "publicBaseUrl">, req: FastifyRequest, reply: FastifyReply,
): TwilioForm | undefined {
  if (!deps.twilioAuthToken || !deps.publicBaseUrl) {
    void reply.code(503).send({ error: "not_configured" });
    return undefined;
  }
  const form = (req.body ?? {}) as TwilioForm;
  const sig = req.headers["x-twilio-signature"];
  if (!isValidTwilioSignature(deps.twilioAuthToken, deps.publicBaseUrl + req.url, form,
    typeof sig === "string" ? sig : undefined)) {
    void reply.code(403).send({ error: "bad_signature" });
    return undefined;
  }
  return form;
}
