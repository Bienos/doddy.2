Proposal, no code change: pull requests wait on the one shared hosted Mac (#354's `ios-build` was still queued after 45 minutes); options for the owner are in decision `2026-11-12-mac-queue` and owner queue 44.
Ran: scripts/ci_needs_mac.sh on #354's 33 changed files (mac=true, first path scripts/ci.sh). Not run: any workflow or filter change.
Also: the booking row in docs/OWNER_QUEUE.md clashed with the Uber rows (two number 40); it is 43 now, marked done, and the decision and note that name it follow.
