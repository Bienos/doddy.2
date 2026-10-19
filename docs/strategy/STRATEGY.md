# Doddy strategy

**Date:** 19 October 2026. **Status:** the direction is the owner's (19 Oct instruction, ADR-540). The targets, thresholds and dates in it are proposals until the owner confirms them. **Short version:** `STRATEGY_ONE_PAGER.md`. **Pitch:** `PITCH.md`. **The first session, step by step:** `sprawa-loop.md`. **How we'll measure it:** `docs/product/VALIDATION.md`.

**What changed from the 17 Oct version:** that version made Doddy a personal memory app ("Tell Doddy before you forget. Find your exact words later."), with recall on a later day as the North Star. The owner replaced it on 19 Oct. Doddy is now a **pomocnik** (a helper) you hand a **sprawa** to, and the North Star is sprawy closed after Doddy brings them back. The 17 Oct text stays on branch `claude/doddy-strategy-docs`; this file's history on main shows the full diff.

**Labels used throughout:**
- **[FACT]**: observed in this repo, in a device log, or on a dated official or press source.
- **[EVIDENCE]**: secondary research that supports the point but doesn't prove it.
- **[ASSUMPTION]**: the owner's or this document's belief. It needs a test.
- **[OWNER]**: the owner said it, in their instruction of 19 Oct 2026.

---

## 1. The direction in one paragraph

Doddy is a pomocnik, not a companion. **[OWNER]** You hand it a **sprawa**: an errand or a promise hanging over you ("Muszę oddać buty na Zalando do piątku"). It keeps your exact words. It brings the sprawa back at the right moment with the next step ready. It acts only on your tap. **[OWNER]**

**Positioning line:** **"Sharp online. Clumsy offline. Honest always."** **[OWNER]**

What the line means in practice [ASSUMPTION: this document's reading; the owner confirms it, open decision 1]:
- **Sharp online.** With the network and the AI, Doddy understands "do piątku", proposes "czwartek wieczorem", prepares the next step and does the phone-side work.
- **Clumsy offline.** Without the network, Doddy still keeps the sprawa and still brings it back, because notes and reminders live on the iPhone. But it's plainer: it asks "Kiedy ci przypomnieć?" with a few buttons instead of guessing. It never pretends to be sharp. The app already does a version of this: offline, the voice screen says voice needs the internet and offers to save a note on the iPhone (ADR-289, `docs/implementation/OFFLINE_STATUS.md`). [FACT]
- **Honest always.** Doddy says what it did, what it didn't do, and what it can't do. "Done" means the user tapped Gotowe, or a provider confirmed the action. [FACT: constitution DOD-02, DOD-08; ASK-01 on main since 18 Oct]

**What "sprawa" means here.** The word is everyday Polish for a matter you have to deal with ("mam sprawę do załatwienia"). In this product, a sprawa is one thing with:
- **your words**, kept exactly;
- **a moment** when it should come back: a deadline, or a time you agree on;
- **a next step** Doddy prepares, or that you add;
- **a state**: open, done, or dropped, with undo.

Typical sprawy [ASSUMPTION: examples for the beta, not research]:
- returns ("oddać buty na Zalando do piątku");
- bills and renewals ("zapłacić za prąd", "OC do 15-go");
- appointments ("zadzwonić do dentysty, przełożyć wizytę");
- promises to people ("wysłać Marcie zdjęcia");
- paperwork ("PIT do końca kwietnia");
- a parcel to pick up ("paczka w paczkomacie do jutra").

---

## 2. Where we are now (19 Oct 2026)

| State | What | Label |
|---|---|---|
| **Seen working on the owner's iPhone** | A live voice conversation on 11 Oct (139 s) used `save_memory`, `search_memories` and `web_search`. | [FACT: `STATUS.md`] |
| **Tested on Linux** | The shared core: 1,146 DoddyCore tests pass (Swift 6.1.2, 19 Oct, this PR). | [FACT] |
| **Compiled in hosted CI, never on a device** | On 18 Oct hosted CI built the app on PR #84's branch and passed the 29 UI tests on the simulator. Main now holds, in merge order: ASK-01, every tool asks first (PR #87, 18 Oct); the BLIK hand-off (PR #85); PR #84 itself (19 Oct: the build fixes, one conversation at a time ADR-496, start logging); then the v1 scope proposal, go-live checklist and two fixes (PR #88). | [FACT: `STATUS.md`, git history] |
| **Built, and what the sprawa loop can reuse** | Notes keep the original text unchanged after edits (`MemoryRecord.rawText`). The user's spoken transcripts are kept on the iPhone with each conversation (`ConversationLogStore`). Note reminders are local notifications with Open, In 1 hour, Tomorrow 09:00 and Done ("Gotowe") on a long press. The agent checks a date against the user's own words for it (`said_time`). "What Doddy did" lists changes with Undo for 24 hours. ASK-01 cards, and `note_capability_gap`. | [FACT: code; details and file references in `sprawa-loop.md`] |
| **Missing for the sprawa loop** | A first screen with one question. Tying the user's spoken words to the sprawa (the transcript is kept, but the note's text is what the agent writes). `said_time` accepting a proposed moment before a deadline (today it flags one). One card that shows the words, the time and the state together. A prepared next step. A logged Done with undo: today, Done on a one-off or place reminder deletes it, with no log and no undo. Any metrics at all. | [FACT: `sprawa-loop.md` "What exists and what's missing"] |
| **Known broken** | Voice sessions sometimes start twice, or connect and stay silent for 30 s (`docs/implementation/VOICE_SESSION_STARTS.md`). On 18 Oct voice couldn't connect at all; the address fix is on main (#88). A 19 Oct check that the server's settings are all set is recorded only on branch `claude/epic-wright-vz93xh`. | [FACT] |
| **Live voice agent settings (18 Oct)** | Authentication off; 10 calls a day for the whole agent; concurrency 2; recordings kept with no time limit. | [FACT: `STATUS.md`] |

