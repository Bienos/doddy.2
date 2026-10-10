# Doddy monetization model v2: audit, redesign and repricing

Date: 2026-10-10. Status: **proposal, nothing built.** All results are scenarios computed by
`docs/business/unit_economics.py`, not forecasts. Prices are first-market (Poland) prices in PLN incl. VAT;
euro figures use 4.40 zł per € and $1 = €0.90 (both slightly pessimistic against ECB rates of 9 Oct 2026).

Labels: **V** verified on an official page · **S** secondary source · **E** our estimate · **D** a decision.

## Verdict

The v1 model doesn't work as priced, and three of its inputs were wrong.
- **Voice in every plan was the costly live speech-to-speech kind.** Live voice re-bills the whole conversation every turn, so with a 5-minute cap and pruning it costs about €0.081 a minute, and long sessions run €0.12–0.15.
- **The free plan relied on Apple's on-device AI, which doesn't support Polish.**
- **Churn was 15% a month.** AI monthly plans really lose about 21% a month.

Re-costed with verified inputs, v1 keeps only 55% per payer and loses €11.6k a month at 100k users with 5% paying.

v2 makes four changes:
- **Cheaper included voice.** It is a turn-by-turn pipeline at about €0.020 a minute.
- **Live talk moves to Pro and paid packs.**
- **The free plan uses no cloud AI.**
- **A real 7-day trial appears after the first save.**

That lifts the blended margin to **71%**, and every monthly plan meets the 70% / 50% per-payer targets. The business stays thin at Polish prices. A founder salary needs about **29k monthly users at 5% paying**. At 100k users and 5%, the model reaches only **2% net margin with a €20k team** (15% needs a team of about €14.5k or 6.3% paying). The share of users who pay matters more than anything else, so the beta has to measure it first.

| | v1 (re-costed with verified inputs) | v2 |
|---|---|---|
| Voice included in plans | Live speech-to-speech, 30 min in Best Mate (€0.081/min) | Doddy voice, turn by turn, 60 min (€0.020/min); Live talk only in Pro (15 min) and packs |
| Free plan | "On-device AI" (none exists in Polish) plus 50 cloud answers | Memory plus search cards, no cloud AI; Apple dictation/voice where the device supports it; about €0.01 a user |
| Trial | 3 min of live voice for half of installs | 7-day free trial (Apple introductory offer), offered after the first saved memory |
| Best Mate | 44,99 zł; yearly 349,99 zł | 44,99 zł; yearly 349,99 zł (−35%) |
| Doddy Crew | 79,99 zł, 60 live min pooled | 79,99 zł, 120 Doddy-voice min pooled, Family Sharing; yearly 749,99 zł |
| Doddy Pro | 89,99 zł, 90 live min, 100 think | 89,99 zł, 15 live + 100 voice min, 50 think, Money Saver included; yearly 899,99 zł |
| Packs | 20 live min for €4.99 | 30 voice min for 14,99 zł; 10 live min for 19,99 zł; Money Saver 14,99 zł; Founding Mate 499,99 zł (500 seats) |
| Blended contribution per payer | €4.27 (55%) | €5.90 (71%) |
| 10k MAU, 5% paying, after running costs | −€209 | +€1,018 |
| 100k MAU, 5% paying, after running costs / after €20k team | €8,413 / −€11,587 | €20,683 / €683 |
| 1M MAU, 5% paying, after team | €11,690 (3%) | €132,008 (35%) |

## Formulas (used everywhere)

```
gross per month     = price_PLN / 4.40 / billing_months             (EUR incl. VAT)
ex_VAT              = gross / 1.23
kept                = ex_VAT × (1 − Apple fee)                      15%; 22.7% blended above $1M/yr
variable            = Σ allowance × usage × unit cost + server × people + support
                      + (refunds 5% + billing leakage 2%) × kept + RevenueCat 1% × ex_VAT
contribution        = kept − variable;   margin = contribution / kept
trial cost / month  = Σ churn_plan × payers / trial_to_paid × €0.43
business contrib.   = payers × contribution − free users × €0.01 − trial cost − marketing
after running       = business contrib. − running costs;  after team = − team;  net margin = after team / kept
Apple above $1M     = 0.7 × 26% + 0.3 × 15% = 22.7%   (share of revenue from first-year subscribers, E)
largest CAC         = contribution after trials × 1 / blended churn
```

---

## 1. Rating of the current (v1) model

