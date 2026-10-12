# DODDY Brain 02: Intent and reasoning

## What exists
- **Voice:** the ElevenLabs agent's LLM is the intent recognizer. It picks a tool from the 59 in `voice-agent/tools.json`.
  The app turns each call into a typed `VoiceToolRequest` (`VoiceTools.swift:158`). The enum already encodes the
  intents the brief lists:

| Brief's intent | Existing representation |
|---|---|
| QUESTION / CONVERSATION | No tool call (agent speaks); typed: `BrainRoute.assistant` |
| PERSONAL_RECALL | `.searchMemories`; typed: notes via `ContextAssembler` |
| RESEARCH | cloud `web_search`, web tools `wikipedia_*`, `get_weather` |
| TRANSLATION | `.startTranslator` / `.stopTranslator` (`TranslatorPolicy`) |
| ORGANIZATION / TASK_CREATION | `.createReminder`, `.createCalendarEvent`, `.addToList`, `.saveMemory`, cloud `add_todoist_task` … |
| MULTI_STEP_REQUEST | `propose_plan` → `PlanProposal` |
| CLARIFICATION_REQUIRED | `.needsClarification(name:, ReminderClarification)`, `PlanParse.refused` |
| Unsupported | `.unsupported(name:)`, `note_capability_gap` (ADR-440) |
| SCHEDULED_MONITORING | none (see 08) |

- **Typed:** there is no intent step. Every question gets a local note search (cheap) and one model call.

## Decision
**No new intent enum.** `VoiceToolRequest` is the intent type for actions, and `BrainRoute` is the route type for
answers. A classifier would add a model call per turn for no gain the tests can show. The router stays deterministic.
It decides *what is allowed*: consent, input limits, whether notes may go. The model decides *what is asked*.

## Reasoning provider
`AssistantClient` (`Ports.swift:155`) is the provider-neutral port. `GatewayAssistantClient` is its only real
implementation, and the gateway chooses the model server-side. Voice reasoning stays with the voice provider. A new provider
is a new `AssistantClient` (text) or `LiveVoiceLink` (voice) adapter. Neither changes the brain.

## Clarification and missing information
The existing pattern holds: parsers return a question (`ReminderClarification`, `PlanParse.refused`) and the agent asks.
Nothing is guessed and nothing is shifted to "the nearest valid time" (ADR-127/128/253).
