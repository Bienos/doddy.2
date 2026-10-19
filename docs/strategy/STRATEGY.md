# Doddy strategy

**Date:** 17 October 2026. **Status:** proposal; owner approval pending. **Short version:** `STRATEGY_ONE_PAGER.md`. **Pitch:** `PITCH.md`.

**Labels used throughout:**
- **[FACT]** means it was observed in this repo, in a device log, or on a dated official or press source.
- **[EVIDENCE]** means it comes from secondary research or a study that supports, but doesn't prove, the point.
- **[ASSUMPTION]** means it is the founder's or this document's belief, and needs a test.

**Owner inputs this strategy rests on (interview, 17 October 2026):**
- The 6-month goal is **real users and retention**, not funding or revenue. [FACT]
- The vision is an agent that "can connect to anything and do anything for you". [FACT]
- The market is the **EU**, because one set of rules covers it. [FACT]
- The ask in every pitch is **join the beta**. [FACT]
- The first user is "anyone", and the character's role is "I don't know". Both were left to this document to decide, so both are marked [ASSUMPTION] below.

---

## 1. Where we are now

| State | What | Label |
|---|---|---|
| **Built and seen working** | Native SwiftUI iPhone app. You save notes in your own words and search them; results show the original text, the date and where it came from. | [FACT] |
| | A live voice agent ran on the founder's iPhone on 11 Oct 2026: a 139 s conversation that used `save_memory`, `search_memories` and `web_search`. | [FACT] |
| | The shared core package has 934 tests passing on Linux. Hosted CI compiles every target and passes the unit and 26 UI tests on the simulator. | [FACT] |
| | Landing page live at doddy.lol in 10 languages, with an early-access waitlist. | [FACT] |
| | A written AI constitution with 12 principles and release gates. | [FACT] |
| **In testing** (built, tried only by the founder) | Voice conversations; calendar, reminders, timers, lists, maps, message drafts, weather, multi-step plans, and personality settings. | [FACT] |
| **Built but never run** | Apple Watch app (compiles, never run). Mac menu bar app (prototype, never compiled). App screens in 8 extra languages (machine-translated, never seen on a device, never read by a native speaker). | [FACT] |
| **Known broken** | Voice sessions sometimes start twice, connect but stay silent for 30 s, or can't hear the user. | [FACT] |
| | The ElevenLabs voice agent is public with no authentication, by the owner's choice for development. The token server code exists; deploying it and turning on authentication is pending. | [FACT: `V1_VOICE_STATUS.md`] |
| **Planned, not built** | Payments, the quota server, the paywall and trial, family sharing, the wake word ("Hey Doddy" needs a Picovoice key and a keyword file). | [FACT] |
| **Claimed but unproven** | "A companion that wants to do it all for you" (blog title). That anyone besides the founder wants this. That the character helps. That anyone will pay. | [ASSUMPTION] |

**External users:** zero. **Interviews on record:** none. **Waitlist size:** not recorded in the repo. [FACT]

**Verdict:** the product is far ahead of the evidence. Doddy has the engineering surface of a 1.0 release: four platforms, ten languages, and about ten tools. It has the user evidence of an idea, because H1, the hypothesis everything rests on, has never been tested on another person. The next 90 days have to close that gap, not widen the product.

---

## 2. The problem

**The problem:** people save small, useful facts all over the place, then can't find them at the moment they need them. Examples are a parcel-locker code, the book a friend recommended, a child's shoe size, the restaurant for a birthday, or where the car is parked.
- These things end up in Notes, a WhatsApp chat with yourself, screenshots, reminders or nowhere. [ASSUMPTION]
- Search fails because you don't remember where you put it or which words you used. [ASSUMPTION]

**Who has it:** adults whose day produces a steady stream of "I'll need this later" moments. [ASSUMPTION]

**How often:** several times a week per person. [ASSUMPTION: no measurement exists]

