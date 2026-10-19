import { createPrivateKey, sign, type KeyObject } from "node:crypto";
import http2 from "node:http2";
import type { ApnsConfig } from "../config.js";
import type { PushSender, PushTarget, SendOutcome } from "./types.js";

const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

/** ES256 provider token for APNs (token-based auth). Apple accepts a token for up to 60 min. */
export function apnsJwt(teamId: string, keyId: string, key: KeyObject, nowSeconds: number): string {
  const enc = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const input = `${enc({ alg: "ES256", kid: keyId })}.${enc({ iss: teamId, iat: nowSeconds })}`;
  const signature = sign("sha256", Buffer.from(input), { key, dsaEncoding: "ieee-p1363" });
  return `${input}.${signature.toString("base64url")}`;
}

// Responses where the device token will never work again.
const GONE_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic", "ExpiredToken"]);

export class ApnsPushSender implements PushSender {
  private readonly key: KeyObject;
  private jwt?: { value: string; issuedAt: number };
  private readonly sessions = new Map<string, http2.ClientHttp2Session>();

  constructor(private readonly config: ApnsConfig, private readonly timeoutMs = 10_000) {
    this.key = createPrivateKey(config.privateKey);
  }

  private token(): string {
    const now = Math.floor(Date.now() / 1000);
    // Refresh well inside Apple's 20–60 minute window.
    if (!this.jwt || now - this.jwt.issuedAt > 40 * 60) {
      this.jwt = { value: apnsJwt(this.config.teamId, this.config.keyId, this.key, now), issuedAt: now };
    }
    return this.jwt.value;
  }

  private session(origin: string): http2.ClientHttp2Session {
    const existing = this.sessions.get(origin);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const s = http2.connect(origin);
    s.on("error", () => this.sessions.delete(origin));
    s.on("close", () => this.sessions.delete(origin));
    this.sessions.set(origin, s);
    return s;
  }

  async send(target: PushTarget, alert: { title: string; body: string }, messageId: string): Promise<SendOutcome> {
    const payload = JSON.stringify({ aps: { alert, sound: "default" } });
    return this.post(target, payload, { "apns-topic": this.config.bundleId, "apns-push-type": "alert", "apns-id": messageId });
  }

  /**
   * ActivityKit push to a Live Activity's own token (call cases). The content state carries a phase
   * and times only, never anything said: the Lock Screen is visible to anyone (ADR-240).
   */
  async sendLiveActivity(target: PushTarget, contentState: Record<string, unknown>, end: boolean): Promise<SendOutcome> {
    const now = Math.floor(Date.now() / 1000);
    const aps: Record<string, unknown> = { timestamp: now, event: end ? "end" : "update", "content-state": contentState };
    if (end) aps["dismissal-date"] = now + 15 * 60;
    return this.post(target, JSON.stringify({ aps }), {
      "apns-topic": `${this.config.bundleId}.push-type.liveactivity`, "apns-push-type": "liveactivity",
    });
  }

  private post(target: PushTarget, payload: string, headers: Record<string, string>): Promise<SendOutcome> {
    let s: http2.ClientHttp2Session;
    try {
      s = this.session(HOSTS[target.environment]);
    } catch {
      return Promise.resolve({ kind: "transient", code: "apns_connect_failed" });
    }
    const messageId = headers["apns-id"] ?? "";
    return new Promise<SendOutcome>((resolve) => {
      let status = 0;
      let data = "";
      let settled = false;
      const done = (o: SendOutcome) => { if (!settled) { settled = true; resolve(o); } };
      const req = s.request({
        ":method": "POST",
        ":path": `/3/device/${target.deviceToken}`,
        authorization: `bearer ${this.token()}`,
        "apns-priority": "10",
        "content-type": "application/json",
        ...headers,
      });
      req.setTimeout(this.timeoutMs, () => { req.close(); done({ kind: "unknown", code: "apns_timeout" }); });
      req.on("response", (h) => { status = Number(h[":status"]); });
      req.setEncoding("utf8");
      req.on("data", (chunk: string) => { data += chunk; });
      req.on("error", () => done({ kind: "unknown", code: "apns_stream_error" }));
      req.on("end", () => {
        if (status === 200) return done({ kind: "accepted", providerId: messageId });
        let reason = "unknown";
        try { reason = (JSON.parse(data) as { reason?: string }).reason ?? reason; } catch { /* empty body */ }
        if (status === 410 || GONE_REASONS.has(reason)) {
          return done({ kind: "rejected", code: `apns_${reason}`, deviceGone: true });
        }
        if (status === 429 || status >= 500) return done({ kind: "transient", code: `apns_${status}_${reason}` });
        done({ kind: "rejected", code: `apns_${status}_${reason}` });
      });
      req.end(payload);
    });
  }

  close(): void {
    for (const s of this.sessions.values()) s.close();
  }
}
