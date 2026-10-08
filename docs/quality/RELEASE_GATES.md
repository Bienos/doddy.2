# Readiness gates
**Gate 0 / Documentation:** clear canonical spec, source provenance, ADR status, owner approvals, no contradictory outstanding blocker silently omitted.

**Gate 1 / Development foundation:** M0 real Xcode build/test evidence, credential scanning, reproducible setup, target iOS decided.

**Gate 2 / Functional memory:** M1 real persistence and migration error tests, deletion/export, no invented recall, accessibility and native QA.

**Gate 3 / Connected AI:** provider contract/terms, cost caps, data minimization/legals, real AI smoke tests, PII-free logs, injection and cancellation cases.

**Gate 4 / Voice/actions:** actual physical iPhone test for every advertised capability; transparent permission, true receipts, interrupted write handling, accessibility.

**Gate 5 / Private external beta:** participant information + consent where required, support/incident route, tested build/signing, documented privacy/security/legal and Store preflight; no unresolved critical defect.

**Gate 6 / Commercial:** actual voluntary repeat usage, controlled acquisition attribution and measured unit economics; separate decision to use in-app purchases/subscription and app-store account lifecycle.

No weighted progress score can override one failed mandatory gate. Each gate needs `owner, timestamp, revision, test evidence, legal/security signoff when applicable`.