**How they solve it today:** they scroll back through chats, search Notes with guessed words, ask the person again, or give up. All of these are free and already on the phone. [ASSUMPTION]

**What it costs them:** a few minutes, some mild embarrassment when they ask again, and lost recommendations or commitments. Each instance is a small cost. [ASSUMPTION]

**Supporting evidence (indirect):**
- People already use AI for everyday life. 24% of US adults use a chatbot daily, and the most common use is looking things up. [EVIDENCE: Pew Research, June 2026]
- More than 70% of ChatGPT messages are about life outside work. [EVIDENCE: NBER w34255]
- 32.7% of EU adults used generative AI in 2025. [EVIDENCE: Eurostat]
- None of this shows that people lose saved information or would switch tools to fix it.

**The hard truth:** this is a real but low-intensity pain. People tolerate it daily and rarely go looking for a fix. That makes Doddy a "vitamin" unless two conditions hold. Capture must be close to effortless (a few seconds, by voice or the share sheet). The first successful recall must feel like magic. If either fails, people will keep using the free tools they already have. [ASSUMPTION; this is the biggest risk in the strategy]

---

## 3. The target user

### Primary user: "the self-messager" [ASSUMPTION; H1 tests it]
- A working adult, aged about 25–40, in the EU, starting in Poland.
- Uses an iPhone, has a WhatsApp or Messenger chat with themselves, or a Notes app full of untitled fragments.
- Saves at least 3 small things a week and often says "I wrote it down somewhere".
- Comfortable talking to a phone, and has tried ChatGPT.
- **Job to be done:** *"When someone tells me something I'll need later, let me put it somewhere in two seconds. When I need it, give me back the exact thing, without me remembering where I put it."*
- **Why this person:** this is the user hypothesis H1 already names. They are easy to find (almost everyone with a smartphone does some version of this). Their current workaround proves the job exists. A five-second screening question identifies them: *"Do you send messages to yourself?"*

### Secondary 1: the family organiser [ASSUMPTION]
- A parent who holds the household's codes, schedules, sizes, school information and who-said-what.
- **Job:** *"Be the shared memory my family can ask, so it isn't always me."*
- This segment fits the Doddy Crew plan and has a stronger reason to pay. Test it after the primary user's retention is known.

### Secondary 2: adults for whom forgetting is costly [ASSUMPTION]
- People who actively look for external-memory tools, including adults with ADHD.
- **Job:** *"Catch the thing before it disappears, without needing a system."*
- Their pain is higher and they seek out tools. Messaging must not make health claims, and memories here can be sensitive. Reach them through communities, carefully.

**Rejected for now:** students (low ability to pay, and character appeal could drift into entertainment) and "everyone". A product for everyone gets generic onboarding, generic copy and no first channel.

---

## 4. The insight and the right to win

### Why now
1. **Voice got cheap enough.** Turn-by-turn voice costs about €0.020 a minute, against about €0.081 for live speech-to-speech. Voice can now be part of a paid plan without destroying the margin. [FACT: repo cost model from verified provider prices, 10 Oct 2026]
2. **Siri still doesn't speak Polish.** Apple Intelligence is unavailable when the phone is set to Polish, and the new Gemini-based Siri launches in English first, with no Polish date. [FACT: Spider's Web, 8 Jun 2026] This is a window in Poland and other smaller EU languages. It will close, but it is open now.
3. **People want help but don't trust agents to act.** Only 9% would let an AI agent finish a purchase on its own, while 32% want it to choose and let them confirm. [EVIDENCE: Accenture Consumer Pulse 2026] "Asks first, shows its work" is what the market is asking for.
4. **EU rules now reward honesty.** AI Act Article 50 transparency duties have applied since 2 August 2026. [FACT, per repo] Doddy was designed around disclosure and verified outcomes, which competitors are adding after the fact.

### What Doddy does that others don't