| Area | Score | Reason |
|---|---|---|
| Pricing level | 6/10 | €9.99 / 44,99 zł sits inside the Polish band (ChatGPT Go 34,99 zł, Replika 39,99 zł, Character.AI+ 49,99 zł). Crew and Pro prices are defensible. The PLN points were never checked against App Store tiers. |
| Packaging and plans | 4/10 | Every plan's main value is the most expensive thing to serve: live voice. Pro's 90 live minutes and 100 Sonnet answers leave it at 51% margin on an average user and 25% on a heavy one. |
| Free plan design | 3/10 | It relies on Apple Intelligence, which doesn't support Polish ([Apple](https://support.apple.com/en-us/121115)), and on Polish on-device speech, which is unconfirmed. For Polish users the "free on-device AI" doesn't exist. |
| Trial design | 3/10 | A 3-minute voice sample isn't a trial. There's no Apple introductory offer, no paywall moment and no plan to test one, even though hard paywalls convert about 5× better (RevenueCat 2026). |
| Cost assumptions | 5/10 | €0.055/min for live voice is below measured costs ($0.05–0.08 for short sessions, $0.12–0.15 for 10–15 min). There's no session cap, and the much cheaper turn-by-turn pipeline was never considered. |
| Usage assumptions | 6/10 | 60% average / 100% stress is sensibly pessimistic. Text at 1,000 answers is generous but cheap. Session-length distribution, which drives live-voice cost, is missing. |
| Running-cost realism | 4/10 | €500/month at 1k users leaves out legal/GDPR/AI Act setup (€4–15k), upkeep (€2–8k a year), accounting and insurance. A realistic figure is about €1,100. |
| Resilience to heavy users | 5/10 | Caps exist, so no plan goes negative, but heavy-user margins are 17–43%, and long live sessions can blow past the per-minute cost assumed. |
| Growth economics | 4/10 | 15% churn is optimistic (AI monthly about 21%). The €31 affordable acquisition cost rests on it, and paid ads in Poland are unlikely to pay back. |
| **Overall** | **4/10** | The unit economics look acceptable only because voice is under-costed and the free plan leans on a capability Polish users don't have. Re-costed, v1 is loss-making at every realistic scale below about 1M users. |

## 2. Assumption audit

| # | Assumption in v1 | Problem | Corrected value (label) |
|---|---|---|---|
| 1 | Real voice €0.055/min | Optimistic. Live APIs re-bill the full history each turn. Gemini Live has no caching and audio-only sessions stop at 15 min. | Live talk $0.09 → **€0.081/min** with a 5-min cap and pruning (E, from V/S). Doddy voice turn-by-turn **€0.0203/min** (V prices, E mix). |
| 2 | Free plan uses on-device AI | Wrong for Polish. Apple Intelligence (iPhone 15 Pro and later only) doesn't list Polish. | Free plan uses **no generative AI** in Polish: search cards only. €0.01 a user (E). |
| 3 | "Unlimited basic Apple voice" | Unverified for Polish. SpeechAnalyzer Polish is unconfirmed; an AVSpeechSynthesizer pl-PL voice exists. | Keep it only "where the device supports it"; check `supportedLocales` at runtime. Paid voice budgets cloud STT at $0.003/min (V). |
| 4 | Paid churn 15% blended | Optimistic. AI monthly plans keep 6.1% after 12 months, about 21% a month; annual plans renew 21.1% (S, RevenueCat via TechCrunch). | Monthly **21%**; yearly 6.6% replaced per month. Blended **16.1%** with the v2 mix. |
| 5 | Apple fee 30% above $1M | Stale. The EU standard IAP rate has been **26% since 1 Oct 2026** (V); 15% under the Small Business Program and after year one. | 15% below $1M; **22.7%** blended above. |
| 6 | Price €9.99 = 44,99 zł | Not checked. Observed pairs: €9.99 ↔ 49,99 zł (Character.AI), €7.99 ↔ 34,99 zł (ChatGPT Go). | 44,99 zł is roughly equalised (about 4.4 zł/€) (E). Confirm points in App Store Connect. |
| 7 | Running costs €500 at 1k | Missing compliance, accounting, insurance. | €1,100 / €1,700 / €6,500 / €30,000 at 1k / 10k / 100k / 1M (E). |
| 8 | Refunds 5% | Fine. The AI median is 4.2% (S). | 5% kept. |
| 9 | Grace period and billing retry | Missing. Involuntary cancellations are about 14% of App Store cancellations (V). | 2% billing leakage of kept revenue (E). |
| 10 | App Store tax handling | Implicit. | Apple deducts VAT before proceeds (S). We invoice Apple Distribution International (Ireland) as an intra-EU service with reverse charge (S). No withholding expected (E; confirm with an adviser). CIT 9% under the €2M limit (S), shown as a line. |
| 11 | Compliance | Missing. AI Act Art. 50 transparency has applied since **2 Aug 2026** (V). We need DPAs with ElevenLabs, OpenAI and Google, and a DPIA. Doddy is not high-risk. | €4–15k setup and €2–8k a year (E), inside running costs. ElevenLabs zero-retention and EU residency are Enterprise-only (repo doc). |
| 12 | Device mix | Ignored. Apple Intelligence runs only on iPhone 15 Pro and newer; active share is not found (E 20–40%). | Irrelevant to Polish users today (0% supported). The design must not depend on it. |
| 13 | Long-session blow-ups | Missing. One measured 14-min session cost $2.05 (S). | 5-min cap on Live talk, history pruned to about 10 turns, 10-min cap on Doddy voice. |
| 14 | Voice abuse and account sharing | Missing. | Quotas per Apple original transaction ID, enforced on our server; one active voice session per account; Family Sharing only on Crew; App Attest on the voice-token endpoint. |
| 15 | Currency | USD costs against PLN revenue were ignored. | Stress: euro −15% costs −€1.2k a month at 100k/5%. |
| 16 | Trial conversion | Not modelled. Sources conflict (S says 8.5% "trial-to-paid" for AI, which looks like a different denominator). | 25% (E, range 15–40%). |
| 17 | Paid share 3–8% of MAU | Plausible. Duolingo, best in class, is 9.0% (V, Q2 2026 filing). | Unchanged; it's the main uncertainty. |
| 18 | Marketing | Excluded, which hides the main risk. Poland iOS CPI is about $0.8–2.5 (E). At 2–5% install-to-paid that's $16–125 per payer. | Paid ads at €40 per payer wipe out profit (stress below). Organic only until the numbers are known. |
| 19 | Engineering fit | Missing. The repo's capability guard currently forbids our own networking, Speech, EventKit and CloudKit, and the PRD lists payments as a non-goal. | Monetization needs an owner-approved milestone: StoreKit 2/RevenueCat, quota server, speech pipeline. |

