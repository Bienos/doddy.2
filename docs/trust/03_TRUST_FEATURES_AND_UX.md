# Doddy Trust System — UX and objection-to-benefit specification

## Product principle
Do not ask users to “trust AI.” Give them tools to **inspect it, control it, correct it, and verify what it did**. Explain trust in natural language, at the point of use. Avoid presenting a complex settings questionnaire before users see value.

## Recommended MVP: five visible trust features

### UX-01 — Memory Wallet (`What Doddy remembers`)
**Concern → benefit:** “AI remembers too much or forgets unpredictably” → useful personalisation with reviewable control.

**User can:** see a list of saved memory records; understand their source and last updated date; edit/remove them; choose a retention/expiry preference; switch long-term memory off. User request “forget that” should open a clear, working deletion flow (with disclosure of any remaining logs/backups as applicable).

**Suggested memory card fields:** short memory statement, category, saved_at, source class, optional expiry, confirmation state. Do not expose unrelated raw conversation excerpts as the default view.

**Default:** only explicitly approved long-term memories until the user selects a well-explained non-sensitive auto-save preference. Sensitive categories require heightened controls and legal assessment, not automatic storage.

**Demonstrable moment:** “You told me you like short answers. Want me to keep that in mind?” → [Remember] [Just this chat].

**Required implementation:** real persistent storage with per-record user ID/scope, source/provenance and deletion handling. No fictitious “I forgot” response when deletion has not occurred.

### UX-02 — Action Receipts (`What Doddy has actually done`)
**Concern → benefit:** “The agent says it's done but I don't know” → verifiable outcomes.

**User sees:** proposed action, target/recipient, crucial fields (time, cost, amount, content), authorisation status, external provider result and status timestamp. For uncertain outcomes, show *Couldn't confirm* instead of success.

**Status wording:** Draft → Needs approval → In progress → Confirmed / Failed / Couldn't confirm. Optional Cancelled and Expired statuses.

**Demonstrable moment:** “I've drafted it. I haven't sent it.” After confirmation and provider acknowledgement: “Sent to [recipient] at [timestamp].” Use redacted views for private recipients and content when privacy requires.

**Required implementation:** explicit state machine; trusted provider result; idempotency/duplicate protection; no unauthorised retry after ambiguous timeout.

### UX-03 — Action Control (`What Doddy can do`)
**Concern → benefit:** “It acts without consent” → understandable capability boundaries.

**User can:** inspect connected services, revoke access, see individual feature permissions, review pending approvals, and disable proactivity. MVP sends/posts/purchases/bookings/deletions always need confirmation of exact action.

**Approval screen:** what / where / who / when / cost / permanence / editable details. Confirm and Cancel. Dangerous actions cannot be authorised by merely saying “sure” to an ambiguously described action.

**Required implementation:** policy enforcement in client/service/tool gateway, scoped tokens and API authorisation. Never trust a generated statement of consent as the sole security control.

**When consent is asked (owner, 2026-10-11, ADR-324):** never up front. A capability is unlocked by a card in the conversation at the moment a request needs it, for that one thing, and stays unlocked until revoked here. See `docs/product/UNLOCK_AS_YOU_GO.md`.

### UX-04 — Reality Check (`How Doddy knows`)
**Concern → benefit:** “AI invents facts” → transparent sources and uncertainty.

**User sees when relevant:** citation/source link or named provider, source freshness, whether the answer was verified, and transparent uncertainty. Avoid fake numeric confidence percentages if not calibrated.

**Demonstrable moment:** “This is based on the service's current status. I haven't independently confirmed it.”

**Required implementation:** citations bound to actual retrieved sources; tool invocation/provenance metadata; no fabricated references.

### UX-05 — Your Doddy (`How Doddy behaves`)
**Concern → benefit:** “It's fake, repetitive, intrusive” → controlled personality without losing character identity.

**User can:** select balanced/direct/playful, change length, restrict nicknames, disable proactive nudges, choose language and access quiet settings. Contextual safety overrides remain active.

**Demonstrable moment:** “Less sarcasm.” → immediate style change, optional save-as-default only through a real preference update.

**Required implementation:** typed persisted preferences read into conversation context; prefer compatibility-safe defaults; regression tests.

## Phase 2 (validate before building)
- Fine-grained memory expiration rules and topic-specific privacy boundaries.
- Rich audit history/export of action receipts and important changes.
- Pre-approved low-risk workflows *only after* clear scopes, revocation, and dedicated tests.
- Proactive assistance with topic/time quiet windows, frequency limits and explicit opt-in.
- User-friendly controls for individual remote model providers and retention if operationally supported.

## Journey examples
**Saving a preference:** User: “I prefer concise answers.” Doddy: “I can keep that for future chats. Save it?” If confirmed, persist memory and show confirmation. If declined, obey for current conversation without persistent retention.

**Booking:** User: “Book a table for four tomorrow at seven.” Doddy checks supported availability; presents restaurant/time/party/cancellation terms and asks approval; executes exactly the approved payload; only reports success when confirmed. If unavailable, reports only verified alternatives; never invents a slot.

**Sensitive moment:** User raises distress. Doddy is calm, does not joke, does not infer a diagnosis or automatically store personal disclosures, and gives proportionate human-help options.

**Error recovery:** Provider call times out. Show “Couldn't confirm”; do not retry a non-idempotent write until a status reconciliation or explicit safe recovery process completes.

## Priority decision
Build UX-02 and UX-03 as foundational to real actions. Build UX-01 alongside actual memory storage, not ahead of it. UX-04 can start with basic source/status labels. UX-05 should be a slim configuration view, not a full character editor. Every feature should be demonstrably functional before being used in marketing.
