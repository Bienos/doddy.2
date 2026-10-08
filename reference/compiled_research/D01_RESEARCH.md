# D01_RESEARCH.md — Doddy | Opportunity framing: independent research

**Research stage only — not `OPPORTUNITY.md` and not a product specification**  
**Research cut-off / access date:** 8 October 2026  
**Geographic emphasis:** Poland / EU; international evidence used only with transferability caveats  
**Population:** adults aged 18+, iPhone-first hypothesis  
**Evidence status:** desk research completed; no Doddy customer interviews, diary studies, comparative user tests, conversion experiments, technical audits, or payment tests have been performed for this report.

## 1. Executive research question and scope

> **Which specific adults encounter a frequent, costly-to-handle, observable moment in which their current phone and AI tools fall short — and could a character-driven assistant improve that outcome enough to induce repeat use and switching?**

The research must distinguish four propositions that are often conflated:

1. **Category demand:** people use conversational AI.
2. **Problem existence:** people have recurring jobs they struggle to complete using today's tools.
3. **Doddy advantage:** its particular workflow, context, voice, or character materially improves those jobs over available alternatives.
4. **Commercial demand:** those improvements cause sustained, voluntary use and, eventually, willingness to pay.

**Provisional outcome:** Proposition 1 has good independent support; historical contextual research lends directional support to proposition 2, but not for a narrowly defined Polish iPhone cohort in 2026. Propositions 3 and 4 are **not established**. The existence of AI companion audiences and a distinctive character does not establish urgency, user retention, or an economically viable subscription. [S01–S09]

**D01 boundary:** This document investigates opportunity, triggers, jobs, competing explanations and research method. Architecture choices, model/provider comparisons, pricing, AI Act legal conclusions, character brand manuals, and implementation specifications remain separate downstream work. Official capability documentation is used here **only** to establish a credible substitute baseline.

**Working interpretation, not a fact:** Doddy has a more testable opportunity as *an approachable interface for a repeatedly needed micro-task with follow-through* than as *a companion people should want to talk to*. Its entertainment character might improve recall, trust, enjoyment, or acquisition — or distract from the task. Both outcomes must be tested.

## 2. Method and source register

### 2.1 Method

- Searched for recent **official population surveys**, **EU statistics**, **observed assistant needs**, **subscription retention benchmarks**, **human–AI companionship studies**, and **first-party competitor/platform documentation**.
- Preferred population surveys and published studies over marketing claims; used vendor documentation for feature existence, not proof of quality or adoption.
- Compared current and historical findings explicitly; historical assistant data is **not** treated as a 2026 feature-capability assessment.
- Converted observations to alternative explanations and proposed **falsifiable, founder-run primary research**.
- Did **not** review Doddy's code, user logs, existing prototype, social analytics or prior internal research artefacts. Their properties, functionality, safety and commercial performance remain owner-provided, unverified statements.

**Evidence ratings:** **A** = strong evidence for the narrow claim (e.g., major survey, official rule/feature); **B** = credible but limited observational / platform-specific evidence; **C** = historical small sample, vendor-selected benchmark, or prescriptive research method. These are not numerical probabilities. A-grade evidence in the US does **not** become A-grade evidence for Poland simply by citation.

### 2.2 Source register

All URLs were checked through live web search or page retrieval on **2026-10-08**. “n.d.” means the live documentation did not expose a stable publication date in the retrieved page. Dates below are publication dates, not guesses from crawl dates.

