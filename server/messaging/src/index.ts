import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createPool, migrate } from "./db.js";
import { providersFrom } from "./providers/index.js";

const config = loadConfig();
const db = createPool(config.databaseUrl);
await migrate(db);
const providers = providersFrom(config);
const app = await buildApp({
  db, ...providers, twilioAuthToken: config.twilio?.authToken, publicBaseUrl: config.publicBaseUrl,
  toolSecret: config.toolSecret, doddyPhoneNumber: config.doddyPhoneNumber,
});
app.log.info({
  push: !!providers.push, sms: !!providers.sms, webhooks: !!config.publicBaseUrl,
  calls: !!(config.toolSecret && providers.cipher), outboundCalls: !!providers.outbound,
  newsWriter: !!providers.news.writer, newsSearch: !!providers.news.search,
}, "configured features");

const shutdown = async () => {
  await app.close();
  await db.end();
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

await app.listen({ host: "0.0.0.0", port: config.port });
