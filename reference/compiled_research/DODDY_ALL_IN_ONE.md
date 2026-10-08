# DODDY — Complete Research & Strategy (All-in-One)

**Product:** DODDY — *Your mate in your pocket.*  
**Compilation date:** 8 October 2026  
**Document purpose:** One searchable Markdown file containing the **entire original text** of all five research, evaluation and strategy documents.  
**Editorial policy:** Each source document is appended verbatim, in source order, without rewriting its claims, conclusions, source citations or headings. The brief navigator below is new.  
**Approval:** **NOT ACCEPTED / NO FOUNDER SIGNOFF.** Compiling a document does not validate or approve its contents.

## Start here — current decision snapshot

- **Current position:** Continue with narrowly bounded research, prototype tests and contained character-content experiments; do **not** treat this as a green light for full-scale Doddy V2 production.
- **Two separate tests:** (1) Does Doddy the Character attract qualified attention? (2) Does Doddy the App demonstrably solve a recurring job better than a realistic substitute, generating voluntary repeat use?
- **First proposed app test:** conversational intention capture and follow-through, compared against users' preferred existing tools; **not** a validated feature choice. Translation and controlled memory recall remain alternatives.
- **Evidence gaps:** No documented founder-run Doddy interviews or user cohorts; no audited prototype source code; no confirmed retained-user acquisition costs, willingness to pay, or inference-based unit economics.
- **Upstream dependencies:** Accepted D03 Voice of Customer and D04 Competitor Analysis are missing. Neither `OPPORTUNITY.md` nor `DEMAND_EVIDENCE.md` has been approved or produced here.
- **Read the strategy first** for priorities and the ten next actions, but consult the original research and evaluations for evidence and caveats.

## Contents

