# Doddy may text the user's iPhone contacts from his own number, one tap per text, 50 a day

- **Date:** 2026-11-09
- **Decided by:** owner. In a conversation where Doddy couldn't text someone: "ale np napisz sms ze swojego numeru to może zrobić", then "a możemy zmienić reguły, że dla moich kontaktów tylko", then, to the proposed signature and limits, "[bez] podpisu, bez limitów albo 50 tylko".
- **Status:** accepted. Step 1 (the rule in `docs/trust/config/doddy_rules.yaml` and DoddyCore `ContactText`, with tests) applied on branch `claude/adoring-feynman-4exvp8`; steps 2 to 4 to follow.
- **Replaces:** for contacts only, "texts to anyone else are not possible" in decision `2026-11-09-restaurant-calls-one-tap` and `contact_policy.text_recipients: allowlist_only`. The user's own number keeps its own rule (`text_me`, no tap).

## Why
On 9 Nov 2026 the owner asked Doddy in a voice conversation whether he could text someone whose number he has. Doddy can only open a draft in Messages, which the user sends from their own number, and the owner wants Doddy to send it himself, from Doddy's number.

## Decision
1. **Contacts only.** The recipient is a contact in the user's iPhone Contacts. The model names the person; the app finds the contact and reads the number from the contact card. The model never gives a number, so Doddy can't text a number the user hasn't saved.
2. **One tap per text.** The card shows the contact's name, the number and exactly the text. The tap approves that number and that text (`ApprovalHash.text`, the hash the server already checks); any change needs a new tap. This is the constitution's rule for external writes (DOD-07) and is not optional.
3. **No signature.** The text goes exactly as shown. The recipient sees Doddy's number and the text, nothing else.
4. **At most 50 a day per account** (`ContactText.maxPerDay`, `contact_texts_per_account_day`), within the server's daily cap for all texts. Only the calling codes the server allows (`allowed_calling_codes`).
5. **STOP is honoured.** A recipient who answers STOP is not texted again.

## Steps
1. The rule as code and in the rules file, with tests (`Packages/DoddyCore/Sources/DoddyCore/ContactText.swift`, `ContactTextTests`). Sends nothing.
2. Messaging server: a route that takes a contact's number, the text and the approval hash, checks the hash, the country list, the 50-a-day cap and STOP, and sends from Doddy's number. Tests against Postgres.
3. App: a voice tool request and the card (contact, number, text, Send), reading the number from Contacts with the user's permission.
4. Voice agent: a `text_contact` tool and a line in the instructions. It goes on the live ElevenLabs agent only on the owner's instruction.

## Consequences
- **Replies are lost for now.** A text from someone other than the user to Doddy's number is dropped without reply and not stored (`unknown_inbound_texts`). Until replies are passed on, the recipient can't answer the user this way; the card should say so.
- The recipient sees an unknown Estonian number (+372) with no name, so the text may look like spam. The owner chose no signature.
- Cost: about $0.05 a text, paid by Doddy (`docs/implementation/PHONE_SMS_MILESTONE.md`).
- Abuse: one person's account can send 50 texts a day to numbers in their own contacts. The server's per-server daily cap still applies.
- Privacy: the contact's number and the text go to Doddy's messaging server and to Twilio.

## Evidence
- Step 1: `make test-core` on Linux (Swift 6.1.2); see the pull request for the counts. Nothing sends a text yet.