**External users:** zero. **Interviews on record:** none. [FACT]

**Verdict:** the engineering is far ahead of the evidence, as it was on 17 Oct. The difference is that the sprawa loop adds no tools, integrations or platforms. Several of its parts exist: the original text kept unchanged, the user's transcripts kept on the phone, local reminders with a Done action, ask-first cards and undo. Joining them is still real work: nine changes in `sprawa-loop.md`, including a new first screen, a changed save path, a change to `said_time` and one data migration. Then it has to be measured. The beta should test that loop with 20 people, not add features.

---

## 3. The problem

**The problem:** small errands and promises pile up and hang over you. Each has a deadline or a person waiting. You carry them in your head, or in a note or a reminder that comes back at the wrong moment with no context. So they slip: the return window closes, the fee lands, the friend is still waiting. [ASSUMPTION]

**Why this is sharper than "I can't find my note"** [ASSUMPTION]:
- The 17 Oct strategy admitted the recall pain was mild: "a vitamin" that people tolerate daily and rarely look to fix.
- A sprawa has a **deadline and a consequence**: money (a missed return, a late fee), time, or a promise broken.
- It also has an obvious **moment of value**: the notification that arrives on Thursday evening, while there's still time.

**How people handle it today** [ASSUMPTION]:
- In their head.
- Apple Reminders: free, but it knows only a title and a time. It doesn't know what the sprawa is or what comes next, and Siri doesn't speak Polish.
- A note to self, or a WhatsApp chat with yourself.
- A calendar entry.
- A task app (Todoist, TickTick), which asks you to keep a system.

**What it costs:** mental load, missed deadlines, small sums of money, and other people's trust. [ASSUMPTION: unmeasured; the beta's interviews ask for a recent example]

**Supporting evidence (indirect):**
- People want AI help but not unsupervised action. Only 9% would let an AI agent finish a purchase on its own; 32% want it to choose and let them confirm. [EVIDENCE: Accenture Consumer Pulse 2026, as cited in the 17 Oct strategy]
- None of this shows that people will hand sprawy to an app, or come back when it reminds them. The beta tests exactly that.

---

## 4. The target user

### Primary: "the person with a pile of sprawy" [ASSUMPTION; the beta tests it]
- A working adult, about 25–45, in Poland, with an iPhone. Comfortable talking to a phone.
- Juggles small errands: returns, bills, appointments, paperwork, promises to friends and family.
- Already uses at least one workaround (Reminders, notes to self, a calendar) and still lets things slip.
- **Job to be done:** *"When something lands on me that I'll have to deal with later, let me hand it off in one sentence. Bring it back when I can actually do it, with the next step ready. Don't do anything without my tap."*
- **Screening questions (10 seconds):**
  1. "Co ci teraz wisi nad głową?" Someone who names two or more things without thinking is in.
  2. "Kiedy ostatnio coś małego ci przepadło: zwrot, płatność, odpowiedź?" A recent, specific answer is the signal.

### Secondary [ASSUMPTION]
- **The family organiser:** holds the household's sprawy (school forms, vaccinations, the car's inspection). Test after the primary user.
- **Adults for whom forgetting is costly,** including people with ADHD. Their pain is higher. Copy must make no health claims, and sprawy can be sensitive.

