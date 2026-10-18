import { createHmac, timingSafeEqual } from "node:crypto";
import type { TwilioConfig } from "../config.js";
import {
  ProviderError, type CallOutcome, type OutboundCall, type OutboundCaller, type PhoneVerifier, type SendOutcome,
  type SmsSender, type VerifyCheck,
} from "./types.js";

type Params = Record<string, string | string[] | undefined>;

/** Twilio's request signature: base64(HMAC-SHA1(authToken, url + sorted key/value pairs)). */
export function twilioSignature(authToken: string, url: string, params: Params): string {
  const data = Object.keys(params).sort().reduce((acc, key) => {
    const v = params[key];
    const values = v === undefined ? [] : Array.isArray(v) ? [...v].sort() : [v];
    return acc + values.map((x) => key + x).join("");
  }, url);
  return createHmac("sha1", authToken).update(data, "utf8").digest("base64");
}

export function isValidTwilioSignature(authToken: string, url: string, params: Params, header: string | undefined): boolean {
  if (!header) return false;
  const expected = Buffer.from(twilioSignature(authToken, url, params));
  const given = Buffer.from(header);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

interface TwilioError { code?: number; message?: string }

const basicAuth = (c: Pick<TwilioConfig, "accountSid" | "authToken">) =>
  "Basic " + Buffer.from(`${c.accountSid}:${c.authToken}`).toString("base64");

export class TwilioClient implements SmsSender, PhoneVerifier {
  private readonly auth: string;

  constructor(
    private readonly config: TwilioConfig,
    private readonly statusCallbackUrl?: string,
    private readonly timeoutMs = 10_000,
  ) {
    this.auth = basicAuth(config);
  }

  private post(url: string, form: Record<string, string>): Promise<Response> {
    return fetch(url, {
      method: "POST",
      headers: { authorization: this.auth, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(form),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
  }

  async send(toE164: string, body: string): Promise<SendOutcome> {
    const form: Record<string, string> = {
      To: toE164, MessagingServiceSid: this.config.messagingServiceSid, Body: body,
    };
    if (this.statusCallbackUrl) form.StatusCallback = this.statusCallbackUrl;
    let res: Response;
    try {
      res = await this.post(
        `https://api.twilio.com/2010-04-01/Accounts/${this.config.accountSid}/Messages.json`, form);
    } catch {
      // The request may have reached Twilio; do not resend automatically.
      return { kind: "unknown", code: "twilio_network" };
    }
    const json = (await res.json().catch(() => ({}))) as TwilioError & { sid?: string };
    if (res.status === 201 && json.sid) return { kind: "accepted", providerId: json.sid };
    const code = `twilio_${json.code ?? res.status}`;
    if (res.status === 429 || res.status >= 500) return { kind: "transient", code };
    // 21610: the recipient replied STOP to this sender.
    return { kind: "rejected", code, unsubscribed: json.code === 21610 };
  }

  async start(toE164: string): Promise<void> {
    const res = await this.post(
      `https://verify.twilio.com/v2/Services/${this.config.verifyServiceSid}/Verifications`,
      { To: toE164, Channel: "sms" });
    if (res.status !== 201) {
      const json = (await res.json().catch(() => ({}))) as TwilioError;
      throw new ProviderError(`twilio_verify_${json.code ?? res.status}`, res.status);
    }
  }

  async check(toE164: string, code: string): Promise<VerifyCheck> {
    const res = await this.post(
      `https://verify.twilio.com/v2/Services/${this.config.verifyServiceSid}/VerificationCheck`,
      { To: toE164, Code: code });
    if (res.status === 404) return "expired_or_missing";
    const json = (await res.json().catch(() => ({}))) as TwilioError & { status?: string };
    if (res.status === 200) return json.status === "approved" ? "approved" : "wrong_code";
    throw new ProviderError(`twilio_verify_${json.code ?? res.status}`, res.status);
  }
}

/**
 * Doddy's calls to the user, from Doddy's own number (ADR-490). Twilio asks `answerUrl` for TwiML
 * when the user picks up, and reports each step to `statusCallbackUrl`. No recording is requested.
 */
export class TwilioVoiceCaller implements OutboundCaller {
  private readonly auth: string;

  constructor(
    private readonly config: Pick<TwilioConfig, "accountSid" | "authToken">,
    private readonly timeoutMs = 10_000,
    private readonly apiBase = "https://api.twilio.com",
  ) {
    this.auth = basicAuth(config);
  }

  async placeCall(call: OutboundCall): Promise<CallOutcome> {
    const form = new URLSearchParams({
      To: call.to, From: call.from, Url: call.answerUrl, Method: "POST",
      StatusCallback: call.statusCallbackUrl, StatusCallbackMethod: "POST",
      // Seconds to ring before Twilio reports no-answer.
      Timeout: "30",
    });
    for (const event of ["initiated", "ringing", "answered", "completed"]) form.append("StatusCallbackEvent", event);
    let res: Response;
    try {
      res = await fetch(`${this.apiBase}/2010-04-01/Accounts/${this.config.accountSid}/Calls.json`, {
        method: "POST",
        headers: { authorization: this.auth, "content-type": "application/x-www-form-urlencoded" },
        body: form,
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch {
      // The request may have reached Twilio and the phone may already be ringing: never redial.
      return { kind: "unknown", code: "twilio_network" };
    }
    const json = (await res.json().catch(() => ({}))) as TwilioError & { sid?: string };
    if (res.status === 201 && json.sid) return { kind: "accepted", callSid: json.sid };
    const code = `twilio_${json.code ?? res.status}`;
    // A server error can come after Twilio created the call, so it is unknown, not failed (DOD-09).
    if (res.status >= 500) return { kind: "unknown", code };
    return { kind: "rejected", code };
  }
}
