# Doddy research: agent competitors, agent phone number, retention (researched 2026-10-24)

Budget used: 14 web searches, 6 page fetches, 1 file read. Everything below is tagged:

- [V] = read on a page I opened (or an official page quoted in a search result)
- [S] = secondary source or search-result summary only
- [N] = from the earlier agent's `notes_raw.md`, not re-checked here
- [I] = my inference or background knowledge, not verified in this session

Corrections to the earlier notes are collected in section 3.

---

## 1. Competitor snapshot (data mostly [N]; items marked otherwise)

| Product | Standout feature | Price | Traction |
|---|---|---|---|
| Poke (Interaction Co, bought by Cognition Jul 2026) | Agent in iMessage / SMS / Telegram (WhatsApp in some markets). First standalone AI agent approved on Apple Messages for Business, 4 Jun 2026 [V] | Free / Pro $19 ($16 yearly) / Ultra $199 (third-party sources) [N] | ~100M messages in 3 months before the deal; "low nine figures" price (TechCrunch via a founder quote) [N] |
| Tolan (Portola) | Voice-first alien companion; Tabs per topic; family groups; months-long memory; crisis flags; asks about real-world relationships | Historic $10-$200/mo by usage; first free tier planned [N] | ~250k MAU, ARR "solidly double-digit millions", $30M raise Oct 2026; family groups = main growth driver [N] |
| ChatGPT | Scheduled Tasks (replaced Pulse); Dots always-on agents; Go tier; voice upgrades | Go ~$8/mo in the US [N] | ~1B weekly users claim, unconfirmed [N] |
| Meta Muse | Cloud-VM personal agent (email, travel, forms), approval before send/buy, Stripe Link one-time cards | Free for most use + paid tiers; US only [N] | Launched 8 Sep 2026 [N] |
| Gemini | Daily Brief, Spark 24/7 agent, Live voice + camera | Ultra cut to $100/mo [N] | 1B+ monthly users (Google, Aug 2026) [N] |
| Siri (iOS 27) / Alexa+ | OS-level personal context / household voice | Free / free with Prime, else $19.99 [N] | Every iPhone / "tens of millions" early access [N] |
| Martin, Lindy, Pally | Phone/SMS/WhatsApp/email assistants; Martin's alarm calls you | ~$30-35; $49.99-$199.99; free-$200 [N] | Not collected |
| Perplexity, OpenClaw | Background assistant (Max $200); open-source self-hosted agent with 145k+ stars and a 1-click RCE flaw (CVSS 8.8) | Pro $20 / Max $200; free | n/a [N] |
| Finch | Self-care pet; no punishment for missed days; widgets | n/a | ~10M MAU, D1/D7 retention 54% / 37% vs Duolingo 51% / 35% (Sensor Tower via Deconstructor of Fun, estimates) [S] |
| ElliQ | Senior companion robot | State-funded pilots | New York State pilot reports 95% less loneliness (self-reported, vendor-linked); 30+ interactions a day [S] |
| Grok companions | Retired (see section 3) | n/a | n/a |
| OpenAI device | Not shipping before end Feb 2027; reveal targeted before end 2026 [N] | n/a | n/a |

---

## 2. Giving Doddy its own phone number (Poland / EU)

### 2.1 Twilio, Polish numbers (both pricing pages say "current as of October 2026") [V]

Voice page, https://www.twilio.com/en-us/voice/pricing/pl
- Local number: $2.90/month. Mobile and national number monthly prices were not listed on this page.
- Inbound: $0.0107/min appears in the table, but the row label was ambiguous in extraction (probably local inbound).
- Outbound to Polish landline: $0.1114/min, with an "EEA" variant at $0.0315/min. Outbound to Polish mobile: $0.2202/min, EEA variant $0.0715/min. (Matters for the AI calls to businesses feature; labels ambiguous, check the CSV on the page.)
- Browser/app and SIP interface calls: $0.0040/min.

