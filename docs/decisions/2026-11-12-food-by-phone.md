# Doddy can order food by phone from a restaurant, on a separate agent that may accept only the order on the card

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026: "Both and merge" (the restaurant's page and ordering by phone), then, on the two open questions: **pay on delivery only**, and the **address typed on the card each time**.
- **Status:** proposed design; no code yet. Built in the steps below, each its own pull request, after `2026-11-12-food-by-voice` (#355) is merged.
- **Replaces:** nothing. Extends `2026-11-12-book-agent` (same pattern, a third agent) and sits beside `2026-11-12-food-by-voice` (the person's own app, no phone call).

## Why
No delivery company lets another app order on a person's own account in Poland (`2026-11-12-food-by-voice`). Many restaurants still take orders by phone. Doddy already phones places and, since #354, books for the person on a card they approved. An order is the same shape: a short list of exact details the person approves, one yes from the other side.

## Decision
1. **A third kind, `order`, and a separate agent** ("Doddy · Zamawia za Ciebie"), made from `voice-agent/task-call-order/` the way the booking agent was made from the ask agent: same voice and settings, only the prompt, name and tags change. The server checks it against its own spec (`TASK_ORDER_AGENT_SPEC`) and refuses order calls while it differs. Off until `ELEVENLABS_TASK_ORDER_AGENT_ID` is set (503 `order_not_configured`; `availability` says `order: false`).
2. **The card is the order.** An `order` task carries `order`: up to 8 lines (`quantity`, `name`, an optional short `note` such as "bez cebuli"), the name it is under, the **delivery address** (street, flat, postcode, city) and the person's **phone number**, or `pickup: true` with no address. The server builds every sentence from it in code (as `booking.ts` does): the question, the lines the agent reads, the **one confirmation sentence** ("Dobrze, proszę o zamówienie: 2 × pizza margherita, 1 × cola, dostawa na ul. Długa 5 m. 12, 00-001 Warszawa, płatność gotówką lub kartą przy odbiorze, na nazwisko Anna Kowalska."). A question written by the app or the model is refused.
3. **Payment: on delivery or at pickup only.** The card says so. Doddy never gives a card number, a BLIK code, an account number or any payment detail on a call. A seller who asks for prepayment, a deposit, a link or a different dish gets "Dziękuję, w takim razie nie zamawiam" and the task ends as "not ordered".
4. **The address is typed on the card each time.** It is sent only for that one call, kept encrypted with the task and erased when the task ends, like the Uber delivery payload (`2026-11-12-uber-direct-deliveries`). Nothing is saved as a home address. It is read to the restaurant only after they say they deliver.
5. **What counts as ordered, decided in code** (as for a booking, `2026-11-12-book-agent` point 3): Doddy said the confirmation sentence (found in the transcript), the result step says the seller agreed to exactly that order, there is a quote of their words, and Doddy said no other commitment word. Anything less ends as "unclear" for the person to read; "ordered" is never claimed and the next place is never called. An order has **one** place, not three: a second restaurant is a new card, so Doddy can never order twice.
6. **Price and time are theirs, not Doddy's.** The agent may write down the total and the delivery time the seller says, as a quote in the result; it never accepts a total above the cap on the card (the person picks it, default 150 zł) and never invents either.
7. **The same limits as every call:** one tap per task (the digest covers the kind, the lines, the address and the cap), calling hours, Polish numbers, the daily caps, the stop list, the kill switch. The result comes back by push: "<place> przyjęło zamówienie: „…”", with the total and time as quoted, or why not.
8. **The app's card** (step 3) shows exactly the lines above, the address as typed, "Płatność przy odbiorze. Doddy nie poda danych karty", and a **Call and order** button. Voice tool `order_by_phone` (`ask: tap`, `confirm_on_screen`) only proposes the card; the tap is the approval (ASK-01, DOD-07).

## Steps (each its own pull request)
1. Server: `order` schema, sentences, migration 029 (widens the two `kind` CHECKs and adds an encrypted `order` payload), brief and result rules, agent spec, drift check, tests with fake Twilio and ElevenLabs. Off.
2. Agent: `voice-agent/task-call-order/`, `scripts/voice_agent_spec.py check --agent task-call-order`, setup script. The **live** ElevenLabs agent is created only on the owner's separate word (owner queue).
3. App: DoddyCore model and parser (like #367), card, tool, activity row; then the tool in `voice-agent/tools.json`.

## Consequences
- An order by phone is a purchase in the person's name and shares a home address and phone number with a third party. The card is the only place they come from, the confirmation sentence is fixed, and the address is erased with the task.
- Doddy can't check that food arrives; the push says what the seller said, not that it was delivered.
- Before anyone but the owner uses it, the open questions of `calls.md` (a legal basis for transcribing the other side, a never-call-me list) still apply, and now also: what a restaurant may do with a number it was given by an AI caller.

## Not decided here
- A cap default and whether to allow pickup in the first release (proposed: both).
- Whether the order agent may take the person's phone number from the card or only say it to the courier.