| ID | Source / author | Date | Direct URL | Evidence and strength | Principal limitation |
|---|---|---|---|---|---|
| **S01** | **Pew Research Center**, Jeffrey Gottfried, William Bishop, Monica Anderson, Michelle Faverio, Eugenie Park, Colleen McClain; *Americans and AI 2026* | 2026-06-17 (survey 2026-02-17–23) | https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/ | **A** for US-adult self-reported adoption, frequency, motivations and concern | US, not EU; self-reported usage, not app telemetry; use is not willingness to pay |
| **S02** | **Eurostat**; *32.7% of EU people used generative AI tools in 2025* | 2025-12-16 | https://ec.europa.eu/eurostat/web/products-eurostat-news/w/ddn-20251216-3 | **A** for EU population penetration | Ages 16–74; all generative AI, not voice, iOS or companion apps; no Polish iPhone cross-tab established here |
| **S03** | **Eurostat**; *64% of 16–24-year-olds used AI in 2025* | 2026-02-10 | https://ec.europa.eu/eurostat/en/web/products-eurostat-news/w/edn-20260210-1 | **A** for EU age cohort | Includes 16–17-year-olds; cannot directly define an adults-only ICP |
| **S04** | **Nielsen Norman Group**, Raluca Budiu & Kathryn Whitenton; *What Could an Intelligent Assistant Do for You? A Diary Study of User Needs* | 2018-10-21 | https://www.nngroup.com/articles/intelligent-assistant-user-needs/ | **C** for transfer to 2026; primary observations about jobs/trigger patterns | 12-person diary sample; 2018 Siri/Alexa/Google assistants were much less capable |
| **S05** | **Nielsen Norman Group**, Kim Flaherty; *Diary Studies: Understanding Long-Term User Behavior and Experiences* | 2024-03-29 | https://www.nngroup.com/articles/diary-studies/ | **B** research-method guidance | Methodology, not evidence of Doddy demand |
| **S06** | **Nielsen Norman Group**, Kim Flaherty; *Contextual Inquiry* | 2020-12-06 | https://www.nngroup.com/articles/contextual-inquiry/ | **B** observational research-method guidance | Methodology, not outcomes |
| **S07** | **RevenueCat**; *State of Subscription Apps 2026* (publisher dataset/analysis) | 2026 edition; publication day not fixed on referenced live page | https://www.revenuecat.com/state-of-subscription-apps | **B** for benchmarked subscription apps within its sample | RevenueCat customers and definitions, heterogeneous app categories; paid-subscriber retention ≠ all-user product retention |
| **S08** | **MIT Media Lab / OpenAI**, Mengying (Cathy) Fang and collaborators; *Early methods for studying affective use and emotional wellbeing in ChatGPT* | 2025-03-21 | https://www.media.mit.edu/posts/openai-mit-research-collaboration-affective-use-and-emotional-wellbeing-in-ChatGPT/ | **B** for reported ChatGPT affective behavior and experimental observations | Studies identified as not peer-reviewed at publication; US, English, ChatGPT; correlations not causal |
| **S09** | **Nature Human Behaviour**, Yutong Zhang, Dora Zhao, Jeffrey T. Hancock, Robert Kraut, Diyi Yang; *Interaction with AI companions and psychological well-being* | 2026-08-04 | https://www.nature.com/articles/s41562-026-02516-2 ; abstract independently accessible via https://pubmed.ncbi.nlm.nih.gov/42552393/ | **B** for correlational evidence among Character.AI users | Character.AI user sample in US; association not causation; full publisher page access was restricted during review |
| **S10** | **Character.AI**, *Character Calls & Voice FAQ* | 2024-08-23 update | https://support.character.ai/hc/en-us/articles/23957274129691-Character-Calls-Voice-FAQ | **A** for vendor-documented voice/character feature existence | Vendor statements, not independently tested feature quality or retention |
| **S11** | **OpenAI**, *ChatGPT Voice* | Live support article; n.d. | https://help.openai.com/en/articles/20001274-chatgpt-voice | **A** for documented voice features/conditions | Rollout, device, limits and regions may vary; documentation is not an independent usability audit |
| **S12** | **OpenAI**, *Memory in ChatGPT* | Live support article; n.d. | https://help.openai.com/en/articles/8590148-memory-in-chatgpt | **A** for existence of personalisation/memory and control options | Availability and exact controls vary by plan, region, account and version |
| **S13** | **OpenAI**, *Connected apps in ChatGPT* | Live support article; n.d. | https://help.openai.com/en/articles/11487775-connected-apps-in-chatgpt | **A** for documented connected-service capabilities | Per-app actions, authorisations, plans and regions differ |
| **S14** | **Google**, *Adding/customising the Gemini widget — iPhone & iPad* | Live support article; n.d. | https://support.google.com/gemini/answer/16179553?co=GENIE.Platform%3DiOS&hl=pl | **A** for documented iOS shortcut/widget launch routes | Feature availability and quality not audited here |
| **S15** | **Apple**, *Translate text and voice for conversations across languages using iPhone* | iOS 26 support guide; n.d. | https://support.apple.com/guide/iphone/translate-text-voice-and-conversations-iphd74cb450f/26/ios/26 | **A** for built-in translated conversation workflow | Supported languages/devices/versions vary; actual translation quality not tested |
| **S16** | **Apple**, *Tap the back of iPhone to perform actions or shortcuts* | Live iPhone guide; n.d. | https://support.apple.com/guide/iphone/back-tap-iphaa57e7885/ios | **A** for user-configurable Back Tap shortcut | Does not confer default, automatic Doddy ownership of the gesture |
| **S17** | **Apple Developer**, *Apple Intelligence* and App Intents overview | Live developer docs; n.d. | https://developer.apple.com/apple-intelligence/ | **A** for officially documented integration surfaces | OS/device/entitlement/API constraints need engineering verification; not carte blanche to control other apps |
| **S18** | **Apple Developer**, *App Review Guidelines* | Live guidelines; n.d. | https://developer.apple.com/app-store/review/guidelines/ | **A** for platform review requirements | Jurisdiction-specific payment rules and changing policies require review before launch |
| **S19** | **European Commission**, *Principles of the GDPR* | Official guidance; n.d. | https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/principles-gdpr_en | **A** for GDPR principle summary | Not project-specific legal assessment |
| **S20** | **EU**, *Regulation (EU) 2024/1689 (AI Act)*, Article 50 and effective-date provisions | Enacted 2024; consolidated EUR-Lex text reviewed 2026-10-08 | https://eur-lex.europa.eu/eli/reg/2024/1689/oj | **A** for legal text | Application/transition dates and possible amendments require qualified contemporaneous review |
| **S21** | **Pew Research Center**, *Appendix: Detailed chart and tables* | 2026-06-17 | https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-appendix-detailed-chart-and-tables/ | **A** for age breakdown among US adults | 2026 wording changes complicate comparison with earlier waves |

**Access notes:** The Nature publisher page was indexed, but direct opening redirected to restricted access; its abstract was cross-checked against PubMed [S09]. RevenueCat's main report and OpenAI/Apple/Google documentation are *living pages*; archive an export/screenshot and re-check before any investment memorandum. No unverified Poland-specific usage percentage is inserted.