## 3. Redesign

| Element | v2 design | Why |
|---|---|---|
| Free: **Pocket Doddy** | Unlimited memory, search, export and delete. Search results shown as cards. Apple dictation and voice where the device supports Polish. No cloud AI. | The core job (find what I saved) needs no AI, so free users cost about €0.01. Export and delete are never paywalled. |
| Paywall | After the **first saved memory**: "Try Best Mate free for 7 days, then 44,99 zł a month. Cancel any time in Settings." "Not now" is as prominent as "Start trial"; monthly and yearly are shown side by side with neither pre-selected; an in-app reminder comes one day before the trial ends. | Value has just been felt. 7-day trials lose fewer users on day 0 than 3-day ones (39.8% vs 55.4%, V). Clear terms meet EU consumer law and App Store rules. |
| Trial | Best Mate with 15 voice min, 3 Live min and 50 answers. Costs €0.43 a trial. | Lets people hear Doddy without exposing us to heavy costs. |
| **Best Mate** (individual) | 60 min of Doddy voice, 300 cloud answers, Reminders action | The main plan. Doddy voice uses his custom ElevenLabs voice through a turn-by-turn pipeline. |
| **Doddy Crew** (family) | Up to 6 people through Apple Family Sharing; 120 min voice and 1,500 answers pooled; shared memories through CloudKit (each person opts in) | Replaces "gifting": a child includes a parent in their Apple family. CloudKit keeps sync cheap. |
| **Doddy Pro** | 15 min Live talk, 100 min Doddy voice, 50 "think harder" (Sonnet 5.5), Money Saver and People pack included | Live talk is the premium experience; it's capped because it costs 4× Doddy voice. |
| Yearly plans | Best Mate −35%, Crew −22%, Pro −17% | Yearly payers stay about 15 months against 4.8, so lifetime contribution is about 1.8× despite lower monthly margin. |
| Add-ons and packs | Money Saver 14,99 zł/mo (89%); 30 voice min 14,99 zł (69%); 10 Live min 19,99 zł (69%) | Money Saver runs on device (receipt reading with Vision, local reminders), so it's nearly pure margin. Packs cover heavy users without raising every plan. |
| **Founding Mate** | 499,99 zł once, Best Mate allowances for life, **max 500 seats**, launch only | Cash up front. It covers 45–66 months of service, and total liability is capped at about €9k a year. |
| Dropped | 30 live min in Best Mate; 90 live min in Pro; free cloud answers; 3-min live sample; 1,000 answers in Best Mate | Each was a loss or margin leak under verified costs (section 2). |
| Non-subscription (upside, not in base) | NFC keychain 59 zł (about €6 contribution, sold outside the app as a physical good); sticker pack 4,99 zł; printed year book 149 zł; opt-in affiliate links later; carrier and benefit deals after scale | Useful for marketing. Too uncertain to count. |
| Not now | Hard paywall with no free plan; language-practice plan; carrier deals | A hard paywall conflicts with "free memory" and must be an explicit experiment. Language practice is voice-heavy, so test demand first. Partners need traction. |