**Rejected for now:**
- Students, who have less to lose and less to pay.
- People looking for a companion to talk to. Doddy isn't one (section 5).
- "Everyone."

---

## 5. Positioning

**Category: a pomocnik for the things hanging over you.**
- **Not "AI companion."** That category is tied to dependency mechanics and a 2026 study linking companion use with lower well-being. [EVIDENCE: Nature Human Behaviour, Aug 2026, as cited on 17 Oct] The constitution already refuses dependency (DOD-10). [FACT]
- **Not "AI agent that does everything."** That means competing with Apple, Google and OpenAI on breadth. Doddy acts one step at a time, on your tap.
- **Not "memory app."** Memory is how Doddy keeps your words. It isn't the promise.

**Positioning statement:**
> For busy iPhone users in Poland who carry a pile of small errands and promises in their head, **Doddy is a pomocnik you hand a sprawa to.** It keeps your exact words, brings the sprawa back at the right moment with the next step ready, and does nothing without your tap. Unlike Reminders or a note to yourself, it knows what the sprawa is and what comes next. Unlike an AI agent, it never acts on its own and never says "done" unless it is.

**Line:** **Sharp online. Clumsy offline. Honest always.** [OWNER]

**One-line promise** [ASSUMPTION: draft; Polish needs a native read, Phase 5]:
- EN: "Hand Doddy what's hanging over you. It brings it back at the right moment, with the next step ready."
- PL: "Powiedz Doddy’emu, co ci wisi nad głową. Wróci z tym we właściwym momencie, z gotowym następnym krokiem."

**What this replaces:**
- "Tell Doddy before you forget. Find your exact words later." (17 Oct strategy)
- "Tell Doddy before you forget. He remembers it, reminds you, and finds it when you ask." (`docs/product/V1_SCOPE.md`, decision 1)
- "Say it once. Tap once. Done." (homepage hero, ADR-482)

"Your mate in your pocket" can stay as a tagline if the owner wants it. It doesn't contradict the direction, but "mate" leans towards companion (open decision 4).

**Copy to change later, not in this PR** [FACT: counted 19 Oct]:
- The voice agent's first line: "You are Doddy, the AI companion inside the DODDY iPhone app" (`voice-agent/instructions.md:1`). Phase 4 rewrites the prompt anyway.
- The website and blog: about 45 uses of "companion" in `site/`, 15 in `blog/`, 12 in the English text of `l10n/site/en.json` (each locale file also repeats them as source keys), and the Polish text says "towarzysz" 13 times.
- The app's own screens: none.

---

## 6. Product strategy

### The wedge: the sprawa loop
**Hand it over → keep your words → one question → bring it back with the next step → you tap → done, with undo.**
- The first session is exactly this loop and nothing else. No tour. [OWNER]
- Typing works fully without voice. Voice is the faster way in, not the only one. [FACT: PRD rule; OWNER: text fallback]
- Step by step, with what exists in the code today: `sprawa-loop.md`.

### The ladder: outcomes tied to how much Doddy does on its own

| Horizon | What Doddy does | What ships | What unlocks the next step |
|---|---|---|---|
| **Now: the 2-week private beta (M5)** | **Hold and bring back.** Keeps the sprawa in your words, asks one question, brings it back at the agreed time, logs Gotowe with undo. | The sprawa loop on the things v1 already ships: notes, note reminders, Reminders and Calendar, ASK-01. Polish and English. 20 Polish iPhone users. | Day-0 activation, sprawy closed after a bring-back, active days in week two (`VALIDATION.md`) |
| **Next** | **Prepare.** The next step is ready when the sprawa comes back: a message drafted, an email drafted, a time free in the calendar. | Phase 4's skills (Message, Email, Summarize, Pilnuj sprawy, Plan dnia, Kalendarz) over tools that already exist, each with a preview card. | Users accept the prepared step without rewriting it; no false "done" |
| **Later** | **Act with approval.** Doddy does the step after your tap: sends, books, moves. Money stays a hand-off to the bank app (BLIK, ADR-510). | Each action passes ASK-01 at its level. In code today there are two: a read takes a spoken yes or a tap; a change takes a tap on a card with the exact payload (`AskFirst.Need`, `scripts/voice_agent_spec.py`). Money is a hand-off to the bank app (BLIK). The owner's third level, a tap plus Face ID or the bank app, is Phase 2 work. | Verified completion rate; zero actions without a tap |
| **Vision** | **More kinds of sprawa, one skill at a time.** | Connectors, still approval-first. | Users trust Doddy with consequential sprawy |