| Alternative | What it does well | Where Doddy wins | Where Doddy loses |
|---|---|---|---|
| **ChatGPT / Claude memory** | Remembers facts about you across chats; free users get memory from recent chats. [FACT] Huge capability. | It hands back the user's **exact original, with date and source**, and says "I couldn't find that" instead of guessing. [ASSUMPTION that users value this difference] | Everything else. ChatGPT Go costs 34,99 zł a month [FACT, repo] and does far more. |
| **Apple Notes, Reminders, Siri** | Free, already installed, private, synced. | Talking in Polish; finding things by meaning rather than exact words; one place to put everything. [ASSUMPTION] | Zero friction to adopt and deep system access. Once Siri speaks Polish and gets personal context, the gap narrows sharply. |
| **Replika, Pi, Character.AI** | Emotional companionship and character. | Doddy is useful and refuses dependency mechanics. [FACT: constitution DOD-10] | Emotional pull. Doddy deliberately doesn't compete on it. |
| **AI "second brain" apps** (Second Brain – AI Memory, Memora, Remember AI) | Same job, already in the App Store. [FACT] | Character, voice, Polish, and honesty about sources. [ASSUMPTION] | They exist today; Doddy doesn't, publicly. |

### Candidate moats, ranked

| Rank | Candidate | Verdict | Why |
|---|---|---|---|
| 1 | **Trust and honesty**: exact sources, "I couldn't find that", verified receipts, asks before acting | **Real differentiator, not yet a moat** | Anyone can copy the features. The moat is a *reputation* for never lying, earned over time and protected by the constitution. This is the positioning anchor. |
| 2 | **The user's own memories**: local-first, with provenance | **Real moat after usage; zero today** | After 200 saved memories, switching hurts. It only exists once people use Doddy for months. |
| 3 | **Polish- and EU-language-first** | **Real, but temporary** | A wedge for the first 12–24 months, not a defence. Apple and Google will close it. |
| 4 | **Character IP** (hand-drawn Doddy) | **Wishful as a product moat; plausible as a distribution advantage** | Characters make content shareable and brands memorable. There's no evidence yet that the character improves retention (H2). |
| 5 | **Voice UX** | **Wishful** | Commoditised, dependent on providers, and currently buggy. |

**Honest summary:** Doddy has **no moat today**. It has a **wedge** (exact recall, honesty and Polish) and **two candidate moats** (accumulated personal memory and a well-loved character brand). The strategy is to use the wedge to get people far enough in that the moats start to form.

---

## 5. Positioning

**Category: a personal memory app.**
- Not "AI companion": that category is tied to Replika-style dependency and a 2026 study linking companion use with lower well-being. [EVIDENCE: Nature Human Behaviour, Aug 2026]
- Not "AI agent": too broad, and it invites a fight with Apple, Google and OpenAI on their ground.

**Positioning statement:**
> For busy iPhone users who save small things everywhere and can't find them later, **Doddy is a voice-first memory mate** that keeps what you tell it in your own words and finds the exact original when you ask. Unlike ChatGPT's memory or Apple Notes, Doddy shows where every answer came from, says so when it can't find something, and never acts without your tap.

**One-line promise:** **"Tell Doddy before you forget. Find your exact words later."**

### Resolving "do it all" versus "remember for you"
**Recommendation:** *remember for you* wins in every public message from now until the beta proves retention. *Do it all* becomes the vision, not the promise.

Why:
1. **Credibility.** A solo founder promising "do anything" competes with Apple, Google and OpenAI on breadth, and loses the comparison in the first minute of use. "Finds your exact words" is a promise Doddy can keep today. [ASSUMPTION]
2. **Honesty.** The website already has to label nine of its ten "do it all" moments as "in testing" or "later, maybe". [FACT: website copy deck] Leading with breadth works against the constitution's own rule DOD-02.
3. **Measurability.** One job gives one North Star. "Everything" gives none.
4. **The vision still holds.** Memory is the foundation of an agent people trust. An assistant that knows what you actually said, and has never lied to you about it, has earned the right to act for you. The ladder is **Remember → Remind → Act**.

