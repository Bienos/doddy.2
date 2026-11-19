# Technology review and current-source evidence

Research date: 18 November 2026. Capability discovery and actual account/device availability are separate claims.

## Official sources inspected

1. [Official ElevenLabs Python SDK README](https://github.com/elevenlabs/elevenlabs-python/blob/4c1a8ec4258e026b31c391cad76712b9bb34b460/README.md) and generated resources at commit `4c1a8ec4258e026b31c391cad76712b9bb34b460`, retrieved from the official repository. Downloaded archive SHA-256: `66bfaf9109dabbe702b6bf4b3c68cd80a8c4917f40ee74915f6e574de11e8f88`. Source was inspected, not executed or installed as a new application dependency.
2. [Agents resource](https://github.com/elevenlabs/elevenlabs-python/blob/4c1a8ec4258e026b31c391cad76712b9bb34b460/src/elevenlabs/conversational_ai/agents/client.py): documented get/list/create/update bindings. Read endpoints support comparing a fresh agent configuration with repository expectations. Their existence does not prove account permission or configuration.
3. [Twilio resource](https://github.com/elevenlabs/elevenlabs-python/blob/4c1a8ec4258e026b31c391cad76712b9bb34b460/src/elevenlabs/conversational_ai/twilio/client.py): outbound-call and register-call bindings. The repository's bridge can be evaluated against a supported official API rather than an invented calling capability.
4. [Conversations resource](https://github.com/elevenlabs/elevenlabs-python/blob/4c1a8ec4258e026b31c391cad76712b9bb34b460/src/elevenlabs/conversational_ai/conversations/client.py): get/list, token/URL, summary, deletion and related conversation resources. Historical transcript/analysis access still requires the right account and privacy authorization.
5. [Agent branches](https://github.com/elevenlabs/elevenlabs-python/blob/4c1a8ec4258e026b31c391cad76712b9bb34b460/src/elevenlabs/conversational_ai/agents/branches/client.py), and the SDK's deployments/drafts resources: official configuration-management surfaces exist. No branch, agent, number or deployment was created in this audit.
6. Repository-pinned iOS SDK integration, `Config/Package.resolved`, `VoiceSessionController.swift`, task-call provider code, agent safety/spec checks and the local test suites provide application-specific evidence. Local mocks establish protocol behavior, not carrier or realtime audio quality.
7. [Pinned official Swift SDK callback](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/5bb21c2cdb54bf465f6bb09ce52fc59b0e22aae5/Sources/ElevenLabs/Public/Conversation/ConversationConfig.swift) and [event dispatch](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/5bb21c2cdb54bf465f6bb09ce52fc59b0e22aae5/Sources/ElevenLabs/Internal/Conversation/Conversation%2BEvents.swift), matching repository SDK 3.3.1: `onUserTranscript` receives user-transcript text and an integer event ID. The second argument is not an identity or approval flag. DODDY now fences that callback by its connection attempt before recording authorization context. Source inspection is not a native compilation, ASR-accuracy or speaker-authentication test.

The direct ElevenLabs docs URL and Apple ActivityKit documentation request were denied by the environment proxy. Their contents were **not freshly read**. Apple framework usage is grounded in existing project patterns; exact current ActivityKit/BackgroundTasks availability, limits and HIG compliance are **NOT YET VERIFIED**. Native iOS compilation and device testing remain required. Do not cite an assumed activity duration or unrestricted background runtime as established evidence from this audit.

## Architecture comparison

| Option | Advantage relevant to DODDY | Cost/complexity/reliability tradeoff | Decision |
| --- | --- | --- | --- |
| Existing ElevenLabs voice plus typed DODDY services and PostgreSQL workers | Matches the implemented trust boundary, encrypted tasks, provider receipts and constrained research | Several feature-specific state machines; explicit checkpoint/attempt work is still needed | Improve this path now; exercised locally without a new runtime |
| ElevenLabs outbound API instead of part of the custom Twilio bridge | Official calling primitive could reduce some glue for a specific provider path | Must preserve DODDY's dispatch gates, one-use authorization, status reconciliation, takeover, deletion and cost accounting; account support and comparative latency were not tested | Evaluate in a separately authorized test-number experiment; no production switch justified yet |
| Durable workflow platform such as Temporal | Could centralize persisted multi-step execution, timers and workflow recovery | New operational/service surface, deterministic execution/versioning discipline and explicit side-effect idempotency still required; no DODDY benchmark or deployment proof | Candidate for a later measured migration, not a dependency added here |
| Graph/agent runtime for planner state and checkpoints | Could support explicit multi-step plans and human review points | Model-generated plans still need DODDY's typed authority and tool limits; persistence, replay cost, account boundaries and cancellation are not obtained merely by adding a library | No demonstrated advantage over repairing current bounded workers in this slice |
| More orchestration in the voice prompt | Easy to change conversation behavior | A prompt does not persist tasks, enforce ownership, grant permissions or confirm provider effects | Use for phrasing/tool selection only; authority and execution stay in code |
| iPhone-only long-running agent | Low server dependency for short local work | Normal app execution can be suspended; cloud research and calls already belong to servers | Keep local short operations local; no indefinite-agent promise |

The comparison is an engineering assessment, not a latency/cost benchmark of uninstalled products. No claim is made that a new runtime will increase completion rate until a representative migration experiment demonstrates it.

## Measurable experiments before a technology change

- Use the same 12 scenario families, user scopes and provider stand-ins for every candidate. Record completed/partial/failed/unknown separately.
- Measure wall-clock first useful response and actual task completion, repeated provider effects, queue recovery, cancellation, omitted/invented report facts and actual billed usage. Fixture runtimes are not iPhone voice latency.
- Exercise worker restart between every pair of durable transitions; preserve one occurrence/attempt identity and task-wide budget.
- For calling, compare the existing bridge and official outbound primitive on an explicitly authorized test number with identical question/language/duration. A returned call ID does not establish connection or a correct answer.
- For report generation, use authorized historical calls with redacted identifying data plus synthetic refusal/hedge/conditional/contradictory cases. Keep source evidence and classify omission separately from hallucination.

## Live inspection still required

Read the current main, phone, inquiry, booking, order and translator configurations and attached tools; compare canonical hashes, IDs, model, language, max duration, first message, variables, system tools, client overrides, telephony binding, webhook signatures, recording and retention. Do not print secrets or copy historical transcripts into a public report. Compare a fresh snapshot rather than treating November 15 notes as current drift.

The requested connectors' read tools were not exposed in this session. GitHub read operations over the existing Git proxy worked; GitHub API calls returned `Forbidden`. No personal token was requested or extracted. Once read access is available, the existing `scripts/voice_agent_spec.py compare` workflow should consume an authorized configuration snapshot; production writes require a separate exact reviewed change. These are concrete integration blockers, not a claim that ElevenLabs or GitHub is generally unavailable.