## 4. Prices

| Plan | Poland | Later EU (DE) | Anchors |
|---|---|---|---|
| Pocket Doddy | free | free | Pi free; Notes and Reminders free |
| Best Mate | **44,99 zł / month** | €9.99 | Replika 39,99 zł, Character.AI+ 49,99 zł, ChatGPT Go 34,99 zł. Doddy adds memory plus his own voice. |
| Best Mate yearly | **349,99 zł / year** (29,17 zł a month) | €79.99 | Replika yearly 244,99–249,99 zł; Headspace 324,99–354,99 zł |
| Doddy Crew | **79,99 zł / month** | €17.99 | Under 2 × Best Mate for up to 6 people |
| Doddy Crew yearly | **749,99 zł / year** | €169.99 | |
| Doddy Pro | **89,99 zł / month** | €19.99 | Below ChatGPT Plus 99,99 zł; Replika Pro $19.99 |
| Doddy Pro yearly | **899,99 zł / year** | €199.99 | |
| Money Saver pack | 14,99 zł / month | €3.49 | Pays for itself with one saved return or cancelled trial |
| Doddy voice pack, 30 min | 14,99 zł | €3.49 | |
| Live talk pack, 10 min | 19,99 zł | €4.49 | |
| Founding Mate (lifetime) | 499,99 zł once | €109.99 | Five months of Best Mate yearly × 1.4 |

Only 14,99, 24,99, 34,99, 39,99, 47,99, 49,99, 59,99, 99,99, 244,99, 249,99, 324,99, 354,99 and 499,99 zł were observed on the Polish App Store. **44,99, 79,99, 89,99, 349,99, 749,99 and 899,99 zł must be confirmed in App Store Connect** (fall back to the nearest point). Test **39,99 vs 44,99 vs 49,99 zł** in the soft launch.

## 5. Unit economics (per payer per month)

Unit costs:
- **Doddy voice:** €0.0203/min (STT $0.003 + LLM $0.0015 + ElevenLabs Flash TTS 450 chars × $0.04/1k).
- **Live talk:** €0.081/min.
- **Text answer:** €0.00065.
- **"Think harder" answer:** €0.0117.
- **Trial:** €0.43.

**Average usage (60% of allowance)**

| Plan | Price | Gross | Apple | Kept | Voice | Live | Text | Think | Server | Support | Refunds | Leakage | RevenueCat | Contribution | Margin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Best Mate | 44,99 zł | €10.22 | €1.25 | €7.07 | €0.73 | – | €0.12 | – | €0.10 | €0.25 | €0.35 | €0.14 | €0.08 | **€5.29** | **75%** |
| Best Mate yearly | 349,99 zł | €6.63 | €0.81 | €4.58 | €0.73 | – | €0.12 | – | €0.10 | €0.25 | €0.23 | €0.09 | €0.05 | **€3.01** | **66%** |
| Doddy Crew | 79,99 zł | €18.18 | €2.22 | €12.56 | €1.46 | – | €0.58 | – | €0.30 | €0.25 | €0.63 | €0.25 | €0.15 | **€8.94** | **71%** |
| Doddy Crew yearly | 749,99 zł | €14.20 | €1.73 | €9.82 | €1.46 | – | €0.58 | – | €0.30 | €0.25 | €0.49 | €0.20 | €0.12 | **€6.42** | **65%** |
| Doddy Pro | 89,99 zł | €20.45 | €2.49 | €14.13 | €1.22 | €0.73 | €0.39 | €0.35 | €0.10 | €0.25 | €0.71 | €0.28 | €0.17 | **€9.94** | **70%** |
| Doddy Pro yearly | 899,99 zł | €17.05 | €2.08 | €11.78 | €1.22 | €0.73 | €0.39 | €0.35 | €0.10 | €0.25 | €0.59 | €0.24 | €0.14 | **€7.78** | **66%** |

