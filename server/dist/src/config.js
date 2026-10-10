import { z } from "zod";
// Every provider block is optional: a missing block switches that feature off and the API
// answers 503 "not_configured". Nothing is faked.
const optional = z.string().min(1).optional();
const schema = z.object({
    DATABASE_URL: z.string().min(1),
    PORT: z.coerce.number().int().positive().default(3000),
    // Public https origin of this service, used to verify Twilio webhook signatures.
    PUBLIC_BASE_URL: z.string().url().optional(),
    APNS_TEAM_ID: optional,
    APNS_KEY_ID: optional,
    APNS_PRIVATE_KEY: optional, // contents of the .p8 file
    APNS_BUNDLE_ID: optional,
    TWILIO_ACCOUNT_SID: optional,
    TWILIO_AUTH_TOKEN: optional,
    TWILIO_MESSAGING_SERVICE_SID: optional,
    TWILIO_VERIFY_SERVICE_SID: optional,
    ELEVENLABS_API_KEY: optional,
    ELEVENLABS_AGENT_ID: optional,
    // S2 phone calls
    MEMORY_ENCRYPTION_KEY: optional, // base64 of 32 random bytes
    ELEVENLABS_TOOL_SECRET: optional, // shared with ElevenLabs as a workspace secret
    ELEVENLABS_PHONE_AGENT_ID: optional,
    ELEVENLABS_PHONE_NUMBER_ID: optional, // ElevenLabs id of the imported Twilio number
    // News digests
    ANTHROPIC_API_KEY: optional, // Claude writes the one-line summaries
    GNEWS_API_KEY: optional, // keyword search across news sources (paid plan for commercial use)
    DODDY_PHONE_NUMBER: z.string().regex(/^\+[1-9][0-9]{6,14}$/).optional(),
});
export function loadConfig(env = process.env) {
    const e = schema.parse(env);
    const all = (o) => Object.values(o).every((v) => v !== undefined) ? o : undefined;
    return {
        databaseUrl: e.DATABASE_URL,
        port: e.PORT,
        publicBaseUrl: e.PUBLIC_BASE_URL?.replace(/\/$/, ""),
        apns: all({
            teamId: e.APNS_TEAM_ID, keyId: e.APNS_KEY_ID,
            // Render env vars often carry the .p8 with literal "\n".
            privateKey: e.APNS_PRIVATE_KEY?.replace(/\\n/g, "\n"), bundleId: e.APNS_BUNDLE_ID,
        }),
        twilio: all({
            accountSid: e.TWILIO_ACCOUNT_SID, authToken: e.TWILIO_AUTH_TOKEN,
            messagingServiceSid: e.TWILIO_MESSAGING_SERVICE_SID, verifyServiceSid: e.TWILIO_VERIFY_SERVICE_SID,
        }),
        elevenLabs: all({ apiKey: e.ELEVENLABS_API_KEY, agentId: e.ELEVENLABS_AGENT_ID }),
        memoryEncryptionKey: e.MEMORY_ENCRYPTION_KEY,
        toolSecret: e.ELEVENLABS_TOOL_SECRET,
        phoneAgent: all({
            apiKey: e.ELEVENLABS_API_KEY, agentId: e.ELEVENLABS_PHONE_AGENT_ID, phoneNumberId: e.ELEVENLABS_PHONE_NUMBER_ID,
        }),
        doddyPhoneNumber: e.DODDY_PHONE_NUMBER,
        anthropicApiKey: e.ANTHROPIC_API_KEY,
        gnewsApiKey: e.GNEWS_API_KEY,
    };
}
//# sourceMappingURL=config.js.map