## 3. Findings — fact, relevance, confidence, limitation, counter-evidence

### F1 — AI use is widespread, but generic adoption is not Doddy demand

**Verified observation.** In 2025, **32.7% of EU residents aged 16–74** reported using generative AI; **63.8% of EU 16–24-year-olds** did so. In Pew's February 2026 US survey of **5,119 adults**, **49%** said they had used a chatbot, and **24%** said they used one daily. These figures measure different populations, tools and periods; they cannot be blended into a Doddy addressable market estimate. [S01–S03]

**Relevance.** There is a meaningful population familiar with AI, reducing the need to explain the category from scratch. Adults who already use conversational AI are more plausible initial participants than an undifferentiated “everyone with a phone” market.

**Counter-evidence / limits.** The same prevalence indicates tough habitual competitors, not an unmet market by itself. No source establishes that **Polish adult iPhone users** need a **new** AI app. Eurostat's young-adult statistic includes minors; US usage intensity cannot be carried over to Poland. **Confidence:** High for EU/US category adoption; **low** for Doddy demand.

### F2 — Real assistant jobs cluster around mundane triggers, not necessarily a desire for companionship

**Historical primary observation.** In NN/g's 2018 assistant-needs study, **12 diary participants** recorded **636 requests** for an imagined capable assistant. The article reports that 14 ambiguous entries were excluded and that 621 remained (a one-entry arithmetic discrepancy in the published counts); **193 reported usable entries were repeats**. Among **428 unique needs**, reminders and local information were prominent. The study found that users actually attempted an existing assistant for only **7% of the unique needs**, although reviewers judged **41% addressable** and **21% partly addressable** by at least one then-current assistant. [S04]

**Trigger examples grounded in the study:** “I must not forget a thing”; “what is my schedule/route/weather”; “I need an answer in this specific moment”; “I have to coordinate a next step.”

**Relevance.** Jobs are occasion-based. Recurrence can be measured per **episode** — not inferred from a broad persona label. The study suggests an *expectation / usability gap*: people may use a familiar phone workflow even when an assistant could theoretically help.

**Counter-evidence / limits.** These are **2018**, small-sample findings; they do **not** prove an unsolved technical gap in 2026, nor that voice/character will fix it. Modern built-in and frontier assistants now handle many of these tasks. **Confidence:** Moderate for the general *method of looking for repeated micro-jobs*; low for contemporary prevalence or Doddy's advantage.

### F3 — Functional need is substantially more common than “AI companionship” in a broad-adult survey

**Verified observation.** Pew's 2026 US population survey found **42% of adults** used chatbots to search for information, **25%** for fun/entertainment, **10%** for emotional support or advice and **4%** for companionship. These are **percentages of US adults**, not mutually exclusive shares of chatbot users. [S01]

**Relevance.** The character might be valuable as a **recognisable entry point and preferred interaction style**, while task utility drives return. The most defensible initial job should be observable without asking, “Do you want a digital mate?”

**Counter-evidence.** Entertainment use is also real, and a smaller dedicated audience might value the character enough to return or pay. Broad survey percentages cannot rule out a niche. However, a premise that *most adults want an AI friend* is directly unsupported. **Confidence:** High for US population task mix; low for specific Doddy character appeal.

### F4 — Competition already offers much of the proposed bundle

**Verified product capabilities (documentation, not firsthand QA):** ChatGPT documents conversational voice, memory, and connected apps/actions subject to availability [S11–S13]. Character.AI documents two-way character voice calls and transcripts [S10]. Gemini documents iPhone widgets and direct entry into Gemini Live [S14]. Apple supports a built-in voice conversation translation workflow [S15]; an iPhone user can configure Back Tap to run a shortcut [S16]. Apple publishes App Intents as a way for app functionality to be available through system integrations [S17].

**Relevance.** “Voice + LLM + memory + reminders + distinctive avatar” is a collection of features, **not yet a defensible unsolved job**. Competition should be compared by the exact task path, including unlock/launch, permissions, time, failures, privacy, and ability to finish.

**Counter-evidence.** Feature presence is not proof of effortless execution, human appeal, excellent Polish language interaction, safe memory, or reliable context. Doddy might win a narrow journey. Yet it should not be positioned as the only assistant capable of voice, memory, translation or actions. **Confidence:** High for documented existence; unknown for side-by-side user outcomes.

### F5 — Subscription-app monetisation and recurring usage are especially risky for AI

**Observed vendor benchmark.** RevenueCat's 2026 report covers **115,000+ apps** and **$16 billion+** in tracked revenue. In its dataset, AI apps generate **41% more revenue per payer** in year one than non-AI apps, while long-term paid subscription retention is weaker: at 12 months, **6.1% vs 9.5%** for monthly plans (AI vs non-AI). RevenueCat also reports higher refund rates among AI apps. [S07]

**Relevance.** This is a strong warning against mistaking curiosity, a viral character, free sign-ups, or an initial payment for long-term value. Paid retention and provider usage costs must eventually be tested separately.

**Limits and counter-evidence.** These are RevenueCat-using apps with different verticals, price points and acquisition channels. The retention figures describe **subscription-plan retention**, not Day-30 app activity or a controlled AI-vs-non-AI causal test. Strong AI products can still succeed. **Confidence:** Moderate for a general commercial risk signal; low for any forecast for Doddy.

