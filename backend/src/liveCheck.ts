import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { addDays, localDate } from "./time.js";

/**
 * Opt-in live check. Read-only. Uses the account the owner ALREADY connected through the app for
 * the Doddy user named in DODDY_LIVE_CHECK_USER_ID (it never creates a connection and never picks
 * an arbitrary account). Prints counts, statuses and receipt fields only — no event content.
 *
 *   DODDY_MODE=live … DODDY_LIVE_CHECK_USER_ID=<uuid> DODDY_LIVE_CHECK_TIME_ZONE=Europe/Warsaw npm run live-check
 */
const userId = process.env.DODDY_LIVE_CHECK_USER_ID;
const timeZone = process.env.DODDY_LIVE_CHECK_TIME_ZONE;
if (!userId || !timeZone) {
  process.stderr.write("NOT RUN: set DODDY_LIVE_CHECK_USER_ID and DODDY_LIVE_CHECK_TIME_ZONE (and live-mode configuration).\n");
  process.exit(2);
}
const config = loadConfig();
if (config.mode !== "live") {
  process.stderr.write("NOT RUN: DODDY_MODE must be live for the live check.\n");
  process.exit(2);
}
const { service, store } = await buildApp(config);
try {
  const status = await service.refreshStatus(userId);
  process.stdout.write(`connection status: ${status.status}${status.reason ? ` (${status.reason})` : ""}\n`);
  if (status.status !== "connected") process.exit(1);
  const date = addDays(localDate(Date.now(), timeZone), 1);
  const result = await service.listEvents(userId, { date, timeZone });
  process.stdout.write(
    `${JSON.stringify({
      date,
      timeZone,
      events: result.events.length,
      allDay: result.events.filter((e) => e.allDay).length,
      recurring: result.events.filter((e) => e.isRecurring).length,
      cancelledHidden: result.cancelledHidden,
      truncated: result.truncated,
      receiptStatus: result.receipt.status,
      providerReferencePresent: result.receipt.providerReference !== null,
    })}\n`,
  );
} catch (error) {
  const code = (error as { code?: unknown }).code;
  process.stderr.write(`live check failed: ${typeof code === "string" ? code : "unexpected error"}\n`);
  process.exitCode = 1;
} finally {
  await store.close();
}