SMS page, https://www.twilio.com/en-us/sms/pricing/pl
- Mobile numbers: outbound $0.0457 and inbound $0.0075 per segment (the extraction did not label columns; mapped by column order).
- Alphanumeric sender IDs: $0.0457 outbound, one-way only, free to hold.
- Carrier fees may apply (amount not extracted). Failed-message fee $0.001.
- A search-result summary of the same page mentions "Clean Mobile Numbers" at $4.00/month [S]. The fetch did not reproduce it, so treat it as unverified.
- Twilio's Poland SMS guidelines say two-way SMS and number portability are supported [S].

Regulatory page, https://www.twilio.com/en-us/guidelines/pl/regulatory [V]
- Number types: local, mobile (+4873, +4879), toll-free (+48800).
- Local number, individual: government ID plus ID number (PESEL, REGON, passport or residence card); address must be inside the prefix's locality or region.
- Local number, business: business register excerpt, registration number (REGON, NIP, KRS), proof of authorised representative (for example power of attorney), business address in the prefix area; PO Box not accepted.
- Mobile and toll-free: same documents, but the address may be anywhere in the world.
- Observation [I]: voice pricing lists local numbers and SMS pricing lists mobile numbers, so one Polish number may not offer both voice and SMS. Confirm in the Twilio Console number search (country Poland, filter Voice + SMS) before buying.

### 2.2 Telnyx [V for the Poland page, S for generic pricing]
- https://telnyx.com/phone-numbers/poland.md lists only local numbers (area codes 12 Krakow, 16 Przemysl, 82 Chelm, 15 Tarnobrzeg, 95 Gorzow Wielkopolski): "start at $1 per month". It says you can send texts from the number but gives no SMS price and no document requirements. It does describe Polish telemarketing rules: prior consent for unsolicited direct marketing and automated calls.
- Generic Telnyx pricing (not Poland-specific) [S]: SMS/MMS add-on $0.10/month per number; SIP trunking inbound from $0.0032/min, outbound from $0.005/min.
- Net: Telnyx is cheaper on paper for a local number, but Poland SMS and compliance paperwork could not be confirmed.

### 2.3 Inbound voice into an ElevenLabs agent [V, page undated]
Source: https://elevenlabs.io/pricing/agents
- Additional call minutes: $0.080/min on every plan. Included minutes: Free 15, Pro $99 = 1,238, Scale $299 = 3,738, Business $990 = 12,375 (so the effective rate is also about $0.080/min). Starter and Creator monthly prices conflict between the cards and the table.
- Burst pricing (up to 3x concurrency): $0.160/min. Text messages: $0.003 each.
- LLM cost "billed separately on top" (another FAQ says deducted from credits; the page does not reconcile them).
- "Telephony is included on every plan": ElevenLabs adds no telephony fee; Twilio or a SIP trunk bills carrier charges directly ("at cost").
- Not on the page: phone-number pricing, inbound vs outbound differences, EU data residency.
- Estimate [I]: inbound call ~ $0.080 + ~$0.011 carrier = ~$0.09/min before LLM. A 3-minute call is ~$0.27; five 3-minute calls a month per user is ~$1.36 before LLM.
- A third-party reseller (2chat.co) offers virtual numbers from $5/month that route to an ElevenLabs agent [S]; it adds a middleman, not needed if Twilio is already in use.

### 2.4 SMS economics [I, from 2.1]
- One round trip (1 inbound + 1 outbound segment) = $0.0532. 15 round trips a month = $0.80 per user. Polish diacritics normally force UCS-2 encoding (70 characters per segment), so longer assistant replies cost 2-3 segments: ~$1.50-2.20 per user per month.
- SMS is not end-to-end encrypted and sender ID can be spoofed. Use it only for one-time codes and a last-resort fallback, never for memory content.