**100% usage (heaviest legitimate user)**

| Plan | Voice | Live | Text | Think | Contribution | Margin |
|---|---|---|---|---|---|---|
| Best Mate | €1.22 | – | €0.19 | – | €4.73 | 67% |
| Best Mate yearly | €1.22 | – | €0.19 | – | €2.45 | 53% |
| Doddy Crew | €2.43 | – | €0.97 | – | €7.58 | 60% |
| Doddy Crew yearly | €2.43 | – | €0.97 | – | €5.06 | 52% |
| Doddy Pro | €2.03 | €1.22 | €0.65 | €0.58 | €8.16 | 58% |
| Doddy Pro yearly | €2.03 | €1.22 | €0.65 | €0.58 | €5.99 | 51% |

Server, support, refunds, leakage and RevenueCat don't change with usage.

**Add-ons (per purchase, 90% / 100% use)**

| Add-on | Price | Gross | Kept | AI cost | All costs | Contribution | Margin |
|---|---|---|---|---|---|---|---|
| Money Saver pack | 14,99 zł | €3.41 | €2.35 | €0 | €0.26 | €2.09 | 89% / 89% |
| Doddy voice, 30 min | 14,99 zł | €3.41 | €2.35 | €0.55 / €0.61 | €0.74 / €0.80 | €1.62 / €1.55 | 69% / 66% |
| Live talk, 10 min | 19,99 zł | €4.54 | €3.14 | €0.73 / €0.81 | €0.99 / €1.07 | €2.15 / €2.07 | 69% / 66% |
| Founding Mate | 499,99 zł once | €114 | €78.53 | – | – | – | Covers 66 months (average) / 45 months (100%) of Best Mate service |

**Blended payer** (mix: Best Mate 48% / yearly 25%, Crew 8% / 4%, Pro 10% / 5%; add-on attach 6% / 4% / 3%):
- **Revenue:** pays €11.96 a month; we keep €8.27.
- **Costs:** variable €2.36.
- **Contribution:** **€5.90 (71%)**, or **€5.63 after trial costs**.
- **Churn:** 16.1% a month blended.

**Target check against the brief:**
- **Monthly plans:** all three meet ≥70% average and ≥50% heavy.
- **Yearly plans:** 65–66% average and 51–53% heavy, below the 70% average target on purpose. A yearly payer is worth about 1.8× a monthly one over their life (Best Mate €45.61 vs €25.20; Pro €118 vs €47.35).
- **No plan loses money on its heaviest user.**

## 6. Business simulation (per month, average usage)

**3% paying**

| MAU | Payers | Users pay | Kept | Variable | Free users | Trials | Contribution | Running | After running | Team | After team | Net margin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1k | 30 | €359 | €248 | €71 | €10 | €8 | €159 | €1,100 | −€941 | €0 | −€941 | −379% |
| 10k | 300 | €3,589 | €2,480 | €709 | €97 | €83 | €1,591 | €1,700 | **−€109** | €4,000 | −€4,109 | −166% |
| 100k | 3,000 | €35,886 | €24,800 | €7,088 | €970 | €832 | €15,910 | €6,500 | €9,410 | €20,000 | −€10,590 | −43% |
| 1M | 30,000 | €358,865 | €225,530 | €69,308 | €9,700 | €8,317 | €138,205 | €30,000 | €108,205 | €75,000 | €33,205 | 15% |

**5% paying**

| MAU | Payers | Users pay | Kept | Variable | Free users | Trials | Contribution | Running | After running | Team | After team | Net margin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1k | 50 | €598 | €413 | €118 | €10 | €14 | €272 | €1,100 | −€828 | €0 | −€828 | −200% |
| 10k | 500 | €5,981 | €4,133 | €1,181 | €95 | €139 | €2,718 | €1,700 | €1,018 | €4,000 | −€2,982 | −72% |
| 100k | 5,000 | €59,811 | €41,333 | €11,813 | €950 | €1,386 | €27,183 | €6,500 | €20,683 | €20,000 | **€683** | **2%** |
| 1M | 50,000 | €598,108 | €375,884 | €115,513 | €9,500 | €13,862 | €237,008 | €30,000 | €207,008 | €75,000 | €132,008 | 35% |

**8% paying**

