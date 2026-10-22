import { loadConfig } from "./config.js";
import { createPool, migrateOrExit } from "./db.js";
import { providersFrom } from "./providers/index.js";
import { taskCallContext } from "./taskCalls/context.js";
import { errandContext } from "./errands/context.js";
import { studioContext } from "./studio/context.js";
import { log, runWorkerLoop } from "./workerLoop.js";

// Stand-alone worker process (render.yaml: doddy-messaging-worker). A single web service can run
// the same loop in-process instead with RUN_WORKER_IN_WEB=1 (src/index.ts).
const config = loadConfig();
const db = createPool(config.databaseUrl);
await migrateOrExit(db, log);
const { push, sms, cipher, news, taskCalls, errands, studio } = providersFrom(config);
const taskCtx = taskCallContext(db, taskCalls, cipher, config.publicBaseUrl, push, log);
const errandCtx = errandContext(db, errands, cipher, push, log);
const studioCtx = studioContext(db, studio, cipher, push, log);
log("worker started", {
  push: !!push, sms: !!sms, taskCalls: !!taskCtx, killSwitch: config.taskCallSettings.killSwitch, errands: !!errandCtx?.enabled,
  studio: !!studioCtx?.enabled,
});

let stopping = false;
process.on("SIGTERM", () => { stopping = true; });
process.on("SIGINT", () => { stopping = true; });

await runWorkerLoop(db, { push, sms, cipher, news, taskCalls: taskCtx, errands: errandCtx, studio: studioCtx }, () => stopping);
push?.close();
await db.end();
log("worker stopped");