### F6 — Anthropomorphic companionship may help some users, but sustained attachment has real downsides

**Research observations.** An OpenAI/MIT research program reported that emotional cues were unusual across most observed ChatGPT sessions, concentrated among a subset of heavy users; a four-week randomised study of nearly 1,000 adults found nuanced effects of interaction format and associations between heavier *voluntary* usage and poorer psychosocial outcomes. The researchers warned that correlations do not show causation and stated that results had not yet been peer-reviewed at the time. [S08]

A 2026 *Nature Human Behaviour* study surveyed **1,131 US adult Character.AI users** and examined **4,664 sessions** from a subset of **237** participants. It reported an association between companionship-primary use and lower self-reported well-being, with stronger associations for intensive/high-disclosure use. **This is observational, not a finding that AI companions cause harm.** [S09]

**Relevance.** Doddy's character should be evaluated for improving usability, expression and approachability **without** inducing dependent behaviour, excessive disclosure, or pretending to be human. A healthy success metric is repeat task value, not maximising time spent or emotional reliance.

**Counter-evidence.** Some users experience enjoyment, comfort and lower social friction from conversational AI. Neither study compares the proposed Doddy design with a neutral, task-capable assistant. **Confidence:** Moderate for the existence of welfare risks and complex use patterns; low for Doddy-specific psychosocial effects.

### F7 — Privacy is part of the switching decision, not a guarantee of differentiation

**Verified observation.** In Pew's 2026 US survey, **71%** expected increased AI use to make their personal information *less secure*. This measures perceived impact, not willingness to grant particular permissions to Doddy. [S01]

**Applicable requirements, not a full legal conclusion.** The GDPR principles of purpose limitation, minimisation, storage limitation and confidentiality apply where personal data processing falls within its scope [S19]. Apple requires truthful permission purposes and has App Review / payment rules relevant to a microphone/location/subscription app [S18]. Article 50 of the AI Act addresses informing people when directly interacting with certain AI systems, subject to its wording, exceptions and applicable timing [S20].

**Relevance.** Personal memory can improve task performance but introduces a **trust/permission cost**. A character can make disclosure feel casual, increasing rather than reducing risk. Measure opt-in and withdrawal separately from general “trust” survey responses.

**Limits.** This is a **research-stage issue map**, not a GDPR impact assessment or confirmation of a legal basis, controller/processor roles, transfer adequacy, DPIA obligation, minimum age or AI Act classification. Have EU/Polish counsel assess actual flows before public launch. **Confidence:** High for general principles; low for a Doddy-specific compliance determination.

### F8 — “Instant access” cannot be assumed from iPhone-first intent

**Verified capability.** Apple's documentation describes Back Tap as a **user-selected** double- or triple-tap action, including running a shortcut [S16]. App Intents enables supported system integrations [S17].

**Relevance.** Doddy's target workflow must be tested with the **real installation, setup and launch sequence**: user configuring the shortcut (if wanted), permissions, recognition accuracy, response latency and tool completion. The app cannot claim automatic Back Tap installation or default replacement of Siri on this evidence.

**Counter-evidence.** The extra setup itself may eliminate any time saved; in other cases users may prefer a recognisable recurring shortcut. **Confidence:** High for documented setup nature; unknown for the feasibility and adoption of a specific Doddy path.

## 4. Candidate jobs, competing hypotheses and alternatives

The following are **research candidates**, not validated segments, feature priorities or specifications.

### 4.1 Episodes that could plausibly recur

| Candidate adult cohort (recruitment hypothesis) | Trigger / observable job | Actors and environment | Current substitutes | Possible burden to look for | What genuine improvement must beat | Serious disconfirmation |
|---|---|---|---|---|---|---|
| **A. Busy iPhone adults with interruptions and follow-through tasks**; e.g., workers/students balancing appointments and personal errands | “I just remembered something while doing another activity; capture it and make sure it happens at the right time” | User; sometimes a third party; phone often locked or hands occupied | Siri, Reminders, Calendar, Notes, ChatGPT voice, writing down/messaging self | Re-entry, missing detail, forgotten follow-up, failed reminder confirmation | Higher **verified task completion** with fewer steps, while offering review/edit control | Siri/Reminders handles it just as well or faster; infrequent missed actions; users do not grant calendar/reminder access |
| **B. Adults with recurring bilingual face-to-face or spoken communication** | “I need to understand/respond now, with minimal conversational interruption” | User and speaking partner; noisy/public location; possibly poor connectivity | Apple Translate, Google Translate, Gemini/ChatGPT voice, human help | Turn-taking, supported language pair, awkwardness, correction burden, latency | Better turn-taking, accuracy and user-rated communication success on the **same language pair** | Built-in offline translation is faster, more private and free; occasions are too infrequent to support retention |
| **C. Existing frequent AI users who repeatedly lose task context** | “I already explained this preference or decision, and need it for another job” | User; repeated multi-session personal context; sometimes external tools | ChatGPT memory/history, Notes, search, calendar, saved prompts | Retrieval failure, stale context, correction, uncertainty about what was stored | Correctly recall **consented, relevant** facts, show provenance, let users change/delete, reduce repeats | ChatGPT memory is sufficient; privacy cost exceeds convenience; perceived errors destroy trust |
| **D. Character-entertainment fans who discover Doddy through content** | “I saw Doddy; I want another amusing interaction” | Viewer and social content; later optional app trial | TikTok/Reels/Shorts, Character.AI, creator communities, ChatGPT | Little evidence of a hard problem; primarily entertainment preference | Voluntary return to a **specific useful in-app job** beyond novelty | High views/follows but low app activation or repeat tasks; character is better as media IP than paid assistant |

