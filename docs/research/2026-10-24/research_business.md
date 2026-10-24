# Doddy business research: pricing, monetization, go-to-market, legal gates, funding

Prepared 2026-10-24 (the brief said 2026-10-23) for the Doddy founder, Warsaw.
Budget used: 16 web searches, 6 page fetches (one of them a 404 that I retried), 3 repo reads.

**Labels**
- **V** = primary or official page read in this session.
- **S** = secondary source (press, law-firm blog, vendor blog, directory) or a search-engine summary of a page I did not open myself.
- **I** = my inference, own arithmetic, or memory. Not verified in this session.

**Method caveat.** WebSearch returns summaries of result pages, so anything marked S was not read on the original page. Partial reads: the RevenueCat page was truncated; the Apple guidelines were read for the first 100,000 of 114,428 characters; Wikipedia's Epic v. Apple article for the first 100,000 of 177,800.

---

## 0. Bottom line: what this research changes in `docs/business/MONETIZATION_MODEL_V2.md`

**Confirmed**
- 7-day trial, not 3-day. Day-0 trial cancellations are 39.8% for 7-day trials against 55.4% for 3-day trials (V, RevenueCat SOSA 2026).
- Hard paywalls convert about 5x better than freemium: 10.7% vs 2.1% download-to-paid medians (V). Keeping a free tier is a deliberate trade, and the hard-paywall variant deserves an explicit experiment.
- AI-app churn assumption of about 21% a month and refund assumption of 5% (S, TechCrunch quoting RevenueCat, 2026-03-10: 12-month retention of AI monthly plans 6.1%, annual renewal 21.1%, refund median 4.2%).
- ChatGPT Go 34,99 zl and Plus 99,99 zl in Poland (S, Tabletowo).
- AI Act Art. 50 chatbot disclosure applies since 2 Aug 2026 (S, several law-firm summaries of the Digital Omnibus).
- EU App Store fee structure of August 2026: 26% standard IAP, 20% alternative payment, 15% link-out, 5% Core Technology Commission (S).
- Apple guideline 5.1.2(i) (V, quoted verbatim below).

**Challenged**
1. **Voice cost.** The doc prices included voice at EUR 0.0203/min. The founder now sees about $0.05/min (EUR 0.045), which is 2.2x. That is the doc's own "voice and AI costs x2" stress case (100k MAU, 5% paying: profit after team falls from +EUR 683 to -EUR 7,166 a month). Section 5 shows the allowances that survive $0.05/min: 40 voice minutes in Best Mate (not 60), 30 in yearly, a 19,99 zl voice pack (not 14,99), Pro at 99,99 zl with 80 minutes, Crew at 80 pooled minutes.
2. **5% paying share is top-quartile, not base.** Freemium top quartile is above 4.5% download-to-paid, median 2.1% (V). Tolan's reported 100k paid out of 3M downloads is about 3.3% cumulative (S, July 2025). Plan on 2-3% of installs, treat 5% of MAU as a stretch. At 3% the doc's own table shows -EUR 10.6k/month after a EUR 20k team at 100k MAU.
3. **Poland's entry-level anchors fell.** Google cut AI Plus from 34,99 zl to 23,99 zl a month (June 2026, S). ChatGPT Go is 34,99 zl. Best Mate at 44,99 zl is 29% above Go and 88% above Google AI Plus. It sits between entry plans (24-35 zl) and flagship plans (98-100 zl). It can work only because of the character, the memory and Doddy's own voice, so it must be tested.
4. **Three price arms are underpowered.** Detecting a 7.5-point difference in trial-to-paid (25% vs 32.5%) needs about 570 trials per arm (80% power, 5% alpha, my arithmetic). A Polish soft launch will likely produce under 1,000 trials in 90 days. Test two wide arms (34,99 vs 49,99 zl), not 39,99/44,99/49,99.
5. **Launch SKUs.** Ship Free plus Best Mate monthly and yearly only. Pro, Crew, Money Saver, the packs and Founding Mate each need something not built yet (quota server, CloudKit sharing, receipt reading) or add review and support load for a solo founder.
6. **No weekly plan.** Weekly plans are 55.5% of revenue across apps (S, Adapty 2026), but AI apps use them less, and a weekly nag-to-cancel plan conflicts with the AI Constitution (no guilt or dependency) and with EU subscription-trap enforcement trends.
7. **The beta is free with no StoreKit (V1_SCOPE section 7), so no willingness-to-pay data exists before 1.0.** Add a pricing survey to the waitlist and beta, and treat Founding Mate pre-sales as the only real-money test (see the App Review caveat in section 6).

---

## 1. Pricing benchmarks (consumer AI assistants and companions)

