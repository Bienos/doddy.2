# Initial threat model — STRIDE-inspired
**Unverified design analysis; rerun against implemented code before TestFlight.**

| Surface | Abuse/failure | Mitigation | Verification |
|---|---|---|---|
| Memory DB | Loss/corruption on migration, locked device, disk full | Atomic versioned migration; failures visible; source preserved | Failure injection and restart |
| Memory search | Old/deleted text appears; hallucinated record | Transactional FTS sync, ID-backed results, expiry of caches | Delete then query, invalid citation injection |
| Memory privacy | Unconsented model egress | Explicit request scope and minimised selected IDs | Network capture and consent toggles |
| Voice | Mic not released; background collection | Foreground-only state machine; interruption cancellation | Real device OS interruptions |
| Action runtime | Prompt injection requests a reminder | Typed schema, independent policy gate, user confirmation | Adversarial tool prompts |
| Action runtime | Duplicate external reminder after timeout | Operation ID and reconciliation, unknown outcome state | Failure/timeout chaos test |
| Gateway | Exposed API key, enumeration, cost attack | Server-held keys, signed/rotating client authorization, caps | Leak scan, negative tests, rate limit |
| Telemetry | Private text leaked in event props | Allowlist enums/metadata and audited log pipeline | Schema/event tests |
| Supply chain | Asset/external package compromised | Lockfile, code review, verified releases/dependency scanning | CI and dependency reports |
| Brand/persona | Undue emotional dependence / false personhood | Transparent AI disclosure, bounded relationship, serious-mode behavior | Character adversarial evals |

Create `SECURITY_REVIEW.md` with evidence of controls and open risks. A threat-model table is not a penetration test.
