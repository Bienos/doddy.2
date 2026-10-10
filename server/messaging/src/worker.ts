import { loadConfig } from "./config.js";
import { createPool, migrate } from "./db.js";
import { purgeExpiredSessions } from "./calls.js";
import { runDueDigests } from "./news/digest.js";
import { dispatchDue } from "./outbox.js";
import { providersFrom } from "./providers/index.js";

// Sends queued updates. Logs counts and ids only, never message text or phone numbers.
const config = loadConfig();
const db = createPool(config.databaseUrl);
await migrate(db);
const { push, sms, news } = providersFrom(config);
const log = (msg: string, extra: object = {}) => console.log(JSON.stringify({ time: new Date().toISOString(), msg, ...extra }));
log("worker started", { push: !!push, sms: !!sms });

let stopping = false;
process.on("SIGTERM", () => { stopping = true; });
process.on("SIGINT", () => { stopping = true; });

while (!stopping) {
  try {
    const r = await dispatchDue(db, { push, sms });
    await purgeExpiredSessions(db);
    const digests = await runDueDigests(db, news);
    if (digests) log("news digests built", { count: digests });
    if (r.processed || r.reaped) log("dispatch pass", r);
    if (r.processed) continue; // more may be due
  } catch (err) {
    log("dispatch pass failed", { error: (err as Error).message });
  }
  await new Promise((resolve) => setTimeout(resolve, 2000));
}
push?.close();
await db.end();
log("worker stopped");
