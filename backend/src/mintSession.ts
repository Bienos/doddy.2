import { randomUUID } from "node:crypto";
import { SignedSessionVerifier } from "./auth.js";
import { SigningKeys } from "./signingKeys.js";

/**
 * Owner-only helper: mints a signed session token for a development device.
 *   DODDY_SESSION_SIGNING_KEY=… npm run session:mint -- [user-uuid] [ttl-days]
 * The token is printed once; paste it into the app (it is stored in the iOS Keychain).
 * It is signed with the session key derived from DODDY_SESSION_SIGNING_KEY (signingKeys.ts), like every
 * token the server makes, and carries that key's id. Use the key the server runs with now; the previous key
 * (DODDY_SESSION_SIGNING_KEY_PREVIOUS) only ever checks, so it is not read here.
 * A token cannot be revoked on its own. Deleting the account on the server (`DELETE /v1/account`) cuts
 * off every token issued to that user before the deletion (ADR-709). A token stops working once the server
 * no longer holds the key that signed it (neither as the current nor as the previous key).
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
const token = new SignedSessionVerifier(new SigningKeys(key)).mint(userId, new Date(), days * 86_400);
process.stdout.write(`user ${userId}\n${token}\n`);