**Research priority, not a product choice:** Test **A** first for clear recurring episodes and objective completion; test **B** as an independent high-intensity situational job; probe **C** carefully due to permission/privacy costs. Treat **D** as a separate *acquisition and creative-format hypothesis*, not proof of an urgent problem. This ordering comes from falsifiability and measurement feasibility, **not** demonstrated market ranking.

### 4.2 Competing explanations for the same observations

| Observation or founder belief | H1: Proposed opportunity interpretation | Rival explanation to actively test | Discriminating evidence |
|---|---|---|---|
| Users do not ask assistants for some tasks | Existing tools are too frustrating or slow | Users prefer direct controls or simply have no reason to delegate | Observe real episodes; ask user to attempt preferred baseline and Doddy without coaching |
| Users abandon generic AI chats | Character/continuity are missing | Task occurs rarely, answer quality is insufficient, or app opens are burdensome | Split recurrence, failures, character preference and actual return behaviour |
| Users respond warmly to animated character | Attachment makes them use the app | Character is only momentarily entertaining; engagement does not transfer to utility | Compare content view → install → completed job → 4-week voluntary reuse |
| More personal data improves assistance | Controlled memory saves repeated explanation | Users already get equivalent memory or will not consent to storage | Consent-choice experiments plus same-context error/correction tests |
| People request translation | A personal speaking companion has a wedge | Default translate tools dominate on speed, offline operation and privacy | Paired test against Apple Translate and current preferred alternative |
| More voice use implies retention | Voice makes interactions accessible and fluid | Voice is socially awkward, inaccurate in noise, slow or unnecessary | In-situ task logs with *quiet/private/public* contexts; text fallback |
| Strong waitlist signup count means demand | Audience wants a companion | Users want free entertainment, early access, or novelty | Require qualified episode evidence and later active tasks, not just emails |
| Longer sessions mean success | People enjoy Doddy | Delay, tool failure, rambling, dependency or engagement manipulation | Measure completion, corrections, voluntary return and self-rated autonomy, not talk minutes |

### 4.3 Switching-cost inventory

For each observed occasion capture all of: **physical launch effort**, **permission and login burden**, **lost existing history/memory**, **trust/security concern**, **required app switching**, **money already spent on alternatives**, **reliance on native services**, **language coverage**, **notification fatigue**, and **learned habits**. These costs may outweigh even a more entertaining UI.

A minimal defensible alternative set for paired testing is:

1. **Native iPhone path:** Siri / Shortcuts / Reminders / Apple Translate, whichever actually solves that episode [S15–S17].
2. **Current preferred AI:** ChatGPT voice + memory/connected apps as available to that particular test user [S11–S13].
3. **Other voice/character experience:** Gemini Live/widget and Character.AI calls, where relevant to the job [S10, S14].
4. **No-assistant workaround:** notes, manual Google/web search, typing, human translation, setting reminders directly.

These are comparison *classes*, not assertions that each service can perform any particular task on all devices or in all regions. Confirm features live on matched iPhones and accounts before tests.

## 5. What each D01 question can and cannot resolve today

### Q1. Who experiences the problem repeatedly?

**Established:** There are adults who regularly use chatbots in the US and substantial AI adoption in the EU; historical field/diary work recorded repeated assistant-related moments [S01–S04]. **Not established:** the precise Polish iPhone cohort with recurring, costly unresolved jobs. **Best recruitment hypothesis:** adults who can recount **at least three real occurrences of one named job in the past seven days** and at least one observed workaround. Do not start from “likes Doddy” or “likes AI”.

### Q2. What event triggers the job?

**Established directionally:** reminders, local information and immediate information needs are recurrent *categories* in historical observed assistant use [S04]. **Not established:** current Doddy trigger frequency or whether a trigger is private enough for voice. **Research requirement:** time-stamped episode record describing the real-world event, environmental conditions, urgency and whether a phone/assistant was already open.

### Q3. What is the current workaround and switching cost?

**Established:** several powerful substitutes exist and already cover voice, memory, translation and shortcuts [S10–S17]. **Not established:** actual end-to-end success, paid entitlements, effort and willingness to switch among target Polish users. **Research requirement:** record **the participant's own first-choice baseline**, not an arbitrarily weak competitor; time and observe it on a real task.

### Q4. What would meaningful improvement look like?

**Not established:** no Doddy comparative measurements. Candidate outcome metrics, selected per job: **successful follow-through**, **correct/accepted conversational translation**, **correct recall with control**, **steps**, **elapsed time**, **corrections**, **privacy/permission rejection**, **independent repeat use**. A smiling animation, a low-latency first reply, a positive comment or viral video alone is insufficient.

## 6. Missing external evidence and concrete founder-run research plan

**No interviews or results are claimed below.** These are prospective methods, sample plans and *proposed decision rules*, to be registered before seeing outcomes. Small qualitative studies reveal failure modes; they do not estimate population prevalence.

