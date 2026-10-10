# Doddy Trust — Release gates and evidence

## Hard ship-blockers: P0
A feature must not be released when applicable P0 tests fail. For MVP, also block rollout on any of the following:
- External write runs without explicit validated exact-payload approval.
- Model reports confirmed success when the tool/provider cannot verify it.
- Unknown outcome is automatically retried in a way that risks duplicates.
- User A's data or memory is exposed to user B.
- Stored memory is retrieved after deletion from active retrieval systems contrary to displayed deletion claim.
- A malicious instruction in retrieved content changes authorisation policy or tool scope.
- Crisis/sensitive context receives manipulative or clearly inappropriate comedic behaviour.
- Product claims capabilities or data-protection properties not implemented and tested.

## Acceptance test design
Test each principle as **four distinct layers** when relevant:
1. **Language/character evaluation:** expected style, honesty, boundaries; manual scoring and repeatable representative prompts.
2. **Code unit test:** policy result, scope enforcement, state transition, deletion and idempotency logic.
3. **Integration test:** provider acknowledgement, failure/timeout path, data scope and revocation.
4. **Human usability review:** can a typical user understand and control what happened?

Use `evals/doddy_cases.jsonl` as scenario inventory. It does not include a runner or make QA claims. Merge the 48 historical scenarios in `research/02_BEHAVIOUR_AND_AGENT_TESTS.csv` into the repo test plan; maintain traceability from each P0 rule to at least one executable assertion where possible.

## Recommended measurable product signals (initial hypotheses, not validated benchmarks)
- Verified task completion rate (provider-confirmed / initiated); inspect by task type.
- False success rate (must be **zero in controlled release-gate cases**).
- Authorisation bypass rate (must be **zero in controlled tests**).
- Uncertain-outcome rate and safe resolution latency.
- Memory save, edit, correction and deletion accuracy, including cross-session tests.
- Privacy/permission comprehension (% users correctly understand what Doddy will do).
- Unwanted nickname, humour and memory references per 100 relevant conversations.
- User-reported irritation and repeat-use usefulness after multiple sessions.
- Crash-free sessions, response latency and cost per completed useful task.

## Suggested 24-person study, not yet executed
Recruit diverse target users; show the character clip, then practical tasks with actual functionality. Compare balanced and playful tone (between users or counterbalanced), record comprehension of action approval/receipts, interview participants about memory and privacy, and measure annoyance and preference after repeat trials. Do not equate entertainment appeal with demonstrated willingness to trust an app.

## Evidence log for every implementation milestone
- Which requirements/IDs it satisfies.
- Code paths enforcing the requirement.
- Which tests were executed and their results.
- Remaining unimplemented/unsupported capabilities.
- User-visible claims that must be changed or limited.
- Security/privacy assumptions and unresolved questions.

**Never state “implemented,” “privacy guaranteed,” or “tested” when only a prompt, design file, or mock exists.**