| Product | Price (Poland unless stated) | What it gates | Caps / credits / family / annual | Label and source |
|---|---|---|---|---|
| ChatGPT | Free; **Go 34,99 zl**; **Plus 99,99 zl**; **Pro 999,99 zl** (Tabletowo cites OpenAI). Go is $8 in the US, went worldwide 16 Jan 2026. A "Pro Lite" tier around 500 zl is rumoured only. | Go: more messages, uploads and images, longer memory and context. Voice limits per plan: not found. Ads reported on Free and Go (US, Feb 2026). | Message and rolling caps, not credits. No annual or family plan found. | S. https://www.tabletowo.pl/?p=1036202 ; https://android.com.pl/tech/962054-chatgpt-go-nowy-plan-subskrypcyjny/ ; https://tldv.io/pl/blog/chatgpt-pricing/ ; https://antyweb.pl/chatgpt-stal-sie-jeszcze-lepszy-oto-nowy-i-do-tego-tani-plan |
| Google AI Plus / Pro | **AI Plus 23,99 zl/month or 239,99 zl/year** (cut in June 2026 from 34,99 / 349,99; storage doubled to 400 GB). **AI Pro 97,99 zl/month** (date not confirmed). | Bundle with Google storage plus Gemini features. | Annual discount only 17%. Family sharing via Google One (I). | S. https://spidersweb.pl/2026/06/google-ai-plus-subskrybcja-obnizka-cen.html ; https://www.telepolis.pl/tech/aplikacje/google-ai-plus-nowa-cena-400-gb-danych ; https://www.benchmark.pl/google-ai-plus-w-polsce-cena-7268588753830977a ; https://www.chip.pl/2026/01/google-ai-plus-w-35-nowych-krajach-polska |
| Claude (Anthropic) | Not found in PLN. From memory: Pro $20/month (about $17 on annual), Max $100 and $200. | Usage limits and model access. | Usage caps; annual about 15% off. | I. The founder's doc cites https://claude.com/pricing |
| Perplexity | Not found in PLN. From memory: Pro $20/month or $200/year, Max $200. | Search depth and model access. | Annual about 17% off. | I |
| Tolan (Portola) | Prices only in the app. **Lite**: 250 messages/day, video chat and screen sharing, "better memory". **Plus**: 600/day, web search, image creation. **Unlimited**: no daily limit, monthly only, priority support and early access. Family plan sharing mentioned. Free tier: "launching soon" in July 2025, not confirmed since. | Daily message caps and memory quality, not minutes. | Caps per day; monthly or yearly for Lite and Plus. | V (help centre, undated): https://intercom.help/portola/en/articles/14039150-what-are-the-subscription-options . S (July 2025: 3M downloads, 100k paid, over $1M a month, $20M Series A): https://www.geekwire.com/2025/ai-companionship-app-tolan-raises-20m-to-help-more-people-grow-with-a-virtual-alien-friend/ |
| Poke (Interaction Co.) | **Free $0; Pro $19/month; Ultra $199/month.** Cognition (Devin) reportedly acquired it in July 2026; still standalone. | Pro: frontier models, background automations, higher rate limits. Ultra: frontier everywhere, pay-as-you-go beyond included credits, "Poke Human" concierge (bookings, calls). | Credits plus pay-as-you-go only at the top tier. Monthly and yearly exist; yearly price not readable. | S. https://tooldirectory.ai/tools/poke ; https://blog.saner.ai/poke-reviews/ ; https://www.layer3labs.io/guides/poke-ai-explained |
| Character.AI | c.ai+ **$9.99/month, $94.99/year** | Speed and priority. | Annual 21% off. | S. https://tech-insider.org/?p=17991 |
| Replika | Pro **$19.99/month, $69.99/year**. Higher tier reports conflict ("Max" or "Ultra"). | Voice and other features (not verified). | Annual 71% off. | S. https://aicompanionpick.com/replika-free-features-2026 |
| Duolingo Max | **$29.99/month, $168/year** (July 2026). Some Max features (Video Call, Explain My Answer) reportedly made free in January 2026. | AI roleplay and explanations. | Annual 53% off. | S. https://dupple.com/learn/best-ai-language-learning-tools |
| Finch, Speechify, Granola | Not found in this session. | | | Unverified |

**Patterns (I, from the table)**
- Caps are mostly messages or usage per day or week. Credits appear only at the top tier (Poke Ultra).
- Annual discounts range from 17% (Google) to 71% (Replika). Doddy's 35% sits mid-range.
- Almost nobody gates memory outright; they gate model quality, volume and "proactive" features. Doddy's free tier (memory, search, export, delete) is on trend.
- Entry anchors in Poland: 24-35 zl. Flagship anchors: 98-100 zl. All prices end in ,99.

**PLN price points.** Everything above ends in ,99 (23,99 / 34,99 / 97,99 / 99,99 / 239,99 / 349,99). The doc's list of observed App Store points still needs checking in App Store Connect for 44,99 / 79,99 / 89,99 / 349,99 / 749,99 / 899,99. I recall that Apple moved to about 900 price points per storefront in 2023, which makes odd points like 44,99 likely available (I, unverified).

---

## 2. Subscription-app benchmarks

Source A (V, page read, truncated): RevenueCat, State of Subscription Apps 2026, 2025 data. https://www.revenuecat.com/state-of-subscription-apps
Source B (S, article read 2026-10-24): TechCrunch, 2026-03-10, quoting the same report. https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows
Source C (S, search summary): Adapty, State of In-App Subscriptions 2026. https://adapty.io/state-of-in-app-subscriptions-report/ ; https://ppc.land/95-of-app-subscription-revenue-goes-to-top-10-adaptys-2026-benchmark-report/