### 2.5 WhatsApp Business API for AI assistants in the EEA
- Meta's policy (announced Oct 2025, effective 15 Jan 2026 per most sources; some say 15 Oct 2025) banned general-purpose AI assistants from the Business API [S/N].
- 5 Mar 2026: Meta offered EU access for a fee of EUR 0.0490-0.1323 per non-template message depending on country [S] https://techcrunch.com/2026/03/05/meta-will-allow-rival-ai-chatbots-on-whatsapp-in-europe-but-for-a-fee/
- 9 Jun 2026: European Commission interim measures order Meta to reinstate the pre-15-Oct-2025 terms within five working days. In force until the antitrust case concludes or June 2029, whichever is first; fines up to 10% of turnover plus daily penalties up to 5% of average daily turnover [S] (Slashdot, Yahoo Finance, Legal500, techjacksolutions links in section 7).
- Meta called it "regulatory overreach" and said it would appeal. One law-firm page (Slaughter and May) says the appeal was filed at the General Court in August 2026. I found no ruling and no sign the order is suspended [S].
- ChatGPT's return to WhatsApp in the EEA on 13 Jul 2026 comes from one source (TechTimes) [N].
- Pricing basics [S]: per-message pricing since 1 Jul 2025; rates depend on template category, country and volume; current rate cards effective 1 Apr 2026. Service messages inside the 24-hour customer-service window are free, and utility templates sent inside that window are free. A Kommo changelog says a 1 Jul 2026 update lowered Poland's marketing, utility and authentication rates. I did not retrieve Poland's actual rate card.
- Practical meaning [I]: an assistant that only replies inside the window costs nothing in channel fees. Proactive reminders outside the window need paid templates. The legal footing is an interim measure under appeal, so build it as a removable channel.
- Onboarding [I, not verified]: Meta business verification and a dedicated number that is not already on WhatsApp.
- Privacy note [I, verify]: Business API messages are processed by Meta's cloud and the business, so they are not private from Meta the way a normal chat is; keep sensitive memory out of the thread and use deep links back to the app.