### Not doing in the beta (feature freeze) [OWNER: no new tools, integrations, platforms or UI features]
1. New tools, integrations or platforms. The Mac and Watch apps stay out of the beta build.
2. Payments. `claude/payments-apple-pay-blik` is not merged. [OWNER]
3. The eight machine-translated languages. Polish and English only. [FACT: `V1_SCOPE.md` suggestion 2]
4. "Hey Doddy", the plan card, online accounts, phone calls and texts: hidden or cut, as `V1_SCOPE.md` suggests.
5. The first-conversation tour, replaced by the one question. [OWNER]

**The freeze and the loop pull against each other in a few places.** Joining the loop changes existing screens (the first screen, the reminder's notification, the Done log). Those changes are listed in `sprawa-loop.md`. The owner decides which of them count as fixes inside the freeze (open decision 2).

### Must-fix before any tester (the five phases)
1. **Voice starts once.** One session owner, no ghost sessions, a lifecycle log (Phase 2).
2. **Every tool waits for its tap** at the right ASK-01 level (Phase 2). `scripts/voice_agent_spec.py` already fails when a tool in the spec has no level; Phase 2 checks that the server and the app enforce the same, and adds the money level.
3. **AI disclosure at first launch and in Settings,** a privacy policy draft, the shortest provider retention that still works, and a server-side daily cap per user (Phase 3).
4. **The bundle ID and team** for TestFlight (Phase 3, owner).
5. **Metrics for the loop,** with no content in them (Phase 5, `VALIDATION.md`).

---

## 7. The business model (not tested in this beta)

- **The beta is free.** No paywall or StoreKit. [FACT: `V1_SCOPE.md` suggestion 7]
- **What changes with the direction** [ASSUMPTION]: a sprawa that saves money or a deadline (a return, a renewal, a trial to cancel) is a clearer reason to pay than finding a note. The pricing work in `docs/business/MONETIZATION_MODEL_V2.md` was built around memory; it gets revisited after the beta, with measured voice costs.
- **Voice cost is the risk to watch:** one measured 14-minute session cost $2.05. [FACT: `MONETIZATION_MODEL_V2.md`, cited in `V1_SCOPE.md` §7] The per-user daily cap (Phase 3) and provider spend limits come before the beta.

---

## 8. Go-to-market for the beta

- **20 Polish iPhone users, 2 weeks, private TestFlight.** [OWNER]
- **Screen everyone** with the two questions in section 4. No more than 20% from the founder's own circle, to limit friendly bias. [ASSUMPTION: carried over from 17 Oct]
- **Ask each tester for one real sprawa before install**, and see whether they hand it to Doddy on day 0.
- **A 15-minute call at the end of week one.** Every slipped sprawa and every "Doddy couldn't" becomes an eval case.
- **The character's job:** recognisable and warm, never in the way of the task. No jokes in sensitive sprawy (health, money, family trouble). [FACT: constitution]
- **After the beta:** the character content and the "Siri still doesn't speak Polish" story from the 17 Oct strategy still apply. Re-check the Siri claim before any use; it was true in June 2026. [FACT: Spider's Web, 8 Jun 2026]

---

## 9. Metrics

**North Star: weekly closers.** Users who, in a given week, mark at least one sprawa Gotowe after Doddy brought it back. This measures the whole promise: they handed it over, it came back at a useful moment, and they finished it. Saves alone can be a list nobody opens. Conversations alone can be entertainment.

**The four the owner named, defined in `docs/product/VALIDATION.md`:**
- **Day-0 activation:** first sprawa saved on the day of install.
- **Sprawa completed:** Gotowe on a sprawa, with undo counted separately.
- **Active days in week two.**
- **Capability-gap events by category.**

**Trust guardrails** (any breach blocks the beta) [FACT: release gates, constitution]:
- Zero "saved" or "done" without a verified store write or provider confirmation.
- Zero actions without the user's tap at the right ASK-01 level.
- Zero sprawy shown with words the user didn't say, without a label saying Doddy wrote them.
- Zero deleted sprawy that come back.

**Beta thresholds** [ASSUMPTION: proposals; the owner sets them before the beta starts, checklist C10]:
- Day-0 activation ≥ 80%. It's the first screen; anything lower means the question doesn't land.
- ≥ 50% of activated users close at least one sprawa after a bring-back in week one.
- ≥ 40% of users active on 3 or more days in week two.
- Undo after Gotowe ≤ 10%. More means the button fires by mistake or the bring-back was wrong.

**Change-course signals:**
- People save sprawy but don't close them after the bring-back. The moment or the notification is wrong.
- People don't save a second sprawa after day 0. The loop didn't pay off the first time.
- Capability gaps cluster in one category. That's the first skill after the beta.

---

## 10. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **Notifications are denied or ignored.** The loop depends on the bring-back. | Medium | High | Ask for notifications at the moment it matters ("Mam ci przypomnieć…?" → tap yes → then the iOS prompt), not at install. If refused, show the sprawa on Home with its time, and say plainly that it can't come back on its own. |
| 2 | **The wrong moment.** "do piątku" → Thursday evening is a guess. | Medium | Medium | Always one question with the proposed time; never set it silently. Measure snoozes and "In 1 hour" taps. |
| 3 | **Voice is unreliable** (ghost sessions, can't hear the user). | High | High | Phase 2. Text works fully from the first screen. |
| 4 | **Polish speech recognition mangles the words** that Doddy promises to keep exactly. | Medium | High | Show the words on the card before saving; easy correction. Phase 5 measures word error rate on 50 real recordings. |
| 5 | **Privacy on the Lock Screen.** A sprawa's words in a notification can be personal. | Medium | Medium | Today the note's text is hidden in notifications by default. Owner decides the sprawa default (open decision 3). |
| 6 | **Scope sprawl.** Phases 4–5 and the open branches pull towards more features. | High | High | The freeze; `docs/branches.md`; one PR per phase. |
| 7 | **Another assistant covers it in Polish.** Siri gains Polish, or people already use Gemini or ChatGPT reminders in Polish. | Medium | High | Re-check before the pitch is used publicly [ASSUMPTION: not researched for this document]. The difference to keep is honesty and the tap, not language alone. |
| 8 | **"Done" that isn't.** | Low | High | Gotowe is the user's own tap; provider actions need the provider's confirmation (ASK-01, DOD-08). `unknown` is never success. |

---

## 11. The plan to the beta

The owner's five phases, one PR each, with a stop for review after each:
1. **Write the direction down** (this PR): this file, `sprawa-loop.md`, `VALIDATION.md`, `docs/branches.md`, STATUS.md pointing here, current milestone M5.
2. **Stabilise main for a device run:** idempotent voice session start, lifecycle logging, the ASK-01 check, a device checklist. The owner runs it on their iPhone.
3. **Clear the TestFlight blockers:** privacy policy draft (PL and EN), AI disclosure, retention settings, a daily usage cap, the bundle ID list, the token flow. The owner does legal, signing and App Store Connect.
4. **A skill router in front of the voice tools** (82 in `voice-agent/tools.json`): a core prompt under 25% of today's size, the P1 skills, evals in both languages.
5. **Polish quality and beta instrumentation:** the Polish string export, the speech-recognition comparison, the metrics and a weekly report.

Then the 2-week beta with 20 users, and the decision M5 asks for: continue, narrow, pivot or stop (`docs/implementation/MILESTONES.md`).

---

## Open decisions for the owner
1. **Confirm the reading of "Clumsy offline"** in section 1: offline, Doddy still holds and brings back sprawy, but asks plainly instead of guessing. The other possible reading is about the character (small and clumsy in the physical world, like "Big brain. Small body." on branch `claude/youthful-pasteur-25tuhv`).
2. **Which loop changes count as fixes under the freeze.** The list is in `sprawa-loop.md`, "Changes the loop needs".
3. **Lock Screen default:** show the sprawa's words in its notification, or keep today's private default.
4. **Tagline:** keep "Your mate in your pocket", or retire it with "companion".
5. **The beta thresholds** in section 9.
6. **`docs/product/V1_SCOPE.md` decision 1** (the one promise) is answered by this direction. Its other rows still stand as proposals; ADR-520 records them once you mark them up.
7. **M5 as written vs this beta.** `MILESTONES.md` asks for 20–24 non-friends, a comparison with each person's substitute, a character-light control and paid intent. Your plan is 20 Polish users for two weeks. The differences are listed in `docs/product/VALIDATION.md`; say which to keep.

## Sources
- Repo: `STATUS.md`, `docs/product/V1_SCOPE.md`, `docs/implementation/GO_LIVE_CHECKLIST.md`, `docs/implementation/MILESTONES.md`, `docs/implementation/OFFLINE_STATUS.md`, `docs/implementation/VOICE_SESSION_STARTS.md`, `docs/quality/VALIDATION_AND_METRICS.md`, `docs/business/MONETIZATION_MODEL_V2.md`, `docs/trust/config/doddy_rules.yaml`, `voice-agent/instructions.md`, and the app and DoddyCore code cited in `sprawa-loop.md`.
- The 17 Oct strategy on branch `claude/doddy-strategy-docs` (`38161c11`), for the Accenture, Nature Human Behaviour and Spider's Web citations.