| Metric | Number | Source |
|---|---|---|
| Download to paid, global median | 2.0% | A |
| ... hard paywall / freemium | **10.7%** (top quartile above 20.0%) / **2.1%** (top quartile above 4.5%) | A |
| ... AI apps vs non-AI | 2.4% vs 2.0% | B |
| ... by price tier | high 2.8%, mid 2.0%, low 1.4% (higher-priced apps convert better in this data; confounded) | A |
| Download to trial | Business median 9.1% (top quartile 16.2%); North America 7.1% (top quartile 15.0%) | A |
| Trial to paid by trial length | at most 4 days **25.5%**; 5-9 days **37.4%**; 17-32 days 42.5%; North America 34.2%; India/SE Asia 15.2% | A |
| "AI trial conversion" 8.5% vs 5.6% non-AI | Different denominator from trial-to-paid (RevenueCat's own trial-to-paid medians are 25-42%). Do not use it as trial-to-paid. | B (flagged) |
| Day-0 trial cancellations | 3-day 55.4%, **7-day 39.8%**, 14-day 35.7%, 30-day 31.1% | A |
| Share of trials started on day 0 | 78-90% depending on category; Adapty says 90% | A, C |
| Retention, AI vs non-AI | Monthly plans, 12 months: **6.1% vs 9.5%**. Annual plans, 12 months: **21.1% vs 30.7%**. Weekly: 2.5% vs 1.7% (only place AI leads). AI annual subscriptions churn 30% faster at the median. | B |
| Refund rate | Median **4.2%** (AI) vs 3.5%; upper bound 15.6% vs 12.5% | B |
| Year-1 revenue per payer (RLTV) | Global median $23 (top quartile $44+). AI monthly $18.92, AI annual $30.16. North America $32, Western Europe $25, India/SE Asia $14. | A, B |
| Median prices | Weekly $5.99, monthly about $10, yearly $34.80 (North America: $9.99 monthly, $39.99 yearly) | A |
| Weekly plans | 55.5% of revenue, up from 43.3% two years ago. Weekly with a trial has the best 12-month LTV ($54.50 vs $7.40 without a trial). Utilities 73.6% weekly. | C |
| Revenue concentration | 95% of subscription revenue goes to the top 10% of apps | C |
| Paid share of MAU, best in class | Duolingo 9.0% (Q2 2026 filing, per the founder's doc) | doc (not re-verified) |
| Tolan cumulative paid per download | about 3.3% (100k / 3M, July 2025) | S, my division |

**Paywall placement.** RevenueCat's page gave no measured placement result. Visible data: hard paywalls show a day 4-7 spike; 80-90% of trials start on day 0 (so the offer must be in the first session). The founder's design (offer after the first saved memory, in session one) fits that. Nothing found on AI-specific placement (I: put the offer straight after the first "aha", not at install).

**Planning numbers for Doddy (I)**

| Item | Pessimistic | Base | Stretch |
|---|---|---|---|
| Install to trial start | 4% | 7% | 10% |
| Trial to paid | 15% | 25-30% | 37% |
| Install to paid | 0.6% | 2.0% | 3.7% |
| Paid share of MAU, month 3 | 1.5% | 3% | 5% |
| Monthly-plan churn | 27% | 21% | 15% |
| Yearly renewal at month 12 | 15% | 21% | 30% |
| Refunds | 8% | 5% | 3.5% |

---

## 3. Monetization models for a per-minute-cost product

| Model | Fit for Doddy | Notes |
|---|---|---|
| Freemium with minute caps | **Core.** Free tier must cost about nothing; paid tier has a monthly minute allowance. | Free voice must average at most about 1 minute per MAU per month (derivation in section 5). |
| Credits and top-up packs | **Good as overflow only.** Poke's pay-as-you-go sits only at the top tier. Packs let heavy users pay for their own cost instead of raising everyone's price. | Pack price must clear $0.05/min plus Apple's 15% and VAT: at least 19,99 zl per 30 minutes. |
| Hard paywall with trial | **Test it.** 5x conversion in RevenueCat's data. Conflicts with "free memory" as a trust promise and removes organic word-of-mouth. | Run as an explicit A/B in the beta, with export and delete always free. |
| Family plans | Later (after paid share reaches 4%). Tolan mentions plan sharing. Apple Family Sharing is the cheapest way (the doc's Crew). | At $0.05/min, Crew's 120 pooled minutes give only 37% margin at full use; cut to 80. |
| Gifting | Apple allows gifting of IAP-eligible items under 3.1.1 as I remember it (I, not in the excerpt I read). Fits "child buys for parent". | Verify the exact gifting rule and mechanics in App Store Connect. |
| Seniors and caregivers | Real segment: voice-first lowers UI friction, and the buyer is often the adult child. Keep claims non-medical (memory aid, not care or diagnosis) to avoid medical-device and AI Act high-risk questions. | I. Not researched beyond reasoning. Needs interviews. |
| B2B2C: telcos, banks, insurers | Not in the first 12 months. I found **no Polish operator AI bundle** (searched Orange, Play, Plus, T-Mobile). Spanish precedents exist: Movistar gave ChatGPT Plus for six months to loyal customers; MasOrange can add Google AI plans to the bill (S). Sales cycles of 6-12 months are typical (I). | https://www.xatakamovil.com/orange/movistar-aposto-chatgpt-plus-para-sus-clientes-ahora-orange-podran-disfrutar-gemini-su-factura |
| Lifetime (Founding Mate) | Worth doing capped at 500 seats: up to about EUR 39k net cash (500 x EUR 78.53). At $0.05/min and a 40-minute cap, EUR 78.53 covers about 50 months of average use or 34 at full use. Define "lifetime" as "while Doddy operates", with a fair-use clause. | I. Polish "was/now" discount claims must show the lowest price of the previous 30 days (Omnibus rule, I, verify). |
| Web subscription for the web app | Stripe/BLIK/P24 cost far less than Apple's 15% (I: card fees about 1.5-3%). The iOS app may honour web-bought access under the multiplatform-services rule (3.1.3(b), from memory) if the same item is also offered as IAP. | Confirm with App Review notes before relying on it. |

**What must be free vs paid for Doddy (I, built on the constitution)**
- **Always free:** capture, text search, reminders and lists, widgets, Face ID lock, backup, **export and delete** (GDPR Art. 17 and 20 duties, and the trust promise), AI-identity disclosure, and any safety or crisis messaging.
- **Free but metered:** one 3-minute "First hello" in Doddy's own voice (about $0.15 per activated user), once per Apple ID.
- **Paid (these cost money per use):** cloud voice minutes, cloud answers, "think harder", live talk, LLM-generated proactive briefings, integrations that need servers.

---

## 4. Where the numbers come from (formulas and assumptions)

Same conventions as the founder's doc so results compare directly:
- EUR 1 = 4.40 zl; $1 = EUR 0.90; so $0.05 = EUR 0.045 = 0.20 zl.
- VAT 23%; Apple 15% (Small Business Program).
- Other variable costs per payer per month from the doc's table: text answers EUR 0.12 average / 0.19 heavy; server 0.10; support 0.25; refunds 5% of kept; billing leakage 2% of kept; RevenueCat 1% of ex-VAT price.
- Average usage 60% of allowance; heavy 100%.
- Contribution = kept - voice - other variable. Margin = contribution / kept.

---

## 5. Recommended tiers, with the $0.05/min sanity check

### Tiers (launch = first two rows only)

| Tier | PLN | EUR (Germany) | USD | What is in it |
|---|---|---|---|---|
| **Pocket Doddy** (free) | 0 | 0 | 0 | Unlimited memories (typed, or Apple dictation where the device supports Polish), text search, lists and reminders, widgets, Face ID lock, backup, **export and delete**. One-time 3-minute "First hello" in Doddy's voice. No recurring cloud voice and no cloud answers. About EUR 0.01 per user per month, plus about EUR 0.07 per install for the intro. |
| **Best Mate** monthly | **44,99 zl** (default; A/B arms 34,99 and 49,99) | 9,99 | 9.99 | 7-day free trial offered after the first saved memory; trial = 10 voice minutes, 30 cloud answers, no live talk (about EUR 0.47). Then: **40 voice minutes a month**, 300 cloud answers, Calendar/Reminders actions, optional morning briefing, one active voice session per account. Hard stop plus voice pack, never silent overage. |
| **Best Mate** yearly | **349,99 zl** (test 299,99) | 79,99 | 79,99 | Same, but **30 voice minutes a month**, pooled as 360 minutes a year. 35% off the monthly price. |
| Voice pack, 30 min | **19,99 zl** (doc: 14,99) | 4,49 | 4.99 | Consumable top-up. |
| **Doddy Pro** (after 8-12 weeks of data) | **99,99 zl** monthly; 899,99 yearly | 19,99; 199,99 | 19.99; 199.99 | 80 voice minutes, 10 live minutes, 50 "think harder" answers. Same price as ChatGPT Plus in Poland. |
| **Doddy Crew** (only after paid share reaches 4% and CloudKit sharing exists) | 79,99 monthly; 749,99 yearly | 17,99; 169,99 | n/a | Up to 6 people via Family Sharing, **80 pooled voice minutes** (doc: 120), 1,500 answers. |
| **Founding Mate** (launch only, 500 seats) | 499,99 once | 109,99 | n/a | Best Mate allowances for as long as Doddy operates, with fair use. |

USD is set equal to EUR (my choice, I). North America's median monthly price is $9.99 but its median yearly is only $39.99 (V), so $79.99 yearly is high for the US; test $59.99 before a US launch.

### Unit economics at $0.05/min (my arithmetic on the doc's inputs)

**Best Mate monthly, 44,99 zl.** Gross EUR 10.22, ex-VAT 8.31, kept EUR 7.07. Non-voice variable cost EUR 1.04 average / 1.11 heavy.

| Included voice minutes | Margin, average use (60%) | Margin, heavy use (100%) |
|---|---|---|
| 60 (doc) | 62% (contribution EUR 4.41) | **46%** (EUR 3.26) |
| **40** | **70%** (EUR 4.95) | **59%** (EUR 4.16) |
| 30 | 74% | 65% |

At $0.05/min the doc's 60 minutes fail its own 50% heavy-user target; 40 minutes meet both targets.

**Best Mate yearly, 349,99 zl.** Kept EUR 4.58. Non-voice cost EUR 0.85 average / 0.92 heavy.
- 40 min: 58% average, **41%** heavy.
- 30 min: 64% average, **51%** heavy.

**Voice pack.** At 14,99 zl (kept EUR 2.35) the margin falls from the doc's 69% to about 40%. At 19,99 zl (kept EUR 3.14) it is about 53%.

**Doddy Pro.** Doc's 89,99 zl with 100 voice + 15 live minutes gives 60% average / **40%** heavy at $0.05/min. 99,99 zl with 80 voice + 10 live gives **68% / 54%**.

**Crew.** 120 pooled minutes at 79,99 zl: 57% average / **37%** heavy. 80 minutes: 66% / 51%.

**Founding Mate.** Net EUR 78.53 per seat (doc). Covers about 50 months of average use or 34 months of heavy use at a 40-minute cap.

**Free tier rule.** If 3% of MAU pay and each payer contributes about EUR 5, that is EUR 0.15 per MAU. Keeping free-user cost under 20% of that (EUR 0.03) allows about 0.7 voice minutes per MAU per month, so "at most about 1 minute per MAU per month". Recurring free cloud voice is impossible; a one-time intro is fine.

**Voice acquisition cost per payer.** Intro 3 min x EUR 0.045 x 50% activation = EUR 0.07 per install. Trial 7% of installs x EUR 0.47 = EUR 0.033. About EUR 0.10 per install. At 2% install-to-paid that is about EUR 5 per payer, against a lifetime contribution of about EUR 28 (EUR 4.5 a month x 6.2 months paid life from the doc's 16.1% churn). Fine.

**Whole-business effect.** At $0.05/min with the doc's allowances unchanged, the 100k MAU / 5% scenario moves from +EUR 683 to roughly the doc's "voice x2" stress result, -EUR 7,166 a month. With the allowances above, the damage is much smaller but the 5% paying-share assumption still carries the business (section 0, point 2).

**Caveat.** If the turn-by-turn pipeline reaches EUR 0.02/min as the doc computes, the doc's 60-minute allowances come back. The latency and real-cost gate in the doc's section 7 decides which set of numbers applies, so ship the minute allowances as server-side configuration, not hard-coded.

---

## 6. Go-to-market (Poland first, solo founder)

### Sequencing
1. **Poland, Polish and English UI** (V1_SCOPE decision 2; the other eight languages are unread machine drafts).
2. **English-speaking markets organically** (UK, Ireland, US) on the same build. No paid acquisition.
3. **Germany/Austria** after Polish thresholds pass, at EUR prices, only after a native German read.
4. **US storefront for web checkout:** Apple's guideline 3.1.1(a) says the prohibition on external purchase links does not apply on the United States storefront (V, quoted below). The commission status is unsettled: the April 2025 order stopped Apple charging on link-out purchases; on remand the district court was to decide what, if anything, Apple may take; Apple's May 2026 stay request was denied; the Supreme Court granted review limited to the contempt question (S, Wikipedia, partially read). Treat "0%" as current but unstable. Texas and other states' app-store age laws also apply to US launches (S).
5. Rest of the EU one language at a time.

### 90-day plan (Mon 26 Oct 2026 to Sun 24 Jan 2027). Each phase is gated; do not launch because the calendar says so.

**Phase 0, weeks 1-4 (26 Oct - 22 Nov): unblock and seed. Budget EUR 1.5-4k.**
- Close GO_LIVE_CHECKLIST items A4, A5, C1, C2 (paid Apple team, production bundle ID, App Store Connect record). Apple Developer Program is $99 a year (I).
- Create the App Store Connect record early. Featuring nominations are filed there, and Apple asks for at least two weeks' notice and recommends up to three months ahead (V).
- Enrol in the Small Business Program (15%) before the first sale.
- Waitlist (doddy.lol): fix consent (checklist C12: Google Analytics and Fonts load before any choice) or switch to cookieless analytics; add a referral queue (invite 3 friends to skip the line) and a 4-question price-sensitivity survey (Van Westendorp) in the confirmation email. Use the waitlist to recruit the beta, as the checklist plans.
- Start the content engine: 3-5 short Polish videos a week, character-first (see the UGC notes). Seed 10 nano-creators (under 10k followers) with TestFlight codes and no fee.
- Start legal: privacy policy, terms, DPAs, DPIA, AI-disclosure copy (section 7).
- Draft Polish ASO and the press kit.

**Phase 1, weeks 5-8 (23 Nov - 20 Dec): external TestFlight beta. Budget EUR 0.5-2k.**
- 20-24 non-friend adults first (checklist C9), then extend to 100-300 from the waitlist in two-week cohorts.
- Measure the doc's activation and aha formulas, real cost per voice minute (provider invoices divided by billed minutes), first-audio latency (target 1.2 s or less), cost per tester.
- Run a fake-door price test honestly labelled ("planned pricing, not charging yet") to read intent per price arm, plus the waitlist survey.
- Run 8-10 recorded interviews against each tester's current habit (Notes, Reminders, Siri, ChatGPT voice).
- Do not submit to App Review between about 20 Dec and 28 Dec: Apple has historically paused review around Christmas (I, from memory).

**Phase 2, weeks 9-13 (21 Dec - 24 Jan): Polish soft launch, only if the gates pass. Budget EUR 2-6k.**
- Gate list: checklist stages A-D closed, StoreKit 2 + RevenueCat + quota server built, DPAs signed, AI-disclosure and consent screens in the app, privacy policy published, support address live, age rating answered.
- Target public availability in the first two weeks of January (resolution season for productivity apps, I). Submit for review by about 5 January, or before 18 December.
- Two-arm price test (34,99 vs 49,99 zl); a hard-paywall variant on a slice of traffic.
- Launch moves: nominate for featuring (App Launch) with a short story, 30-second video and assets; Polish tech press 2 weeks ahead under embargo with TestFlight codes; 10-20 paid micro-creators (PLN 500-3,000 each, I); Product Hunt on the English side for backlinks (free); a LinkedIn founder story (Polish solo founder, memory app).
- Optional Apple Search Ads test on exact-match Polish keywords, EUR 300-1,000 (I). Paid acquisition beyond that only if the payer cost stays under EUR 20 (the doc's ceiling).

**Budget summary (I, ranges, not quotes)**

| Item | Lean | Stretch |
|---|---|---|
| Apple Developer Program | about EUR 95 | same |
| Legal: Polish lawyer for privacy policy, terms, DPAs, DPIA, AI Act check (the doc's full setup is EUR 4-15k) | EUR 1.5k | EUR 5k |
| Creator seeding (10-20 micro-creators) | EUR 0.5k | EUR 5k |
| Voice cost for beta and launch testers | EUR 0.15k | EUR 1k |
| Apple Search Ads test | 0 | EUR 1k |
| PR freelancer | 0 | EUR 1.5k |
| Tools, analytics, trademark search (EUIPO filing about EUR 850 per class, from memory) | EUR 0.2k | EUR 1.5k |
| **Total, 90 days** | **about EUR 2.5-4k** | **about EUR 12-16k** |

### Apple editorial (V: https://developer.apple.com/app-store/getting-featured/)
- Submit through Featuring Nominations in App Store Connect. Minimum two weeks' notice; up to three months ahead for wider consideration.
- Criteria Apple lists: user experience, UI design, innovation, uniqueness, accessibility, localization, product page quality (screenshots, previews, ratings and reviews). There is no checklist.
- If selected for certain Today placements, Apple notifies you in the App Store Connect app and emails Admin, App Manager and Marketing roles for promotional assets.
- Doddy's pitch angles (I): Polish-first localisation (rare among AI apps), voice-first accessibility, Dynamic Island and Back Tap, widgets, privacy (Face ID, local storage, "what leaves this iPhone" screen). Do not claim features that are not built (CLAUDE.md rule).

### UGC and character marketing
- **Duolingo (S):** started on TikTok in early 2021; the character is the content, entertainment before selling, running gags, trend audio, commenting on other creators; about 7M followers and 147M+ likes at the time of the article; the marketing director says a significant part of user growth comes from TikTok, skewing younger. Users also made content from the passive-aggressive push notifications. https://thehustle.co/how-duolingo-struck-social-gold-by-going-unhinged ; https://blog.hubspot.com/marketing/duolingo-unhinged-content ; https://www.fastcompany.com/90963949/duolingo-duo-owl-gen-z-obsessed
- **Tolan and Finch:** my search returned nothing on how they grew. Unverified. Tolan's size is public (3M downloads by July 2025).
- **For Doddy (I):** copy the character-first humour and community comments, **not** the guilt notifications, which the AI Constitution forbids. Use only the owner's imported pose pack for art (CLAUDE.md). Give beta users a "Doddy remembered" share card so users produce the content. Use the Polish voice as a reusable TikTok sound.

### Other channels (I unless noted)
- **Polish ASO:** localised name (30 characters), subtitle (30) and keyword field (100). Candidate terms: notatki głosowe, asystent głosowy, pamięć, przypomnienia, listy zakupów, zapamiętaj, AI po polsku. Polish screenshots. Custom Product Pages per channel (TikTok, press, referral). Rating prompt only after a successful retrieval.
- **Polish media that covered AI subscriptions in 2026 (S, they appeared in my searches):** antyweb.pl, tabletowo.pl, android.com.pl, imagazine.pl, spidersweb.pl, telepolis.pl, chip.pl, benchmark.pl. Fit for a Polish-built AI voice companion is my judgment. No YouTuber list verified.
- **Product Hunt:** free, mainly useful for English backlinks and credibility; expect hundreds, not tens of thousands, of installs (I).
- **Waitlist and referral loop:** queue-jump for invites; "invite 3, get a month free" for the beta; Founding Mate early access. Target invite-to-install K of 0.1-0.3 (I).

### Metrics
Use the doc's pre-registered formulas (activation, aha, paywall-to-trial, trial-to-paid, day-0 cancel, paid share of MAU, churn, usage share, real unit cost, contribution per payer, refunds, support load). Add: waitlist-to-install, product-page conversion rate, ratings count and average, K-factor, blended cost per payer, and first-audio latency.

---

## 7. Launch legal gates (EU / Poland / Apple)

| # | Gate | What it requires | Status of my evidence |
|---|---|---|---|
| 1 | **Apple 5.1.2(i)** | Quote: "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so." Name each provider (ElevenLabs/OpenAI/others) and data category (audio, transcripts, notes, contacts, calendar) in a consent screen before the first conversation; store the choice; re-ask if the provider changes. Checklist item B10 ("What leaves this iPhone") is the base. | **V** (read 2026-10-24) https://developer.apple.com/app-store/review/guidelines/ |
| 2 | Apple 2.5.14 | Explicit consent and a clear visual or audible indication when recording with the microphone. | V |
| 3 | Apple 5.1.1(v), 4.8 | In-app account deletion if accounts exist; an equivalent privacy-preserving login (Sign in with Apple) next to Google. Checklist C16 covers both. | V |
| 4 | Apple 3.1.1 / 3.1.2 | Digital features unlock via IAP; show what the user gets for the price and the trial terms before asking to subscribe; subscriptions at least 7 days. External purchase links are allowed on the US storefront only. | V |
| 5 | **Age rating and Declared Age Range** | Answer Apple's updated age-rating questionnaire (the original deadline was 31 Jan 2026 and unanswered questions block updates). Apple reworked ratings (13+, 16+, 18+ tiers) and extended its Declared Age Range API (iOS 26 to 27, more countries in 2026). A September 2026 "social media" declaration exists but should not apply unless Doddy gets sharing features. For an open-ended AI companion, rate conservatively, state a minimum age of 16 in the terms (the GDPR Art. 8 default age of digital consent; I believe Poland did not lower it, verify), and read the Declared Age Range signal where available. No EU or Poland mandate for app-level age assurance found. | **S** https://developer.apple.com/forums/thread/810473 ; https://dev.to/mr_manushukla/app-store-age-ratings-1-answer-becomes-mandatory-in-september-2026-and-it-can-force-a-13-rating-1eih ; https://www.techrepublic.com/de/article/news-apple-expands-age-verification-api-global-compliance/ ; https://ecorpit.com/ios-27-parental-controls-app-developer-guide-2026/ . The single-blog "September 2026" claim is unconfirmed. |
| 6 | **EU AI Act Art. 50** | The Digital Omnibus on AI (Regulation (EU) 2026/1744 per law-firm summaries; adopted by Parliament 16 June, Council 29 June, signed 8 July, in force 27 July 2026) delayed the high-risk rules (Annex III to 2 Dec 2027, Annex I to 2 Aug 2028) but **not** the Art. 50 transparency duties: chatbot disclosure applies since **2 Aug 2026**. The only Art. 50 deferral is machine-readable marking of synthetic content (Art. 50(2)) for systems already on the market before 2 Aug 2026, until 2 Dec 2026. Doddy is a new system, so assume no grace. Do: tell users in onboarding, in the first voice session and in the store listing that Doddy is an AI; ask ElevenLabs whether its synthetic audio carries the Art. 50(2) marking and who is the obliged provider; keep the Art. 50(4) deepfake rule in mind for any voice clone of a real person. Fines for Art. 50 go to EUR 15M or 3% of turnover (from memory). | **S** https://www.gibsondunn.com/eu-ai-act-omnibus-agreement-postponed-high-risk-deadlines-and-other-key-changes/ ; https://usercentrics.com/knowledge-hub/eu-ai-act-high-risk-delay-article-50-transparency-consent/ ; https://www.joneswalker.com/en/insights/blogs/ai-law-blog/yes-august-2-still-matters-the-eu-approved-a-high-risk-ai-delay-but-most-trans.html ; https://www.legalithm.com/en/blog/eu-ai-act-what-applies-2-august-2026 ; https://www.certivo.com/blog-details/eu-ai-act-august-2026-what-applies-after-the-digital-omnibus . I did not read the Official Journal text. |
| 7 | **GDPR vendor terms** | Art. 28 DPAs with ElevenLabs, OpenAI (and Anthropic/Google if used), Vercel, Upstash, RevenueCat; transfer mechanism (SCCs or Data Privacy Framework) for US vendors. ElevenLabs: the DPA is downloadable and covers paid tiers with SCCs; **EU data residency is Enterprise-only**; Zero Retention Mode is limited and still lets custom LLMs and webhooks send data outside the EU. Fix the live agent's `retention_days -1` and `record_voice: true` (checklist C4). | **S/V**: ElevenLabs docs https://elevenlabs.io/docs/overview/administration/data-residency ; law-firm review https://compound.law/en-DE/tools/elevenlabs/ . No plan-by-plan matrix found; ask ElevenLabs which plan gives Zero Retention for Agents. |
| 8 | GDPR DPIA and special categories | A DPIA (Art. 35) for voice plus personal memory at scale (I). Notes will contain health, religion, family data, which are Art. 9 special categories: obtain explicit consent, minimise, and let users mark notes private (already in the app). Records of processing (Art. 30); 72-hour breach notification to UODO; DPO question if special-category processing becomes a core large-scale activity. | I |
| 9 | **Recording calls in Poland (not searched)** | My understanding: a participant recording their own call is generally not an offence; third-party interception is (Penal Code Art. 267); publishing a recording can breach personal rights. A commercial AI service that records and processes a conversation needs a GDPR legal basis and notice, and ePrivacy Art. 5(1) requires consent of the users concerned. So: announce recording at the start, get consent from the other party before storing or sending their voice (the Translator and phone-number features), or do not store it. V1 hides Translator and cuts phone calls. Get counsel before reviving either. | **I**, unverified. |
| 10 | **Polish and EU consumer subscription law** | Consumer-facing terms and key information in Polish; prices shown in PLN including 23% VAT; trial-to-paid, renewal and cancellation terms stated clearly before purchase; 14-day withdrawal right for distance contracts (Apple handles refunds for IAP; you must implement it for any web checkout); **withdrawal-function ("button") rule** from Directive 2023/2673 reported to apply from **19 June 2026**, but the Polish transposition status is unclear in what I found; the CJEU case C-565/22 can extend the withdrawal period by up to 12 months when information is missing. Omnibus 30-day rule for "was/now" price claims. | **S/I**: https://itwiz.pl/odstapienie-od-umowy-jednym-kliknieciem-nowe-obowiazki-dla-e-sklepow-od-2026-roku/ ; https://pro.rp.pl/nawigator-prawny-poradnik/art44408141-jeden-przycisk-ktory-zmieni-e-handel . Check the text on ISAP. |
| 11 | **Digital Fairness Act (watch)** | A proposal is expected on **11 Nov 2026** per one law firm; Commissioner McGrath has said before the end of 2026. Scope under discussion: subscription traps, hard cancellation, auto-renewing free trials, dark patterns, addictive design, protection of minors. I found nothing confirming AI companions are targeted. | **S** https://cms.law/en/aut/legal-updates/inside-the-eu-s-planned-digital-fairness-act-digital-design-subscription-traps-and-influencer-marketing ; https://www.privacylaws.com/news/eu-proposal-on-digital-fairness-act-expected-by-the-end-of-2026/ |
| 12 | **Apple fees and Small Business Program** | Enrol in the Small Business Program (15% under about $1M of annual proceeds). EU terms announced mid-August 2026: 26% standard IAP, 20% with alternative payment processing, 15% when steering to an external website, 5% Core Technology Commission on alternative distribution; Small Business and other programmes get further discounts (details conflict between sources). | **S** https://www.techrepublic.com/de/article/news-apple-eu-fees-digital-markets-act/ ; https://aa.com.tr/en/science-technology/apple-revamps-eu-app-store-fees-to-resolve-regulatory-dispute/4031035 ; https://mjtsai.com/blog/?p=52942 ; the doc cites https://developer.apple.com/support/dma-and-apps-in-the-eu/ and https://developer.apple.com/app-store/small-business-program/ |
| 13 | **US external purchase links** | Allowed on the US storefront (3.1.1(a), V). Commission: the April 2025 order barred Apple from charging on link-out purchases; remand to set any permitted amount; Supreme Court review granted, limited to the contempt question; no current rate stated on the page I read. Plan for 0% but model a possible reasonable commission. | V for the guideline; **S** for the litigation status: https://en.wikipedia.org/wiki/Epic_Games_v._Apple (partial read) |
| 14 | Website | Cookie and analytics consent (ePrivacy; Polish electronic-communications law, I), waitlist retention period, deletion on request with a real address (checklist C7, C12). | I (checklist V) |
| 15 | Company and tax | Apple organisation enrolment needs a legal entity and a D-U-N-S number (I). Apple VAT handling, reverse-charge invoicing of Apple Distribution International, 9% small-taxpayer CIT: per the doc (S). Trademark clearance for "Doddy" (EUIPO TMview search is free; I). | doc / I |

---

## 8. Money and credits

| Source | What | Status | Label |
|---|---|---|---|
| **PARP** | 22 calls planned for 2026, nearly PLN 1.3 bn in total. "Platformy startowe" component IIa opened 30 June 2026, up to PLN 600k a project, for **Eastern Poland** (the five eastern voivodeships; Warsaw is outside, I). Component IIb (first call closed 10 Feb 2026; eight projects, nearly PLN 15M) is only for startups that finished IIa. "Start-ups Are Us" (smart city, FENG, PLN 2M) closed 25 June 2026. | Not a fit for a Warsaw solo founder on this evidence. | S https://www.parp.gov.pl/component/content/article/90835:masz-pomysl-ktory-nie-powinien-lezec-w-szufladzie-parp-uruchamia-nabor-dla-startupow ; https://www.parp.gov.pl/component/content/article/90606:prawie-15-mln-zl-dla-innowacyjnych-startupow-zakonczylismy-kolejny-nabor ; https://xyz.pl/?p=141519 |
| **NCBR Ścieżka SMART** | PLN 1 bn call ran 1 July - 30 Sept 2025, closed; no 2026 round found. Needs real R&D, usually a consortium, and a long grant process. | Not a 90-day source. Check ncbr.gov.pl. | S (same search) |
| Polish tax levers | IP Box (5% on qualified IP income), R&D relief, prototype relief, Estonian CIT, and the 9% small-taxpayer CIT the doc already uses. | Ask an accountant; I recall them but did not verify rates or eligibility. | I |
| EU programmes | EIC Accelerator, Horizon Europe: aimed at deep tech, poor fit for a consumer app now. | | I |
| **ElevenLabs Startup Grants** | One aggregator lists 33M credits plus 12 months on the Scale tier for companies under 25 employees with no VC requirement. Voice is the largest cost, so this is the most valuable credit to chase. Check whether credits apply to Agents (per-minute) as well as TTS. | Single source. | S https://www.everythingstartups.com/article/ai-startup-programs |
| **Google for Startups Cloud Program** | Up to $200k over two years standard; up to $350k on the AI track (ceiling; AI-first with Gemini as the core). Relevant only if Gemini or Google TTS replaces ElevenLabs. | | S https://creditforstartups.com/companies/google ; https://fin.ai/learn/ai-credits-for-startups |
| **AWS Activate** | Founders $1k; Portfolio up to $100k via a provider; invite-only AI tiers of $200k or more (sources conflict). | | S |
| **Anthropic, OpenAI** | No published dollar amounts. Widely quoted $25-100k figures are not from Anthropic. Anthropic credits cover only the first-party Claude API. Mostly VC-gated. | Do not plan on them. | S https://fin.ai/learn/ai-credits-for-startups |
| **Apple** | Small Business Program (15%) is the only Apple money lever I verified. Apple Entrepreneur Camp exists but eligibility is restricted (unverified). | | doc V / I |
| **Customer money** | Founding Mate pre-sale: up to 500 seats, about EUR 39k net via Apple IAP at 15%. Cash up front, but a service liability; define "lifetime" and fair use in the terms. A web pre-sale before the app exists avoids Apple's cut, but unlocking an iOS app from a web purchase must be squared with App Review (see section 3). | | I |

---

## 9. Unverified items (do not state as fact)

1. PLN prices for Claude Pro, Perplexity Pro, Gemini AI Pro date, Finch, Speechify, Granola. US prices for Claude and Perplexity are from memory.
2. Whether ChatGPT Go/Plus include specific voice minute caps; OpenAI's own Polish pricing page (I relied on Tabletowo).
3. Tolan: current prices, whether the free tier launched, the "about 250k MAU" figure, and its growth channels. Finch's growth channels.
4. Poke's acquisition by Cognition (directories only). Poke yearly price.
5. Any Polish telco or bank AI bundle (none found, not proof none exists).
6. App Store PLN price points 44,99 / 79,99 / 89,99 / 349,99 / 749,99 / 899,99 (only checkable in App Store Connect).
7. RevenueCat refund and retention figures come via TechCrunch; the RevenueCat page I fetched was truncated and lacked retention, refund and AI breakdowns.
8. Adapty AI-specific benchmarks and paywall-placement data (not found).
9. The "8.5% AI trial conversion" definition (flagged ambiguous).
10. Declared Age Range obligations in the EU/Poland, the "September 2026" social-media declaration, and the Polish age of digital consent (16, from memory).
11. Polish transposition and in-force date of the withdrawal-button rule (Directive 2023/2673).
12. DFA date (11 Nov 2026 from one law firm) and its scope for AI companions.
13. Official Journal text of Regulation (EU) 2026/1744 and whether Art. 50(2) marking obliges Doddy or only ElevenLabs.
14. ElevenLabs plan matrix for Zero Retention and EU residency on Agents; OpenAI and Anthropic DPA and residency terms.
15. Exact EU Apple fee tiers for a small developer under the August 2026 terms (sources conflict); US link-out commission after remand.
16. Call-recording law in Poland (section 7, row 9), Omnibus 30-day price rule, gifting rule 3.1.1, multiplatform rule 3.1.3(b), App Review holiday pause, Apple Developer Program fee, EUIPO fee: all from memory.
17. Whether Warsaw is excluded from PARP's Eastern Poland call (I believe so), and whether any 2026 NCBR or PARP call fits an AI consumer app.
18. Anthropic, OpenAI and ElevenLabs credit amounts and terms.
19. Polish creator rates, ASA costs, K-factor, install and trial rates for Doddy (all planning assumptions, not measurements).
20. Seniors and caregivers segment sizing, willingness to pay, and regulatory boundary (no research done).

---

## 10. Sources (all accessed 2026-10-24)

**Read directly (V)**
- Apple App Review Guidelines (first 100,000 of 114,428 characters): https://developer.apple.com/app-store/review/guidelines/
- Apple, Getting featured: https://developer.apple.com/app-store/getting-featured/
- RevenueCat, State of Subscription Apps 2026 (truncated): https://www.revenuecat.com/state-of-subscription-apps
- Tolan help centre, subscription options (undated): https://intercom.help/portola/en/articles/14039150-what-are-the-subscription-options
- Repo: `docs/business/MONETIZATION_MODEL_V2.md`, `docs/implementation/GO_LIVE_CHECKLIST.md`, `docs/product/V1_SCOPE.md`

**Secondary (S)**
- TechCrunch, 2026-03-10: https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows
- Wikipedia, Epic Games v. Apple (partial): https://en.wikipedia.org/wiki/Epic_Games_v._Apple
- Search-result pages summarised by the search tool, listed inline above: Tabletowo, Android.com.pl, tl;dv, Antyweb, Spider's Web, Telepolis, Benchmark.pl, Chip.pl, GeekWire, tooldirectory.ai, saner.ai, layer3labs.io, tech-insider.org, aicompanionpick.com, dupple.com, adapty.io, ppc.land, Gibson Dunn, Usercentrics, Jones Walker, Legalithm, Certivo, CMS, PrivacyLaws, ElevenLabs docs and compound.law, TechRepublic, AA, mjtsai.com, PARP, xyz.pl, fin.ai, everythingstartups.com, creditforstartups.com, itwiz.pl, rp.pl, The Hustle, HubSpot, Fast Company, Xataka Movil.
