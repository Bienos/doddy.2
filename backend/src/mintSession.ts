import { randomUUID } from "node:crypto";
import { SignedSessionVerifier } from "./auth.js";

/**
 * Owner-only helper: mints a signed session token for a development device.
 *   DODDY_SESSION_SIGNING_KEY=… npm run session:mint -- [user-uuid] [ttl-days]
 * The token is printed once; paste it into the app (it is stored in the iOS Keychain).
 * Tokens cannot be revoked one by one: rotating DODDY_SESSION_SIGNING_KEY revokes all of them.
 * Keep lifetimes short (default 7 days, max 30) until a real sign-in replaces this.
 */
const raw = process.env.DODDY_SESSION_SIGNING_KEY;
const key = raw ? Buffer.from(raw, "base64") : null;
if (!key || key.length < 32) {
  process.stderr.write("Set DODDY_SESSION_SIGNING_KEY (base64, ≥32 bytes). Generate one with: openssl rand -base64 32\n");
  process.exit(1);
}
const userId = process.argv[2] ?? randomUUID();
const days = Number(process.argv[3] ?? "7");
if (!Number.isInteger(days) || days < 1 || days > 30) {
  process.stderr.write("ttl-days must be 1–30\n");
  process.exit(1);
}
const token = new SignedSessionVerifier(key).mint(userId, new Date(), days * 86_400);
process.stdout.write(`user ${userId}\n${token}\n`);
