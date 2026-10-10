# Ready-to-paste initial prompt for Codex or Claude Code

You are building DODDY V2 **from scratch in the current NEW repository**. Do not read from or modify any legacy DODDY repository unless I explicitly request it.

Read the DODDY AI Constitution pack included in this repository (`README_START_HERE.md`, `docs/trust/`, `config/doddy_rules.yaml`, `research/`, `evals/`). Treat it as a proposed requirements baseline; identify contradictions, missing platform capability verification, and security/legal assumptions. Read brand guidelines if present and preserve the defined character identity. Do not invent or fill absent brand assets.

FIRST MILESTONE ONLY:
1. Audit the repository and list existing implementation vs mocks vs missing parts.
2. Propose the smallest iOS-first module boundaries and typed models needed for: (a) persona context routing, (b) preferences, (c) action intent/approval/status/receipt, (d) capability registry, and (e) opt-in local memory interface. Do NOT build every integration.
3. Implement one isolated end-to-end **mock-tool** path: propose a send/draft-like action; display exact payload, ask for explicit approval, execute through a fake adapter, show confirmed/failed/unknown receipt. Mock actions must be labelled in app/tests as simulation, not real sends.
4. Enforce approval and execution state transitions in application code, not in the LLM prompt. Ensure modified payload invalidates approval; unknown provider outcomes cannot produce success or blind retries.
5. Add automated tests for all critical state transitions, unauthorised calls, fake successes, cancellation and duplicate execution attempts. Add basic character scenarios (no sycophancy; no sensitive-context joking) as test fixtures, describing which are manual.
6. Give a concise report with files created, test commands and results, gaps, next milestone. Do not claim to have verified live integrations or data deletion until implemented and tested.

TECHNICAL DEFAULTS: prefer a simple, modular Swift / SwiftUI design and local-first storage where practical. Verify current platform SDK support before committing. Avoid premature cloud infrastructure, vector databases, cross-device sync or multi-agent orchestration. Maintain a clear separation between model text and trusted authorisation/data logic.

Do not skip the first milestone or attempt to implement the entire product in one operation. Ask me to resolve only blocking architecture decisions; otherwise choose documented reversible defaults.
