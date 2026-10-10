import { createPrivateKey, sign } from "node:crypto";
import http2 from "node:http2";
const HOSTS = {
    production: "https://api.push.apple.com",
    sandbox: "https://api.sandbox.push.apple.com",
};
/** ES256 provider token for APNs (token-based auth). Apple accepts a token for up to 60 min. */
export function apnsJwt(teamId, keyId, key, nowSeconds) {
    const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
    const input = `${enc({ alg: "ES256", kid: keyId })}.${enc({ iss: teamId, iat: nowSeconds })}`;
    const signature = sign("sha256", Buffer.from(input), { key, dsaEncoding: "ieee-p1363" });
    return `${input}.${signature.toString("base64url")}`;
}
// Responses where the device token will never work again.
const GONE_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic", "ExpiredToken"]);
export class ApnsPushSender {
    config;
    timeoutMs;
    key;
    jwt;
    sessions = new Map();
    constructor(config, timeoutMs = 10_000) {
        this.config = config;
        this.timeoutMs = timeoutMs;
        this.key = createPrivateKey(config.privateKey);
    }
    token() {
        const now = Math.floor(Date.now() / 1000);
        // Refresh well inside Apple's 20–60 minute window.
        if (!this.jwt || now - this.jwt.issuedAt > 40 * 60) {
            this.jwt = { value: apnsJwt(this.config.teamId, this.config.keyId, this.key, now), issuedAt: now };
        }
        return this.jwt.value;
    }
    session(origin) {
        const existing = this.sessions.get(origin);
        if (existing && !existing.closed && !existing.destroyed)
            return existing;
        const s = http2.connect(origin);
        s.on("error", () => this.sessions.delete(origin));
        s.on("close", () => this.sessions.delete(origin));
        this.sessions.set(origin, s);
        return s;
    }
    async send(target, alert, messageId) {
        const payload = JSON.stringify({ aps: { alert, sound: "default" } });
        let s;
        try {
            s = this.session(HOSTS[target.environment]);
        }
        catch {
            return { kind: "transient", code: "apns_connect_failed" };
        }
        return new Promise((resolve) => {
            let status = 0;
            let data = "";
            let settled = false;
            const done = (o) => { if (!settled) {
                settled = true;
                resolve(o);
            } };
            const req = s.request({
                ":method": "POST",
                ":path": `/3/device/${target.deviceToken}`,
                authorization: `bearer ${this.token()}`,
                "apns-topic": this.config.bundleId,
                "apns-push-type": "alert",
                "apns-priority": "10",
                "apns-id": messageId,
                "content-type": "application/json",
            });
            req.setTimeout(this.timeoutMs, () => { req.close(); done({ kind: "unknown", code: "apns_timeout" }); });
            req.on("response", (h) => { status = Number(h[":status"]); });
            req.setEncoding("utf8");
            req.on("data", (chunk) => { data += chunk; });
            req.on("error", () => done({ kind: "unknown", code: "apns_stream_error" }));
            req.on("end", () => {
                if (status === 200)
                    return done({ kind: "accepted", providerId: messageId });
                let reason = "unknown";
                try {
                    reason = JSON.parse(data).reason ?? reason;
                }
                catch { /* empty body */ }
                if (status === 410 || GONE_REASONS.has(reason)) {
                    return done({ kind: "rejected", code: `apns_${reason}`, deviceGone: true });
                }
                if (status === 429 || status >= 500)
                    return done({ kind: "transient", code: `apns_${status}_${reason}` });
                done({ kind: "rejected", code: `apns_${status}_${reason}` });
            });
            req.end(payload);
        });
    }
    close() {
        for (const s of this.sessions.values())
            s.close();
    }
}
//# sourceMappingURL=apns.js.map