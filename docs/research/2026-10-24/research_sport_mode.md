# Sport mode: data sources, trainer knowledge, food and safety (24 Oct 2026)

Research for a possible "sport mode": Doddy rates workouts, writes running and gym plans (easy or goal-based), explains exercises like a personal trainer, and gives food advice that fits the person's day. **Nothing here is built.** Sources were checked on 2026-10-24 by two research agents in this session; the Strava policy and Apple's capability table were re-read by hand. Tags: **[V]** read on the source page, **[S]** secondary source, **[U]** could not be confirmed, **[I]** inference. Not legal or medical advice.

The owner's infographic of this research (Polish): `sport_mode_infographic.html` next to this file. Owner decisions: ADR-620.

## Main findings

1. **Strava's API cannot feed an AI coach.** The API Policy in force since 1 Jun 2026 forbids using Strava data "in connection with the development, training, evaluation, or operation of any AI Application", explicitly including "ingestion into a context window or working memory" (§5.3) [V, 1]. It also forbids analytics and insight generation (§5.4), anything "competitive to Strava" (§5.2), caching longer than 7 days (§6.2), any persistent index (§5.5), and intermediaries or third-party MCP servers (§5.16). The only AI route is Strava's own MCP, for subscribers' personal use only, "not authorized for … any commercial or third-party access" (§3.5) [V, 1]. Strava owns Runna (Apr 2025) [S].
2. **HealthKit is the primary source.** On the device, free, per-type permission, and it is where most watches already write: Garmin Connect, Strava, Polar, Suunto, COROS, Oura and WHOOP can each write workouts or sleep to Apple Health when the user turns that on [I, from each vendor's Health sync; not checked per vendor]. Reading HealthKit therefore covers most watches without their APIs. Whether Strava activities read through HealthKit fall outside the Strava API terms needs a lawyer [U].
3. **HealthKit works on a free (Personal) Apple team.** Apple's capability table marks HealthKit for ADP, ADEP and the free "Apple Developer" account [V, 2]. `project-iphone.yml` has no entitlements since 20 Oct, so the HealthKit entitlement would have to be added there.
4. **WorkoutKit (iOS 17+) puts Doddy's workouts on the Apple Watch** without a watch app: `CustomWorkout` intervals, single-goal, pacer and multisport; `WorkoutScheduler` syncs them into the Workout app under the app's icon, with the user's permission, up to `maxAllowedScheduledWorkoutCount` (value not documented) [V, 3].
5. **Other vendors restrict AI too.** Oura (agreement of 8 Jun 2026): no prompting an AI model with API data; LLM use only through Oura's MCP; aggregators may not pass Oura data to AI (§4(d), §2(c)) [V, 4]. Garmin: AI processing needs an AI transparency statement and explicit consent (read in one regional version of the agreement) [V/U]. COROS openly offers a self-serve MCP for "AI coaching apps" that reads data and writes workout plans [V, 5].

## Data sources

| Source | Data | Push workouts? | Access and cost | iOS effort |
|---|---|---|---|---|
| HealthKit | workouts and routes, HR, HRV, resting HR, VO2 max, sleep stages, steps, energy, running power/speed/stride, HR recovery, effort score (iOS 18), weight, nutrition | writes workouts and nutrition | free; App Review 5.1.3 | low |
| WorkoutKit | scheduled workouts on Apple Watch | yes | free | low to medium |
| Voice and files | sets, reps, loads (HealthKit has none), RPE, pain, goals; GPX/FIT via Save to Doddy | n/a | free | low |
| Strava | activities, streams, segments | completed uploads only; no plans | review above 10 athletes; **AI banned** | blocked for AI |
| Garmin | activities, health (FIT) | Training API to the Garmin Connect calendar | programme reopened 21 Oct 2026: Personal, Starter (business), Enterprise (paid; billing from 1 Apr 2027 [S]) | high (server, OAuth) |
| COROS | workouts, health | yes (MCP or Partner API) | MCP self-serve, one account; Partner API by application | low to medium |
| Polar AccessLink | exercises from the last 30 days, sleep | no | free, self-serve | medium |
| Suunto | workouts (FIT) | routes and completed FIT; plans [U] | businesses only, free, about 2 weeks review | high |
| Oura / WHOOP | sleep, readiness, HRV, strain | no | free; review above 10 users; Oura: AI only via its MCP | medium |
| Fitbit → Google Health API | health, activity | some writes | Fitbit Web API off 2 Nov 2026; restricted scopes and a CASA assessment [V, 6] | high |
| intervals.icu | activities, wellness | calendar workouts | free key; OAuth apps approved; never exposes Strava data | low to medium |
| TrainingPeaks | workouts, plans | yes | not accepting new API partners [V] | blocked |
| Aggregators (Terra, Junction, ROOK, Thryve, Spike) | many | Terra add-on only | about $300 to $999 a month [V/S]; another processor of health data; Strava §5.16 and Oura §2(c) shut them out of AI use | low to medium |

Every cloud API needs a backend to hold the OAuth secret and receive webhooks.

## Trainer knowledge to encode

- **WHO 2020:** adults 150–300 min moderate or 75–150 min vigorous activity a week, plus muscle strengthening on 2 or more days [V, 7].
- **ACSM 2026 resistance-training position stand** (MSSE 58(4)): every major muscle group twice a week; failure not required, 2–3 reps in reserve is enough; hypertrophy from about 10 sets per muscle per week. CC BY-NC-ND: paraphrase with a citation [V, 8].
- **Heart-rate zones:** Tanaka 208 − 0.7 × age, still about ±11–12 bpm off for an individual, so show ranges and prefer a measured max, RPE or the talk test [V, 9].
- **80/20:** a sensible default; meta-analysis shows a small advantage only [V, 10].
- **Run length:** Frandsen et al., BJSM 2025 (5,205 runners): risk rises when one run is more than 10% longer than the longest run of the previous 30 days; week-to-week change was not associated with injury [V, 11]. The weekly "10% rule" is weakly supported.
- **Load:** session-RPE × minutes (Foster). Do not use ACWR to predict injury [V, 12].
- **Paces from a race result:** Daniels and Gilbert's 1979 equations may be implemented under Doddy's own name; the book's tables and the VDOT name are not copied [S].
- **Beginner running:** model on NHS Couch to 5K (9 weeks, 3 runs a week, week 1 alternates 60 s running and 90 s walking) without NHS branding or audio [S].
- Copyrighted books (ACSM Guidelines, NSCA Essentials, Daniels' Running Formula): facts and numbers paraphrased with a citation only.

### Exercise databases

- **wger** (recommended): 932 exercises, 383 images, 78 videos; per-entry Creative Commons licences with author fields; open API without a key; AGPL code [V, 13]. Attribution must be shown.
- **free-exercise-db:** 800+ exercises with images, Unlicense code, image origin undocumented: risky for a paid app [V/U].
- **ExerciseDB:** 1,500 exercises with GIFs, no commercial licence stated: needs written permission [V].
- **API Ninjas:** text only free, no commercial use on the free tier [V]. **ExRx:** paid licence [V].
- Doddy himself in exercise poses only from the owner's pack (CLAUDE.md character-art rule); never generated.

## Food

- **Logging:** voice, barcode (Open Food Facts), photo as an editable range only. Written to HealthKit only after the person confirms (5.1.3(ii): no false data) [V].
- **Photo estimates are inaccurate:** about 36% mean energy error for GPT-4o and Claude 3.5 Sonnet, worse for larger portions (Fridolfsson 2025); 24–33% per meal in a 2026 feeding trial [V/S, 14].
- **Formulas:** Mifflin-St Jeor resting energy; FAO/WHO activity levels 1.40–2.40; protein 1.4–2.0 g/kg a day, 20–40 g a meal (ISSN 2017); water about 2.0 L (women) and 2.5 L (men) a day including food (EFSA 2010) [V, 15, 16].
- **Data:** Open Food Facts (ODbL; 38,424 products tagged Poland of 4.83 M, queried today) [V]; USDA FoodData Central (CC0, key kept off the client) [V]; Polish NIZP PZH-PIB tables are a book and PDF with no API or open licence [U]; FatSecret free tiers are US data only [V]; Edamam free developer tier, then from $69 a month [V].
- Competitors that log food with AI take the numbers from a curated database, not from the model (MacroFactor, Cronometer) [V].

## Safety and law (EU, Poland)

- **MDR:** wellness and lifestyle software is outside the medical-device rules (recital 19) while its intended purpose is not diagnosis, prevention, monitoring or treatment of disease or injury (Art. 2(1); MDCG 2019-11 rev.1). Never claim "rehab your knee", "detect arrhythmia", "predict injury risk" or "manage diabetes" [V, 17].
- **GDPR Art. 9:** heart rate, HRV, sleep, weight, injuries, pregnancy and diet are health data: explicit consent, a DPIA, easy withdrawal. Polish age of digital consent 16 [V/S, 18].
- **AI Act:** a fitness coach is not high-risk on its own; Art. 50 transparency (say it is an AI) applies since 2 Aug 2026 [V/S, 19].
- **App Store:** 1.4.1 (methodology behind accuracy claims, advise seeing a doctor), 5.1.2(i) (disclose and get permission before sending personal data to third-party AI), 5.1.3 (no ads or data mining with health data, no false HealthKit data, no health data in iCloud) [V, 20].
- **PAR-Q+ is copyrighted** [V]; ACSM 2015 screening logic can be implemented instead [V].
- **Cautionary case:** NEDA's "Tessa" chatbot was taken down in 2023 for giving weight-loss advice to people with eating disorders [V, 21].

### Rules to enforce in code (not only in the prompt)

1. Red flags (chest, neck, jaw or arm pain; fainting; dizziness; unusual breathlessness; palpitations) give a fixed "stop now; in an emergency call 112" message and end the sport session. The model cannot change it.
2. Screening before any plan above light intensity; any "yes" means "see a doctor first".
3. No target below resting energy or 800 kcal; deficit at most about 500 kcal a day; no weight loss under BMI 18.5.
4. Eating-disorder cues switch off calorie and weight targets.
5. Under 18: no deficit or maximal loads; under 16 parental consent. Pregnancy: WHO-level guidance and "ask your doctor or midwife" only.
6. Injuries: no diagnosis or rehab; refer to a physiotherapist or doctor.
7. One run at most 10% longer than the longest of the last 30 days; about 80% easy; no injury-risk percentages.
8. Load goes up only after sessions completed with 2–3 reps in reserve.
9. Estimates shown as ranges; "logged" only after a verified write (constitution: never claim a write that did not happen).
10. Say it is an AI and not medical advice; explicit consent before health data leaves the phone.

## Competitors (short)

Fitbit + Gemini personal health coach (preview, expanded to 37 countries including Poland in Apr 2026; full version in Premium) [V, 22]; Runna ($19.99 a month, Strava-owned) [S]; Strava Athlete Intelligence [S]; Apple Workout Buddy (watchOS 26, English at launch) [V]; Garmin Connect+ ($6.99 a month) [S]; WHOOP Coach and Oura Advisor (in the membership) [V]; Fitbod (algorithmic, $15.99 a month) [S]; MacroFactor and Cronometer (AI logging over curated data) [V]; MyFitnessPal bought Cal AI (announced 2 Mar 2026) [V]. Common pattern: numbers from databases and deterministic engines; the model explains and motivates.

## Paths

- **A. Apple first (owner chose this, ADR-620):** HealthKit, WorkoutKit and voice. No server for the data, free, covers most watches through Apple Health. Loses vendor-only detail (Garmin training load, Strava segments).
- **B. A + Garmin and COROS directly:** plans on those watches; needs a server with OAuth, Garmin's business application and AI consent.
- **C. Aggregator:** fastest multi-vendor route; $300–999 a month, a further health-data processor, and still no Strava or Oura for AI.

Suggested order for A (each a small change with tests; a new milestone, so it needs the owner's go-ahead before any code): HealthKit permissions and reads with a "what Doddy can see" screen → "How did it go?" and a weekly summary (numbers computed in code) → voice gym log and wger exercises → running and strength plans with the rules above → WorkoutKit and calendar after a yes → food (tips by default, counting calories and protein only after the person turns it on and passes the check; ADR-620) → extras (readiness from HRV and sleep, Garmin/COROS, photo estimates, live coaching in headphones).

## Sources

1. Strava API Policy (effective 1 Jun 2026): https://www.strava.com/legal/api_policy ; Agreement: https://www.strava.com/legal/api ; limits: https://developers.strava.com/docs/rate-limits/
2. Apple supported capabilities (iOS): https://developer.apple.com/help/account/reference/supported-capabilities-ios/
3. HealthKit: https://developer.apple.com/documentation/healthkit ; privacy: https://developer.apple.com/documentation/healthkit/protecting-user-privacy ; WorkoutKit: https://developer.apple.com/documentation/workoutkit ; WWDC26 zones: https://developer.apple.com/videos/play/wwdc2026/207/
4. Oura API agreement: https://cloud.ouraring.com/legal/api-agreement
5. COROS MCP: https://support.coros.com/hc/en-us/articles/53181619102996-Build-on-COROS-MCP ; Garmin: https://developer.garmin.com/gc-developer-program/overview/ and /training-api/
6. Google Health API: https://developers.google.com/health/about
7. WHO 2020: https://pmc.ncbi.nlm.nih.gov/articles/PMC7719906/
8. ACSM 2026: https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823
9. Tanaka: https://pubmed.ncbi.nlm.nih.gov/11153730/
10. Polarized meta-analysis: https://pmc.ncbi.nlm.nih.gov/articles/PMC11329428/
11. Frandsen 2025: https://doi.org/10.1136/bjsports-2024-109380
12. ACWR critique: https://iris.univr.it/handle/11562/1139126
13. wger: https://github.com/wger-project/wger
14. Photo estimates: https://pmc.ncbi.nlm.nih.gov/articles/PMC12513282/
15. ISSN protein: https://doaj.org/article/fcc34534a75d466aa37abda0042df7a7
16. EFSA water: https://www.efsa.europa.eu/pl/press/news/nda100326
17. MDR: https://eur-lex.europa.eu/eli/reg/2017/745/oj
18. GDPR: https://eur-lex.europa.eu/eli/reg/2016/679/oj
19. AI Act: https://eur-lex.europa.eu/eli/reg/2024/1689/oj
20. App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
21. Tessa: https://www.npr.org/2023/06/08/1181131532/eating-disorder-helpline-takes-down-chatbot-after-it-gave-weight-loss-advice
22. Fitbit coach expansion: https://blog.google/products-and-platforms/devices/fitbit/fitbit-personal-health-coach-expansion/
