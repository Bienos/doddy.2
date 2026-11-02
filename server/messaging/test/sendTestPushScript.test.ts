// scripts/send-test-push.mjs: what it checks before it sends, what it says for each answer from Apple, and that it
// never prints the key or the token. The sender is a fake; nothing here reaches APNs.
import assert from "node:assert/strict";
import { describe, test } from "node:test";

type Outcome =
  | { kind: "accepted"; providerId: string }
  | { kind: "rejected"; code: string; deviceGone?: boolean }
  | { kind: "transient"; code: string }
  | { kind: "unknown"; code: string };
interface Sender { send(t: { deviceToken: string; environment: string }, a: { title: string; body: string }, id: string): Promise<Outcome>; close?(): void }
interface Script {
  run(argv: string[], io?: {
    env?: Record<string, string | undefined>; stdout?: (s: string) => void; stderr?: (s: string) => void;
    makeSender?: (config: { teamId: string; keyId: string; bundleId: string; privateKey: string }) => Promise<Sender> | Sender;
  }): Promise<number>;
  describeOutcome(o: Outcome, env: string): { code: number; text: string };
  readApnsEnv(env: Record<string, string | undefined>): { config?: { privateKey: string }; missing?: string[] };
}
const script = (await import(new URL("../../scripts/send-test-push.mjs", import.meta.url).href)) as Script;

const TOKEN = "ab".repeat(32);
const ENV = { APNS_TEAM_ID: "TEAM123456", APNS_KEY_ID: "KEY1234567", APNS_BUNDLE_ID: "com.example.doddy", APNS_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\\nSECRETKEYTEXT\\n-----END PRIVATE KEY-----" };

function harness(outcome: Outcome, env: Record<string, string | undefined> = ENV) {
  const out: string[] = [];
  const err: string[] = [];
  const sent: { deviceToken: string; environment: string; alert: { title: string; body: string } }[] = [];
  let closed = false;
  const io = {
    env, stdout: (s: string) => out.push(s), stderr: (s: string) => err.push(s),
    makeSender: () => ({
      send: async (t: { deviceToken: string; environment: string }, alert: { title: string; body: string }) => { sent.push({ ...t, alert }); return outcome; },
      close: () => { closed = true; },
    }),
  };
  return { io, out, err, sent, closed: () => closed };
}

describe("send-test-push", () => {
  test("sends one fixed notification to the sandbox by default and exits 0 on accepted", async () => {
    const h = harness({ kind: "accepted", providerId: "x" });
    assert.equal(await script.run([TOKEN.toUpperCase()], h.io), 0);
    assert.equal(h.sent.length, 1);
    assert.equal(h.sent[0]!.deviceToken, TOKEN, "the token is sent as lowercase hex, as the app uploads it");
    assert.equal(h.sent[0]!.environment, "sandbox");
    assert.equal(h.sent[0]!.alert.title, "Doddy");
    assert.match(h.out.join("\n"), /accepted it \(sandbox\)/);
    assert.ok(h.closed(), "the connection is closed so the script exits");
  });

  test("production is chosen only when asked for", async () => {
    const h = harness({ kind: "accepted", providerId: "x" });
    assert.equal(await script.run([TOKEN, "production"], h.io), 0);
    assert.equal(h.sent[0]!.environment, "production");
  });

  test("bad arguments send nothing and exit 2", async () => {
    for (const argv of [[], ["not-hex"], ["ab".repeat(10)], [TOKEN, "staging"]]) {
      const h = harness({ kind: "accepted", providerId: "x" });
      assert.equal(await script.run(argv, h.io), 2, JSON.stringify(argv));
      assert.equal(h.sent.length, 0);
    }
  });

  test("a missing variable is named and nothing is sent", async () => {
    const h = harness({ kind: "accepted", providerId: "x" }, { ...ENV, APNS_KEY_ID: undefined, APNS_BUNDLE_ID: "" });
    assert.equal(await script.run([TOKEN], h.io), 2);
    assert.match(h.err.join("\n"), /APNS_KEY_ID, APNS_BUNDLE_ID/);
    assert.equal(h.sent.length, 0);
  });

  test("the .p8 text with literal \\n is turned back into lines, as the server does", () => {
    const r = script.readApnsEnv(ENV);
    assert.equal(r.config?.privateKey, "-----BEGIN PRIVATE KEY-----\nSECRETKEYTEXT\n-----END PRIVATE KEY-----");
  });

  test("a refusal exits 1 and explains the likely cause", () => {
    const gone = script.describeOutcome({ kind: "rejected", code: "apns_BadDeviceToken", deviceGone: true }, "sandbox");
    assert.equal(gone.code, 1);
    assert.match(gone.text, /production/);
    assert.match(script.describeOutcome({ kind: "rejected", code: "apns_400_TopicDisallowed" }, "production").text, /APNS_BUNDLE_ID/);
    assert.match(script.describeOutcome({ kind: "rejected", code: "apns_403_InvalidProviderToken" }, "production").text, /Team ID|Key ID/);
  });

  test("an unknown answer is not called success and is not retried", async () => {
    const h = harness({ kind: "unknown", code: "apns_timeout" });
    assert.equal(await script.run([TOKEN], h.io), 1);
    assert.equal(h.sent.length, 1);
    assert.match(h.err.join("\n"), /may or may not/);
  });

  test("neither the key nor the token is ever printed", async () => {
    for (const outcome of [{ kind: "accepted", providerId: "x" }, { kind: "rejected", code: "apns_BadDeviceToken", deviceGone: true }] as Outcome[]) {
      const h = harness(outcome);
      await script.run([TOKEN], h.io);
      const all = [...h.out, ...h.err].join("\n");
      assert.ok(!all.includes("SECRETKEYTEXT") && !all.includes(TOKEN));
    }
  });
});
