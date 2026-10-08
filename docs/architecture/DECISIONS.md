# Architecture Decision Register (proposed, not implemented)
| ADR | Candidate decision | Reason | Revisit gate |
|---|---|---|---|
| 001 | Greenfield repo `Bienos/doddy.2`, preserve prototype read-only | Prevent old demo code/scope contamination | M0 repo setup |
| 002 | iOS17+ SwiftUI + Swift Concurrency | Broad iPhone support and native core | Validate Xcode + deployment SDK in M0 |
| 003 | Local-first SQLite via GRDB | Transactional persistence, migrations, FTS5; no mandatory backend for M1 | Library/tool security + implementation test |
| 004 | Exact original text and immutable provenance | Avoid fabricated personal memory and enable corrections | Data acceptance tests |
| 005 | Lexical/FTS candidate retrieval first | Inspectable, repeatable, easy to evaluate | After corpus tests justify embeddings |
| 006 | Provider-neutral AI interface, server-side cloud-key proxy | Credentials out of app; replace provider; control quotas | M2 with cost/legal review |
| 007 | Typed tool schema, user confirmation, receipts | A model cannot authorize side effects | M4 |
| 008 | No account/cloud sync/central Postgres until demanded | Minimize personal-data exposure and cost | Post-M5 retained user need |
| 009 | Character prompt separate from safety, data and action policy | Personality cannot override truth | M2/M3 persona evals |
| 010 | Choose ONE brand ZIP as master only after art QA | Two versions of v1.3 differ | M0 design signoff |
| 011 | Telemetry is content-free and separately controlled | Privacy minimization | Legal/data review before beta |
| 012 | Source files under `reference/` never override canonical docs | Archive contains conflicting historical build prompts | Always |

**Owner action:** mark each ADR `accepted / rejected / needs investigation` in the new repository and record evidence + date; this table is a proposal, not implied approval.
