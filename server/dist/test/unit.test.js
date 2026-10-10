import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { test } from "node:test";
import twilio from "twilio";
import { apnsJwt } from "../src/providers/apns.js";
import { isValidTwilioSignature, twilioSignature } from "../src/providers/twilio.js";
import { classifySms } from "../src/sms.js";
test("Twilio signature matches the official twilio library", () => {
    const url = "https://doddy.example.test/webhooks/twilio/sms";
    const params = { From: "+48500100200", To: "+48600000000", Body: "STOP ąę", MessageSid: "SM123", AccountSid: "AC1" };
    const ours = twilioSignature("secret", url, params);
    assert.equal(ours, twilio.getExpectedTwilioSignature("secret", url, params));
    assert.ok(isValidTwilioSignature("secret", url, params, ours));
    assert.ok(!isValidTwilioSignature("secret", url, { ...params, Body: "START" }, ours));
    assert.ok(!isValidTwilioSignature("other", url, params, ours));
    assert.ok(!isValidTwilioSignature("secret", url, params, undefined));
});
test("APNs provider token is a valid ES256 JWT", () => {
    const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const jwt = apnsJwt("TEAM123456", "KEY1234567", privateKey, 1_700_000_000);
    const [h, p, s] = jwt.split(".");
    assert.deepEqual(JSON.parse(Buffer.from(h, "base64url").toString()), { alg: "ES256", kid: "KEY1234567" });
    assert.deepEqual(JSON.parse(Buffer.from(p, "base64url").toString()), { iss: "TEAM123456", iat: 1_700_000_000 });
    assert.ok(verify("sha256", Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(s, "base64url")));
});
test("SMS keywords", () => {
    assert.equal(classifySms(" stop "), "opt_out");
    assert.equal(classifySms("Unsubscribe"), "opt_out");
    assert.equal(classifySms("START"), "opt_in");
    assert.equal(classifySms("help"), "help");
    assert.equal(classifySms("please stop texting"), "other");
});
//# sourceMappingURL=unit.test.js.map