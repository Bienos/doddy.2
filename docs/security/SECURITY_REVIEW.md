# Security review: controls and what was checked (4 Nov 2026)

`THREAT_MODEL.md` (imported pack, left unchanged) asks for this file: evidence of controls and open risks. A code review of every component on 4 Nov 2026 led to ADR-702 to 725. **This is not a penetration test.** Nothing here has been checked on a device or against the live services, and the iPhone app files under `DoddyApp/` have not been compiled (no Xcode in the sessions that made the changes); the hosted macOS build is the first compile.

## Controls added and how each was checked

| Surface | Abuse/failure | Mitigation | Verification |
|---|---|---|---|
| Messaging accounts and paid features | Many anonymous accounts use up paid AI capacity or leave real users on "daily limit" | Daily caps per address and per server on new accounts; a separate small daily pool for new accounts; a research budget per errand (ADR-702) | Messaging tests (caps, pools, parallel requests). Provider spend limits are dashboard settings, not checked |
| Phone verification, texts and calls | Cost fraud through numbers in unexpected countries, or through many accounts | Country allowlist; daily caps per account, address and server; per-account and per-number task-call limits; blocked-number list; maximum call length in the agent spec (ADR-704, 705) | Messaging tests. Twilio geo-permissions, Fraud Guard and the live agent's call length are dashboard settings, not checked |
| Backend device sign-in | A server with no owner handed to the first caller; tokens that outlive account deletion; invite codes minting unlimited sessions | Owner claim closed in live mode unless the operator opens it; a per-person token cut-off written by deletion; invite-code try, session and device caps (ADR-707, 709) | Backend tests; 40 parallel callers against a real Postgres |
| Agent hands a task over | Text the agent read on the web or in an email steering a task whose text leaves the phone | Tap-only card showing the exact words and note; links refused on the phone and on the server; research budget (ADR-716, 703, 702) | DoddyCore tests; the app wiring is not compiled or run on a device |
| Contacts and private answers before a tap | The agent enumerating contacts, or learning private facts from replies given before a card | Doddy's Contacts switch and a three-search budget; capped name lists; generic replies before a tap (ADR-717, 718) | DoddyCore tests; the app wiring is not compiled |
| Server address in the app | The device ID (a credential) sent to an address a person was talked into typing | A typed address is ignored in shipped builds; Debug accepts https or localhost only (ADR-720) | DoddyCore tests; app files not compiled |
| Face ID lock | Ways in that open private screens or start a conversation without the lock; app-switcher picture | One lock policy asked at every entry point; screens closed when the lock returns; an opaque cover (ADR-723) | DoddyCore policy tests and a Linux harness for the router. RootView and the cover are not run on a device |
| Privacy disclosure | The privacy screen saying nothing leaves the phone when something does | The screen is built from the address in use and the real data flows (ADR-721) | DoddyCore tests |
| Voice token server | A few accounts using the shared limits; a copied refresh token | Sign-in throttle per address, daily caps, a reused refresh token ends the session (ADR-712) | voice-token tests, including real Redis scripts |
| Site waitlist admin | Password guessing; a third-party script on the admin page | Its own policy; a wait on a wrong password (ADR-714) | Site tests. A Vercel Firewall rate limit is an owner setting |
| Sign-out and the messaging server (audit 9 Nov 2026) | A signed-out iPhone's copied token still works; its push address still gets private notifications; a late refresh or server answer restores a signed-out account | `DELETE /v1/device` ends one iPhone's token and push binding; the app keeps the call owed until answered; an epoch makes late answers change nothing | Messaging tests on Postgres, DoddyCore tests on Linux. App wiring not compiled; no device check. See `AUDIT_2026-11-09_REMEDIATION.md` |
| Copies of a person's documents at Anthropic (audit 9 Nov 2026) | A copy left behind by a failed download, a restart, a refused delete or an account erasure | File ids written down when seen, deleted in `finally`, `200`/`404` only counts, hourly retry, kept through erasure | Backend tests (PGlite, scripted Anthropic). Not run against Anthropic |
| CI | Mutable action tags | Actions pinned to commit SHAs (ADR-715) | Pins compared with the tags on GitHub |

## Open items for the owner

Dashboard and provider settings the code cannot make are in `docs/OWNER_QUEUE.md` (spend limits, Twilio and ElevenLabs settings, Vercel Firewall rules, the live agent's wording). Decisions that chose a default the owner may want different are marked "Owner decision needed" in the ADR rows.

## Still not covered

- Anything on a real iPhone (Face ID lock routes, the cover, notifications, Keychain after a reboot, clipboard).
- Behaviour of the model itself against hostile web or email text; only the code around it was reviewed.
- An outside penetration test of the backend and the messaging server, and a red-team of the voice agent with planted web and email content.
- Encryption of generated documents and receipts at rest (backend); a zod 4 upgrade; premium-rate number ranges inside allowed countries (Twilio settings).
