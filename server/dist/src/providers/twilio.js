import { createHmac, timingSafeEqual } from "node:crypto";
import { ProviderError } from "./types.js";
/** Twilio's request signature: base64(HMAC-SHA1(authToken, url + sorted key/value pairs)). */
export function twilioSignature(authToken, url, params) {
    const data = Object.keys(params).sort().reduce((acc, key) => {
        const v = params[key];
        const values = v === undefined ? [] : Array.isArray(v) ? [...v].sort() : [v];
        return acc + values.map((x) => key + x).join("");
    }, url);
    return createHmac("sha1", authToken).update(data, "utf8").digest("base64");
}
export function isValidTwilioSignature(authToken, url, params, header) {
    if (!header)
        return false;
    const expected = Buffer.from(twilioSignature(authToken, url, params));
    const given = Buffer.from(header);
    return expected.length === given.length && timingSafeEqual(expected, given);
}
export class TwilioClient {
    config;
    statusCallbackUrl;
    timeoutMs;
    auth;
    constructor(config, statusCallbackUrl, timeoutMs = 10_000) {
        this.config = config;
        this.statusCallbackUrl = statusCallbackUrl;
        this.timeoutMs = timeoutMs;
        this.auth = "Basic " + Buffer.from(`${config.accountSid}:${config.authToken}`).toString("base64");
    }
    post(url, form) {
        return fetch(url, {
            method: "POST",
            headers: { authorization: this.auth, "content-type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams(form),
            signal: AbortSignal.timeout(this.timeoutMs),
        });
    }
    async send(toE164, body) {
        const form = {
            To: toE164, MessagingServiceSid: this.config.messagingServiceSid, Body: body,
        };
        if (this.statusCallbackUrl)
            form.StatusCallback = this.statusCallbackUrl;
        let res;
        try {
            res = await this.post(`https://api.twilio.com/2010-04-01/Accounts/${this.config.accountSid}/Messages.json`, form);
        }
        catch {
            // The request may have reached Twilio; do not resend automatically.
            return { kind: "unknown", code: "twilio_network" };
        }
        const json = (await res.json().catch(() => ({})));
        if (res.status === 201 && json.sid)
            return { kind: "accepted", providerId: json.sid };
        const code = `twilio_${json.code ?? res.status}`;
        if (res.status === 429 || res.status >= 500)
            return { kind: "transient", code };
        // 21610: the recipient replied STOP to this sender.
        return { kind: "rejected", code, unsubscribed: json.code === 21610 };
    }
    async start(toE164) {
        const res = await this.post(`https://verify.twilio.com/v2/Services/${this.config.verifyServiceSid}/Verifications`, { To: toE164, Channel: "sms" });
        if (res.status !== 201) {
            const json = (await res.json().catch(() => ({})));
            throw new ProviderError(`twilio_verify_${json.code ?? res.status}`, res.status);
        }
    }
    async check(toE164, code) {
        const res = await this.post(`https://verify.twilio.com/v2/Services/${this.config.verifyServiceSid}/VerificationCheck`, { To: toE164, Code: code });
        if (res.status === 404)
            return "expired_or_missing";
        const json = (await res.json().catch(() => ({})));
        if (res.status === 200)
            return json.status === "approved" ? "approved" : "wrong_code";
        throw new ProviderError(`twilio_verify_${json.code ?? res.status}`, res.status);
    }
}
//# sourceMappingURL=twilio.js.map