### Study 0 — Instrument and recruiting screen (3–5 working days of founder effort; calendar estimate, not validated)

**Deliverables:** participant screener, consent/privacy notice, episode log template, scorecard, baseline task list, moderated interview guide, and test eligibility sheet.

- Recruit **24 adult iPhone users**, split **8 A / 8 B / 8 C**. Aim for Poland-heavy recruitment with a documented subset from another EU country only if feasible. Record country, language, iOS version, accessibility needs, baseline assistant and existing subscriptions; no need to collect sensitive traits.
- **Recruit based on episodes:** at least 3 episodes in the past 7 days for that assigned job. Exclude founder's close friends from the primary sample or tag relationship and analyse separately.
- Seek contrasting behaviours: frequent/current AI users vs Siri/native-first users, voice-preferring vs text-preferring users; do not require all participants to like anthropomorphic apps.
- Avoid under-18 participants. Use a minimal privacy-preserving recruitment dataset and participant IDs. Do not require raw chat histories.
- Suggested screening question: “In the last seven days, exactly when did you need to [capture and follow up / translate a live exchange / retrieve a personal detail]? Tell me the last three occurrences and what you did.” **Do not** lead with “Would you use Doddy?”
- Google Forms may organise screening, but submitted intentions are **not behavioural validation**.

**Possible failure:** the alleged recurring problem is rare when probed for dates and concrete instances. If so, stop the relevant cohort rather than loosening the screen to make it pass.

### Study 1 — Recent-episode interview + contextual baseline (24 x 45–60 minutes)

**Tasks:**

1. Ask for the *last actual episode* first, then reconstruct a timeline: trigger → attempted actions → substitute → outcome → corrections → lost/forgotten steps.
2. Request a voluntary **walkthrough on their own phone** of the existing workaround; do not request access to unrelated personal content. Permit a realistic mock task if live data is sensitive, but tag mock vs real.
3. Collect **real consequences** (missed deadline, rework, awkward exchange, money/time lost) separately from annoyance scores.
4. Probe non-use: “Why didn't you ask Siri/ChatGPT/Translate?” and “What would make you keep your current method?”
5. Introduce a neutral description of a better workflow **after** baseline observation; ask for concrete adoption obstacles, not purchase promises.

**Episode record:** anonymised participant ID; segment; event; last-occurrence timestamp; weekly frequency evidence; context/private or public; required permission; existing apps; number of transitions; elapsed time; completion; consequence; monetary cost if any; dissatisfaction *in the user's words*; alternative cause; interviewer's confidence in observation.

**Analysis:** use a jobs-based thematic matrix, count repeatedly observed *patterns within sample*, mark contradictory cases, and publish anonymised cases only with explicit participant permission. **Do not** extrapolate “X% of Polish users”.

### Study 2 — Prospective 14-day contextual diary (18 participants: 6 per A/B/C)

**Purpose:** verify naturally occurring frequency; reduce retrospective and aspirational bias. NN/g identifies diary work as suitable for longitudinal, in-context behaviours [S05]; contextual observation adds evidence on the actual workflow [S06].

- Prompt once per day to report **episodes that happened**, including when a participant used **no AI**. Permit zero-episode days.
- For each: trigger, tool chosen, environment, approximate duration, result, follow-through, reason for rejecting AI or voice, and any *uncompleted* job.
- Randomly select a handful of episodes for brief verification or voluntary screen recording of a **redacted/synthetic reproduction**.
- No full conversation transcripts or microphone recordings by default; request explicit additional permission if a narrow research question genuinely requires them.
- Count **episodes per person per week**, concentration across contexts, and number of genuinely painful/failed episodes. Compare diaries to claimed screener frequency to identify overstatement.

**Go/no-go candidate for proceeding to task benchmarking (not an industry benchmark):** At least **half of the 18 eligible diarists** exhibit **≥3 relevant episodes in a 7-day period**, and **at least one episode per such diarist** has a concrete, observed drawback with the existing method. With only 18 participants this is a **screen**, not a market-size estimate. Failure means revise the job definition or population.

### Study 3 — Head-to-head job completion with a prototype (task-specific, not full beta)

**Preconditions:** the founder supplies a build stable enough to execute the chosen job, an equivalent text-only/neutral mode if testing personality, and a documented permitted iOS launch path. Record API/provider differences so they do not contaminate character comparisons.

- Recruit **20–30 adults** from the matching job cohort, preferably including new people who have not seen the character content.
- Within-subject comparison: **participant's current best method vs Doddy**, matched tasks, counterbalanced task and presentation order. Include an unaffected no-assistant path when relevant.
- Measure end-to-end **time to correct final result**, step count, corrections, failures, user confirmation and permission refusals; for reminders verify the reminder actually exists and triggers as expected (not merely that AI said it did).
- For translation, predefine language pair, noise condition and fidelity scoring by appropriate bilingual reviewers; verify whether an Apple offline baseline is available.
- For memory, use explicit, consented test facts and score recall accuracy, omission, correction/deletion and unsupported inference.
- Test **personality effect separately**: same functionality and comparable voice/latency with Doddy character on vs neutral mode; if true isolation is not feasible, call it a confounded exploratory comparison.