1. [D01 — Opportunity framing: independent research](#source-d01-research) — original file: `D01_RESEARCH.md`
2. [D01 — Opportunity framing: adversarial evaluation](#source-d01-evaluation) — original file: `D01_EVALUATION.md`
3. [D05 — Demand and channel signals: independent research](#source-d05-research) — original file: `D05_RESEARCH.md`
4. [D05 — Demand and channel signals: adversarial evaluation](#source-d05-evaluation) — original file: `D05_EVALUATION.md`
5. [Doddy — Strategic recommendations and 90-day action plan](#source-doddy-strategy) — original file: `DODDY_STRATEGIC_RECOMMENDATIONS.md`

## How to use this file in Claude / Claude Code

Use the full document as **reference evidence, not as a specification or approved roadmap**. Prefer the individual files in the ZIP when context size matters. When a source report disagrees with its evaluation, flag the difference and consider the evaluation's critique; do not silently alter the source. Never claim interviews, A/B experiments, legal approval or technical audits happened merely because the reports propose them.

## Full source documents — unmodified


---

<a id="source-d01-research"></a>

## SOURCE 1/5 — D01 — Opportunity framing: independent research

**Original filename:** `D01_RESEARCH.md` · **Original ZIP path:** `docs/research/D01/D01_RESEARCH.md` · **Source below is reproduced verbatim.**

<!-- BEGIN VERBATIM SOURCE: D01_RESEARCH.md -->

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

<!-- END VERBATIM SOURCE: D01_RESEARCH.md -->

---

<a id="source-d01-evaluation"></a>

## SOURCE 2/5 — D01 — Opportunity framing: adversarial evaluation

**Original filename:** `D01_EVALUATION.md` · **Original ZIP path:** `docs/research/D01/D01_EVALUATION.md` · **Source below is reproduced verbatim.**

<!-- BEGIN VERBATIM SOURCE: D01_EVALUATION.md -->

# D01_EVALUATION.md — Doddy | Opportunity framing: adversarial evaluation

**Status:** EVALUATED; **NOT ACCEPTED / NO SIGNOFF**  
**Decision:** **CONDITIONAL CONTINUE — research and narrowly scoped tests only. Do not commit to a full personal-companion application or paid acquisition on current evidence.**  
**Evaluation/access date:** 8 October 2026  
**Geography:** Poland and EU as intended launch/research markets; US sources are contextual comparators  
**Input audited:** `D01_RESEARCH.md` (373 lines, dated 8 October 2026), available in this conversation. This evaluation supersedes no source document and does not create `OPPORTUNITY.md`.

## Executive assessment

The research report is substantially more careful than a typical AI-app market assessment: it separates category adoption from Doddy-specific demand, documents strong substitutes, flags psychosocial and privacy issues, and explicitly admits no founder-run user studies have occurred. Most of its key *descriptive* third-party claims are traceable to the cited original publications. **There is no verified material fabrication in the audited high-impact figures.**

But **the opportunity is still undefined at the level D01 requires**. Three distinct practical jobs (follow-through, translation, personal-context recall) and a fourth entertainment/distribution strategy are bundled into one proposed product without observed local problem frequency, quantified present-day failure, or an empirically superior Doddy experience. The chosen first cohort is an *investigation convenience*, not evidence of a market. Existing-app features and US/EU aggregate adoption cannot establish a Poland-first, iPhone-specific, paid market.

**A key new finding omitted in the original source interpretation:** Eurostat reported **49.3% generative-AI use among Polish people aged 16–24 in 2025**, the third-lowest figure in the listed EU comparison. This is useful geographic counterweight to the EU-wide **63.8%** figure, **but still includes minors, measures all generative AI, and does not measure iPhone users, voice, unmet need or intent to pay** [E01]. Therefore the original report's choice not to invent an adult Polish iPhone estimate was correct; its statement that no Poland-specific usage figure was inserted was unnecessarily incomplete.

**Another material time-sensitive correction:** EU AI Act **Article 50 transparency provisions have applied since 2 August 2026**, not merely at some unspecified future point. The European Commission's July 2026 guidance says users of directly interactive AI systems must generally be informed that they are interacting with AI, subject to the statutory ‘obvious’ exception. A narrow pre-market grace period described by the Commission concerns Article 50(2) marking/detection, **not an unrestricted delay of AI-interaction disclosure** [E08]. Applicability to Doddy's precise role and outputs requires specialist review.

**Top-level confidence:** High for the existence of competing solutions and broad AI adoption; moderate for category-level subscription and anthropomorphism risks; **very low for the specific Doddy opportunity, switching advantage, repeat use and payment propensity**. This is a confidence assessment, not a numerical probability.

---

## 1. Factual claim and source audit

### 1.1 Evidence rules used for this evaluation

- **SUPPORTED:** source located and the narrow cited fact is accurately described; not necessarily generalisable to Doddy.
- **SUPPORTED WITH LIMITATION:** claim is directionally accurate but source, population, metric or causal inference limits its use.
- **REQUIRES CORRECTION:** imprecise interpretation, omitted contrary evidence, or wrong present-tense legal framing.
- **UNVERIFIED:** no original Doddy data or independent observation exists. This does not mean the hypothesis is false.
- **DISPUTED:** contradictory direct evidence has been located. None of the primary audited statistics warranted a definitive “false” verdict; several *inferences* are unsupported.

Direct-source checks were conducted on 8 October 2026, primarily by retrieving the cited publisher or regulatory page. Living documents are not reliably versioned; all platform capabilities must be rechecked on the actual EU account/device for a real test. Primary figures and dates below are from linked sources, not invented tests.

### 1.2 Decision-critical claim-by-claim audit

| ID | Original claim / reliance | Audit verdict | Independent check and caveat | Consequence for D01 |
|---|---|---|---|---|
| **C01** | Eurostat: 32.7% of EU residents aged 16–74 used generative AI in 2025 | **SUPPORTED** | Eurostat, **16 Dec 2025**, explicitly says 32.7% during the prior three-month reference period [E01a]. Not conversational AI frequency, iOS, or willingness to switch. | Category familiarity **only**. |
| **C02** | Eurostat: 63.8% of EU 16–24-year-olds used generative AI | **SUPPORTED; geographical qualification required** | Eurostat, **10 Feb 2026**, states 63.8%; **Poland 49.3%** in same age band [E01]. Neither figure isolates adults aged 18+. | Poland-wide extrapolation must be blocked. |
| **C03** | Pew: 49% of US adults had used chatbots; 24% use daily | **SUPPORTED** | Pew, **17 Jun 2026**; US survey of **5,119 adults** conducted **17–23 Feb 2026** [E02]. The daily group is a share of all adults, not 24% of users. | Not a Polish iPhone market size. |
| **C04** | Pew: 42% information search, 25% entertainment, 10% emotional support/advice, 4% companionship | **SUPPORTED; interpretation restricted** | These are nonexclusive purposes among **all US adults**, not usage shares or motives for a character-styled *utility assistant* [E02]. Low explicit companionship use does **not** disprove demand for a friendly character *interface*. | Do not equate character styling with companionship as a user job. |
| **C05** | Pew: 71% think increased AI use makes personal data less secure | **SUPPORTED WITH LIMITATION** | Exact Pew sentiment figure [E02]; measured expectations about AI in society, **not** observed grant/decline decisions for Doddy permissions. | Measure actual permission choices. |
| **C06** | NN/g: 12 participants, 636 imagined needs, 14 excluded, 621 analysed, 193 repeat, 428 unique; 7% assistant use | **SUPPORTED WITH PUBLISHED ARITHMETIC ERROR** | NN/g, **21 Oct 2018**, contains those exact numbers, but **636 − 14 = 622**, not 621. The source itself is inconsistent [E03]. Participants were instructed to imagine a *perfect* assistant; outcomes from 2018 cannot describe a 2026 unmet need. | Use as inspiration for a study design only; do **not** use the 7% as contemporary market evidence. |
| **C07** | RevenueCat: >115,000 apps, >$16bn, AI 12-month monthly-plan subscriber retention 6.1% vs 9.5%, 41% higher Y1 revenue per payer | **SUPPORTED WITH LIMITATION** | RevenueCat 2026 [E04]. App sample is its tracked ecosystem; cross-category composition and subscriptions are confounders; this is **paid-subscriber retention**, not user D30 or app sessions. An internal page passage gives inconsistent weekly figures; do not rely on weekly figure without dataset clarification. | A category warning, **not** a retention prediction or calibration for Doddy's beta. |
| **C08** | MIT/OpenAI 2025 programme: affective ChatGPT usage concentrated; study of nearly 1,000 over four weeks | **SUPPORTED WITH LIMITATION** | MIT, **21 Mar 2025** [E05]. Mixed observational and intervention designs; findings include nuance and no evidence that an engaging voice by itself worsened outcomes within the study. Do not claim simple causal harm. | Design safeguards; do not turn engagement into attachment optimisation. |
| **C09** | Zhang et al., *Nature Human Behaviour*: 1,131 US Character.AI users, 4,664 sessions donated by 237; certain companionship patterns associated with lower well-being | **SUPPORTED WITH LIMITATION** | Peer-reviewed journal article published **4 Aug 2026** [E06]. Self-selection and correlational analysis limit causation; actual Doddy behaviour unexamined. Original research's warning is appropriate. | Guardrail and outcome risk, not proof against all character apps. |
| **C10** | Competitors offer voice, memory, connected apps, character calls, iOS launch shortcuts and translation | **SUPPORTED AS CAPABILITY CLAIM, NOT UX RESULT** | First-party pages for ChatGPT/Character.AI/Google/Apple [E07a–E07f]; plans, entitlements, language pairs, age, OS and rollout vary. Character Calls provides two-way audio; its separately described “Character Voice” function is one-way, so distinguish them [E07b]. | Baselines must be reproduced with actual eligible accounts and phones. |
| **C11** | Back Tap cannot be silently made Doddy's default gesture on installation | **SUPPORTED FOR THE DOCUMENTED PATH** | Apple directs the user to **Settings → Accessibility → Touch → Back Tap** and choose a double/triple action [E07e]. No ability to seize the gesture by default is evidenced. | Count configuration as switching cost. |
| **C12** | GDPR principles and Apple review rules matter; AI Act Article 50 may apply | **SUPPORTED BUT TIMELINE TOO VAGUE** | GDPR baseline, Apple 5.1/3.1; **AI Act Article 50 applying since 2 Aug 2026** per Commission [E08–E10]. Research-participant data is itself regulated; contractual/consent basis cannot be guessed. | Legal review **before** live user research involving personal data; more detailed review before public beta. |
| **C13** | Adults with interruption/reminder problems are the strongest first segment | **UNVERIFIED INFERENCE** | NN/g historical study demonstrates conceivable jobs, **not** relative Polish 2026 urgency or a stronger alternative than native Reminders. No targeted diaries yet. | Change wording from “priority segment” to “first falsifiable test candidate”. |
| **C14** | 24 interviews, 18 diarists, 20–30 benchmark participants and 60–90 field-testers give sufficient D01 evidence | **NOT ESTABLISHED** | These are founder-designed sample counts, not powered sample sizes. Combining six diarists each from three jobs conceals per-job heterogeneity; recruiting only high-frequency screeners creates selection bias. | Revise method and per-job decision denominators; qualitative discovery ≠ prevalence. |
| **C15** | ≥15pp task-success uplift **or** ≥20% time reduction; ≥30% repeated-use are valid decision thresholds | **UNVERIFIED / UNDER-SPECIFIED** | The report properly calls them illustrative. Baseline task success, severity, variance, error rates, cohort eligibility, task frequency and sample precision were not used to set them. A faster answer can be less safe or correct. | Retain only as *candidate preregistration targets* after pilot variance/baseline measurement; never call them industry norms. |
| **C16** | Doddy's existing prototype supports reliable actions, distinctive voice, memory or privacy-preserving behaviour | **UNVERIFIED** | Founder assertion; repository/code, device tests, instrumentation and security not examined. | No technical capability signoff or product claim. |
| **C17** | Character-led content can create a qualified, retained and payable Doddy audience | **UNVERIFIED** | No view→click→adult iPhone install→completed job→voluntary return funnel; follows and views have no validated conversion. | Test content as a separate acquisition hypothesis. |

**Principal interpretation error to avoid:** `adoption of AI` → `recurring pain` → `preference for Doddy` → `paying subscriber` is **not** an evidence chain. Every arrow needs direct observations with appropriate denominators.

### 1.3 Original source-register integrity (S01–S21)

| Original ID | Source integrity as of 8 Oct 2026 | Evidentiary use allowed |
|---|---|---|
| S01 Pew 2026 | Publisher report and February 2026 fieldwork verified [E02]. | US self-reported categories and sentiment. |
| S02 Eurostat 2025 | Official article, **16 Dec 2025**, verified [E01a]. | EU aggregate, last-three-month generative AI use. |
| S03 Eurostat youth | Official article, **10 Feb 2026**, verified; **Poland 49.3%** omitted from analysis [E01]. | EU and Polish age-16–24 comparisons, *not* adult-only market. |
| S04 NN/g 2018 needs | Publisher study verified, including small sample/imagined needs and own numerical inconsistency [E03]. | Historic task taxonomy/research approach; not 2026 demand. |
| S05 NN/g diary methods | Accessible method guidance, **29 Mar 2024** [E11]. | How to conduct longitudinal self-reports, not evidence of a customer problem. |
| S06 NN/g contextual inquiry | Accessible method guidance, **6 Dec 2020** [E12]. | How to observe workflows, not evidence of a customer problem. |
| S07 RevenueCat 2026 | Vendor benchmark accessible, methodology partially self-described [E04]. | Directional commercial warning; cohort nonrepresentative. |
| S08 MIT/OpenAI 2025 | Primary institutional page and two-study structure verified [E05]. | Possible psychosocial mechanisms with design restrictions. |
| S09 Nature 2026 | Publisher metadata and abstract located via indexing; Nature page direct retrieval constrained, PubMed record supports bibliographic and abstract facts [E06]. | Correlations among Character.AI users, not causal inference. |
| S10 Character.AI FAQ | First-party support, updated **23 Aug 2024**, retrieved [E07b]. | Existence of voice calls, not present-day PL voice quality. |
| S11 OpenAI voice | First-party living help article retrieved [E07a]. | Current documented voice features, subject to account testing. |
| S12 OpenAI memory | First-party living help article retrieved [E07a]. | Memory feature/control presence, not retrieval accuracy. |
| S13 OpenAI connected apps | First-party living help article retrieved [E07a]. | Documented integration categories, not Polish actions guaranteed. |
| S14 Google Gemini widget | First-party living support retrieved [E07c]. | iOS widget/launch entry point, not task efficacy. |
| S15 Apple Translate | First-party iOS 26 guide retrieved [E07d]. | Translation route, with exact device/language requirements to retest. |
| S16 Apple Back Tap | First-party iPhone guide retrieved [E07e]. | User-configured shortcut availability. |
| S17 Apple Intelligence/App Intents | First-party developer overview retrieved [E07f]. | Integration surface only; not unrestricted OS access. |
| S18 Apple App Review | First-party living guideline retrieved [E09]. | Current review baseline: subscriptions, privacy and app quality. |
| S19 Commission GDPR summary | Official general principles verified [E10]. | Baseline obligations, not controller-specific compliance result. |
| S20 AI Act EUR-Lex | Enacted law retrieved; **more precise current interpretation in July 2026 Commission guidance** [E08]. | General legal baseline; specialist applicability review required. |
| S21 Pew appendix | Publisher demographic appendix retrieved [E02b]. | US cross-tabs, no Polish extrapolation. |

**Source-provenance finding:** This is a reasonably well-sourced desk research report, **not** a systematic literature review: search queries/inclusion rules are not logged; some sources are self-interested platform vendors; many pages change over time; no Poland-specific adult iPhone cross-tab, baseline-app audit, raw survey instrument review or meta-analysis of research interventions was performed. “21 sources verified” should not be interpreted as 21 independent lines of demand evidence; several are documentation and methodological guidance.

---

## 2. Alternatives and decision matrix

### 2.1 What alternative decisions are actually available?

**A — Full “mate in your pocket” general companion now.** Voice + character + memory + varied tools, freemium iOS app. *Potential upside:* unified personality and breadth. *Why it may fail:* indistinct broad job, complicated permissions, vendor feature parity, excessive costs, unclear core behaviour. **High sunk cost / difficult to reverse after launch.**

**B — Narrow utility workflow first, character layered on top.** Select **one** demonstrably repeated outcome (e.g., capture → verify reminder → actual follow-through); retain a companion-style visual and voice skin but don't require emotional reliance. *Upside:* measurable task win and affordable scoped test. *Why it may fail:* iOS native tools already suffice, and charming persona may have negligible incremental value. **Relatively reversible** until full integration.

**C — Translation-first conversational product.** Target people with demonstrably frequent bilingual exchanges, with clear language pairs and real environments. *Upside:* urgent episodes and objective bilingual scoring. *Why it may fail:* irregular frequency, Apple/Google baseline, noise, offline/privacy disadvantage; subscription value uncertain. **Reversible** if translation remains a modular experiment.

**D — Personal-context retrieval specialist.** Focus on explicit remember/recall/correct/delete across actual repeated tasks. *Upside:* potentially durable value. *Why it may fail:* ChatGPT already provides memory, privacy friction high, incorrect recall costly; identity/memory plumbing expands solo-founder scope. **Medium reversibility / persistent data commitments.**

**E — Character-media IP only at first.** Publish expressive Doddy content without claiming or shipping a full assistant. *Upside:* cheaply tests creative resonance and permits independent entertainment business. *Why it may fail:* followers do not need an app; likes cannot identify repeated work problems; platform reach fragile. **High creative reversibility; weak evidence for software demand.**

**F — Parallel two-track discovery (recommended near term).** Run a *small character-content test* and *independent job discovery/prototype comparisons* with shared measurement but **separate success criteria**. Only join them after qualified audience-to-task conversion is shown. *Upside:* protects both original vision and independent falsification; low speculative engineering commitment. *Why it may fail:* founder's capacity becomes fragmented; two experiments must be deliberately bounded. **High reversibility.**

**G — No Doddy app; rely on ChatGPT/Shortcuts/native tools.** A genuine alternative if no measurable job remains underserved. *Upside:* no operating burden; strongest baseline for value. *Why it may fail:* leaves differentiated character/content opportunity untested. **Fully reversible.**

### 2.2 Evidence-sensitive decision matrix

Legend: **Favourable / Conditional / Unfavourable / Unknown** reflects *relative validation attractiveness*, **not verified market performance**. No fake weighted ROI or unmeasured competitive scores are assigned.

| Route | Clear testable real-world job | Hard incumbent comparison | Character-IP learning | Privacy/engineering burden | Speed/cost of falsification | Reversibility | Evidence-based present posture |
|---|---|---|---|---|---|---|---|
| A. Broad companion | **Unfavourable** (many jobs) | **Hard** (multi-feature) | Favourable | **High** | Slow/costly | Low | **Do not fund build** |
| B. Follow-through microjob | Favourable *in design*; need unverified | Siri/Reminders strong | Conditional | Medium if permissions deferred | Favourable | High | **First falsifiable candidate, not winner** |
| C. Translation wedge | Favourable *when high frequency proven* | Apple/Google strong | Conditional | Medium (voice/data) | Conditional; language scoring required | High | **Test only for frequent real episodes** |
| D. Memory specialist | Conditional | ChatGPT strong | Conditional | **High** | Slower | Medium | **Defer until memory pain observed** |
| E. Character media first | **No utility job tested** | Competes for attention | **Favourable** | Low for software; IP/content obligations | Favourable | High | **Creative experiment only** |
| F. Parallel bounded tests | Favourable process, not proven demand | Incumbent tests retained | Favourable | Low–medium if limited | **Favourable** | **High** | **Recommended research strategy** |
| G. Existing tools/no app | Already covers many jobs | **Baseline** | Can retain media IP | Lowest software burden | Immediate | Highest | **Default if new job fails** |

**Choice reversibility constraint:** The earliest irreversible commitments are not a sketch or a TikTok. They include permanent personal-memory architecture, cloud retention promises, subscription entitlements, licensed/contracted voice assets, large production animation inventory and third-party data flows. Delay these until an outcome and audience are selected.

**Commercial alternatives cannot be ranked yet:** Subscription, one-off payment, ad-funded content and no app remain hypotheses. Paid-tier pricing and CAC/LTV are *not* determined by a 12-month RevenueCat category benchmark.

---

## 3. Contradictions, noncontradictions and missing upstream decisions

**Accepted upstream documents:** **None supplied for D01**. The user explicitly specifies no upstream dependencies. Therefore **no verified contradictions with an accepted upstream specification** can be claimed. `D01_RESEARCH.md` is a draft input, *not* an approved opportunity decision.

Internal tensions that must be resolved before final framing:

1. **Named objective vs unit of analysis.** D01 requires *one concrete audience / triggered observable job*. The founder brief proposes a broad personal companion serving translation, memory, advice, reminders, local search, entertainment. The research creates A/B/C/D candidate cohorts without choosing a validated job. This is appropriate for exploration but does **not** meet acceptance.
2. **Problem framing vs preselected solution.** “Conventional assistants feel impersonal” and “a mate in your pocket” are *solution/experience hypotheses*. Whether users actually fail to finish tasks is the prior question. Avoid recruiting on appreciation of the Doddy character.
3. **Character affinity vs companionship metric.** Pew's **4% direct companionship** question does not measure preference for animated styling in a practical product. Using it as direct disproof or proof of character-led advantage would both be invalid.
4. **Urgency vs frequency.** The 3-episodes-in-7-days filter prioritises frequent tasks but could exclude high-stakes, occasional bilingual communication. Frequency, consequence, context and willingness to replace a baseline must be recorded separately.
5. **Selection bias built into the screening criterion.** Recruiting *only* people already able to cite three recent episodes then reporting many recurring episodes is circular. Add a broader population screen or explicitly label results as within a deliberately high-frequency segment.
6. **Pooled diary pass gate is invalid for choosing one job.** Nine qualifying of 18 across three jobs could mean 6/6 from one segment, 3/6 in another and 0/6 in the third; pooling hides where opportunity exists. Report per-job denominators and negative cases, never pooled aggregate as proof.
7. **End-to-end success vs isolated character value.** A Doddy-vs-ChatGPT speed win could result from a different model, prompt, account, UI, training or number of steps. Identical-function neutral/character conditions, with counterbalanced task orders, are needed to attribute an advantage to character identity.
8. **App launches/engagement vs quality of follow-through.** Favourable session length, animation views and conversation counts do not imply saved time, successful action, independence or consent.
9. **D01 acceptance vs later PMF proof.** The original report effectively places a four-week product-return cohort and real payment test before a final opportunity specification. These are valuable **later viability tests**, but D01's own stated gate is *observable recurring problem and falsifiable assumptions*. Don't require commercial PMF to document a provisional opportunity, and don't mistake completing D01 for validating PMF.
10. **Adult-only positioning vs widely distributed cartoon content.** Public videos are discoverable by minors even if the eventual app is meant for 18+. Define audience, content moderation, and data collection early; no assumption of closed adult distribution.

---

## 4. Severity-ranked risks and mitigation experiments

**Severity convention:** **P0** can invalidate the *opportunity*; **P1** can make a validated need unattractive or block ethical/technical delivery; **P2** reduces confidence or scaling options. Severity measures consequence, not probability.

| Rank | Risk / disconfirming outcome | Severity | What would falsify the direction | Concrete owner-run test / mitigation | Evidence presently missing |
|---|---|---|---|---|---|
| 1 | **Nobody in a recognisable cohort has repeated *unmet* episodes** | **P0** | Consequences rare; incidents resolved satisfactorily with today's tools; candidate pain inflated in interviews | Independent broad screener plus 10–14 day prospective task diaries; demand actual dates, outcomes and unprompted workarounds | Base-rate frequency in Polish adults and repeat rate within selected cohort |
| 2 | **Incumbents beat Doddy end-to-end** | **P0** | Participant's *own* Siri/Reminders/Translate/ChatGPT path is more accurate, faster, easier and preferred | Record baseline before showing Doddy; matched tasks, cross-over order, verify final artefacts and permissions | Actual baseline error/time/setup on Polish devices |
| 3 | **Character only generates novelty, not chosen use** | **P0** for character-led product thesis | Enjoyment or viewing lifts but voluntary job completion and week-3/4 use do not | Two-arm same-capability/latency character-vs-neutral task study; later content→install→successful job cohort | Incremental character effect independent of model and workflow |
| 4 | **No switching incentive / subscription surplus** | **P0 commercial** | Users keep paying or defaulting to other tools; no real trial/paid transaction despite demonstrated job win | Observe voluntary post-study substitute; only later run transparent paid offer; contribution margin after inference and store fees | WTP revealed behaviour, true provider costs, price elasticity |
| 5 | **Actual app access adds friction** | **P1** | Shortcut setup or permissions exceed time saved; voice launch unreliable under lock/noise | Real iPhone usability test across iOS models and contexts; include first-run effort and cold start; use supported App Intents/Shortcuts | Device/OS-specific prototype validation |
| 6 | **Task failure / false claims of completed actions** | **P1** | Reminders fail to be created, translations mislead, memories hallucinate, agent claims to act when it did not | Ground-truth task suite, error taxonomy, external-artifact verification, explicit confirmations and fallbacks; red-team prototype | End-to-end reliability, safety baseline and failure recovery |
| 7 | **Privacy/permissions make memory unusable** | **P1** | Target users refuse microphone/calendar/location/memory; erase history; loss of trust after retrieval mistakes | Test progressively requested permissions and **no-memory condition**; measure actions, not agreement with abstract privacy language | Lawful processing map, actual permissions, deletion/correction test |
| 8 | **Character creates harmful social or dependency incentives** | **P1** | Increased inappropriate disclosure, pressure to return, perceived human claims, dependency signals | Ethical dialogue review; explicit non-human identity; bounded emotional language; measure autonomy and adverse events rather than time spent | Persona safety protocol and supervised test criteria |
| 9 | **Sampling/measurement confounds fabricate an apparent win** | **P1** | Results disappear among independent nonfans; only coached tasks succeed; inflated denominator | Neutral recruiter; tag acquisition; preregister denominator, missing events, exclusions; report intention-to-test and per-job groups | Independent sample, preregistration, missingness analysis |
| 10 | **Poland transferability and language fails** | **P1** | Imported US demand pattern not found locally; Polish accents/noise and translation pairs create unacceptable errors | Poland-first cohort; bilingual independent scorers; compare actual PL/EU iPhones and plans | Poland adult iPhone sample and voice/language test |
| 11 | **Research or live beta violates data and platform obligations** | **P1/blocker for launch** | Unlawful recordings/transfers, absent transparency, incorrect data rights, unlicensed voice/IP, noncompliant subscription | Counsel review before recruitment with actual data; then DPIA necessity screen / provider contracts / app review audit before beta | Role mapping, lawful bases, subprocessor and transfer list, rights workflow, rights to character assets |
| 12 | **Solo-founder scope/cost overload** | **P2 now; P1 at build decision** | Animation, real-time speech and actions exceed budget/time or gross margin | Narrow prototype cost trace; measure voice minutes, tokens, speech, retries and provider charges *per completed task* | Real telemetry, per-segment unit economics, technical debt assessment |

**Risk interaction:** The combination of a friendly character, personal memory and natural audio increases the chance that people reveal private information before the app needs it. A positive UX test that depends on extensive data capture may therefore be **commercially or legally non-transferable** to an acceptable privacy model.

---

## 5. Recommendation, strong counterarguments, and decision boundaries

### Recommendation: bounded two-track D01 follow-up, then choose one micro-job or stop

**Track 1 — independent problem discovery:** Recruit adult Polish iPhone users around **specific recent tasks**, and a small broader screen that estimates the share eligible for the high-frequency cohort. Observe uncoached workflows **before** describing a character. Investigate A (follow-through), C (memory pain), and B (translation) as separate hypotheses. The order may be set by ease of recruiting; it is **not** a proven ranking of potential business value. Terminate a job if its workarounds prove satisfactory.

**Track 2 — character resonance, kept separate:** Publish a limited batch of Doddy character experiments, retain platform/date/creative and adult-targeting indicators, and measure behaviour beyond views. Test whether people who enjoy Doddy can name a recurring practical task and subsequently complete it in a prototype. This can validate creative direction **even if an AI-companion application is not viable**; it must not substitute for Track 1.

**Once there is one credible job**, run a narrow end-to-end comparison against each participant's actual best tool with full onboarding included; also compare character vs neutral *within the same working functionality*. Keep optional memory and permissions minimal. Proceed to a small, time-bounded field pilot only if the candidate job is genuinely present and Doddy has a credible better outcome.

### Strongest counterarguments to the recommendation

- **“A broad companion becomes valuable through cumulative context, so narrow tasks miss the point.”** Plausible. An episode-based starting point could underestimate value of a long-running relationship. Rebuttal: establish the minimum recurring data-backed job before exposing user information and building expensive infrastructure; add longitudinal continuity as a separate test when recurrence exists.
- **“Character entertainment is itself the paid value; it need not beat Siri.”** Also plausible. The correct business would then be a *character entertainment / parasocial media experience* with different success metrics and welfare safeguards, not a general productivity companion justified by reminder frequency. Explore as a separate opportunity definition rather than smuggling entertainment success into a task-utility claim.
- **“A solo founder can ship quickly, so testing costs more than building.”** A throwaway prototype may be cheaper than extensive interviews. That supports **testable low-cost builds**, not accepting broad product/retention/permissions assumptions. Don't conflate a demo with reliable paid delivery.
- **“The market can change as AI models improve; today's narrow gap may close.”** Correct. Therefore assess strategic differentiation as *workflow distribution/brand* plus proven outcome, not proprietary access to commodity model features.
- **“A highly engaged niche could be viable despite Pew's low companionship statistic.”** Correct. Survey average prevalence cannot falsify concentrated preference or payer intent. Recruit the niche directly and require revealed behaviour while monitoring safety.

**Most serious potential invalidator of the entire app direction:** When users are observed under natural conditions, their preferred existing tools are good enough, they do not voluntarily switch, and character exposure yields only a short novelty spike. In that case the rational outcome is **character media-only, a different user job, or no app**, not an expanded feature set.

---

## 6. Confidence and explicit decision thresholds

### 6.1 Confidence by proposition

| Proposition | Confidence | Reason |
|---|---|---|
| Many EU/US consumers know and use generative/conversational AI | **High**, within defined populations | Pew and Eurostat representative surveys [E01a, E02]. |
| At least some adults encounter ordinary task capture, translation and context episodes | **Moderate for existence** | Longstanding human workflows and historical NN/g observations; contemporaneous local burden not measured. |
| Polish adult iPhone users have a sizeable, underserved *weekly* job | **Very low** | No episode data, population denominator or matched incumbent outcome. |
| Doddy completes that job meaningfully better | **Unassessed** | No inspected prototype / comparisons. |
| Doddy's character increases healthy voluntary reuse rather than novelty | **Unassessed** | No independent two-arm test or retention cohort. |
| Character content acquires people who complete the target job | **Unassessed** | No attributable audience→task funnel. |
| Freemium subscription will sustain contribution margin | **Unassessed** | No price test, cost trace, churn observation or acquisition economics. |
| Personal-data flows and app can legally launch in Poland/EU | **Unassessed** | General regulatory sources only; no flow/contract review. |

### 6.2 Distinguish three gates — do not collapse research completion into PMF

**Gate D01-A — permitted to write a *provisional* `OPPORTUNITY.md` (not accept it as validated):**

1. **One** named adult cohort and one primary job; documented trigger, actors/context, incumbent workflow, consequences, and switching friction.
2. Minimum **8–12 independent, relevant episodes** collected across **at least 5 people**, including at least **3 prospectively observed episodes** (not solely retrospection), plus **at least 5 negative/disconfirming cases** recorded. These counts are **proposed research-management minimums, not statistical representativeness or industry benchmarks**.
3. There is an **observable, nontrivial shortcoming** in some incumbent outcomes (failure, rework, repeated context, harmful latency or meaningful user effort), not merely a preference survey or avatar admiration. Record raw denominators and failed recruitments.
4. At least one plausible, *permitted and testable* Doddy intervention exists; no need to claim it already outperforms incumbents.
5. Top 3 falsifiable assumptions, rival explanations, measurement plan and critical ethical/legal conditions are documented. Absence of these fails the gate.

**Gate D01-B — recommendation to spend on a *scoped* outcome prototype / field pilot (stronger than D01-A):**

- Same one-job cohort, independent prospectively recorded triggers; participants successfully reproduce or experience the task without coaching; acceptance and baseline outcomes reported separately.
- A matched test (target **20–30**, adjusted after pilot variability) finds a **practically important improvement** against each participant's real preferred baseline in verified end-to-end success and/or effort, **with no worse material accuracy, permission or safety outcomes**. Report effects and uncertainty; the original `+15pp success OR −20% time` are **illustrative targets only**, to be adapted and preregistered, not post-hoc success claims.
- Distinguish *functional* effect from *character* effect; if character cannot be isolated, say so rather than attributing a win to Doddy's identity.
- Independent reviewer confirms feasible permitted iOS path and critical data handling for pilot.

**Gate D01-C — future commercial viability (not a prerequisite for a D01 provisional document):**

- In a **single predefined job cohort**, instrument a real 4-week pilot; record opt-in, installs, first task success, failed tasks, opportunity exposure and **eligible opportunities** as well as repeats. Use trigger-adjusted repeat rates, since some participants have no relevant real-world trigger every week.
- Report voluntary task completion and verified outcome, retention definition, censoring/attrition, nonfan users, permissions, safety, **and baseline substitute reversion**. The prior 30% weeks-3-and-4 threshold is an **unvalidated proposal**; set job-appropriate thresholds with pilot observations and sample uncertainty.
- After useful repetition is established, obtain actual purchase behaviour under a transparent compliant offer and a provider-cost/StoreKit-margin model. No willingness-to-pay inference from interviews or signups alone.

**Predeclared stop/pivot logic:**
- If no distinct cohort produces observed pain: **stop D01-A for that job**, don't manufacture recurrence via recruiting criteria.
- If incumbent outcomes are reliably as good/better and launch/permissions worsen the workflow: **stop that utility wedge** or pivot to distinct problem.
- If character is liked but doesn't improve qualified activation or voluntary use: **retain it as branding/media**, not as validated software differentiation.
- If a narrow job works but personification creates disclosure/safety harms: ship a neutral/less intimate interface or stop that mode.
- A threshold exceeded by the screened cohort is **not** a general-population market estimate and does not constitute approval.

---

## 7. Required human, legal and technical verification

### Founder / human research owner — before interpreting any D01 gate

- Specify **one episode and one outcome** per experiment, with recruiting eligibility and *separate* broad screener denominator. Report how many approached, screened, eligible, enrolled, completed; tag founder followers/friends/AI professionals.
- Prepare participant information, privacy notice, consent-to-participate and relevant data-processing documentation; record lawful basis separately from mere agreement to take part. Do not request raw private conversations by default.
- Conduct actual phone walk-throughs with present-day Siri/Reminders/ChatGPT/Apple Translate/Google Translate/Character.AI as appropriate; record iPhone model, iOS, paid tier, language, connectivity and whether the alternate feature worked.
- Run prospective zero-episode diaries, moderate failed recordings/workarounds, preserve negative cases, and preregister statistical/clinical-equivalent materiality definitions for each job without researcher coaching.
- Character creative assets and voice: maintain provenance, licences, assignment/IP releases (including generated designs), no unlicensed impersonation; adult-market moderation and advertising review.
- Have someone independent of the founder review coding of pain and exclusion of disconfirming incidents.

### EU / Poland legal/privacy specialist — before any identifiable pilot recruitment and before release

1. Identify controller(s), processor(s), actual model/voice/analytics subprocessors, storage locations, transfers, retention/deletion/export and Article 6 bases by purpose; separately assess any **Article 9** special-category disclosures. **Voice recordings do not automatically become Article 9 biometric data** merely because they are audio; assess if used for unique identification and any sensitive content revealed.
2. Check recruitment forms/diaries, voluntary screenshots/audio, participant notices, withdrawal, masking, access controls and incident response. Do not assume pseudonymisation makes datasets anonymous.
3. Assess **Article 50 AI-interaction notice effective since 2 Aug 2026**; assess whether machine-readable marking and public-facing media labelling are implicated, by role/output. Do not claim broad deferral from the limited marking grace period [E08].
4. Determine whether a **DPIA** is required based on actual proposed processing risk, not because an app uses AI in the abstract; assess age access, EU/Poland requirements and the distinction between “18+ target” and real minors encountering open social content.
5. Review Apple privacy declarations/permissions, subscriptions (Guideline 3.1.2), in-app deletion, misleading character claims, and EEA payment/consumer requirements using current store rules [E09].
6. IP/licence verification for Doddy character, animation, music, generated art, and cloned/synthetic voices; contracts with content creators and distribution platforms.

*This is an issue list, not legal advice or a finding that any specific technical design is compliant.*

### iOS, backend and AI engineering reviewers — before attributing task wins to product quality

- Inspect the actual prototype/repository, SDK versions and supported devices. No code audit has been performed for this evaluation.
- Verify correct App Intents/Shortcuts path and **user-configured** Back Tap, lock-screen and background behaviour on actual test phones; reject unsupported automatic access claims [E07e–E07f].
- For each target job implement a **ground-truth success check**: reminder exists/activates, translation is bilingual-reviewed, memory cites a consented stored fact and can be corrected/deleted, tool execution returns real success/failure.
- Measure **latency to *correct final action***, not first audio token; include cold starts, poor connections, speech noise, cancellation, retries, user confirmations, provider errors, and recovery.
- Compare matched LLM, STT/TTS, prompt and tool backends for character-vs-neutral experiments; otherwise log confounds explicitly.
- Obtain provider contracts, logging/training settings, security controls, cost per **successful** job, operational alerting and privacy-design constraints; no assumptions of zero memory/voice infrastructure cost.

---

## 8. Source notes, access log and limits

**Access date for all entries below: 8 October 2026.** Publication dates are shown where the publisher states them. These direct URLs support the narrow audited claims; source quality differs substantially.

| Ref | Author / publication date | Direct primary URL | Evidentiary strength and caveat |
|---|---|---|---|
| **E01** | Eurostat, **10 Feb 2026**, “64% of 16–24-year-olds used AI in 2025” | https://ec.europa.eu/eurostat/en/web/products-eurostat-news/w/edn-20260210-1 | **Strong official statistics** for EU/Polish 16–24 group, not adult-only iPhone. **Poland = 49.3%, EU = 63.8%.** |
| **E01a** | Eurostat, **16 Dec 2025**, EU generative AI usage | https://ec.europa.eu/eurostat/web/products-eurostat-news/w/ddn-20251216-3 | **Strong official statistics**: 32.7% of EU ages 16–74 over prior three months. |
| **E02** | Pew Research Center, Gottfried et al., **17 Jun 2026**, survey **17–23 Feb 2026** | https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/ | **Strong US survey**, self-reported, 5,119; not EU or Doddy. |
| **E02b** | Pew Research Center, **17 Jun 2026**, detailed appendix | https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-appendix-detailed-chart-and-tables/ | Strong for US stratification; does not give Polish iPhone estimates. |
| **E03** | Raluca Budiu, Kathryn Whitenton / Nielsen Norman Group, **21 Oct 2018** | https://www.nngroup.com/articles/intelligent-assistant-user-needs/ | Small, historical imaginative assistant diary; published arithmetic mismatch. |
| **E04** | RevenueCat, *State of Subscription Apps 2026*, **2026 edition; exact day not established** | https://www.revenuecat.com/state-of-subscription-apps | Large vendor-selected app sample; biased for broader market; **6.1% vs 9.5% 12-month monthly subscriber retention**, not app usage. |
| **E05** | MIT Media Lab/OpenAI research collaboration, **21 Mar 2025** | https://www.media.mit.edu/posts/openai-mit-research-collaboration-affective-use-and-emotional-wellbeing-in-ChatGPT/ | Research programme, observational plus four-week RCT; not Doddy-specific, limited generalisability. |
| **E06** | Yutong Zhang et al., *Nature Human Behaviour*, **4 Aug 2026** | https://www.nature.com/articles/s41562-026-02516-2 ; https://pubmed.ncbi.nlm.nih.gov/42552393/ | Peer-reviewed correlational user study; US Character.AI selection. Publisher direct access limited, metadata/abstract verified through search and PubMed. |
| **E07a** | OpenAI, living support docs, **publication date not stated** | https://help.openai.com/en/articles/20001274-chatgpt-voice ; https://help.openai.com/en/articles/8590148-memory-in-chatgpt ; https://help.openai.com/en/articles/11487775-connected-apps-in-chatgpt | Vendor statements: availability not same as end-to-end quality. |
| **E07b** | Character.AI, support FAQ **updated 23 Aug 2024** | https://support.character.ai/hc/en-us/articles/23957274129691-Character-Calls-Voice-FAQ | Vendor documented two-way Character Calls, distinct from Character Voice. |
| **E07c** | Google, Gemini iPhone widget help, **publication date not stated** | https://support.google.com/gemini/answer/16179553?co=GENIE.Platform%3DiOS&hl=pl | Official launch affordance, verify country/account/device. |
| **E07d** | Apple, iOS 26 Translate guide, **publication date not stated** | https://support.apple.com/guide/iphone/translate-text-voice-and-conversations-iphd74cb450f/26/ios/26 | Official built-in translation substitute. |
| **E07e** | Apple, iPhone Back Tap guide, **publication date not stated** | https://support.apple.com/guide/iphone/back-tap-iphaa57e7885/ios | Explicit manual gesture-setting instructions. |
| **E07f** | Apple Developer, Apple Intelligence/App Intents overview, **publication date not stated** | https://developer.apple.com/apple-intelligence/ | Official integration surface, not unlimited app/OS control. |
| **E08** | European Commission, **20 Jul 2026** guidance; Article 50 FAQ live on **8 Oct 2026** | https://digital-strategy.ec.europa.eu/en/news/commission-publishes-guidelines-transparency-obligations-providers-and-deployers-certain-ai-systems ; https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act ; https://eur-lex.europa.eu/eli/reg/2024/1689/oj | **Authoritative time-sensitive EU regulatory sources**; Article 50 applies **2 Aug 2026**, precise role/exception assessment remains legal work. |
| **E09** | Apple, App Review Guidelines, **living page** | https://developer.apple.com/app-store/review/guidelines/ | Current platform requirements: Sections 3.1.2, 4.2, 5.1, app privacy and account deletion. |
| **E10** | European Commission, GDPR principles; EDPB legal-basis overview, **living pages** | https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/principles-gdpr_en ; https://www.edpb.europa.eu/topics/key-gdpr-concepts/legal-basis_en | High authority for general law; not a project-specific legal basis or DPIA outcome. |
| **E11** | Kim Flaherty / Nielsen Norman Group, **29 Mar 2024**, diary methods | https://www.nngroup.com/articles/diary-studies/ | Research methodology only. |
| **E12** | Kim Flaherty / Nielsen Norman Group, **6 Dec 2020**, contextual inquiry | https://www.nngroup.com/articles/contextual-inquiry/ | Research methodology only. |

**Uninspected materials:** actual Doddy source code, prototype/device interactions, private analytics, prospective users' recordings, retention cohorts, costs, user acquisition data, IP licences, provider contracts, qualified Polish counsel opinion. These missing inputs block a confident investment or product-market-fit conclusion. This evaluation neither fabricates their contents nor requests the owner to repeat already-provided project context.

---

## 9. Structured handoff — evaluation only

```yaml
MODULE: D01
DOCUMENT: D01_EVALUATION.md
AS_OF: 2026-10-08
STAGE: EVALUATE
SIGNOFF: NOT_GIVEN
ACCEPTED: false
POSTURE: CONDITIONAL_CONTINUE_DISCOVERY
SUPPORTED:
  - Broad generative/conversational AI use in surveyed US/EU populations.
  - Present-day substitutes already cover significant parts of Doddy's bundle.
  - Historical assistant workflows suggest topics to observe, not modern market gaps.
  - AI subscription retention and anthropomorphic welfare warrant scrutiny.
  - EU AI Act Article 50 transparency provisions apply from 2026-08-02.
CORRECTIONS:
  - Polish 16–24 generative AI usage in 2025 was 49.3%; mixed-minor group only.
  - NN/g 2018 numeric discrepancy belongs to original source (636 - 14 != 621).
  - Original diary and field gates pool distinct jobs and need per-job denominators.
  - Proposed 15pp/20%/30% gates are not validated industry thresholds.
  - Character appeal, companionship motive and actual utility retention are distinct constructs.
BLOCKERS:
  - No observed recurring underserved Polish adult iPhone job.
  - No actual incumbent-vs-Doddy outcome or switching evidence.
  - No isolated character effect or qualified content-to-task funnel.
  - No credible voluntary retention, pricing, unit economics or legal/technical review.
NEXT_ACTIONS:
  - Recruit and observe independent real episodes for one job at a time.
  - Record baseline workarounds, switching costs and counterexamples before demonstrating Doddy.
  - Pilot narrow, verified task improvement without invasive data requirements.
  - Test character creative appeal separately from utility and payment demand.
  - Obtain research-data/privacy review before collecting identifiable participant material.
D01_DECISION: NOT_ACCEPTED; FINAL_OPPORTUNITY_SPEC_NOT_PRODUCED
```

<!-- END VERBATIM SOURCE: D01_EVALUATION.md -->

---

<a id="source-d05-research"></a>

## SOURCE 3/5 — D05 — Demand and channel signals: independent research

**Original filename:** `D05_RESEARCH.md` · **Original ZIP path:** `docs/research/D05/D05_RESEARCH.md` · **Source below is reproduced verbatim.**

<!-- BEGIN VERBATIM SOURCE: D05_RESEARCH.md -->

# D05 — Demand and channel signals | RESEARCH

**Project:** DODDY — *Your mate in your pocket*  
**Module:** Blueprint Studio / D05 / Independent research  
**As-of / access date:** 8 October 2026  
**Markets:** Poland first; EU comparison; US evidence only where explicitly labelled  
**Output status:** Research only. **Not** `DEMAND_EVIDENCE.md`; no module acceptance, decision sign-off, interviews, campaign results or forecasts asserted.

> **Decision in scope:** Does observable behaviour show demand for Doddy's potential jobs, and which channels warrant controlled tests to reach paying, repeat users? **Not in scope:** product-market fit, pricing, commercial viability, or legal clearance. The founder-provided product description is a hypothesis, not market evidence.

## 1. Executive research question and scope

**Question:** Is there independent evidence of demand for (a) everyday AI assistance, (b) voice-based help, and/or (c) character-led AI companionship, and can a solo founder plausibly discover *which* Polish adult iPhone users will adopt and retain Doddy through short-form content or other channels?

**Research finding:** There is **strong evidence that people use generative AI** and **moderate evidence of consumer spending on AI apps**, but only **weak or indirect evidence for Doddy's specific promise** and **no first-party evidence of an affordable acquisition channel for Doddy**. Mass social-media reach is *channel capacity*, not willingness to install, return or subscribe. Similarly, AI companionship and utility assistance are distinct demand categories; blending them risks misreading an entertainment audience as a market for a daily assistant.

**What is observed versus unknown:**

| Question | Evidence to date | Status |
|---|---|---|
| Do people already use general-purpose generative AI? | Eurostat 2025 EU household survey; Pew 2026 US survey; NBER analysis of ChatGPT conversations. [S01–S03] | **Supported, strong**, but population and product are broader than Doddy. |
| Is there consumer engagement and payment in AI mobile applications? | Sensor Tower industry estimates; RevenueCat subscriber dataset. [S04–S05] | **Supported for the category**, not for a new entrant's retention or margin. |
| Is character-based conversation an existing behavior? | Character.AI's voice product and observable Similarweb *modeled website* traffic. [S06–S07] | **Supported that it exists**; repeat use, profitable conversion and Polish iPhone demand unknown. |
| Are channels accessible in Poland? | Platform ad-reach compilations for Poland. [S08] | **Reach opportunity supported**; acquisition affordability unknown. |
| Do Poles search for the problem Doddy might solve? | Google Trends/Keyword Planner methodology verified; **no actual exported term-level trend or volume series obtained**. [S09–S10] | **Not measured**. |
| Can social views convert to retained paying iPhone customers? | No Doddy channel analytics or instrumented cohorts supplied. Apple offers source/retention instrumentation. [S11–S12] | **Not validated**. |
| What does a profitable buyer segment look like? | No approved D03 voice-of-customer evidence, no cohort economics, no paying cohort. | **Unknown**. |

**Implication for subsequent decisions:** Focus validation on two separate questions: *does Doddy's character win qualified attention?* and *does a single useful job create repeat activation and payment?* Do not allow one to substitute for the other.

### Geographic, demographic and data-definition rules

- **Poland-first iPhone adults 18+** is the target *hypothesis*. None of the reviewed market datasets represents exactly that population.
- Eurostat's *individuals 16–74* statistic and its *recent internet users* statistic use **different denominators**; do not mix their percentages into a single penetration claim. [S01]
- US Pew survey results describe *self-reported ever use* for US adults, not frequency, Poland, or app payment. [S02]
- App-industry aggregate downloads, time spent, revenue, and subscription retention use different units and cohorts; none should be treated as Doddy TAM, serviceable market, or forecast. [S04–S05]
- Platform **potential ad reach** is not monthly actives, unique adult iPhone users, organic views, reachable installs, or buyers. [S08]
- Google Trends scores are normalized 0–100 within the selected period/geography; they are not absolute search volume. [S09]

## 2. Method and source register

### Method

This is *desk research*, not original human-subject research. Sources were checked online on **8 October 2026**. Preference was given to official EU statistics, independent survey research, original provider disclosures, platform documentation and methodological notes. Commercial vendor reports are used as directional category evidence with explicit selection/estimation bias. Public user comments are qualitative leads, not population statistics. No source was treated as an instruction to modify the task.

**Evidence grades:** **A** = official representative survey/primary regulatory or platform definition; **B** = credible original research or sizeable but non-representative commercial dataset; **C** = modeled estimates/provider-marketing or direct product evidence; **D** = anecdote. Grades indicate *methodological strength for the particular inference*, not blanket endorsement.

### Source register — direct URLs, dates, access and limitations

_All accessed 2026-10-08. “Undated” means no reliable article publication date was confirmed on the retrieved page; it is not a guessed publication date._

| ID | Author / publisher; publication or data date | Direct source URL | Strength / supported use | Limitation |
|---|---|---|---|---|
| **S01** | Eurostat, *Use of artificial intelligence by individuals*; data 2025, extracted March 2026, page reflects 2026 edition | https://ec.europa.eu/eurostat/statistics-explained/index.php?title=Use_of_artificial_intelligence_by_individuals | **A**: representative EU household-ICT survey, recent AI adoption, reasons not to use AI | 16–74; three-month recall, not device, app, need frequency or payment; nuanced denominators |
| **S01b** | Eurostat, *Digitalisation in Europe – 2026 edition*; 2026 edition, underlying 2025 data | https://ec.europa.eu/eurostat/en/web/interactive-publications/digitalisation-2026 | **A**: EU and Poland recent-*internet-user* AI use | Denominator differs from S01's whole 16–74 population |
| **S02** | Pew Research Center, *Americans and AI 2026*; 17 June 2026, survey 17–23 February 2026 | https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/ | **A**: nationally surveyed US task categories | US only; ever-used, not frequency, product conversion or payment |
| **S03** | Chatterji et al., NBER Working Paper 34255, *How People Use ChatGPT*; September 2025 | https://www.nber.org/papers/w34255 | **B**: classified representative sample of ChatGPT interactions | ChatGPT-only; classification categories do not directly measure individual satisfaction or unmet needs |
| **S04** | Sensor Tower, *State of AI 2026*; 16 June 2026 | https://sensortower.com/press/sensor-tower-state-of-ai-2026-report-global-time-spent-on-generative-ai-apps-projected-to-more-than-double-year-over-year | **B/C**: proprietary global modeled mobile activity | H1 2026 activity explicitly **projected**; no Poland, niche, paid user cohort or acquisition costs |
| **S04b** | Sensor Tower, *State of Mobile 2026*; 21 January 2026 | https://sensortower.com/press/press-release-boosted-by-gen-ai-services-consumers-spent-more-money-in-apps-than-games-for-first-time | **B/C**: mobile industry expenditure and app trend | Aggregate IAP, not companion revenue or standalone iOS subscription TAM |
| **S05** | RevenueCat, *State of Subscription Apps 2026*; 2026 report; methodology explained in 19 March 2026 companion article | https://www.revenuecat.com/state-of-subscription-apps | **B**: observed subscription-app cohort metrics within RevenueCat's dataset | Clients of one subscription infrastructure provider, non-random app population; *payer* retention ≠ app-user retention |
| **S05b** | Lorelei Whitman, RevenueCat overview; 19 March 2026, updated 22 April 2026 | https://www-docs.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/ | **B**: report scope (115k+ apps, $16bn+ revenue) | Vendor-owned comparison; survivorship/composition possible |
| **S06** | Character.AI, *Introducing Character Calls*; June 2024 | https://blog.character.ai/introducing-character-calls/ | **C**: verified existence of competing character voice conversations | Product feature does not establish demand size or retention |
| **S07** | Similarweb, character.ai website analytics; **September 2026** estimate, observed page 8 October | https://www.similarweb.com/website/character.ai/ | **C**: website-category competitive directional signal | Extrapolated traffic; desktop/web figures ≠ app users, distinct people, spend or Polish iPhones |
| **S07b** | Similarweb, *How We Measure the Digital World*; undated | https://www.similarweb.com/corp/ourdata/ | **C**: documents modeled, multi-source traffic measurement | Promotional methodology; model accuracy not independently audited here |
| **S08** | Kepios / DataReportal, *Digital 2026: Poland*; 2026-report vintage with advertising data from late 2025 | https://datareportal.com/reports/digital-2026-poland | **B/C**: sourced platform ad-planner reachable audiences | Cross-platform overlap; estimated ad reach not MAUs and not organic/paid acquisition conversions |
| **S09** | Google, *FAQ about Google Trends data*; undated, checked 8 Oct 2026 | https://support.google.com/trends/answer/4365533?hl=en | **A** for methodology, **no term-level observation** | Relative normalized sampled interest; low-volume terms may show zero |
| **S10** | Google Ads Help, *About Keyword Planner forecasts*; undated, checked 8 Oct 2026 | https://support.google.com/google-ads/answer/3022575?hl=en-uk | **A** for tool definitions, **no keyword outputs** | Rounded average monthly volume; estimates/forecasts affected by configuration |
| **S11** | Apple Developer, *Acquisition — App Store Connect Analytics*; undated, checked 8 Oct 2026 | https://developer.apple.com/help/app-store-connect-analytics/acquisition/acquisition/ | **A**: available attribution and funnel metrics, not Doddy figures | Privacy thresholds and source definitions; only once app generates data |
| **S12** | Apple Developer, *Campaign links*; undated, checked 8 Oct 2026 | https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links/ | **A**: source-linked app campaigns and privacy thresholds | App must first have analytics data; only applies to measured campaigns |
| **S13** | Apple Developer, *App Analytics*; undated, checked 8 Oct 2026 | https://developer.apple.com/app-store-connect/analytics/ | **A**: retention and acquisition source segmentation | Device-based retention, not necessarily person-level or causal attribution |
| **S14** | Pew Research Center, *How opinions and use of AI differ by age*; 17 June 2026 | https://www.pewresearch.org/internet/2026/06/17/how-opinions-and-use-of-ai-differ-by-age/ | **A**: US age differences in AI uses | Not Poland or 18+ iPhone incidence |
| **S15** | Reddit r/ChatGPT, voice-use complaint; 8 Jan 2026 | https://www.reddit.com/r/ChatGPT/comments/1q78scw/anyone_else_find_advanced_voice_mode_unusable_for/ | **D**: candidate pain theme—speech interruption/turn-taking | One self-selected post, no incidence or verification of root cause |
| **S16** | Reddit r/CharacterAI, user disappointment discussion; 29 Apr 2026 | https://www.reddit.com/r/CharacterAI/comments/1sz007w/honestly_is_it_officially_over_for_us/ | **D**: candidate pain theme—quality continuity, changing limits | Highly selected negative community; no representative churn measure |
| **S17** | UOKiK, influencer marketing guidance; initial recommendations September 2022, live page checked 8 Oct 2026 | https://uokik.gov.pl/influencer-marketing | **A**: Polish commercial-content disclosure guidance | Specific campaign/format must still be reviewed under current law |
| **S18** | European Commission, AI Act Article 50 transparency guidance; 20 July 2026; obligations from 2 Aug 2026 | https://digital-strategy.ec.europa.eu/en/library/guidelines-transparency-obligations-providers-and-deployers-ai-systems | **A**: relevant EU AI-interaction/AI-content transparency framework | Applicability varies by system, role, output and exceptions; counsel required |
| **S19** | Apple Developer, *ATT updates in EU*; **16 September 2026** | https://developer.apple.com/news/?id=idsft9ai | **A**: current EU Apple tracking prompt update and unchanged permission rule | No basis to infer that every analytics event needs ATT; depends on cross-company tracking |
| **S20** | Apple Developer, *Ad Attribution*; undated, checked 8 Oct 2026 | https://developer.apple.com/app-store/ad-attribution/ | **A**: privacy-preserving advertising attribution options | Delayed / privacy-thresholded reporting; platform/vendor implementation needed |
| **S21** | Apple, App Review Guidelines (Polish version), checked 8 Oct 2026 | https://developer.apple.com/app-store/review/guidelines/pl/ | **A**: App Store data-sharing/privacy controls and permission expectations | Applies to app submission and actual implementation; review not performed |
| **S22** | TikTok support, *AI-generated content* (Polish); undated, checked 8 Oct 2026 | https://support.tiktok.com/pl/using-tiktok/creating-videos/ai-generated-content | **A** for TikTok rules, not legal ruling | Platform policy evolves; check each planned visual/voice format at publication |

**Retrieval/tool availability log:** Semrush keyword research was queried via its connected integration and returned **insufficient API units** (https://www.semrush.com/mcp-access); its traffic analytics action returned **current subscription does not include the feature** (https://www.semrush.com/analytics/traffic/trends-api). No raw Google Trends or Google Ads Keyword Planner exports were supplied; this report **does not substitute invented search volumes or CPCs**. Public Similarweb character.ai data was accessible; account-level competitor exports were not. No access to Doddy's own channel, app store, analytics, ad manager, subscription or prototype usage data was provided.

## 3. Evidence findings: demand, intent, channels, contradictions

### F1 — Broad demand for AI assistance exists, but not necessarily for another assistant (**high confidence, narrow claim**)

- **Verified:** Eurostat's detailed 2025 survey found **33% of EU residents aged 16–74** had used generative AI tools during the previous three months. Young people 16–24 reported **64%** usage; **64% of non-users** said the leading reason for not using AI was that they did not see a need. [S01]
- **Separate denominator:** Eurostat's 2026 interactive publication reports **35% of *recent internet users*** across the EU and **25% in Poland**, also for the 2025 measurement period. These differ legitimately from the whole-16–74 figures above. [S01b]
- **Verified (US):** Pew's February 2026 US survey (n=5,119 adults) reported **42%** had used AI chatbots for *searching for information*, **25%** for *fun/entertainment*, **10%** for *emotional support/advice* and **4%** for *companionship*. Usage questions are **ever use**, not daily/weekly usage. [S02]
- **Verified (platform-specific):** NBER found that by July 2025, over 70% of ChatGPT message volume related to non-work use; practical guidance, seeking information, and writing together made up nearly 80% of sampled conversation-topic categories. This is a message-level measure on ChatGPT, **not an EU adult adoption measure**. [S03]
- **Relevance:** Everyday search and guidance are demonstrated behavior categories. Entertainment engagement also exists, but the distinct “companion” label attracts a smaller self-reported audience in Pew's specific US survey.
- **Counter-evidence:** Apparent market familiarity means a new app may be redundant, and non-users may simply lack a problem. Nothing here demonstrates that a branded animation improves a daily job, removes friction, or wins payment.
- **Conclusion usable downstream:** “People use AI for information, guidance and some entertainment” is substantiated. “Polish adults want Doddy” is **not**.

### F2 — Substantial category-level mobile engagement and monetization coexist with a retention problem (**medium confidence, category only**)

- **Verified provider claim:** Sensor Tower's June 2026 release projected global time spent on generative-AI apps to rise from **17.2bn hours H1 2025 to 36bn hours H1 2026**. The latter is **a projection**, not a final observed H1 figure. [S04]
- **Verified provider claim:** Sensor Tower's January 2026 report estimated **$167bn** global 2025 mobile in-app purchase spending **across apps and games**. It cannot be interpreted as AI-market revenue. [S04b]
- **RevenueCat dataset:** Its 2026 subscription analysis reports median *12-month retention of monthly paid subscriptions* of **6.1% for AI-powered apps versus 9.5% for non-AI apps**; median download-to-paid conversion **2.4% AI versus 2.0% non-AI**; median AI realized year-one revenue per payer **$30.16 versus $21.37** non-AI. These are **different denominators** (paid subscription retention, initial downloads, payers), not a single funnel. [S05]
- **Sample selection:** RevenueCat describes analysis of over 115,000 subscription apps generating over $16bn in revenue. This is large yet restricted to the provider's clientele, and all-category medians obscure direct competitors or Poland-specific behavior. [S05b]
- **Counter-evidence:** High first-time conversion may be curiosity; faster cancellation and inference usage can erode margins. No cost-of-inference, net-of-platform-fees or Doddy cohort data are in these sources.
- **Conclusion usable downstream:** Monetization is possible in consumer AI applications, but **renewed usefulness and unit economics** are material constraints. **No subscription price, retention target or CAC can be derived mechanically** from these numbers.

### F3 — Character-led AI conversation exists, but character “fandom” and assistant demand are unproven to overlap (**moderate for existence; low for transferability**)

- **Verified product:** Character.AI documented real-time character voice calling, interruptibility and text↔voice switching in June 2024. Doddy cannot claim exclusive novelty for expressive character + voice. [S06]
- **Modeled web signal:** Similarweb's September 2026 public estimate showed character.ai **global website rank #202**, **a displayed 150.9m visit estimate within a last-three-month comparison widget** (the visible page does not unambiguously identify whether this figure is a single-month value or period total), and **71.8% estimated direct share of desktop traffic in the cited month**. The page itself explicitly says it is **estimated data**. Do **not** interpret visits as unique users, active app users, or three months of paying customer demand. [S07–S07b]
- **Anecdotal counter-signals:** One r/CharacterAI discussion describes users considering competitors following product changes; one r/ChatGPT thread describes voice interruption and turn-taking problems. These are **hypothesis-generating complaints from self-selected communities**, not measured prevalence or evidence of an addressable switch-ready segment. [S15–S16]
- **Competing explanation:** Character.AI demand may center on fandom, role-play and fantasy rather than practical scheduling, reminders or accurate advice. An entertaining content viewer could remain a non-user of a functional assistant.
- **Conclusion usable downstream:** Treat character desirability and practical assistant demand as **two separately measured outcomes**. Preserve safeguards against emotionally dependent use; any emotional-attachment claim requires dedicated human-centered research.

### F4 — Poland has large social-channel reach; *acquisition affordability* remains completely unobserved (**high for ad-audience descriptions; very low for CAC**)

**DataReportal's “Digital 2026: Poland” compilation, using mostly late-2025 advertising-tool figures:** [S08]

| Channel | Publicly reported Poland **potential advertising reach** | Interpretation / measurement trap |
|---|---:|---|
| YouTube | **27.1m** (age mix depends on Google reporting) | Video/discovery inventory; not Shorts-only audience, unique 18+ iPhone users or organic view prediction |
| Instagram | **12.4m**; equivalent to **39.5%** of Polish adults in ad reporting | Not the number who will watch character cartoons or click an app-install link |
| TikTok | **12.4m adults aged 18+**; estimated **39.8%** of Polish adults | Estimates are limited to adult ad audience; not total TikTok usage, and no CAC |

- These overlapping audiences **must not be summed**; the same user may be on every platform. Reported advertising audiences may change when platforms update definitions or remove duplicate accounts; year-on-year reach shifts are **not reliable subscriber growth**. [S08]
- **Qualified opportunity:** The founder could publish character-led demonstrations on TikTok, Reels and Shorts and reach viewers in Poland; *reachability* is more credible than affordability.
- **Missing:** Historic views on Doddy's accounts, unique adult Poland audience, audience-to-link click rates, iPhone share, attributable install rates, D7/D30 retention, subscription conversion, production/editing cost and paid acquisition costs.
- **Counter-evidence:** Platform algorithm volatility, link friction, weak buyer intent and viewing children/minors can make large organic reach commercially unhelpful. Large reach is not evidence of working unit economics.

### F5 — Search intent has **not** been quantitatively established (**low confidence / measurement blocked**)

- **Verified method:** Google Trends expresses a normalized share of searches as 0–100 relative interest by location and period; identical indices in different countries do not represent equal volumes. [S09]
- **Verified method:** Google Ads Keyword Planner can provide *rounded* average monthly searches for a phrase and close variants, conditioned on selected country, network and date range. Its bid/performance forecasts are modeled. [S10]
- **Not obtained:** No exported Google Trends relative index, Google Keyword Planner monthly volume, CPC, seasonality plot or Poland-specific English/Polish language comparison was produced. The Semrush connected keyword lookup failed owing to insufficient API units. **Do not report any specific keyword as high- or low-volume.**
- **Interpretive challenge:** Terms such as “ChatGPT”, “AI friend”, “asystent AI”, “aplikacja do tłumaczenia”, “przypominanie głosem” and “AI companion” have different intent (brand, education, entertainment, utility, purchase) and differing translation/disambiguation issues. Brand-search growth largely reflects competitor awareness, not desire to switch to Doddy.
- **Hypothesis:** Search may work for focused jobs with explicit intent (e.g., conversational translation) better than for a broad “mate in your pocket” identity. A neutral branded term “Doddy” has no verified discoverability or search demand yet.

### F6 — Channel attribution is technically feasible, but channel quality cannot be inferred from platform dashboards alone (**high for documentation; unknown outcomes**)

- Apple App Store Connect reports impressions, product-page views, total/first-time downloads, source types and retention; campaign links can associate downloads, usage and subscription outcomes with a campaign. Apple notes privacy restrictions and limited reporting for very small campaigns; campaign links become usable once an app has generated analytics data. [S11–S13]
- **Not all clicks are users:** Social-platform counts, landing sessions, email leads, App Store installs and *qualified activated users* are different cohorts. Last-click attribution may hide cross-device or view-through influence; returning fans can search the brand directly after viewing a video.
- **Definition proposed for future validation:** `activated_user = unique adult iPhone participant in eligible market who completes one real, user-initiated target job in a first session without researcher guidance`, with a privacy-preserving first-party event schema. This is **not a measured Doddy result**.
- **Avoid default cross-app tracking:** Apple requires ATT permission when data are shared for cross-company tracking; its 16 September 2026 EU update affects prompt options from iOS/iPadOS 27.2, without eliminating the permission condition. Privacy-preserving AdAttributionKit is available, subject to reporting thresholds. [S19–S20]

### F7 — Polish promotional and EU AI-transparency requirements materially affect channel design (**high for rule existence; fact-specific application to review**)

- UOKiK's influencer-marketing guidance covers clearly labelling commercial collaborations **and promotion of one's own brand**; paid partnerships, gifted material and promotional content require classification and appropriate disclosure. [S17]
- European Commission guidance published **20 July 2026** explains Article 50 AI-system and generated-content transparency obligations effective **2 August 2026**. Doddy being a cartoon does **not** automatically mean it is exempt from disclosing AI interaction or from relevant synthetic-content labels. Which duties apply depends on exact product and content. [S18]
- TikTok maintains a platform AI-generated-content labelling policy, which must be checked for each video type (e.g., fully animated, altered person, synthetic voice); a generic statement that “all cartoons need the same label” would be unjustified. [S22]
- Tracking/consent, profiling, age eligibility and marketing-data retention are **not fully legally evaluated in D05**. Review actual event schema, consent flow, website cookies, App Store privacy details and third-party tools before live tracking/paid campaigns. [S19–S21]

## 4. Alternatives, counter-evidence and decision-relevant trade-offs

This is a **research comparison**, not a final strategic selection; empirical performance scores are **unavailable**.

| Acquisition route | What existing evidence supports | Main mechanism | Cost / reversibility | Main counterargument or failure mode | Evidence necessary |
|---|---|---|---|---|---|
| **A. Character-led organic TikTok/Reels/Shorts** | Large Poland platform ad audiences [S08]; no Doddy organic proof | Attention → affinity → follow → link → activation | Modest cash spend possible; founder production time potentially high; reversible | Viral entertainment viewers may not use an AI assistant; weak downstream tracking; age mix | Per-post qualified profile visits, clicks, installs, D7 job repeats by content theme |
| **B. Job-demonstration organic video** | AI information/guidance tasks observed [S01–S03]; video platforms have potential reach [S08] | Specific pain and 10–30s visual payoff → trial | Low cash, moderate content work; reversible | Utility demos can be less shareable; proof depends on product reliability | Same audience with paired character-only vs task-specific hooks and downstream activation |
| **C. Intent-led search/content/ASO** | Search and information use broadly established; *no measured PL keyword demand* [S01–S03; S09–S10] | Existing problem query → narrowly matched page/app | Reversible but SEO can be slow and competitive | Generic AI searches dominated by incumbents; weak high-intent search volume possible | Actual Poland keyword volume + landing-query-level qualified conversions |
| **D. Niche communities/ambassador pilots** | Qualitative pain leads exist [S15–S16], not representative | High-intent recruiting and peer demonstration | Very low cash, founder time intensive; reversible | Forum self-selection and noncommercial rules; tiny scale | 18+ screened interviews, referral installs, repeat use, community rule compliance |
| **E. Micro-creator/paid UGC collaborations** | Social channels exist; Polish promotion disclosures [S08; S17] | Audience trust → use-case demonstration → install | Spend capped per creator; contract reversible | Fake engagement, brand mismatch, low iPhone/adult share, disclosure friction | Verified target-audience analytics, unique campaign links, incremental activated users, cost |
| **F. Paid iOS install campaigns (Meta/TikTok/Apple Ads)** | Ad inventory exists; Apple attribution tools exist [S08; S11–S12; S20] | Targeted paid reach → App Store → activation | Highly controllable spend, reversible | CAC exceeds gross-margin LTV; targeting/privacy limits; creative fatigue | Actual campaigns with event-level first-party metrics, CAC to activated and retained users |
| **G. Character-only waitlist** | No evidence that email registration maps to product use | Exposure → email sign-up | Cheap setup, reversible | Vanity leads / friends-of-founder bias; survey response ≠ install or payment | Verified adult target leads who opt into actual beta, then activation and retention |

**Tactical inference (not validated):** Run **A and B together**, while building **C/D** around a single job. Defer aggressive E/F spending until activation and repeat usefulness are demonstrated. A separate “pure character fandom” route can remain an entertainment-brand experiment without pretending it proves demand for an assistant.

**Alternative product/channel hypotheses to rule out:**

1. **Existing ChatGPT/Apple functionality is good enough.** Viewers may like Doddy but retain their current assistants. [S02–S03; S06]
2. **Audio novelty has little net value.** Voice turn-taking, environment privacy and latency can make repeat use worse than text. [S15]
3. **Character audiences want play, not productivity.** Discoverable via independent creative-versus-task cohorts; don't merge conversion rates. [S06–S07; S16]
4. **Poland is a lower-adoption entry market than EU average.** The 2025 recent-internet-user share for Poland is below EU in Eurostat's interactive publication; differences could reflect language, composition, awareness or relevance, not automatically demand gaps. [S01b]
5. **An established platform wins through distribution even if feature parity is equal.** Dominant competitor behavior and modeled character.ai traffic do not establish an obtainable route for an unknown app. [S03; S07]

## 5. Missing external evidence and concrete research plan

### The blocking evidence, ranked

| Priority | Missing artifact | Why it matters | Owner / collection |
|---|---|---|---|
| **P0** | **Accepted** D03 `VOICE_OF_CUSTOMER.md` | Need validated adult segment, repeated trigger, current workaround and realistic switch behavior. Current workflow explicitly says dependency missing. | Founder/Blueprint D03; do not infer results. |
| **P0** | **Accepted** D04 `COMPETITOR_MATRIX.md` | Prevent recommending an easily copied feature or reporting existing capabilities as opportunity. Current workflow explicitly says dependency missing. | Founder/Blueprint D04; do not invent its conclusions. |
| **P0** | Instrumented Doddy beta cohorts by **acquisition source, job and adult Poland/iPhone eligibility** | Without this, no direct-channel ROI or habit/repeat-use evidence. | Founder/product analytics. |
| **P0** | Unit economics: incremental inference+speech costs, app-store fees, refunds, retention curves, net margin | Paid installs are meaningless if marginal servicing cost exceeds net return. | Founder, vendor invoices and finance. |
| **P1** | Google Trends **exports** and Google Keyword Planner or equivalent query-level Poland data | No search trend/volume/CPC presently observed. | Founder export, set geography/terms/date correctly. |
| **P1** | Native channel screenshots/exports for own social accounts: 18+ audience geography, engagement, profile taps and outbound clicks | Determines reach quality; cross-platform overlap and minors need controls. | Founder platform analytics. |
| **P1** | Comparative content creative and landing experiments | Separates affection for Doddy from active job demand. | Founder controlled publishing. |
| **P1** | Independent EU/Poland legal, age, IP and measurement review | Avoids misleading claims, unlawful promotion or noncompliant attribution. | Qualified counsel/technical privacy review. |
| **P2** | Competitor app traffic/revenue segmented by Poland+iOS, including estimate quality | Tests competitor context; useful but not a substitute for first-party demand. | Licensed estimates if needed, with confidence caveats. |

### Protocol A — Search-intent triangulation (research only)

**Purpose:** Test whether people search for specific *jobs* rather than AI as an abstract technology.

1. Define five disjoint topic buckets: **voice assistant**, **live conversational translation**, **reminder/follow-through**, **remember/find personal context**, **AI friend/character entertainment**. Include baseline competitors (ChatGPT, Gemini, Character.AI) *in separate branded bucket*.
2. For every bucket enter **actual Polish and English query variants**, confirm ambiguity manually, record search intent classification (informational / navigational / transactional / entertainment), and translate rather than equate superficially similar terms.
3. Export Google Trends comparisons for **Poland**, **past five years** and **past 12 months**, fixed search type and query/topic distinction; document retrieval timestamp and low-volume suppression. Repeat for selected EU markets separately rather than averaging incomparable normalized values. [S09]
4. Export Keyword Planner **average monthly searches** by term, language, country, network and 12-month history, with CPC/bid estimates **labelled as estimates**. Record all zeros, rounding, ranges and account settings. [S10]
5. Independently code top ~20 SERP/App Store results per bucket for the actual *situation solved*, incumbent strength, repeated pain and overt commercial intent. Two coders if possible; resolve disagreements visibly.
6. Produce per-job `query | country | language | period | normalized index | monthly range | intent | source | uncertainty`. **Do not manufacture an index before access.**

**Falsification:** If only branded search is detectable, or volume clusters around role-play/content without practical assistant jobs, **reject SEO as a near-term acquisition thesis for practical Doddy**. Lack of search is not conclusive if the product creates a new behavior; other channels still need direct testing.

### Protocol B — Character content versus utility content, randomized creative cells

**Question:** Does the character bring the *right* viewers or only entertainment impressions?

- Audience: Polish-language adults 18+, target iPhone users *when identifiable*, with separate English/other-country cells; **no inference from view counts alone**.
- Produce at least **three matched story pairs** for **three actual jobs** (e.g. “what did I promise?”, translation in a realistic conversation, voice-to-reminder). Each pair has: **B1 character-led skit** and **B2 concrete task demo**. Add **B0 neutral/function-first** comparison when feasible. Maintain same user problem, CTA, video length bracket, creator/account mix and production quality.
- Publish on TikTok, Instagram Reels, YouTube Shorts in balanced sequence/time windows or use randomized paid splits where controls permit. Organic platform distribution is not randomized; describe as **quasi-experimental**, not causal proof.
- CTA to **separate tagged landing pages** that require users to select their actual use case; an eligibility question records adult+Poland+iPhone intention without creating needless personally identifying data. Track `view → profile_visit → unique_landing → qualified_waitlist_or_beta → install → activation_by_job → repeat_job_D7/D14 → paid_if_offered` with **denominators**.
- **Primary outcome:** activated, independently returning adult iPhone users per **1,000 actual attributable unique landing sessions** (or per spend in paid cells). Secondary: qualified waitlist conversion and creative cost; tertiary: plays, shares, follows. Never optimize on views alone.
- **Bias controls:** Attribute with privacy-aware links; mark self-reported source when strict tracking not possible; exclude founder friends/employees from primary cohorts; track country, eligible device, organic versus paid, language, reposts, bots and minors where detectable.
- **Proposed sample stopping rule, not a statistical guarantee:** run for **at least 4 full weeks** and enough unique landing sessions to compare meaningful differences; pre-register effect size and sample calculation before claims of creative superiority. If underpowered, report descriptive counts and uncertainty, **not a winner**.

**Disconfirming patterns:** character content produces views but fewer eligible clicks, lower first-job completion or worse D14 repeat; creator nostalgia does not follow into app; paid viewers behave differently from organic fans.

### Protocol C — Channel test with *real* costs, retention, and source quality

1. **First establish activation** in product-led research, not from a vanity waitlist. Predefine the *one target job*, event success, errors and what “returning for the same need” means; isolate per job.
2. Pilot **three bounded acquisition sources**: one content route, one targeted community route, and one narrow paid source **only if** product events and compliance permit. Set explicit per-channel budget caps **before launch**. Do not assume a universal Polish CPI/CAC.
3. Instrument source links in App Store Connect where applicable; track first-party in-product activation, repeat use, paid conversion and cancellations. Do not silently merge iPhone + Android or Poland + global cohorts. [S11–S13]
4. Compute transparent metrics: `landing→activated = activated eligible users / unique eligible landing sessions`; `CAC_activated = paid media + attributable external creative / newly activated acquired users`; `CAC_D14 = same spend / D14 qualified repeat users`; `content cost per activated user = incremental production+editing+distribution labor / activated acquired users`; `net contribution per paying user = net receipts after storefront fees/refunds/taxes where applicable - incremental AI/speech/tool/storage/support cost`.
5. Calculate **contribution-adjusted CAC payback** from *observed* renewal and marginal service-cost data. Without observed payer cohorts, report scenario bounds explicitly as **assumptions**, not profitability.
6. Run at least one holdout or staggered geography/time-window test for *incrementality*, because paid campaigns can take credit for people who would have installed organically. Holdouts may be difficult for small cohorts; mark uncertainty.
7. **Suggested decision rule to pre-register (not externally validated benchmark):** A source is eligible for scaling only if it repeatedly produces qualified first-job activations **and** returning D14 users with bounded cost; full-scale paid acquisition additionally requires a plausible, evidence-backed positive contribution margin and acceptable CAC payback *under conservative retention*. Founder must set affordability and time horizon from actual finances.