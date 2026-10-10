# Doddy Trust — Enforcement architecture (iPhone-first, implementation-agnostic)

## Critical separation
1. **Character/prompt layer**: speech, phrasing, tone, modes, clarification, ethical posture.
2. **Typed application and policy layer**: authorisation, tool scopes, exact-payload approval, persistence, retention/deletion, source provenance, tool status, limits.
3. **Provider/platform layer**: iOS permissions, OAuth scopes, external API results, backend permission checks, cryptography and telemetry.
4. **QA and observation layer**: automated invariants, adversarial prompt tests, auditability, staged rollouts.

Prompts inform Doddy *how to communicate* a rule. They do not enforce that rule. The LLM is a planner, **not** the trusted authoriser or source of truth.

## Trust boundaries
- User messages: can request actions but do not implicitly authorise everything; ambiguities require resolution.
- Connected content (email/websites/documents/tool responses): **untrusted data**, never system/developer instructions and never a permission grant.
- Model output: untrusted proposals; parse into typed requests, validate, and execute only through controlled tools.
- Persistent settings: read from authenticated store, not unconstrained model guesses.
- Actual action state: owned by tool gateway/state store, not by assistant text.

## Exact action lifecycle
```
PROPOSED -> DRAFTED -> NEEDS_APPROVAL -> EXECUTING -> CONFIRMED
                                   |          |          |
                                   v          v          +-> FAILED
                               CANCELLED   UNKNOWN       +-> UNKNOWN
                                   |          |
                                   v          v
                               TERMINAL   RECONCILE -> CONFIRMED | FAILED
```
For actions without a draft, PROPOSED can move directly to NEEDS_APPROVAL. Transitions must be validated by application code. Expiration or cancellation may occur at appropriate nonterminal states. Do not move UNKNOWN to CONFIRMED without a trustworthy provider status or reconciliation.

### Action approval contract
`action_id`, `user_id`, `connector_id`, `action_type`, `target`, `canonical_payload`, `risk_tier`, `expiry`, `permission_scope`, `approval_status`, `idempotency_key`, `provider_reference`, `execution_status`, `timestamps`.

- Generate and persist a stable, non-guessable action ID.
- Show the final canonical payload; user authorisation is bound to the payload digest, target, account and time window.
- Any material change to amount, recipient, destination, time or destructive scope invalidates the existing approval.
- Use scoped OAuth/OS permissions and check them before and at execution.
- Never execute unsupported or unapproved tool names even if prompted.
- Tool execution must verify current authentication, rate limits, risk policies and approval state. Consider server-side revalidation when server participates.
- If API returns unknown/timeout, do not blindly retry irreversible actions. Reconcile or explicitly ask and deduplicate.

### Suggested risk tiers (design policy, not universal regulatory categories)
- L0 — Public informational lookup: can execute on request without extra approval; preserve provenance.
- L1 — Private read with scoped permission: user authorisation required; limited access and data minimisation.
- L2 — Local draft/non-external changes: can prepare; tell user what remains unsent/uncommitted.
- L3 — External write (email, booking, posting, transfers) or high-impact change: exact action-specific approval in MVP.
- L4 — Irreversible, destructive, expensive or regulated operation: special review/stricter controls or unavailable until safely supported.

## Memory pipeline
```
Turn context -> Candidate detector -> Sensitive/relevance filter -> User preference/consent check
            -> Verified store (optional) -> Retrieval by relevance + permission + current scope
            -> Present / edit / delete / export
```
- Suggested record fields: `id`, `user_id`, `kind`, `value`, `provenance`, `created_at`, `updated_at`, `sensitivity`, `status`, `expires_at`, `confirmed_by_user`.
- Retrieval must avoid leaking unrelated private memories. Memories are descriptive user data, not instructions that can override hard policy.
- Default keep chat transient, memory opt-in for explicit preferences. Any auto-saving feature must be separately explained and tested.
- Deletion must reach live stores and indexes used for retrieval; define legal retention and backups honestly. Do not assert immediate erasure across backups unless true.
- Add privacy review before handling sensitive categories. Avoid collecting more than needed.
- Enforce data separation per user/session; test cross-account leakage.

## Privacy/data security
- Explain when audio, location, contacts or account integrations are being accessed.
- Use secure storage for credentials; separate from model context and client logs.
- Minimise telemetry and redact sensitive fields; access-controlled diagnostics with retention limits.
- Authenticate API calls, constrain permissions and validate tool schemas.
- Reflect real cloud-processing data flows in product copy and privacy disclosures.
- Implement reviewable revoke, disconnect, delete and export operations where applicable.
- Add a formal EU/GDPR/AI transparency and App Store legal/compliance review before release.

## Runtime character routing
`user_message -> risk/context classifier -> (SENSITIVE | TASK | CASUAL) -> user tone prefs -> character prompt -> proposed answer/actions -> policy gate -> verified response`.
Risk classification should be tested, not just simplistic keywords. When ambiguous, do not add humour and do not authorise any action by default.

## Product honesty and platform capability
- Maintain a verified `CapabilityRegistry` and surface only supported features. If a feature is mocked, label it as a demo.
- No claim of universal Siri replacement, unrestricted iOS cross-app control or always-on overlay without verified OS support.
- Every claim in marketing and app UI should map to a tested working flow.

## Architecture implementation milestones
**M1 — Core types and gates:** `CharacterPolicy`, `UserPreferenceStore`, `CapabilityRegistry`, `ActionIntent`, `ActionApproval`, `ActionReceipt`, `ActionPolicyEngine`; fake tool adapters and unit tests.

**M2 — User-visible status:** Approval UI and action receipt UI. Test cancellation, exact payload, unknown state, duplicate execution.

**M3 — Memory control:** Local storage and candidate/confirm/edit/delete UX, source and expiry metadata, private recall filters, migration and deletion tests.

**M4 — Live supported integration:** One low-risk tool connected end-to-end, observe actual status; expand deliberately.

**M5 — Voice and model routing:** Implement interruption, transcription confirmation for critical fields, bilingual tests and character regression pipeline.

Do not create cloud sync, vector DB, agent swarms or complex knowledge graphs merely to satisfy this policy. Choose the smallest technically sound solution and document trade-offs.
