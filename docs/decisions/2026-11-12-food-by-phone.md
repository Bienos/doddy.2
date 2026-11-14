# Doddy can order food by phone from a restaurant, on a separate agent that may accept only the order on the card

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026: "Both and merge" (the restaurant's page and ordering by phone), then, on the two open questions: **pay on delivery only**, and the **address typed on the card each time**.
- **Status:** design merged (#371). Step 1 (server and agent folder) is in the pull request that adds this line; step 3a (DoddyCore model and parser, #435) is merged; step 3b (the card, the availability check and the `order_*` fields of `call_places` in `tools.json`) is in its own pull request. Built in the steps below, each its own pull request, after `2026-11-12-food-by-voice` (#355, merged 12 Nov 2026).
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

## What step 1 changed from the design above
- **The courier's phone** is a Polish number kept as nine digits ("600 000 000"; a typed "+48" is dropped), so the call audit never reads it as a PESEL.
- **Number audit:** a postcode or phone number that is on the card (`doddy_order`) is no longer "a number Doddy wasn't given"; without that every delivery order would have ended "unclear". A number that isn't on the card still warns.
- **With #396 (booking audit, no goal in the prompt):** the order prompt has no `{{doddy_goal}}` either (the card holds it; the server sends a fixed sentence). The new audit flags a yes while the seller offers another time, price or a condition; for an order the only price that counts is one **above the card's highest total**, so the seller naming the total or a dish price, or a delivery time, is the answer and not an offer, while prepayment and a total above the cap are. Without this every real order would have ended "unclear".
- **Erased with the task:** the brief (address, phone) is deleted the moment the task ends, not when the phone acknowledges the result.
- **Agent and spec:** `voice-agent/task-call-order/` (prompt, session, no tools beyond `end_call` and voicemail), `TASK_ORDER_AGENT_SPEC`, `scripts/voice_agent_spec.py check --agent task-call-order` in `scripts/ci.sh`, `setup-task-call-agent.mjs --agent order`. Migration `037_order_calls.sql` only widens two CHECKs.
- **Off until set up** (owner queue 61): without `ELEVENLABS_TASK_ORDER_AGENT_ID`, 503 `order_not_configured`; `/v1/call-cases/availability` gains `order`, `orderAgentConfigured`, `orderAgentProblems`.
- An order is meant to go through a task (one place). A single call case of kind `order` is accepted by the server like a booking one, but its brief is then deleted only when the phone acknowledges the result.

## What step 3 changed from the design above
- **No separate `order_by_phone` tool.** Like a booking, an order is `call_places` with `order_*` fields and exactly one place (`order_name`, `order_item_names` with `order_item_quantities` and optional `order_item_notes`, then `order_street`, `order_apartment`, `order_postcode`, `order_city`, `order_phone` or `order_pickup`, and optional `order_max_total_pln`). The tool stays `ask: tap`, `confirm_on_screen`; one tool is one place for the owner to attach, not two. The quantities are digit strings, because the voice agent's tool arrays hold strings only.
- **The card** shows the lines, the address as typed (or "Pickup at the restaurant"), the courier's phone, the name, the highest total, "Payment on delivery or at pickup. Doddy never gives card details.", the server's confirmation sentence, and a **Call and order** button. Without `order: true` from `/v1/call-cases/availability` the tool answers "ordering by phone isn't switched on" and no card is shown.
- Not on the live main agent: `call_places` is `not_synced` (owner queue 48).

## Not decided here
- A cap default and whether to allow pickup in the first release (proposed: both).
- Whether the order agent may take the person's phone number from the card or only say it to the courier.
