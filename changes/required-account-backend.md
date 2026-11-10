Backend, first step of decision `2026-11-08-required-account` (every user has a Doddy account: Apple, Google or a code by email):
- the Supabase token check accepts email accounts and refuses any session made with a password (`amr`);
- `POST /v1/account/link-device` lets an account take over an iPhone's earlier data once, with the iPhone's device token as proof, never merging accounts (new table `account_links`); after it the device token and device sign-in are refused for that iPhone;
- `DELETE /v1/account` with an account's token also queues the Supabase user for removal and ends that account's earlier tokens at once.
Ran: `scripts/ci.sh --only backend` PASS (type-check; tests on PGlite: the 649 that passed before, two of them updated for the intended change, plus 6 new in `test/account-links.test.ts`). Not run: anything against the real Supabase project (not set up for email yet, OWNER_QUEUE 23), and the iPhone side (a later pull request).
