# AI runtime, grounding and provider gateway
## M1 is offline, M2 introduces model intelligence
Do not ship `MockAIService` under the impression it answers real user questions. For M1, local capture and recall are deterministic. For M2, add real text model behind typed `AssistantClient`, with local memory retrieval as explicit separate capability.

## Request flow
```
User prompt → intent/risk classification → permissioned context selection
→ lexical memory candidates (only if relevant + allowed)
→ minimal disclosure and request assembly → HTTPS gateway with server-side key
→ AI model/provider → response contract validation + cited memory-ID verification
→ final text → user-visible source/uncertainty + opt-in save proposal
```
Model output is never authoritative for external action state. Prompt text from websites, memory or tools is lower trust than system/device policy. Treat model tool calls as *proposals*, not permission grants.

## Client request contract
- `sessionId` random UUID, `requestId` random UUID, `taskType` enumerated, `locale`, consented style flags, minimal last turns, zero or more selected allowed memory snippets `{id, currentText, source}`.
- No bulk export of memory, background uploads or content-rich analytics.
- Egress audit for what leaves device, why, which provider, data retention and transfer treatment. Cloud model requires clear user-facing notice and privacy-policy disclosure.
- Gateway authenticates anonymous devices/session quotas without assuming persistent personal profiles; formal solution chosen in M2 security design. Apply rate limiting, retries with bounded exponential backoff, cancellation, response validation and cost instrumentation without raw content logs.

## Retrieval-augmented personal answers
Local query yields `candidateIds`. Include only explicit allowed records. A model response may summarize existing selected records and cite IDs, but may not invent an unseen memory. Post-response verifier checks every returned citation ID belongs to submitted candidate set; otherwise refuse provenance claim. Distinguish "I found this saved note" from "I think ...".

## Error taxonomy
`notAuthorized`, `offline`, `timeout`, `rateLimited`, `providerUnavailable`, `unsafeToolRequest`, `invalidCitations`, `cancelled`. Any network failure preserves local unsaved drafts and local memory operations. Sensitive context must not appear in URL query, request logs, crash metadata or alert titles.

## Persona policy
Read compact character rules in `docs/design/BRAND_AND_CHARACTER.md`, and the full character sources under `reference/`. For serious/high-risk tasks, humor off. Don't create fabricated human experiences or relationship pressure. User controls verbosity, joking, spoken output, language, explicit memory.

## Production gate
Current provider pricing, DPA, subprocessor/region details, EU transfer and retention settings, input/output moderation, key security, spending limits and abuse protections must be checked at implementation time. No provider-specific rates in this document are guaranteed current.