| MAU | Payers | Users pay | Kept | Variable | Free users | Trials | Contribution | Running | After running | Team | After team | Net margin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1k | 80 | €957 | €661 | €189 | €9 | €22 | €441 | €1,100 | −€659 | €0 | −€659 | −100% |
| 10k | 800 | €9,570 | €6,613 | €1,890 | €92 | €222 | €4,409 | €1,700 | €2,709 | €4,000 | −€1,291 | −20% |
| 100k | 8,000 | €95,697 | €66,132 | €18,901 | €920 | €2,218 | €44,093 | €6,500 | €37,593 | €20,000 | €17,593 | 27% |
| 1M | 80,000 | €956,972 | €601,414 | €184,821 | €9,200 | €22,180 | €385,213 | €30,000 | €355,213 | €75,000 | €280,213 | 47% |

**Apple fee:**
- **15% in every scenario below 1M users.** At 100k/8% proceeds are about $880k a year, still under the $1M threshold.
- **22.7% at 1M users,** which is already included in the 1M rows.

**CIT (9%):**
- 100k/5%: €61 a month.
- 100k/8%: €1,583 a month.
- 1M users: €6.3k / €25.1k / €53.2k a month at 3% / 5% / 8%.

**Stress tests (100k users, 5% paying, profit after team; base €683)**

| Stress | After team | Change |
|---|---|---|
| Every payer uses 100% of allowances | −€3,557 | −€4,240 |
| Voice and AI costs ×2 | −€7,166 | −€7,849 |
| Voice ×2 and 100% usage | −€15,646 | −€16,329 |
| Monthly-plan churn 27% (base already uses 21%) | €267 | −€416 |
| Prices 15% lower (złoty discount) | −€5,010 | −€5,693 |
| Euro 15% weaker against USD | −€494 | −€1,177 |
| Trial conversion 15% | −€241 | −€924 |
| Paid ads at €40 per new payer | −€31,525 | −€32,208 |

**Sensitivity ranking (100k users, 5% paying)**

| Rank | Input (worse ↔ better) | Profit swing |
|---|---|---|
| 1 | Paying share 3% ↔ 8% | €28,183 |
| 2 | Price level −20% ↔ +10% | €11,386 |
| 3 | Team cost ±25% | €10,000 |
| 4 | TTS price ×2 ↔ ×0.25 (ElevenLabs vs Gemini/Chirp TTS) | €7,338 |
| 5 | Average usage 100% ↔ 40% | €6,348 |
| 6–11 | Running costs, refunds, support, Live-talk cost, trial conversion, churn | €0.8–3.9k each |

**Break-even**

| Paying share | MAU for running costs | MAU for running costs + €4k founder |
|---|---|---|
| 3% | 19,302 | 59,108 |
| 5% | 5,718 | 29,182 |
| 8% | 3,178 | 14,772 |

**Acquisition:**
- **Contribution per payer:** €5.63 a month after trials. At 16.1% churn that's a paid life of 6.2 months.
- **Largest affordable cost to win a payer: about €35.** That's break-even with no profit. With churn ×1.3 it drops to €26.
- **Months to recover:** €10 → 1.8; €20 → 3.6; €30 → 5.3; €40 → 7.1.
- **Recommended ceiling:** €20 (recovers within 4 months).
- **In practice:** organic, content, referrals and partners. Paid installs at Poland CPIs only work if conversion is high.

**Brief targets, honestly:**

| Target | Result | Verdict |
|---|---|---|
| 70% / 50% per plan | Monthly plans met; yearly 65–66% / 51–53% | Accept for yearly (lifetime value 1.8×) |
| Profit after running costs at 10k users, 3% paying | −€109 | Missed narrowly. It's met if running costs are ≤ €1.59k, or with any small non-subscription income. |
| Founder covered at ≤25k users, 5% paying | 29,182 users | Missed. 25k works at about 5.5–6% paying (6% → 22.5k), or with prices about 11% higher (Best Mate 49,99 zł → 24k). |
| ≥15% net margin after team at 100k users, 5% paying | 2% | Unrealistic with a €20k team at Polish prices. It's met with a team of about **€14.5k** (founder plus 2), or with **6.3% paying**. |

## 7. Recommendation

**Final model:** v2 as above. **Launch order:**
1. **Before any paid launch (needs an owner-approved milestone):**
   - A token and quota server; it's needed anyway, because the ElevenLabs agent is public with no authentication.
   - StoreKit 2 with RevenueCat.
   - The turn-by-turn Doddy-voice pipeline, with a latency test: first audio in 1.2 s or less on a mid-range iPhone over LTE.
   - Session caps.
   - Enrolment in the Small Business Program.
   - DPAs with providers and the AI-disclosure copy.
