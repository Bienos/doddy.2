# Competitor comparison — Instinct (instinct.com) vs DODDY

**Date:** 2026-10-12. **Status:** desk research, not validated. Not a product decision or approved positioning.

## Evidence quality

- **OBSERVED (first-party):** the instinct.com landing page, fetched 2026-10-12. It is thin: no pricing, no named audience, little on how the product works. It links to a privacy policy and terms of service that were **not** read.
- **SECONDARY (unverified):** third-party write-ups surfaced by web search (eesel.ai guides, a Vellum breakdown, a TechCrunch item). Details below marked *(secondary)* come from these and need a primary-source check before anyone relies on them. This includes the funding/valuation figure.
- **DODDY side:** taken from `README.md` and `docs/product/PRODUCT_REQUIREMENTS.md`. DODDY is a proposed documentation baseline. No native app has been built or tested, so every DODDY behavior below is a plan, not shipped functionality.

## What Instinct is

A personal assistant you text or call rather than open as an app. Its own words: "a personal assistant that understands what you're working on and what's important to you," with "no new interfaces." It "can use a phone and computer in the same way that humans do." Example tasks on the page: disputing an unwarranted bill, sending birthday gifts, ordering groceries, scheduling doctor's appointments, planning a weekend getaway.

Reported by third parties *(secondary)*:

- Built by Spear Street Technology, Inc. (San Francisco).
- Invite-only beta with a waitlist; 18+; one account per person; signup by phone number and SMS code.
- Reached via iMessage or WhatsApp, plus a Mac app and a web workspace (app.instinct.com) for connections and settings. Has expanded into group chats.
- Connects to email, messaging, screen, audio and location.
- Model training on user data is on by default, with an opt-out. The terms reportedly say actions may not always be reversible and disclaim responsibility for unintended actions.
- Reported valuation of $10B at its latest funding round (TechCrunch, via search snippet; not verified).

## Side-by-side

| | **Instinct** | **DODDY (V2 baseline)** |
|---|---|---|
| Pitch | Understands what you're working on; gets things done | "Your mate in your pocket." Tell Doddy before you forget; find the original later. |
| Core job | Delegated errands and admin | Explicit memory capture, then source-grounded recall |
| Interface | Text/call, iMessage/WhatsApp *(secondary)*; Mac app and web dashboard | Native iPhone app (SwiftUI), character-led |
| Autonomy | High: operates a phone and computer like a person | Low by design: exact payload plus explicit approval for any external write; "done" only on trusted provider confirmation |
| Memory | Implicit, inferred from connected data | Explicit only; immutable original, editable current text, provenance, export, delete. No passive lifelong memory. |
| Data reach | Email, messaging, screen, audio, location *(secondary)* | M1 is local-only and offline, no account. Gmail/Calendar are non-goals on day one. |
| Privacy posture | Training on by default, opt-out *(secondary)*; actions possibly irreversible *(secondary)* | Local SQLite first, no model credentials in the client, content-free analytics, deletion verified after restart |
| Access | Invite-only beta *(secondary)* | Unreleased; 18+ audience hypothesis |
| Maturity | Live and funded | Documentation baseline; M0/M1 not built |

## Where Instinct is ahead

- It does things in the world. DODDY's M1 only remembers and retrieves.
- No install or UI to learn; it lives in existing messaging apps.
- It is shipping, with real users and funding.

## Where DODDY is deliberately different

- DODDY's non-goals (`PRODUCT_REQUIREMENTS.md`) exclude unrestricted screen reading, autonomous browsing, passive lifelong memory and unbounded cloud sync. These are the capabilities Instinct's pitch rests on.
- DODDY's trust rules (never claim memory saved without a verified store operation; `unknown` is never success and is never blindly retried; model output is a proposal that typed code validates) answer the reversibility and unintended-action concerns reported about Instinct.
- DODDY is an AI character with constitution-level limits on flattery, guilt and dependency hooks.

## Positioning read

They do not compete head-on today. Instinct sells **delegation** ("get my life admin done"); DODDY sells **a memory you can trust** ("I told it, and I can find the original"). If DODDY later adds actions (M4 reminders is the first), Instinct is the cautionary reference, and DODDY's approval-bound, verified-receipt design is the counter-position.

This is a hypothesis. Nothing here shows users want a trustworthy memory more than delegation, or that the difference is visible to them.

## Open items before relying on this

1. Read Instinct's privacy policy and terms (primary source) and confirm the training-default, reversibility and liability claims.
2. Confirm pricing, platforms and access model from Instinct directly.
3. Verify the funding/valuation figure against a primary report.
4. Re-check before any external use of the comparison; the product is moving quickly.

## Sources

- https://instinct.com/ (fetched 2026-10-12)
- https://www.eesel.ai/es/blog/que-es-instinct-ai (secondary)
- https://www.vellum.ai/blog/official-instinct-breakdown (secondary)
- https://techcrunch.com/?p=3173877 (secondary; seen only as a search result)
