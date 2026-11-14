import { Store } from "./store.js";

/**
 * Operator-only: ends a Doddy account's link to an iPhone's earlier data (decision
 * 2026-11-08-required-account), whenever it was made. Within a day of the link the iPhone can do this
 * itself (`POST /v1/account/link-device/undo`); after that, this is the way.
 *
 *   DATABASE_URL=postgres://… npm run account:unlink -- <account-or-data-user-id>
 *
 * The id is either the account (the Supabase user id) or the data's user id (the iPhone's own). The
 * link row goes, and so does every way into the data opened since the link: browser sessions are
 * revoked, Apple or Google sign-ins linked to it and other iPhones that joined it are removed, unused
 * sign-in codes and tickets go. The data itself stays with the iPhone, whose device sign-in works again.
 * Without DATABASE_URL it opens the local PGlite directory (DODDY_DB_PATH), as the server does.
 * Prints what it did; changes nothing when there is no such link.
 */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const id = (process.argv[2] ?? "").trim().toLowerCase();
if (!UUID.test(id)) {
  process.stderr.write("Usage: npm run account:unlink -- <account-or-data-user-id>   (a UUID)\n");
  process.exit(1);
}
const url = process.env.DATABASE_URL?.trim() || undefined;
const store = await Store.open({
  url,
  caCert: process.env.DATABASE_CA_CERT?.trim() || undefined,
  dataDir: url ? undefined : (process.env.DODDY_DB_PATH ?? "./data/doddy-backend.pglite"),
});
try {
  const ended = await store.unlinkAccount(id, Date.now());
  if (!ended) {
    process.stdout.write("No account link has that id. Nothing changed.\n");
  } else {
    process.stdout.write(
      [
        `Unlinked account ${ended.subject} from the data of ${ended.user_id} (linked ${new Date(ended.linked_at).toISOString()}).`,
        `Ended since the link: ${ended.ended.webSessions} browser session(s), ${ended.ended.webIdentities} Apple or Google sign-in(s), ` +
          `${ended.ended.deviceJoins} joined iPhone(s), ${ended.ended.pending} unused code(s) or ticket(s).`,
        "",
      ].join("\n"),
    );
  }
} finally {
  await store.close();
}