2. **Polish soft launch:**
   - Pocket Doddy, Best Mate (monthly and yearly), the 7-day trial after the first save, and the Money Saver pack.
   - Optionally Founding Mate, 500 seats, only if cash is needed.
   - A price test of 39,99 / 44,99 / 49,99 zł.
3. **After 8–12 weeks of data:** voice and Live packs, then Doddy Pro.
4. **After paying share is at least 4%:** Doddy Crew (Family Sharing and CloudKit sharing).
5. **Germany and the EU** at the € prices above, once Polish thresholds pass.
6. **Alongside:** NFC keychain and stickers as marketing. Affiliate links and partner deals only after trust and scale.

**Beta metrics (exact formulas; pre-register before launch)**

| Metric | Formula |
|---|---|
| Activation | installs with ≥1 saved memory within 24 h ÷ installs |
| Aha rate | activated users who retrieve a saved memory on a later calendar day within 7 days ÷ activated users |
| Paywall → trial | trial starts ÷ users shown the post-save offer |
| Trial → paid | trials converted to a first paid period ÷ trials that ended (exclude ongoing) |
| Day-0 trial cancel | trials cancelled on day 0 ÷ trials started |
| Paid share of MAU | active paying subscriptions ÷ monthly active users |
| Monthly paid churn | subscriptions lost in month (voluntary and billing separately) ÷ subscriptions at start of month |
| Usage share | minutes (or answers) used ÷ allowance, per plan; report median, p90, p99 |
| Real unit cost | provider invoices (€) ÷ billed minutes, per pipeline and per session-length bucket |
| Contribution per payer | (Apple proceeds − refunds − provider invoices − server − support) ÷ average payers |
| Refund rate | refunded proceeds ÷ proceeds |
| Support load | tickets per 100 payers; minutes per ticket |

**Decision thresholds** (proposed; owner to confirm before the soft launch; judge after at least 300 trial starts or 12 weeks)

| Signal | Continue | Change price or packaging | Stop or pivot |
|---|---|---|---|
| Activation | ≥ 50% | 35–50%: fix onboarding | < 35% after two onboarding iterations |
| Aha rate | ≥ 30% | 15–30% | < 15% |
| Trial → paid | ≥ 25% | 15–25%: test price, trial length, offer copy | < 15% |
| Paid share of MAU (month 3) | ≥ 4% | 2.5–4% | < 2.5% by month 4 |
| Monthly-plan churn | ≤ 21% | 21–30%: push yearly, add Money Saver value | > 30% |
| Doddy voice €/min | ≤ €0.025 | €0.025–0.04: switch TTS (Gemini/Chirp) or cut minutes | (not a stop signal alone) |
| Live talk €/min | ≤ €0.09 | > €0.09: shorten cap, prune, or move to ElevenLabs flat rate | (not a stop signal alone) |
| Contribution per payer | ≥ €5.00 | €3.00–5.00 | < €3.00 with no fix in sight |

**Top 5 risks**

| # | Risk | Mitigation |
|---|---|---|
| 1 | Paying share stays at the freemium norm of about 2–3%. Then the business never covers a salary. | Offer the trial at the first save; test a stricter variant (paywall at day 3); push Money Saver value; price test. Decide by month 4 using the thresholds. |
| 2 | Voice cost or quality. The turn-by-turn pipeline may feel slow, and Live costs may blow up. | Latency gate before launch; session caps and pruning; budget alerts per account; keep providers swappable (ElevenLabs, Gemini TTS at $9/1M through 2026 and $18 from 2027, Chirp 3 HD). |
| 3 | Polish platform gaps: no Apple Intelligence in Polish, and on-device Polish STT unconfirmed. | Free plan needs no AI; paid plans budget for cloud STT; re-check `supportedLocales` each iOS release. |
| 4 | AI-app churn and novelty decay. | Yearly plans (about 15-month life); concrete value (Money Saver savings counter); family plan; no guilt or dependency mechanics. |
| 5 | Platform, regulatory and currency changes: Apple fees, AI Act Art. 50 (applied since 2 Aug 2026), GDPR transfers to US providers, USD costs. | Enrol in the Small Business Program; DPAs and EU processing where offered; AI-disclosure labels; 15% currency buffer in caps; quarterly review of `unit_economics.py`. |

## Runnable model

`docs/business/unit_economics.py` (Python 3.10+, no dependencies) prints every table above. Every input is a named constant with a source label. Change the constants when beta numbers arrive and re-run:

