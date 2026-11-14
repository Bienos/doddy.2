import { loadConfig } from "./config.js";
import { dealWatchContextFor } from "./deals/dealWatches.js";
import { createPool, migrateOrExit } from "./db.js";
import { providersFrom, scheduledCallsFrom } from "./providers/index.js";
import { taskCallContext } from "./taskCalls/context.js";
import { errandContext } from "./errands/context.js";
import { studioContext } from "./studio/context.js";
import { watchContext } from "./watches/context.js";
import { catalogContext, log, radarContext, runWorkerLoop } from "./workerLoop.js";

// Stand-alone worker process (render.yaml: doddy-messaging-worker). A single web service can run
// the same loop in-process instead with RUN_WORKER_IN_WEB=1 (src/index.ts).
const config = loadConfig();
const db = createPool(config.databaseUrl);
await migrateOrExit(db, log);
const providers = providersFrom(config);
const {
  push, sms, phoneAgentVoice, phoneAgentId, cipher, news, taskCalls, errands, studio, watches, limits, deleter, taskDeleter, deleteAfterMinutes,
} = providers;
const scheduledCalls = scheduledCallsFrom(config, providers);
const taskCtx = taskCallContext(db, taskCalls, cipher, config.publicBaseUrl, push, log);
const errandCtx = errandContext(db, errands, cipher, push, log);
const studioCtx = studioContext(db, studio, cipher, push, log);
const watchCtx = watchContext(db, watches, cipher, push, log);
const radarCtx = radarContext(db, config.radarAlertsEnabled, news, push, cipher, config.quietHours);
const dealWatchCtx = dealWatchContextFor({ db, ...providers, quietHours: config.quietHours }, log);
const catalogCtx = catalogContext(db, providers.deals, dealWatchCtx);
log("worker started", {
  push: !!push, sms: !!sms, scheduledCalls: !!scheduledCalls, taskCalls: !!taskCtx, killSwitch: config.taskCallSettings.killSwitch,
  errands: !!errandCtx?.enabled, studio: !!studioCtx?.enabled, watches: !!watchCtx?.enabled, radarAlerts: !!radarCtx,
  leafletCatalog: !!catalogCtx, dealWatches: !!dealWatchCtx?.enabled,
});

let stopping = false;
process.on("SIGTERM", () => { stopping = true; });
process.on("SIGINT", () => { stopping = true; });

await runWorkerLoop(db, {
  push, sms, phoneAgentVoice, phoneAgentId, cipher, news, taskCalls: taskCtx, errands: errandCtx, studio: studioCtx, watches: watchCtx, limits,
  deleter, taskDeleter, deleteAfterMinutes, scheduledCalls, radar: radarCtx, catalog: catalogCtx, dealWatches: dealWatchCtx,
}, () => stopping);
push?.close();
await db.end();
log("worker stopped");