**Concrete changes:**
- Retitle the blog post. For example: "Meet Doddy: tell him before you forget, find your exact words later".
- Lead the homepage with the 18:45 "My brain has left the chat" moment, which is the built one.
- Keep "one skill at a time, and it asks first" as the "where we're going" section.

---

## 6. Product strategy

### The wedge
**Capture in a few seconds, then recall the exact original with its source.**
- Capture works by voice, text or the share sheet. Text must work fully without voice. [FACT: PRD]
- Success is measured on **recall on a later day**, not on saves.

### The ladder: outcomes tied to autonomy levels

| Horizon | Autonomy level | What ships | Outcome that unlocks the next step |
|---|---|---|---|
| **Now** (0–3 months) | **L0: save and recall** | Capture by voice and text, recall with source, edit, export and delete. Polish and English only. Private TestFlight, then open TestFlight. | ≥30% of activated users recall a memory on a later day within 7 days; 4-week retention ≥25% among activated users. [ASSUMPTION: targets] |
| **Next** (3–6 months) | **L1: suggest** | Doddy proposes a reminder from something you saved ("Marta's book: remind you on Saturday?"). One verified action, Apple Reminders (H4). Paywall and trial in a Polish App Store soft launch. | Reminder follow-through beats the no-reminder group; trial → paid ≥25%; paid share heading towards 4%. |
| **Later** (6–18 months) | **L2: act with approval** | Calendar, lists, message drafts, multi-step plans, each passing the three tests (asks first, checks its work, can be switched off). English-speaking EU markets, then Germany. Family plan. | Verified task completion rate; zero false "done". |
| **Vision** | **L3: "anything", one skill at a time** | Connectors to other apps and services, still approval-first. | Users trust Doddy with consequential actions. |

### Not doing (until the "Now" gate passes)
1. **Mac app and Apple Watch app.** Freeze them; they aren't needed to prove H1.
2. **Eight of the ten languages.** Keep Polish and English. Unreviewed machine translations are a trust risk in a product sold on honesty.
3. **New tools.** Hide weather, maps, timers, lists, drafts and plans from the beta by default. They dilute the test of the core job and add failure surface. Reminders stays, because it is H4.
4. **"Hey Doddy" wake word, Live talk, and the Pro tier.** These are expensive and secondary.
5. **Family plan, Money Saver, packs, NFC keychain.** Not until paid share and retention are known.
6. **Passive or ambient memory, cloud sync, Android, web app.** Already excluded by the PRD. [FACT]

**Must-fix before any external user:**
- Fix the voice double-start, ghost-session and can't-hear bugs, or ship the beta with voice clearly marked experimental and text as the main path.
- Deploy the existing token server, turn on authentication for the voice agent, and add per-user quotas. [FACT: currently public; `V1_VOICE_STATUS.md` says this must change before anyone else uses it]
- Add content-free analytics events for activation, saves, recall attempts, found or not found, and retention.

---

## 7. The business model

### What the proposal gets right [FACT: `MONETIZATION_MODEL_V2.md`]
- The free plan uses no cloud AI, so each free user costs about €0.01.
- Export and delete are never paywalled.
- The trial is offered after the first save, when value has just been felt.
- Session caps protect voice costs.
- It already defines its own decision thresholds.