```
python3 docs/business/unit_economics.py
```

## Sources (accessed 2026-10-10 unless dated)

- Gemini API pricing (updated 2026-10-09): https://ai.google.dev/gemini-api/docs/pricing
- Gemini Live best practices, re-billing of context (updated 2026-10-07): https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/live-api/best-practices
- Gemini Live session limits and compression (updated 2026-09-15): https://ai.google.dev/gemini-api/docs/live-session
- Google AI forum, no caching for Live native audio: https://discuss.ai.google.dev/t/title-context-caching-or-cached-input-pricing-for-the-gemini-live-api-native-audio/186850
- OpenAI API pricing: https://developers.openai.com/api/docs/pricing
- HackerNoon, realtime costs from 4,000 sessions (Mar–Apr 2026 data): https://hackernoon.com/openai-realtime-api-pricing-in-2026-real-world-data-from-4000-measured-sessions
- ElevenLabs Agents pricing: https://elevenlabs.io/pricing/agents
- ElevenLabs API (TTS) pricing: https://elevenlabs.io/pricing/api
- ElevenLabs LLM billing: https://elevenlabs.io/docs/agents-platform/customization/llm
- ElevenLabs Agents pricing explained (2026-09-24): https://www.getmacha.com/blog/elevenlabs-agents-pricing-explained
- ElevenLabs Agents pricing guide: https://thunderphone.com/guides/elevenlabs-agents-pricing
- Claude pricing: https://claude.com/pricing
- Google Cloud TTS voices (Polish): https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types
- Apple Intelligence devices and languages (2026-09-14): https://support.apple.com/en-us/121115
- Apple Intelligence for developers: https://developer.apple.com/apple-intelligence/
- Apple Technote TN3193, Foundation Models context window (revised 2026-03-31), developer.apple.com (exact URL not captured)
- SpeechAnalyzer languages (2026-08): https://blog.addpipe.com/apple-speechanalyzer-api
- AVSpeechSynthesizer voices (2014): https://useyourloaf.com/blog/synthesized-speech-from-text/
- Counterpoint, Apple Intelligence-capable iPhones shipped (2026-06-08): https://counterpointresearch.com/en/insights/apple-has-shipped-over-450-million-apple-intelligence-capable-iphones
- ECB EUR/USD (2026-10-09): https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/eurofxref-graph-usd.en.html
- ECB EUR/PLN (2026-10-09): https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/eurofxref-graph-pln.en.html
- Apple, DMA and apps in the EU (terms updated 2026-08-18, effective 2026-10-01): https://developer.apple.com/support/dma-and-apps-in-the-eu/
- Apple Small Business Program: https://developer.apple.com/app-store/small-business-program/
- Apple, understanding taxes: https://developer.apple.com/help/app-store-connect/making-payments-to-apple/understanding-taxes/
- EU VAT and the App Store (2014): https://oleb.net/blog/2014/07/eu-vat-changes-2015/
- App Store Poland and Germany listings: https://apps.apple.com/pl/app/id1671705818 , https://apps.apple.com/de/app/id1671705818 , https://apps.apple.com/pl/app/id6448311069 , https://apps.apple.com/de/app/id6448311069 , https://apps.apple.com/pl/app/id6477489729
- RevenueCat State of Subscription Apps 2026 (March 2026): https://www.revenuecat.com/state-of-subscription-apps
- TechCrunch on RevenueCat AI data (2026-03-10): https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows
- RevenueCat billing-error churn: https://www.revenuecat.com/blog/growth/google-play-billing-error-churn-how-to-fix
- RevenueCat pricing: https://www.revenuecat.com/pricing
- Duolingo Q2 2026 shareholder letter (2026-08-05): https://www.sec.gov/Archives/edgar/data/0001562088/000162828026053299/q2fy26duolingo6-30x26share.htm
- Mem pricing: https://get.mem.ai/pricing · Notion pricing: https://www.notion.com/pricing
- Polish CIT 9% limits 2026: https://akademialtca.pl/blog/kto-moze-placic-9-proc-cit-w-2026-r-znamy-juz-limity
- App Store sales accounting in Poland: https://ifirma.pl/blog/sprzedaz-na-app-store-rozliczenie
- EU AI Act timeline (updated 2026-08-03): https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai
- GDPR documentation costs in Poland: odo24.pl (exact page not captured)
- iOS CPI benchmarks: thesocialoutline.com and mapendo.co (exact pages not captured; SECONDARY)
