# Scoped autonomy and execution policy

This implements the owner's 18 November 2026 direction. `DOD-01`, `DOD-02`, `DOD-07`, `DOD-08`, `DOD-09` and `DOD-11` remain enforced through typed code and existing server gates. The user's direct instruction can be the authorization for that instruction; retrieved text and model output cannot create it.

## Act → verify → continue → report

1. Resolve the objective from the user's words and already authorized context. Use existing public/private read tools immediately; retain each connection's standing consent and OS permission.
2. Classify the actual effect. A research job, inquiry, booking, payment and message are different effects even when one tool family can represent several of them.
3. Resolve only essential ambiguity. Missing recipient identity is not permission; a known budget or preference should not be asked again.
4. Dispatch through the existing typed service. Verify the echoed payload and use its digest, account, limits and one-use approval.
5. Persist and report the provider's actual state. Queued, dialing, answered, uncertain and completed are different observations.

## Policy matrix

| Effect | Default | Code boundary |
| --- | --- | --- |
| Searches, comparisons, lookups and connected-account reads | Execute the requested read within existing scopes and budgets | `AskFirst`, `ToolGate`, cloud prepare/run and server tool allowlists |
| Personal reversible notes/lists/drafts | Existing Undo/connection/privacy rules; no new blanket prompts | Existing local-action and outside-content rules; unchanged by this patch |
| Substantial requested read-only research | The exact, recent user instruction can authorize one handoff | `RequestedWorkSession`, `ErrandDraft.validationIssues`, digest-checked `createErrand`/`approveErrand`, server caps |
| One directly requested inquiry call | Direct authorization when recipient, question, configured language and compiled preview match | `RequestedWorkSession`, live structured place destinations or explicitly spoken number, existing call-task digest approval and all dial gates |
| Booking, order, purchase/payment | Exact card approval remains | No grant can be issued for these effects; existing booking/payment enforcement is retained |
| Consequential messages, external deletion/change, private disclosure beyond the request | Existing scoped exact-payload approval | No broad `trusted`/`approved` tool argument or prompt-only bypass |
| A proposed proactive action without a direct request | Suggest; or execute only under a separately stored standing grant | Generic proactive workflow execution is not implemented; existing morning-call/radar/watch rules remain scoped |
| Unknown outcome after an attempted side effect | Reconcile the original task/provider reference | Never issue an automatic duplicate because a reply was lost |

Normal provider usage inside existing research/call caps is part of the requested operation. This creates no new purchasing capability, wallet authority, unlimited model budget or permission to make unrelated calls.

## Implemented direct-request contract

`RequestedWorkSession` is per conversation, fed only from the app's user-side final transcript path. A grant has a private turn identifier, exact typed request, effect scope and a two-minute lifetime. It is consumed synchronously before dispatch. A changed request, changed user turn, expiry, backward clock or second concurrent tool invocation cannot consume it again. Starting/ending a conversation resets it. No grant is accepted from web/email text or a model-produced boolean.

### Research

The utterance must be a recognized Polish/English research/find/compare/check command. The `words` and `brief` must match that utterance after folding and punctuation normalization. Existing length/link/schema checks still apply. Shopping priorities must come from the instruction. This intentionally supports a narrow reliable path; rephrased/expanded briefs, contextual follow-ups and unsolicited jobs keep the existing card.

The model should copy the instruction rather than invent scope. A successful handoff is queued, not completed. The worker can continue when the phone conversation ends. A failed or uncertain submission is not automatically repeated. The existing server status/adoption path is the recovery mechanism.

### Inquiry calls

The utterance must explicitly say `call … and ask …` or `zadzwoń … i zapytaj …`. The question is copied verbatim, and the effect is inquiry only. One destination must match either:

- the number explicitly spoken by the user; or
- an unambiguous named listing plus its structured phone number from a successful **live** `find_places` response in this conversation.

The new `callDestinations` response field comes from parsed provider listing fields, never generated prose, snippets or instructions. Mock results do not seed this authority cache. Two listings with the same name and different numbers are ambiguous. A changed number/question, SMS request, booking/order, deferred call, consequential-action question or unsupported call language keeps the existing card. Current server call payloads are Polish; English instruction parsing in the core is tested, but English automatic dialing is not enabled by pretending the Polish agent is an English agent.

After the server returns its compiled preview, the app checks kind, language, number, name, question, goal, recording/disclosure state, facts and calling availability. It also rechecks the current conversation, pause state and principal name. Only then does it consume the grant and call the same digest-bound approval endpoint used by the card. Existing phone verification, account isolation, hours, destination restrictions, kill switch, agent-safety checks, concurrency/cost caps and unknown-outcome behavior remain in force.

`text_result` now defaults to false for voice-created call tasks. A call instruction alone does not request an extra SMS. A user-requested text remains a separately reviewed effect on the card.

This is not a semantic authorization oracle: deictic recipients such as “them”, rewritten questions, a contact whose number was never exposed through a trusted resolver, and appointment changes still require clarification/review. The full dentist-search-and-call example remains an integration acceptance scenario, not a claimed production success.

## Proactivity and standing authorization

For a future standing grant, persist account, trigger, allowed tools/effects, destination scope, data categories, budget, schedule/time zone, expiry, revocation, notification policy and version. Show an editable human preview once; bind the accepted payload and retain its receipt. A model cannot widen it later. Price checks can execute under it; a purchase still requires purchase approval. “Research a restaurant” does not create standing calling authority.

Revocation stops new dispatch, cancels queued work, and asks running work to stop at safe boundaries. Already attempted external effects need reconciliation, not a fabricated rollback. Every recurring occurrence needs a stable idempotency identity and a durable outcome.

## Verification and risks

The new policy tests exercise positive PL/EN commands, exact scope, known/unknown recipients, ambiguity, changed parameters, repeated tools, expiry, negation, quoted instructions, delayed calls, messaging and booking boundaries. Existing call-task server tests remain necessary because client authorization is only one gate.

Voice transcription is not biometric identity. False ASR, a nearby speaker, device lock transitions, real agent argument generation and exact user phrasing need device evaluation. The native controller wiring is not compiled in this Linux session. The default safe fallback is the existing card, not a permissive guessed grant. See [test results](DODDY_AGENT_TEST_RESULTS.md) for executed checks.
