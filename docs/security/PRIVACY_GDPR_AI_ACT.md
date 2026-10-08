# Privacy, security and regulatory preflight (NOT legal advice / clearance)
## Architecture posture
Minimise collection; M1 local-first without login or cloud memory. Provide opt-in memory saves, source trace, editing, explicit deletion, data export and private sessions. If features send content off-device, explain provider, purpose, categories, retention and geography *before enabling* and obtain valid permissions as applicable.

## Data inventory / controller worksheet (complete before beta)
| Data class | M1 storage | Purpose | Third-party flow | Controls | Status |
|---|---|---|---|---|---|
| Explicit saved note | Protected local SQLite | User memory/retrieval | None M1 | Export/correct/delete | Proposed |
| Original and edited versions | Local database | Provenance | None M1 | Show original, delete both | Proposed |
| Temporary chat | RAM | Current help | No cloud M1; M2 provider if enabled | No-history option | Proposed |
| Voice audio | RAM only M3 by default | ASR/TTS | Route-dependent | Mic disclosure/stop | Not designed/verified |
| External reminder | Apple system/EventKit | User-approved follow-through | Apple on user device | Confirmation + receipt | M4 only |
| Anonymous event counters | Local or approved limited telemetry | Evaluate task outcomes | Depends on telemetry plan | Consent/settings, retention | Decision required |
| Device/service tokens | Keychain/gateway | API protection | Cloud backend M2 | Rotation/revocation | Future |

## GDPR work items
Confirm controller and processors; map legal bases by purpose; comply with privacy by design/default, minimisation, retention, transparent notices, valid data-subject processes, processor agreements and international transfer rules if applicable. Define deletion/export support, security incident response and any DPIA requirement after actual flow assessment. Do not state "GDPR compliant" because a checklist exists. Data Protection on the phone does not guarantee total deletion of OS/cloud backups, and a local app can still process personal data subject to GDPR.

## EU AI Act and transparency
Show clear AI identity and limitations and review potentially relevant transparency and deployment obligations under applicable current law. Distinguish role (provider/deployer of product, supplier/provider of underlying model), specific practices and effective dates. Article 50 timing/applicability and amendments require specialist review. Character is fictional; never present a real person or human operator in AI interactions.

## App Store / iOS
App Review Guidelines, privacy labels, nutrition labels/disclosures, mic/speech descriptions, Sign in with Apple requirements if accounts added, account-deletion UI when offered, minors policy, data safety and subscription claims require launch review. Dynamic Island/shortcut actions must follow supported APIs, not platform-exploit behavior.

## Privacy threat controls
- Local: protected file locations, SQLite WAL/SHM, backups, clipboard leakage, screen snapshots/switcher, lock state.
- Model: prompt injection, overbroad personal context, provider transcript retention, SSRF/content instructions if web later used.
- Actions: duplicate write, stale permission, wrong timezone, ambiguous target, fabricated receipt, wrong recipient.
- Operations: leaked keys, oversized payloads, abusive cost usage, uncontrolled logs, crash reports with transcripts, compromised dependencies.

## Release blockers
No production/beta release until verified: user notice, personal-data flow map, processor/vendor controls, Apple entitlement usage, security checklist, export/deletion test, consent/permission UI, provider DPA/retention, appropriate qualified legal assessment. Record named reviewer, date and version.

## Authoritative starting references (recheck during implementation)
- EU GDPR text: https://eur-lex.europa.eu/eli/reg/2016/679/oj
- EDPB SME GDPR guidance: https://www.edpb.europa.eu/sme-be-compliant/be-compliant_en
- EU AI Act: https://eur-lex.europa.eu/eli/reg/2024/1689/oj
- Apple App Review: https://developer.apple.com/app-store/review/guidelines/
- Apple Account Deletion: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion
