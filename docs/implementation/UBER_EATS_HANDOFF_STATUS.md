# Uber Eats handoff status

Updated: 2026-10-16.

## Implemented in the app source

- A list menu can open a handoff sheet showing the list's open items. The user can share or copy the list through the iOS share sheet, then open Uber Eats.
- In voice mode, `open_ubereats` proposes a confirmation card. Only after the user taps **Open Uber Eats** does Doddy open `https://www.ubereats.com/`.
- The order summary shown on the voice card stays in Doddy. It is not placed in a URL, sent to Uber, or written to the local activity receipt.
- The app says that no cart or order was created. The user chooses the restaurant and items and completes review and checkout in Uber Eats.
- `Pause all connections` blocks the handoff. Translator mode refuses it like other tools.

## Not implemented or verified

- No Uber Eats marketplace, menu, cart, checkout, payment, order-status, or delivery API is connected.
- No Uber Direct integration is present. Direct-delivery access would be a separate merchant/fulfillment integration.
- This cloud environment's restricted network policy does not allow Uber developer domains, and it has no Uber credentials or partner access. Current official API eligibility, terms, and market availability could not be verified here. Do not infer API access from this handoff.
- The iOS app has not been built or tested on a device in this task. The public website URL may open the Uber Eats app through iOS universal-link handling or open the website; that behavior is not verified here.
- The new `open_ubereats` tool is marked `not_synced` in the local ElevenLabs spec. It is available to the app's bundled OpenAI Realtime spec after building the app; ElevenLabs needs the tool and prompt synchronized before its live agent can call it.

## Next gate for direct ordering

Obtain written access to the specific Uber Eats partner API for the intended market, verify that it supports the required consumer ordering steps, and provide approved sandbox credentials securely. Then design the server-side account connection, menu/cart adapters, exact-order approval, idempotency, payment handoff, and provider-verified order receipt before implementing checkout.

## Constitution evidence log (`docs/trust/config/doddy_rules.yaml`)

| Rule | Evidence | Limitation |
| --- | --- | --- |
| DOD-07 `scoped_action_approval` | Voice tool is `.handoff`/`.card`; the action runs only after **Open Uber Eats**. The list UI exposes a share sheet and a separate link for the user to choose. | Card and sheet UI have not been compiled or exercised on iOS. |
| DOD-08 `verified_status_and_receipts` | Reply distinguishes an opened app from an order; it explicitly says no cart or order was created. Activity receipt omits the proposed items. | Universal-link behavior and the spoken follow-up have not been exercised on a device. |
| DOD-11 `observable_privacy` | `Pause all connections` blocks the handoff; the summary stays local, is not put in the URL or activity receipt, and list items leave only through the user-triggered share sheet. | iOS share destinations are user-selected; the app cannot control where the user shares the list. ElevenLabs has not been synchronized with this tool. |
