import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createPool, migrateOrExit } from "./db.js";
import { providersFrom } from "./providers/index.js";
import { taskCallContext } from "./taskCalls/context.js";
import { errandContext } from "./errands/context.js";
import { log, runWorkerLoop } from "./workerLoop.js";

const config = loadConfig();
const db = createPool(config.databaseUrl);
await migrateOrExit(db, log);
const providers = providersFrom(config);
const app = await buildApp({
  db, ...providers, twilioAuthToken: config.twilio?.authToken, publicBaseUrl: config.publicBaseUrl,
  toolSecret: config.toolSecret, doddyPhoneNumber: config.doddyPhoneNumber,
  trustProxyHops: config.trustProxyHops, verifyDailyCap: config.verifyDailyCap,
});
app.log.info({
  push: !!providers.push, sms: !!providers.sms, webhooks: !!config.publicBaseUrl,
  calls: !!(config.toolSecret && providers.cipher), outboundCalls: !!providers.outbound,
  newsWriter: !!providers.news.writer, newsSearch: !!providers.news.search,
  taskCalls: !!(providers.taskCalls && providers.cipher && config.publicBaseUrl), taskCallsKillSwitch: config.taskCallSettings.killSwitch,
  errands: !!(providers.errands.researcher && providers.cipher), errandsModel: config.errandSettings.model,
  assistant: !!providers.assistant.responder, assistantModel: config.assistantSettings.model,
  deals: config.dealsSettings.enabled, dealsReader: !!providers.deals.model, shoppingOffers: !!config.shoppingSettings.serperApiKey,
}, "configured features");

// One service instead of web + worker (a small or free deploy): RUN_WORKER_IN_WEB=1 runs the
// worker loop in this process too. Jobs are claimed with SKIP LOCKED, so a separate worker
// running at the same time is still safe.
let stopping = false;
let workerDone: Promise<void> | undefined;
if (config.runWorkerInWeb) {
  log("worker started in the web process", { push: !!providers.push, sms: !!providers.sms });
  const taskCtx = taskCallContext(db, providers.taskCalls, providers.cipher, config.publicBaseUrl, providers.push, log);
  const errandCtx = errandContext(db, providers.errands, providers.cipher, providers.push, log);
  workerDone = runWorkerLoop(db, { ...providers, taskCalls: taskCtx, errands: errandCtx }, () => stopping);
}

const shutdown = async () => {
  stopping = true;
  await app.close();
  await workerDone;
  providers.push?.close();
  await db.end();
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

await app.listen({ host: "0.0.0.0", port: config.port });