### What's weak
1. **The core job is free, so people pay for the interface, not the outcome.** Paid plans sell voice minutes and AI answers. If the self-messager is happy with free text recall, the paid share stays at the freemium norm of about 2–3%. [ASSUMPTION; this is the repo model's own top risk]
2. **Too many products for zero users.** The proposal has three plans, three yearly plans, three packs and a lifetime deal. At launch, ship **Free plus Best Mate (monthly and yearly)**, nothing else.
3. **The price sits above a strong anchor.** Best Mate at 44,99 zł is above ChatGPT Go at 34,99 zł, which does far more. [FACT: repo price research] Widen the test to **29,99 / 39,99 / 49,99 zł**, not 39,99 / 44,99 / 49,99. A wider spread teaches more.
4. **Poland alone can't carry the business.** A founder salary needs about 29k monthly users with 5% paying; at 100k users and 5% paying, net margin with a €20k team is about 2%. [FACT: repo model] The EU decision fixes this direction. Polish prices are for learning; the business case runs on EU prices (€9.99 for Best Mate).
5. **Provider dependency.** Voice runs on ElevenLabs and OpenAI. Price or terms changes hit the margin directly. Keep providers swappable, as the repo plans. [FACT]

### Test order (money comes third)
1. **Does anyone come back to find something?** Activation and later-day recall (H1). Without this, pricing is irrelevant.
2. **Would they pay?** Do this before building payments. In week 9 of the beta, show the price screen as a fake door: "Best Mate, 39,99 zł a month: reserve a Founding Mate spot, no charge today." Measure the click-through rate and the reservation rate.
3. **Do they pay?** Run the soft launch with StoreKit, the 7-day trial after the first save, and the three-price test. Use the repo's thresholds: trial → paid ≥25%; paid share ≥4% by month 3; monthly churn ≤21%. [FACT: repo thresholds]

---

## 8. Go-to-market

**Principle:** organic only until the numbers are known. Paid installs in Poland cost about $0.8–2.5 each; at 2–5% install-to-paid, that's $16–125 per payer, which wipes out profit. [FACT: repo estimate]

### First 100 users (weeks 1–8): hand-picked, not broadcast
1. **Screen everyone.** Use one question, *"Do you send messages to yourself or keep a notes dump?"*, plus *"When did you last fail to find something you saved?"* Only people who answer yes join the beta.
2. **Sources:**
   - Convert the existing waitlist.
   - The founder's network: no more than 20% of the beta, to limit friendly bias.
   - Polish communities on Facebook groups, r/Polska and Wykop, framed as "help me break this".
   - A LinkedIn build-in-public series, which plays to the founder's commercial strength.
3. **Every beta user** gets a 15-minute call at week 2. Every "couldn't find it" moment becomes an eval case.

### First 1,000 users (months 3–6)
1. **Character content is the engine.** The ten "ordinary day" moments in the website copy are ready-made short-video scripts for TikTok, Reels and Shorts. Measure **qualified waitlist sign-ups per post**, not views. [ASSUMPTION: H2]
2. **Built-in sharing.** The share lines already written ("Send this to someone who's always late") become referral prompts in the app after a successful recall.
3. **Polish press angle.** Polish tech media keep asking when Siri will speak Polish (Spider's Web, Antyweb, June 2026). [FACT] The story: *"A Polish founder built the Polish-speaking pocket mate Apple hasn't."*
4. **App Store soft launch in Poland**, then English-speaking EU markets (Ireland, Netherlands, the Nordics), then Germany at € prices once Polish thresholds pass.

**The character's job in GTM:** distribution and memorability, under the rule "Useful first. Charming second." [FACT: blog] It never claims feelings and never slows a task. Its effect on retention is tested, not assumed.

---

## 9. Metrics

**North Star: Weekly Recalling Users (WRU).** These are users who, in a given week, successfully retrieve a memory they saved on an earlier day. This measures the whole promise: they saved it, came back, and Doddy found it. Saves alone can be a diary nobody reads; conversations alone can be entertainment.

**Input metrics** (formulas pre-registered in `MONETIZATION_MODEL_V2.md`):

| Metric | Definition |
|---|---|
| Activation | ≥1 save within 24 h of install |
| Aha rate | activated users who recall a memory on a later day within 7 days |
| Capture speed | median seconds from opening Doddy to a verified save |
| Recall success | searches that return the right original ÷ searches for something that was saved (sampled by asking the user "Was this it?") |
| Retention | 4-week and 8-week retention of activated users |
| Voice share | share of captures made by voice (H3) |
| Reminder follow-through | share of reminders created from memories that get completed (H4) |

**Trust guardrails** (any breach blocks release) [FACT: release gates]:
- Zero false "saved" outcomes.
- Zero recall answers not backed by a real stored record.
- Zero actions without the user's tap.
- Zero memories retrievable after deletion.
- Crash-free sessions ≥99.5%. [ASSUMPTION: threshold]

**"The MVP worked"** after 8 weeks and at least 100 activated beta users [ASSUMPTION: targets, owner to confirm]:
- Activation ≥50%.
- Aha rate ≥30%.
- 4-week retention of activated users ≥25%.
- ≥40% of users with 3 or more recalls say they'd be "very disappointed" without Doddy (the Sean Ellis test).

**"Kill or pivot"** signals:
- Aha rate below 15% after two onboarding iterations.
- 4-week retention below 10%.
- Below 20% "very disappointed".
- Users save but almost never recall. That means Doddy is a journal, not a memory, and the job is wrong.

---

## 10. Risks and kill criteria

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **The pain is too mild.** People don't change habits for it (H1 fails). | High | High | Test H1 before building more. Make capture take seconds. Use a 7-day diary study before the beta. |
| 2 | **Scope sprawl.** One founder spread across four platforms, ten languages and about ten tools ships nothing well. | High | High | The "not doing" list. One milestone at a time, as `CLAUDE.md` already requires. |
| 3 | **Paid share stays at 2–3%,** so the business never pays a salary. | High | High | Fake-door price test before payments. EU pricing. Yearly plans. Decide by month 4 against the thresholds. |
| 4 | **Platforms absorb the job.** Siri gains Polish and personal context; ChatGPT memory gets exact recall. | Medium | High | Move fast in the window. Build the trust reputation and the accumulated-memory lock-in. Stay the honest, local-first option. |
| 5 | **Voice is unreliable** (double sessions, latency, Polish speech recognition). | High | Medium | Text is the main path in the beta. Fix bugs before inviting anyone. Latency gate: first audio in 1.2 s or less. |
| 6 | **Security or privacy incident.** The voice agent is public with no authentication; sensitive memories go to US providers. | Medium | High | Authentication and quotas before the beta. Data processing agreements, a data protection impact assessment, minimal context sent to models, clear disclosure. |
| 7 | **The character pulls the wrong users** (teens, people seeking entertainment) or the "AI companion" label brings the wrong associations. | Medium | Medium | An 18+ gate. Position as a memory app, not a companion. Measure task completion with and without the character. |
| 8 | **Provider costs or terms change** (ElevenLabs, OpenAI). | Medium | Medium | Swappable providers, session caps, per-account budget alerts, a 15% currency buffer. |

**Stop or pivot when any of these is true:**
1. After 12 weeks and 100 or more activated users, the aha rate is below 15% **and** 4-week retention is below 10%. The wedge is wrong. Pivot the job (for example to the family organiser) or stop.
2. The fake-door price test shows under 5% reserving at any price **and** 4-week retention is under 25%. Nobody would pay for this version.
3. By month 4 of the soft launch, paid share is below 2.5%. The business doesn't work at these prices. Rethink packaging or the segment before EU expansion.

---

## 11. The next 90 days

| Week | Priority | Done when |
|---|---|---|
| 1 | **Freeze and decide.** The owner approves this strategy and the "not doing" list. Hide non-core tools behind a flag. Retitle public "do it all" copy. | Flags in place; homepage and blog lead with memory |
| 1–2 | **H1 diary study** (cheapest test, no app needed): 20 screened people log every "I saved it somewhere" search for 7 days. | 20 diaries; frequency and failure rate known |
| 2 | **Fix the foundations:** voice bugs, authentication on the voice agent, content-free analytics, AI disclosure and privacy copy. | Device log shows no double sessions in 20 test calls |
| 3 | **Ten problem interviews** with diary participants, before they see the app. | Written notes, quotes tagged [EVIDENCE] |
| 4 | **Private TestFlight,** 30 screened users, Polish and English. | 30 installs |
| 5–6 | **Measure and fix onboarding** (iteration 1). Week-2 calls with every user. | Activation and aha rate reported |
| 6 | **H2 character test:** two landing pages (character-led versus plain memory app), €100 of social ads each, measuring qualified sign-ups. In the app, compare task completion with the character on and off. | Cost per qualified sign-up for each page |
| 7–8 | **Open TestFlight to 100+** from the waitlist and community posts. Onboarding iteration 2. Reminders action enabled for half the cohort (H4). | ≥100 activated users |
| 9 | **Fake-door pricing:** Founding Mate reservation at three prices. | Reservation rate per price |
| 10 | **Retention read:** 4-week cohort, Sean Ellis survey, H3 (voice versus text captures and their retention). | Numbers against the thresholds in section 9 |
| 11–12 | **Decision prep:** write up the evidence log; turn every "couldn't find it" case into an eval. | Evidence log complete |
| 13 | **Go / change / stop.** If the MVP gate passes: payments milestone and Polish App Store soft launch. If not: pivot per section 10. | A recorded decision (ADR) |

### Cheapest validation per hypothesis

| Hypothesis | Cheapest test | Pass signal [ASSUMPTION: thresholds] |
|---|---|---|
| **H1** People save, then return to find things, and prefer Doddy | 7-day diary study (no app), then TestFlight later-day recall | ≥3 lost-item searches a week per person in the diary; aha rate ≥30% |
| **H2** The character helps acquisition without hurting tasks | Two-landing-page ad test; character on/off in the beta | Character page converts ≥1.3× the plain page; no drop in task completion |
| **H3** Voice reduces friction once text works | Compare voice and text capture share and speed among beta users | Voice capture faster; voice users retain at least as well |
| **H4** One verified action (Reminders) improves follow-through | Reminders on for half the cohort | Higher follow-through in the reminder group, with ≥70% permission acceptance |

---

## Open decisions for the owner
1. Approve the primary user (the self-messager) and the category (personal memory app). Both are currently [ASSUMPTION].
2. Approve the "not doing" list, especially freezing Mac, Watch and eight languages.
3. Confirm the MVP-worked and kill thresholds in sections 9 and 10.
4. Approve the copy changes that move the blog and homepage from "do it all" to memory.

## Sources
- Repo: `STATUS.md`, `README.md`, `docs/00_START_HERE/DECISIONS_AND_STATUS.md`, `docs/product/PRODUCT_REQUIREMENTS.md`, `docs/business/MONETIZATION_MODEL_V2.md`, `docs/trust/01_THE_DODDY_CONSTITUTION.md`, `docs/trust/05_RELEASE_CRITERIA_AND_METRICS.md`, `design/website-what-can-doddy-do/COPY.md`, `blog/posts/2026-10-10-meet-doddy-ai-agent.md`.
- [Spider's Web: iOS 27, Apple Intelligence and Siri in Poland (8 Jun 2026)](https://spidersweb.pl/2026/06/ios-27-aktualizacja-iphone-apple-intelligence-ai-polska-siri.html)
- [The Decoder: OpenAI brings longer-term memory to free ChatGPT users (Jun 2025)](https://the-decoder.com/openai-brings-longer-term-memory-feature-to-free-chatgpt-users/)
- [App Store: Second Brain – AI Memory](https://apps.apple.com/app/id6760254340) · [App Store: Remember AI](https://apps.apple.com/us/app/remember-ai/id6743806304)
- Pew Research (2026), NBER w34255, Eurostat (2025), Accenture Consumer Pulse 2026 and Nature Human Behaviour (Aug 2026), as cited in the repo blog post with links.