**Proposed gate (set before observing results):** consider further exploration if the winning job shows **≥15 percentage-point improvement in end-to-end successful completion** *or* **≥20% reduction in median completion time** without worse error/privacy outcomes against the participant's preferred current method. These are **founder-selected hypotheses**, not externally proven market standards. Report effect sizes, task variance and sample uncertainty. A task-level win is not evidence of retention or PMF.

### Study 4 — Four-week repeated-use field experiment and character-to-app funnel

**Purpose:** measure voluntary return for a specific problem and separate brand interest from operational use. This is a **future test**, not D01 evidence.

- Invite approximately **60–90 eligible adult users**, divided by initial primary job and logged acquisition source; instrument minimum viable analytics with explicit privacy disclosure.
- **Primary return metric:** unique users completing their pre-registered target job on **at least 2 separate days per week** in **both weeks 3 and 4**, excluding onboarding tasks and researcher-requested sessions.
- Report denominator from invite → consent → install → first *successful task* → week-3/4 repeat; stratify by organic / content-driven / directly recruited and by original job.
- Collect failed attempts and whether the same person abandoned the app for their old method. Do not define “retention” as app open, animation watched, total messages, or emotional dependence.
- **Character experiment:** matched task-flow prototype with expressive Doddy vs neutral presentation, where practical; track *task success and voluntary return*, as well as perceived warmth and distraction. Avoid deceptive claims that the agent is a human friend.
- **Distribution experiment:** release character-led videos with clearly instrumented links and content variants; evaluate **qualified, adult iPhone activations and successfully completed jobs** rather than aggregate views, likes or follows. Organic distribution can be extremely uneven; record platform and creative effects.
- After demonstrated utility, test payment with a **real, transparent offer** compliant with relevant platform/consumer rules; survey “would you pay?” is only exploratory. Define price and cost later, not in D01.

**Illustrative continuation gate, not a benchmark:** **≥30%** of fully onboarded eligible users in the leading job cohort satisfy the above *both-weeks repeat criterion*; task success and safety do not degrade; meaningful content acquisition yields observable qualified activations. Small-cohort thresholds are directional and must be re-tested with a larger, less biased cohort. A failed gate means revisit problem/positioning, not automatically add features or gamification.

### Study 5 — Explicit falsification and synthesis session

Prior to any `OPPORTUNITY.md` decision:

- Collect the **five strongest episodes where the incumbent was better** and the **five strongest reasons participants refused Doddy**.
- Make a side-by-side table of *new job success vs extra friction*, including setup, iOS restrictions, errors and privacy.
- Re-check whether *character preference* predicts task success or is merely entertainment exposure.
- Make a **sample-bias register**: founder/social followers, AI enthusiasm, Polish/English proficiency, iPhone model and free-vs-paid baseline entitlements.
- Retain inconclusive findings as inconclusive. A “market exists” summary without cohort-level evidence should **not pass D01 acceptance**.

## 7. Risks, confidence assessment and unresolved questions

| Risk | Severity to D01 conclusion | Evidence/confidence | Falsification or mitigation |
|---|---|---|---|
| **No narrow recurring unmet job** | **Critical** | Generic AI category adoption strong; Doddy episode-level need unmeasured | Recruitment based on dated episodes and diary confirmation |
| **Character solves marketing, not daily utility** | **Critical** | US entertainment demand exists but companionship niche; no Doddy retention evidence | Isolate character condition; follow content-to-task funnel |
| **Incumbents already win target journey** | **Critical** | Strong documentation of substitute capabilities [S10–S17] | Time current preferred workaround side by side; no strawman |
| **Additional launch/configuration friction on iOS** | High | Supported setup constraints [S16–S17], implementation unreviewed | Test real onboarding and device-specific flow |
| **AI app subscription churn** | High | RevenueCat observational benchmark [S07] | Return-to-job measure, cohort-based follow-up, later actual payment test |
| **Oversharing or unhealthy anthropomorphic attachment** | High | Independent studies show heterogeneous patterns and welfare associations [S08–S09] | Adult-only protocol, user agency, limited data, safe persona boundaries, welfare monitoring |
| **Perceived privacy risk / refusal of memory and location** | High | Pew perception [S01], GDPR baseline [S19] | Observe actual consent behaviour; optional memory and permissions |
| **Poland-specific demand inferred from US or all-EU data** | High | Direct transfer not supported | Poland-heavy interviews and diaries; avoid ungrounded national figures |
| **Translation accuracy, multilingual performance, noisy voice** | High for segment B | No side-by-side Doddy verification | Bilingual scoring; test indoor/outdoor, network and offline substitutes |
| **Uncontrolled prototype quality and AI costs** | High for later delivery, unresolved at D01 | Owner-provided prototype statement only | Separate technical review and unit-economics evaluation after problem confirmation |
| **Minors may still reach public content/app** | High legal/ethical review | Age-screening and legal plan not established | Define adult-only access/marketing and obtain counsel review |
| **Sample selection / social desirability / founder bias** | High | Research design risk | Recruit outside own audience, observe behaviour, blind comparisons where possible |

**Confidence summary:**

