Server: deliveries through Uber Direct, step 1 (decision `2026-11-12-uber-direct-deliveries`): quote, confirm on the card's exact hash, status, cancel; encrypted details erased when done; caps of 60 zł, 2 a day per account and 5 a day in all. Off by default (`UBER_DIRECT_ENABLED=0`, mode `test`). No app or voice change yet.
Ran: the messaging server's whole suite against Postgres 16 (939 tests, 0 failures), `scripts/ci.sh --only checks`. Not run: anything against Uber (no credentials here).
Owner steps: OWNER_QUEUE rows on Uber credentials (sandbox), who pays, and production access.
