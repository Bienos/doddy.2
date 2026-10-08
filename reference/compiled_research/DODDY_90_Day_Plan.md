# DODDY | 90-day validation operating plan
**Starting 9 October 2026. All numeric acceptance levels are provisional founder decision thresholds, NOT published category benchmarks.**

## Core question
Do unfamiliar adults voluntarily complete a useful real task with Doddy, return without prompting, and pay enough to cover expected service costs — *and is the character measurably improving that path?*

| Experiment | Days | Hypothesis | Sample and implementation | Primary measures | Decision rule / what it tells us | Incremental cash budget |
|---|---|---|---|---|---|---|
| 1. Need discovery | 1–14 | Target users experience repeated small memory/follow-through failures | 15–20 users aged 18–34 recruited outside personal network; 5-day micro-diary, actual recent episodes | Count of weekly repeated relevant problems, current workaround, problem intensity | Continue wedge if 10+ describe a real recent recurring problem *and* at least 5 show workaround cost; otherwise replace wedge | $100–400 incentives |
| 2. Recognition | 10–35 | Doddy is identifiable beyond one-off viral exposure | 15–24 shorts, 3 repeatable formats; 30-person blinded recognition survey vs similar stick figures | Returning viewers, recognition after 7 days, audience age signal | Continue selected style if 60%+ aided and 25%+ unaided recognition in exposed panel; modest precision | $500–1,500 |
| 3. Content-format A/B | 15–42 | Showing a *real task* performs better for software demand than pure comedy | Publish 6–8 each: entertainment-only, task-demo, direct no-character explainer; track tagged URLs; rotate hooks & schedule | Qualified product clicks per 10,000 impressions, adult waitlist completion | Choose content by quality-tagged installs, not raw views. Reject formats with high views but near-zero clicks | $400–1,500 |
| 4. Interest / intent | 15–45 | People want their own Doddy rather than just footage | Landing page to genuine working demo + age-screen; no fake countdown; 200+ qualified page visitors target | Click→demo-start, demo task completion; segmented by story source | Promote top funnel only if ≥20% of visitors try the demo; decision rule, not statistical benchmark | $100–400 |
| 5. Actual task activation | 30–65 | New users can save and later retrieve successfully | 50–100 consenting adult outsiders on TestFlight; two scripted + one free task; human-verified receipts | Meaningful completion within first 48h, false success, retrieval correctness | Go if ≥60% complete first meaningful task and critical unauthorized actions = 0; fix failures before launch | $500–2,000 |
| 6. Character-value A/B | 36–75 | Animation/voice increases repeat use *without* slowing useful tasks | Random assignment on first install if feasible: full Doddy vs low-animation neutral utilitarian UI, same model/actions | Return rate by variant, completed tasks/returning person, task time, annoyance rating | If character doesn't help, keep for marketing but make task mode minimal | $200–1,000 |
| 7. Retention / utility | 45–90 | A material share returns intentionally to solve a new problem | Analyze eligible activated cohorts at D1/D7; only cohorts with 30 days followup for D30; qualitative exits | D7/D30 return, real useful sessions per week, memory corrections, reminder acknowledgment | Initial rule: ≥25% D7 and ≥12% D30 among activated outsiders, with ≥2 useful actions weekly among retained; small-N uncertainty | $400–1,000 |
| 8. Real willingness-to-pay + voice margin | 65–90 | Pricing and usage produce positive contribution | Real subscription offer / genuine allowed checkout, transparent beta service terms; use split $7.99/$9.99 tiers if exposure sufficient | Completed purchases, refund requests, per-user voice min/day, cost per completion and 14-day paid return | Need ≥10 actual unrelated payers, no severe negative contribution by expected usage tier and no unresolved safety issues. Too few => no scale inference | $100–500 |

**Budget logic.** Direct experimental costs across rows may be $2,300–$8,300; add contingency, review and specialist privacy/security support to remain inside suggested **$5–15k** total *cash* cap if existing prototype is usable. Does not include unpaid founder work, the value of developers' time or a legal opinion fee. Any full contracted build is outside this validation budget.

## Weekly operating rhythm

**Week 1:** instrument events; privacy/age disclaimers; interviews and storyboard template. **Week 2:** need diaries, production pilots, pre-register targets. **Week 3:** publish 4–6 pieces, landing/demo instrumentation. **Week 4:** compare branded/unbranded creatives; recruiting outreach. **Week 5:** beta onboarding to non-friends, task success tests. **Week 6:** test character-rich vs reduced-motion utility UI. **Week 7:** fix top failure modes, monitor save/retrieve reliability. **Week 8:** monitor returns, record reasons for deletion and incorrect memories. **Week 9:** implement transparent paid offer with actual caps. **Week 10:** no new features; stabilize privacy, cost/latency and retention tracking. **Week 11:** audit paid cost and audience source; widen only supported variants. **Week 12–13:** analyze matured D30 cohorts, safety findings, produce GO/PIVOT/STOP decision memo.

## Event specification for the prototype

`acquisition_source`, `content_series`, `creative_id`, `age_eligibility_confirmed`, `landing_view`, `install`, `onboard_complete`, `first_meaningful_task`, `memory_save_approved`, `memory_recall_verified`, `reminder_created_approved`, `reminder_completed`, `manual_memory_correction`, `voice_minutes_used`, `AI_cost_allocated`, `session_return_D7`, `session_return_D30`, `checkout_shown`, `checkout_completed`, `refund`, `data_export`, `account_delete`.

Avoid collecting raw sensitive transcript contents in analytics. Establish appropriate processing basis and tracking consent. Use random session/pseudonymous identifiers and honor deletion requests.

## Pre-registered dashboards

**Character**: 7-day returning viewers; direct search lift; qualified adult clicks per 10k impressions; cost per repeat viewer. **Product**: activated installs; verified task outcomes; D7/D30 among cohort-complete activated adults; median/90th-percentile task latency; recalled-memory correctness; number of important errors. **Money**: real new paid users per 1k installs, net-of-store receipts, variable API cost per active free/paid user, paid churn when measurable, acquisition spend per activated person. **Guardrails**: age-gate failures, dependency signals, unintended external actions, privacy deletion/export failures.

## Stop rules

Immediate safety hold for unauthorized external actions, disclosure/permission violations, significant exposure of private data or serious unresolved teen-safety failures. Commercial **PIVOT** if character content works but 50+ outsider beta users rarely use practical features again. Commercial **STOP** if after a single focused correction cycle both repeat meaningful action and real paid intent remain absent, or if gross paid per-user contribution is negative at a price users accept. **GO** only for limited beta, not a claim of proven general-market PMF.

## Interpretation warning

At n=100 and a 12% observed D30 retention, the binomial confidence interval is broad; a single short beta cannot distinguish modest changes reliably. All stated thresholds are *decision heuristics* that should guide whether to spend more, not empirical constants of a new market.