- **High:** conversational AI is an established category in the EU/US; competitors offer overlapping functions; privacy and subscription-risk concerns are real at category level.
- **Moderate:** repeated reminder, information and context jobs are plausible discovery areas; assistant usability and psychosocial effects require careful empirical observation.
- **Low:** exactly which Polish/EU adult iPhone cohort is underserved; whether character improves task success; whether voice launch is habitual; willing-to-switch rates; willingness to pay; content-to-app conversion.
- **Unassessed:** Doddy prototype reliability, practical App Intent/Back Tap integration, actual operating expenses, data-processing inventory, age verification, security and legal compliance.

**Open research questions:**

1. Which distinct job crosses the threshold of genuine weekly recurrence *without the researcher prompting it*?
2. Is the main obstacle **unmet capability, access friction, trust, knowledge/expectation, or the lack of a compelling reason to bother**?
3. Can Doddy outperform the participant's **best** substitute, or does personality merely decorate equivalent functionality?
4. Do people choose voice in the real environments where episodes occur, or switch immediately to text/native controls?
5. What user context is truly necessary for task improvement; what do people permit, correct and revoke?
6. Does character-led entertainment deliver qualified adults with the target recurrent job, rather than just fans?
7. Are Polish-language / bilingual use cases materially different from English-language research, especially in errors and cadence?
8. What proportion return **without** a researcher reminder or an app push, and why do others stop?
9. What later value is sufficiently distinct to justify payment beyond existing free and already-paid services?
10. Can an adults-only positioning be enforced and marketed responsibly, given the character's potential appeal to younger viewers?

## 8. Findings subsequent decisions may rely on — versus hypotheses to test

### Rely on as externally supported premises (only within the stated scope)

- Conversational / generative AI is already widely known and used; **this proves category familiarity, not a Doddy market** [S01–S03].
- Everyday reminder, local-information and information-retrieval moments are defensible starting points for **investigation**, based on historical observation; **2026 recurrence must be measured anew** [S04].
- Voice, persistent personalisation, translation, mobile entry points and character voice calls are **existing competitive capabilities** and should be treated as baselines, with account/device caveats [S10–S17].
- Paid AI apps have material subscriber-retention risk in a large but nonrepresentative benchmark sample [S07].
- Companion-like AI engagement has heterogeneous psychological associations; **more emotional dependence is not an acceptable proxy for product value** [S08–S09].
- Privacy, platform and AI-transparency obligations cannot be postponed merely because a product is character-led [S18–S20].
- Contextual inquiry and diary studies are appropriate ways to investigate **real episodes** as distinct from survey preferences [S05–S06].

### Do not treat as facts until directly tested

- Polish iPhone users prefer a character companion to ChatGPT, Siri, Gemini or native utilities.
- Busy users forget enough follow-through tasks to install a new app.
- A conversational translation helper beats Apple's existing Translate experience.
- Doddy's memory is more accurate, controllable, useful or trusted than existing AI memory.
- Animation/cheekiness increases task completion or multiweek healthy retention.
- Short-form characters generate low-cost activated app users.
- People will accept always-on or frictionless background operation on iOS.
- Doddy users will pay a subscription or use it often enough to cover AI costs.
- Doddy's existing prototype is stable, privacy-preserving, secure, commercially deployable or compliant.

## 9. Compact structured summary

```yaml
FACTS:
  - "2025: 32.7% of EU people aged 16–74 used generative AI (Eurostat S02)."
  - "2026 US adult survey: 24% reported daily chatbot use; 42% information search; 4% companionship (Pew S01)."
  - "Historical assistant diary research found repeat practical tasks but does not establish a 2026 Poland-specific opportunity (NN/g S04)."
  - "Major substitute products document voice, memory, translation and character experiences (S10–S17)."
  - "RevenueCat 2026 shows weaker median 12-month AI monthly-plan paid retention in its sample (S07)."
ASSUMPTIONS:
  - "Busy adult iPhone users have repeated, painful follow-through moments."
  - "Contextual voice or memory can outperform a participant's current baseline."
  - "Doddy's character makes meaningful tasks more approachable without harming task success."
  - "Character-led audience attention can convert to voluntary repeated task usage."
RISKS:
  - "No concrete unsolved weekly job; substitute superiority; setup friction; paid churn."
  - "Privacy rejection, over-personalisation, unhealthy attachment, unreliable tasks."
  - "US/EU-to-Poland transfer error and nonrepresentative recruited samples."
OPEN_QUESTIONS:
  - "Which actual weekly trigger, which cohort and what measurable consequence?"
  - "Which substitute wins, including trust, setup, latency and permissions?"
  - "Does character change successful repeat use or only initial attention?"
  - "Can users choose not to remember and still receive enough value?"
RECOMMENDATIONS:
  - "D01 status: RESEARCH COMPLETE; OPPORTUNITY NOT YET VALIDATED."
  - "Recruit on documented episodes, not enthusiasm for AI or cartoons."
  - "Run 24 interviews, 18-person 14-day diary, paired task tests and later an opt-in repeated-use field cohort."
  - "Benchmark against preferred incumbent; pre-register task-based gates and negative cases."
  - "Do not author final OPPORTUNITY.md until observed recurring pain and a credible better outcome are demonstrated."
```

---

**Research-stage completion statement:** The independent **secondary research** requested by D01 has been conducted and conflicting evidence recorded. The **opportunity itself is not validated**. No customer research, actual subscription transaction, local-market penetration study or Doddy prototype evaluation is implied by this document. The next evidence must come from founder-conducted observations and prospective tests; those results will determine whether the problem statement merits a final specification.