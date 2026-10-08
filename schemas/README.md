# Machine contracts — PROPOSED
`memory.schema.json`: serialization contract and provenance semantics. Nullable `capturedAtMs` exists only for imported records with unknown historic timestamp; actual M1 saving always fills it. `tool_proposal.schema.json`: M4 action proposals are *not permission*; typed application policy and native receipt enforce authorization. `telemetry.schema.json`: allowlisted content-free event envelope; storage/transmission awaits legal/privacy approval. See docs/architecture for full implementation decisions.

JSON Schema checks syntax/shape; it cannot prove user consent, secure persistence, proper deletion, or correct external action. Build those invariants as code + tests.