### 2.6 Apple Messages for Business (can a small developer get in?)
Source: TechCrunch, 4 Jun 2026 [V] https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/ plus AppleInsider, TechTimes, Relve [S].
- Apple's conditions as reported: Poke had to verify it "could offer live support, if needed"; the agent had to be "clearly identified as such" (AI); Poke submitted "testimonies from its messaging providers"; it customised the UI to Apple's guidelines (link previews instead of inline links, Apple's style guide for buttons).
- Time: "a couple of months", and the co-founder said others would face a similar process.
- Fees: the article carries a correction that Poke pays its messaging service provider on a per-user basis, "not Apple directly". Amount undisclosed, "significantly lower than Meta AI" fees. (TechTimes' headline implies Apple charges per user; the TechCrunch correction is the better source.)
- Access: the platform "hadn't been open to stand-alone third-party AI agents" until now. No public application process or eligibility criteria were described, and Apple has not said when others can apply. Countries are not stated.
- Poland: I found no source listing Poland. The 2018 Business Chat launch list was Australia, Canada, France, Germany, Hong Kong, Italy, Singapore, Japan, Switzerland, UK (https://www.engadget.com/2018-10-02-apple-business-chat-international.html) [S, old]. Treat Polish availability as unknown.
- Verdict [I]: not available to a solo founder in Poland today. It needs an Apple-approved messaging service provider, months of review, a live-support promise, and an undisclosed per-user fee. Revisit only if Apple publishes criteria and confirms Poland.
- Also [I]: in Messages for Business the customer normally starts the conversation, which limits proactive reminders.

### 2.7 Unofficial iMessage relays [S]
- Twilio is quoted (through a competing vendor's blog, so treat as advocacy) saying any vendor offering "business iMessage" is using workarounds that violate Apple's terms; the same post says Apple blocks Apple IDs, phone numbers, device patterns and developer accounts tied to it, and that a few spam reports can trigger restrictions within hours (secondhand): https://blog.agent-crm.com/why-agent-crm-doesnt-offer-blue-bubble-texting/
- Precedent: Apple blocked Beeper Mini within about three days in December 2023, citing metadata exposure, spam and phishing risk: https://512pixels.net/2023/12/apple-kills-beeper-mini/ and https://www.mactech.com/2023/12/11/apple-puts-the-kibosh-on-the-beeper-app-of-sending-imessages-on-android-devices/amp/
- Fragility: BlueBubbles-style bridges need an always-on Mac; the private-API path requires disabling System Integrity Protection and injecting a library into Messages.app; invite-only vendors apply send limits and warm-up because Apple flags bulk-like senders: https://help.dmchamp.com/messaging-channels/imessage/
- Not found: anything specific on Sendblue or Linq, or on legal liability for bans.
- Verdict [I]: do not build on it. Business continuity, user-privacy and trust risks all point the same way; a privacy-first memory product should not route memory through a grey-market Mac fleet.

### 2.8 Telegram and Signal [I, NOT searched this session]
- Telegram Bot API: free, no phone number needed, the user must press Start, supports voice notes and files, and Poke already offers Telegram [V for Poke]. Bot chats are cloud chats, not end-to-end encrypted. Likely lower reach in Poland than WhatsApp or Messenger.
- Signal has no official bot API; unofficial tooling (signal-cli, as used by OpenClaw [N]) needs a dedicated number and is not a production path.

### 2.9 Recommendation for Doddy (Poland / EU)
1. Now: buy one Twilio Polish number (local, $2.90/mo; pick the prefix that matches the company's registered address, or a mobile number if the Console confirms voice) and attach it to the existing ElevenLabs agent through the native Twilio integration. Two jobs: "Call Doddy" for people who will not open the app (parents, car, landline), and caller ID plus callback for the AI errand calls, with voicemail transcribed and summarised in the app. Fixed ~$3/mo; variable ~$0.09/min plus LLM.
2. Guard rails (constitution): AI disclosure at the start of every call; caller-ID match to a verified number is only a hint (caller ID can be spoofed [I]), so require a spoken passphrase or in-app confirmation before memory, Gmail or any external write; read-only tool allowlist until verified; per-user monthly minute cap and per-number rate limit (anyone can dial a paid line); an approval for a write must repeat the exact payload and be confirmed in the app; "message delivered" or "call completed" only on provider confirmation, otherwise "unknown".
3. Cheap test: a Telegram bot linked by a one-time code from the app (text + voice notes). Cost is LLM only.
4. Around Q1 2027: WhatsApp Business number via Cloud API as the main text channel, relying on the EC interim order, with Telegram and push as fallbacks, replies inside the 24-hour window, and only a few utility templates for reminders (look up the Poland rate card first).
5. Do not: build on unofficial iMessage; use SMS as a main channel; chase Apple Messages for Business now.

Indicative monthly cost per 1,000 users [I]: voice at 5 calls x 3 min = ~$1,360 before LLM (so cap minutes and make it a paid-tier perk); SMS at 15 round trips = ~$800; WhatsApp in-window replies = $0 channel fee; Telegram = $0 channel fee.

---

## 3. Verification of the notes' unverified items

1. ChatGPT Dots and the EEA: CONFIRMED by several secondary sources (relevantaudience, nerdschalk, innfactory, mindstudio, aiweekly) [S]. Pro launch excludes the EEA, Switzerland and the UK; Business Premium is available in all supported regions; Enterprise/Edu/Healthcare get a beta once an admin enables it; Free/Go/Plus do not get dots. OpenAI does not say when or whether Pro in Europe follows. I did not open OpenAI's Help Center page.
2. Grok companions retired: MOSTLY CONFIRMED but all sources are low-quality blogs and aggregators [S]. xAI called the 3D companions (Ani, Mika, Valentine, Rudi) an "experiment" on 24 Jul 2026; an in-app notice reportedly named 1 Sep 2026; the avatars moved to a separate app, Animates, with a separate account and no progress transfer. One site (roborhythms) says no date was announced. No primary xAI source found.
3. ChatGPT group chats retiring: CONFIRMED by OpenAI's own Help Center article 12703475, "Retiring group chats in ChatGPT" [V by result snippet; page not opened]. From 9 Jul 2026 you cannot create, convert to, or join (by invite link) group chats; existing chats stay active for now, later become read-only; history can be exported; reason given: simplifying, the feature began as a pilot.
4. Pulse retirement: CONFIRMED [S, several]. OpenAI's 17 Jun 2026 release notes sunset Pulse (Pro keep access 14 more days) and move its briefings into Scheduled Tasks. Pulse was previewed to Pro on mobile on 25 Sep 2025 and reached web 29 Oct 2025; I found no confirmation it ever reached Plus. OpenAI's own lesson: proactive experiences work best when "personalised, action-oriented, and steerable by the user", and tasks saw strong engagement inside Pulse. The claim that "users rejected Pulse" is NOT supported by what I found; the evidence says a passive feed lost to user-defined tasks.
5. Gemini Daily Hub removed on Pixel for poor feedback: NOT VERIFIED. My search returned nothing on it. The Daily Brief (I/O, 19 May 2026) comes only from the notes [N].
6. Poke fee correction: the notes say Poke pays Apple a per-user fee. TechCrunch's correction says the per-user payment is to Poke's messaging service provider, not to Apple directly [V].

---

## 4. Retention, delight, family, senior, proactive patterns

### 4.1 What the evidence says
- Finch [S]: estimated ~10M MAU, D1/D7 54% / 37%, versus Duolingo 51% / 35% (Sensor Tower via Deconstructor of Fun). Core loop: do self-care tasks, earn energy, then outfits and room decor, evolve the pet, unlock areas. Reviewers describe no punishment for missed days: the pet stays home, no red marks, and a streak can be paused. Home-screen widgets give passive value without urgency. Sources: https://www.deconstructoroffun.com/blog/x0hd2ssr80y5n7gv0w967pg7hwd7tl , https://screenwiseapp.com/media/finch-app . Caveats: third-party estimates, and I found NO study comparing gentle designs with streak pressure, and no Duolingo-specific retention research in this pass.
- Tolan [N]: 30-day net user retention +115% year on year; family group feature is a major growth driver; tests of hanging out with friends and their Tolans; proactive "flag dropped obligations" is next; asks about real-world relationships and suggests calling a relative; company survey of ~5k users (Aug): 91% have someone to count on, more than half say real relationships improved (self-reported); 40% of users are parents and 1 in 6 care for an aging parent. Rate limits and pricing changes caused loud Reddit/Discord complaints.
- ChatGPT group chats were wound down (confirmed, 3.3) while Tolan's family groups grew. Inference [I]: share objects (lists, reminders, plans, errands), not open AI group chats; every member keeps their own Doddy and privacy.
- ElliQ [S]: New York State Office for the Aging pilot reported 95% loneliness reduction and 30+ interactions per day, but it is self-reported and linked to the vendor; a BYU psychologist warns such devices may reduce human contact. Sources: https://www.robotics247.com/article/elliq_companion_robot_reduces_loneliness_95_percent_finds_new_york_state_rollout , https://vivo.weill.cornell.edu/display/pubid38449726 . The 2026 NYSOFA report exists but I could not see its findings.
- Proactive patterns: what survived is user-defined and action-oriented (Scheduled Tasks; Daily Brief requires opt-in memory and Workspace [N]). What was retired is the passive feed (Pulse), open AI group chats, and (per low-quality sources) Grok's 3D companions.

### 4.2 Mechanics that fit an honest cute character (all [I] unless cited)
1. Usefulness loop, not guilt loop: people return because a reminder fired, an errand finished, or their day was read to them. Every proactive message must come from a trigger the user created or asked to be told about, carry one action, and be mutable in one tap. Cap unsolicited messages and respect quiet hours.
2. Passive presence: Dynamic Island, Lock Screen and widgets show the next thing and a small Doddy, with no push. Finch credits widgets for passive value [S].
3. Pause without penalty: routines can be paused or skipped; no red marks, no "Doddy missed you", no loss framing. The pet "stays home" pattern is the model [S].
4. Shared objects: family lists, school pickup reminders, a parent's medication schedule. The invitee gets value before signing up (a shared list works only if both have Doddy), which also drives growth.
5. Point outward: suggest calling the person, ending the session, going outside; user-set nudges ("call Babcia on Sunday"). This matches the constitution's anti-dependency rule and Tolan's approach [N].
6. Memory you can see: a journey screen showing what Doddy remembers and where it came from; "you told me on 3 March" moments. Never invent memory.
7. Milestones, not streaks: private keepsakes ("100 reminders kept"), cosmetic accessories the user picks, no pay-to-avoid-guilt.
8. Predictable limits: show remaining usage, warn before a limit, never cut mid-conversation. Tolan's backlash shows this matters [N].
9. Senior/caregiver angle: a phone line with no app, large-type and voice-first UI, scam protection (Polish cases: fake courier SMS, "BLIK to a friend" requests, "wnuczek" calls [I]), and caregiver features that only share what the older person approved. No covert monitoring.

---

## 5. 30 feature ideas for Doddy, ranked (value x feasibility x constitution fit)

Ranking logic [I]: top items reuse blocks Doddy already has (reminders, calendar, Gmail, memory, calls, approvals), match evidence from section 4, and add little risk. All "done" states require provider confirmation; every external write shows the exact payload and needs approval.

Daily life
- #1 User-defined scheduled tasks ("weekdays 07:30, read me my day"): one visible list, pause/delete, quiet hours. What survived Pulse.
- #4 Share-sheet capture: screenshot, link, receipt or voice note becomes a memory, list item or reminder with its source stored.
- #6 Receipt and warranty vault: photo in, return-window and guarantee-expiry reminders out.
- #9 "Call Doddy" +48 line: caller-ID hint plus passphrase, read-only tools until verified.
- #15 Gmail "what needs me?" on request; replies are drafts, sent only after approving the exact text.
- #24 Morning and wind-down presets (alarm, quiet voice, tomorrow's first thing); no streaks.

Family
- #8 Family circle: shared grocery/school lists and reminders, per-item consent, each member keeps their own Doddy.
- #12 Parent call-in line (no app needed) with a weekly summary the parent approves.
- #19 Medication or appointment reminders for a relative delivered as voice calls, set up with their consent.
- #27 User-set nudges toward people ("call Babcia on Sunday"), never guilt.

Work
- #7 Compare-quotes errand: calls up to three businesses with an approved script and returns a table; unanswered stays "unknown".
- #10 Meeting capture with a consent banner: decisions, owners, reminders, in Polish and nine other languages.
- #16 Callback number for errand calls; voicemail transcribed and summarised.

Health / wellbeing
- #13 Appointment prep and post-visit voice capture, stored as the user's own notes.
- #14 Medication routine with snooze/skip; "taken" means the user said so, not verified compliance.
- #29 Optional mood notes with private trends; distress handling that points to 112 or a trusted person, no jokes.

Money
- #3 Subscription and bill tracker from receipts, renewal alerts, cancellation as an approved draft.
- #11 Polish formal-letter drafts (reklamacja, wypowiedzenie umowy, odwolanie) in correct form; nothing sent without approval.
- #18 BLIK "request money" and bill-split message drafts; Doddy never sends money.
- #22 Price watch (flight, product) with a user-set threshold; alerts only, never buys.

Travel
- #17 Trip folder: bookings from Gmail, calendar, packing list, translator phrase cards.
- #20 Leave-by timeline from calendar plus transit/traffic search, with reminders approved once.

Fun / character
- #23 Pose-pack state animations in Island/Home (listening, thinking, waiting for approval); UI states, not claimed feelings. Art only from the owner's imported pack.
- #25 User-defined quests (gym three times a week) with pause-without-penalty and optional cosmetic accessories.
- #26 Monthly keepsake of moments the user saved, consent per item, never invented memories.
- #28 Short Polish voice games (word chain, 20 questions) for kids and grandparents, no child data collected.

Safety
- #2 Action receipts: draft, approved, sent, provider-confirmed or "unknown"; exportable and deletable.
- #5 Scam check for Polish cases (fake courier SMS, BLIK requests, "wnuczek" calls): paste or forward, get red flags in plain Polish.
- #21 Opt-in check-in for people living alone; if no reply, ask them first, then notify only a contact they chose.
- #30 Permission dashboard: which tools Doddy may use, last use, one-tap revoke (Gmail, calendar, calls).

---

## 6. What I could not verify (and cheap next checks)
- Twilio: Polish mobile number price (the $4.00 figure came from one search summary), whether Polish mobile numbers do voice, whether one number can do voice and SMS, carrier fees, bundle approval time. Next check: Console number search for +48 with Voice + SMS filters, and https://www.twilio.com/en-us/guidelines/pl/voice.
- Telnyx: Poland SMS price, mobile numbers, document requirements.
- ElevenLabs: pricing page is undated; Starter/Creator price conflict; LLM billing conflict; whether the native Twilio integration has its own fee; EU data residency.
- Apple Messages for Business: Poland availability, which service providers Poke used, whether Apple will take other applicants and on what terms.
- WhatsApp: Poland template rates, appeal outcome or suspension, whether Doddy would count as a "general-purpose AI assistant" under the order, ChatGPT's 13 Jul EEA return (single source), Meta Cloud API privacy position.
- Telegram, Signal: not searched.
- Dots: no OpenAI primary page read; Pro-in-Europe timing unknown. Grok companions: no primary xAI source. Gemini Daily Hub: nothing found.
- Poke pricing and message counts, Tolan metrics, Muse, Gemini and Alexa+ figures: copied from the earlier notes.
- Finch/Duolingo retention comparison is a third-party estimate; no study of gentle versus streak designs; ElliQ results are self-reported and vendor-linked.
- Whether EU AI Act transparency duties (AI disclosure on calls) apply to Doddy's phone channel and from when: not checked [I].

---

## 7. Sources (all opened or returned by search 2026-10-24 unless noted)

Phone numbers and voice
- https://www.twilio.com/en-us/voice/pricing/pl (fetched, "current as of October 2026")
- https://www.twilio.com/en-us/sms/pricing/pl (fetched, "current as of October 2026")
- https://www.twilio.com/en-us/guidelines/pl/regulatory (fetched)
- https://www.twilio.com/en-us/guidelines/pl/sms (search result)
- https://telnyx.com/phone-numbers/poland.md (fetched); https://telnyx.com/pricing/numbers ; https://telnyx.com/pricing/voice-ai-agents (search results)
- https://elevenlabs.io/pricing/agents (fetched, undated); https://elevenlabs.io/pricing (fetched, no agent prices in text)
- https://2chat.co/integrations/elevenlabs (search result)
- https://www.happyrobot.ai/hub/elevenlabs-pricing , https://trtc.io/blog/details/elevenlabs-conv-ai-vs-trtc-2026 (search results, secondary)

Apple and iMessage
- https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/ (fetched, 4 Jun 2026)
- https://appleinsider.com/articles/26/06/04/first-ai-agent-for-messages-business-chat-approved-by-apple
- https://www.techtimes.com/articles/317863/20260605/apple-approves-poke-first-imessage-ai-agent-charging-per-user-before-wwdc.htm
- https://relvehq.com/blog/noise/poke-becomes-first-ai-agent-on-apple-messages
- https://www.engadget.com/2018-10-02-apple-business-chat-international.html (2018)
- https://register.apple.com/resources/messages/messaging-documentation/go-live (search result)
- https://blog.agent-crm.com/why-agent-crm-doesnt-offer-blue-bubble-texting/ ; https://512pixels.net/2023/12/apple-kills-beeper-mini/ ; https://www.mactech.com/2023/12/11/apple-puts-the-kibosh-on-the-beeper-app-of-sending-imessages-on-android-devices/amp/ ; https://alternativeto.net/news/2023/12/apple-blocks-the-new-imessage-for-android-app-beeper-mini-over-security-concerns ; https://help.dmchamp.com/messaging-channels/imessage/

WhatsApp
- https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing
- https://support.kommo.com/docs/updated-pricing-rules-for-whatsapp-business.md
- https://meta.slashdot.org/story/26/06/09/1958236/eu-orders-meta-to-open-whatsapp-to-rival-ai-chatbots (9 Jun 2026)
- https://finance.yahoo.com/economy/policy/articles/eu-orders-meta-reopen-whatsapp-142603730.html
- https://www.slaughterandmay.com/recent-work/meta-on-its-appeal-against-the-european-commission-s-whatsapp-interim-measures-decision/
- https://www.legal500.com/intelligence/belgium/antitrust-competition-law/must-meta-open-whatsapp-to-competing-ai-assistants
- https://techjacksolutions.com/ai-brief/eu-orders-meta-to-reopen-whatsapp-api-to-rival-ai-assistants/
- https://techcrunch.com/2026/03/05/meta-will-allow-rival-ai-chatbots-on-whatsapp-in-europe-but-for-a-fee/ (5 Mar 2026)

Verification items
- https://www.relevantaudience.com/ai/openai-dots-always-on-agents-chatgpt/ ; https://nerdschalk.com/chatgpt-dots-regional-availability/ ; https://www.mindstudio.ai/blog/chatgpt-dots-pricing-access ; https://innfactory.ai/en/blog/openai-dots-always-on-ai-agents-enterprise/ ; https://aiweekly.co/alerts/openai-launches-dots-always-on-chatgpt-agents-at-devday
- https://www.roborhythms.com/grok-companions-discontinued/ ; https://www.layer3labs.io/guides/grok-companions-explained (updated 22 Aug 2026) ; https://aiinsightsnews.net/grok-ani-gone-what-happened/
- https://help.openai.com/en/articles/12703475-retiring-group-chats-in-chatgpt
- https://yellow.com/news/chatgpt-pulse-scheduled-tasks-hub ; https://aiinsiders.net/article/openai-retires-chatgpt-pulse-unifies-tasks-into-one-hub ; https://prowlo.com/blog/chatgpt-pulse-shut-down ; https://justinmckelvey.com/blog/chatgpt-pulse ; https://help.openai.com/en/articles/12293630-chatgpt-pulse (from notes)

Retention, family, seniors
- https://www.deconstructoroffun.com/blog/x0hd2ssr80y5n7gv0w967pg7hwd7tl ; https://screenwiseapp.com/media/finch-app ; https://www.monterail.com/blog/how-to-make-your-app-attract-users-every-day (marketing blog, weak)
- https://www.robotics247.com/article/elliq_companion_robot_reduces_loneliness_95_percent_finds_new_york_state_rollout ; https://vivo.weill.cornell.edu/display/pubid38449726 ; https://aging.ny.gov/node/11461 ; https://leadingage.org/?p=565168
- Tolan, Poke, Muse, Gemini, Alexa+ and the rest: see `notes_raw.md` in the same folder (not re-verified).
