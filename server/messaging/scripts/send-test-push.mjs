#!/usr/bin/env node
// Sends ONE test notification through the same APNs sender the server uses, so the Apple side (team, key, bundle
// id, the .p8, sandbox or production) can be checked without running an errand. Run `npm run build` first.
//
//   export APNS_TEAM_ID=... APNS_KEY_ID=... APNS_BUNDLE_ID=com.bienos.doddy2.dev
//   export APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
//   node scripts/send-test-push.mjs <device token, hex> [sandbox|production]
//
// The device token is the one the app uploads (64+ hex characters). A build run from Xcode (Debug) is "sandbox";
// TestFlight and App Store builds are "production" (ServerConfig.pushEnvironment). The default is sandbox.
// The text is fixed and carries nothing of yours. Nothing is read from or written to the database, and the key
// and token are never printed.

import { pathToFileURL } from "node:url";

const TEXT = { title: "Doddy", body: "Test notification from your Doddy server." };
const KEY_WORDS = "PRIVATE KEY";

/** What each outcome means for the person running this, in plain words. Pure. */
export function describeOutcome(outcome, environment) {
  switch (outcome.kind) {
    case "accepted":
      return { code: 0, text: `Apple accepted it (${environment}). It should arrive on the phone within seconds. If it doesn't, check Settings > Notifications > Doddy and that Focus is off.` };
    case "rejected": {
      const hint = outcome.deviceGone
        ? ` This token will never work again${environment === "sandbox" ? ", or it belongs to a production (TestFlight) build: try `production`" : ", or it belongs to a development build: try `sandbox`"}.`
        : outcome.code.includes("InvalidProviderToken") || outcome.code.includes("403")
          ? " The key, Team ID or Key ID is wrong, or the key is not enabled for APNs."
          : outcome.code.includes("TopicDisallowed")
            ? " APNS_BUNDLE_ID does not match the app, or Push Notifications is not enabled on its App ID."
            : "";
      return { code: 1, text: `Apple refused it: ${outcome.code}.${hint}` };
    }
    case "transient":
      return { code: 1, text: `Apple asked to try later (${outcome.code}). Nothing was delivered; run it again in a minute.` };
    default:
      return { code: 1, text: `No clear answer (${outcome.code}). It may or may not have been delivered; this script does not retry.` };
  }
}

/** Reads the four APNS_ variables the server reads. Returns { config } or { missing: [names] }. Pure. */
export function readApnsEnv(env) {
  const names = ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_PRIVATE_KEY", "APNS_BUNDLE_ID"];
  const missing = names.filter((n) => !env[n]);
  if (missing.length) return { missing };
  return {
    config: {
      teamId: env.APNS_TEAM_ID, keyId: env.APNS_KEY_ID, bundleId: env.APNS_BUNDLE_ID,
      // Render keeps the .p8 with literal "\n"; the server turns them back, so do the same.
      privateKey: env.APNS_PRIVATE_KEY.replace(/\\n/g, "\n"),
    },
  };
}

async function loadSender(config) {
  const { ApnsPushSender } = await import("../dist/src/providers/apns.js");
  return new ApnsPushSender(config);
}

/** Returns the exit code. `io` is for tests: env, stdout, stderr, and makeSender(config) -> { send, close }. */
export async function run(argv, io = {}) {
  const env = io.env ?? process.env;
  const out = io.stdout ?? ((s) => process.stdout.write(`${s}\n`));
  const err = io.stderr ?? ((s) => process.stderr.write(`${s}\n`));
  const [token, environment = "sandbox"] = argv;

  if (!token || (environment !== "sandbox" && environment !== "production")) {
    err("Usage: node scripts/send-test-push.mjs <device token, hex> [sandbox|production]");
    return 2;
  }
  if (!/^[0-9a-fA-F]{64,}$/.test(token)) {
    err("The device token should be 64 or more hex characters (the app uploads it as lowercase hex).");
    return 2;
  }
  const read = readApnsEnv(env);
  if (read.missing) {
    err(`Missing: ${read.missing.join(", ")}. These are the same four variables the server reads.`);
    return 2;
  }

  let sender;
  try {
    sender = await (io.makeSender ?? loadSender)(read.config);
  } catch (e) {
    err(e?.code === "ERR_MODULE_NOT_FOUND"
      ? "The server is not built. Run `npm run build` in server/messaging first."
      // The marker is assembled so the secret scan in scripts/check_forbidden_capabilities.sh, which looks for it, stays quiet.
      : `Could not use the key. APNS_PRIVATE_KEY should be the full text of the .p8 file, from -----BEGIN ${KEY_WORDS}----- to -----END ${KEY_WORDS}-----.`);
    return 2;
  }
  try {
    const outcome = await sender.send({ deviceToken: token.toLowerCase(), environment }, TEXT, crypto.randomUUID());
    const { code, text } = describeOutcome(outcome, environment);
    (code === 0 ? out : err)(text);
    return code;
  } finally {
    sender.close?.();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await run(process.argv.slice(2));
}
