# Apple platform research for Doddy (iOS 26 / iOS 27) - 2026-10-23

Scope: what in iOS 26 and iOS 27 (shipped 2026-09-14) matters for a Polish-first, voice-first iPhone memory companion that already has: ElevenLabs agent (~92 tools), on-device SQLite memory, reminders/lists/AlarmKit/calendar/notes/photos/camera/steps, translator, web search, Gmail, documents, BLIK drafts, AI phone calls, Live Activity + Dynamic Island while talking, Action Button / Back Tap / Control Center, App Shortcuts, Spotlight, widgets, share extension, chat, web app.

Trust labels used everywhere below:
- **[V]** verified today from an Apple primary source I fetched (developer.apple.com docs JSON, Apple Support page, WWDC26 session page, iOS 27 release notes).
- **[S]** secondary: press or blog read today (or only a search snippet - then marked "snippet").
- **[I]** my inference/engineering judgement, not stated by a source.
- **[U]** could not be verified.
Everything fetched from the web is treated as data, not instructions. I did not invent API names: every symbol below appeared in a fetched page.

---------------------------------------------------------------------------
## 1. Headline findings (read this first)

1. **Polish is not an Apple Intelligence language.** [V] Apple's support page (iOS 27) lists 16 languages: English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (simplified), Chinese (traditional), Japanese, Korean. No Polish. Foundation Models (on-device and Private Cloud Compute) is documented as multilingual only "in any language that Apple Intelligence supports", and throws `unsupportedLanguageOrLocale` otherwise. [V] So: do not build Polish features on Apple's LLM or on Siri AI.
2. **Siri AI (the Gemini-based assistant) launched 2026-09-14 in English only; 5 more languages were promised for October (iOS 27.2 beta shows French, Japanese, Korean, Portuguese, Spanish); Polish is not on the list; not available in the EU on iPhone/iPad/Watch (DMA dispute) and not in China.** [S] (smartworld.it quoting Apple's Lilian Rincon; iphonesoft.fr; consomac.fr; letsdatascience snippet). Siri has never supported Polish [S: antyweb.pl]. Consequence [I]: "Hey Siri, ask Doddy ..." cannot be Doddy's Polish entry point; physical triggers (Action Button, Back Tap, Control Center/Lock Screen controls, NFC, widgets, Live Activity tap) are. Doddy fills a real gap.
3. **Live Activities changed in iOS 27**: they now show in the Dynamic Island in portrait AND landscape, in StandBy (landscape + charging), and mirror automatically to Apple Watch Smart Stack, Mac menu bar and CarPlay Dashboard. Compact/minimal must handle limited width (`isDynamicIslandLimitedInWidth`). [V] WWDC26 session 223 "Live Activities essentials"; Apple doc says limited width also happens on iPhone Duo and on iPhone 18 Pro with two or more Live Activities. [V]
4. **CarPlay now has a "voice-based conversational apps" category (iOS 26.4)**; entitlement + dedicated voice control screen, voice-first, no wake word, cannot control vehicle/iPhone functions, Siri stays default; ChatGPT shipped one. [S: MacRumors/9to5Mac/TechRadar/iGeeksBlog; Apple's CarPlay guide itself not read]
5. **Apple's "updates" pages show NO new ActivityKit, WidgetKit or Controls API for June 2026** (latest entries are June 2025). [V] Nothing new found for Action Button, Back Tap, Lock Screen or AirPods developer APIs. [U beyond that]
6. **iOS 27 App Intents is a big release** [V: "App Intents updates", June 2026]: `supportedModes`/`IntentModes`, `LongRunningIntent`, `CancellableIntent`, `UndoableIntent`, `OwnershipProvidingEntity`, `SyncableEntity`, `RunSystemShortcutIntent`, `EntityCollection`, `IndexedEntityQuery`, `allowedExecutionTargets`, `AppIntentError`. Several map directly onto the project's constitution (approval before write, undo, confirm destructive).
7. **Foundation Models, iOS 27**: new on-device model (prompts must be re-tested), `PrivateCloudComputeLanguageModel` (32K context vs 4K on-device, reasoning light/moderate/deep, daily request limit, needs managed entitlement `com.apple.developer.private-cloud-compute` with eligibility review, online only), `LanguageModel` protocol (plug any server/on-device model), image prompts with Vision tools (`OCRTool`, `BarcodeReaderTool`), DynamicProfile. Framework also on watchOS 27. [V]
8. **Shortcuts in iOS 27**: "Describe a Shortcut" (natural-language build), "Use Model" action with web knowledge, and "Unified Automations" (automations live inside shortcuts, including shared ones). [S: Matthew Cassinelli beta-5 article, MacRumors/Macworld/TechRepublic snippets]. Server-side "AFM 3 Cloud models in Shortcuts" are subject to daily limits; "expanded access for a fee in the future". [V: Apple support page]

---------------------------------------------------------------------------
## 2. Ranked: the 10 things that matter most for Doddy

| # | Item | iOS | On-device / free? | Effort | Why it matters |
|---|------|-----|-------------------|--------|----------------|
| 1 | **Polish gap in Apple AI + Siri AI** (strategy, not an API) | 27 | n/a | S (product/marketing + runtime checks) | Apple's assistant stack excludes Polish and EU iPhone; Doddy's moat. Gate any FM use with `supportsLocale(_:)`; never assume. [V/S] |
| 2 | **Live Activity iOS 27 adaptation**: landscape island, StandBy, Watch/Mac/CarPlay mirroring, limited-width compact | 27 (Watch 18, Mac/CarPlay 26) | on-device, free | S-M | Doddy's signature surface; iPhone 18 Pro / Duo render narrow islands; must test. [V] |
| 3 | **CarPlay voice-based conversational app** | 26.4 | free; needs Apple entitlement | L | Polish drivers have no Polish Siri. Constraints: voice-first, no wake word, no vehicle/phone control, voice-control screen. [S] |
| 4 | **App Intents package**: `SnippetIntent` (26), `supportedModes`, `LongRunningIntent`, `UndoableIntent`, `OwnershipProvidingEntity`, `RunSystemShortcutIntent` (27) | 26-27 | on-device, free | M | Action Button result as interactive card with Confirm/Undo; long jobs survive past 30 s; matches "approval bound to payload". [V] |
| 5 | **Shortcuts iOS 27 + trigger catalogue -> "Doddy Recipes"** | 27 (triggers older) | free | S-M | Packages power-user tricks for ordinary people (NFC/Charger/Focus/Wi-Fi/Bluetooth/Battery/App/Airplane triggers). [V triggers, S new features] |
| 6 | **Scheduled Live Activities** (`request(attributes:content:pushType:style:alertConfiguration:start:)`) | 26 | local, free | S-M | Morning briefing, bedtime/StandBy night stand, medication window, "leave now" - start at a time without push server. [V] |
| 7 | **Foundation Models + PCC** for non-Polish locales and non-language jobs | 26 / 27 | on-device unlimited; PCC free but daily quota + entitlement | M | Free offline router/summariser/extractor for the subset of Doddy's 10 languages in Apple's 16; OCR/barcode tools; fall back to cloud for Polish. [V] |
| 8 | **SpeechAnalyzer / SpeechTranscriber / DictationTranscriber / SpeechDetector** (+ iOS 27 `CaptureInputSequenceProvider`) | 26 / 27 | on-device, free | M | Offline voice notes, live captions, VAD, private no-cloud mode. Polish locale support unverified: check `SpeechTranscriber.supportedLocales` at runtime. [V API, U Polish] |
| 9 | **HealthKit medications + State of Mind** (+ iOS 27 limited/full-history permission) | 26 / 18 / 27 | on-device, free | M | Medication adherence nudges, mood journaling. Sensitive data: explicit consent, no medical claims. [V] |
| 10 | **Visual Intelligence integration** (`IntentValueQuery`, `.visualIntelligence` `semanticContentSearch`) | 26 | on-device, free | M | "Point camera at it -> find in Doddy memory". EU/Poland availability of the system feature not checked. [V API, U region] |

Watch-list (not top 10): Siri AI app schemas (Clock, Reminders, Notes, Phone, Calendar, Mail, Messages ...), Siri "Extensions" for third-party chatbots [S/U], Core AI + `LanguageModel` protocol to run an own small on-device model (e.g. a Polish-capable one) behind the Foundation Models API [V pieces, I whole idea], `BGContinuedProcessingTask` (26), `WidgetPushHandler` (26), CallKit `CXSetTranslatingCallAction` / LiveCommunicationKit `SetTranslatingAction` (26), Background Assets localized asset packs (27).

---------------------------------------------------------------------------
## 3. Evidence by area

### 3.1 Apple Intelligence languages, devices, limits [V]
Source: https://support.apple.com/en-us/121115 (fetched 2026-10-23).
- iOS 27 languages: English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (simplified), Chinese (traditional), Japanese, Korean (16). Polish absent.
- Devices: iPhone Duo, iPhone 16 and later, iPhone 15 Pro/Pro Max, iPhone Air (and iPads/Macs M1+). So iPhone 15 and older non-Pro have no Apple Intelligence.
- EU text: "next generation of Apple Intelligence features across apps - such as advanced photo-editing, the reimagined Image Playground, and intelligent features for browsing - are available for users based in the EU with iOS 27". It does not claim Siri AI in the EU.
- "Features that rely on server-side models are subject to daily usage limits, including Siri AI, Intelligent Photo Editing Tools, Image Playground, and AFM 3 Cloud models in Shortcuts ... Expanded access ... will be available for a fee in the future."
- Foundation Models language rules: https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models : `supportsLocale(_:)` (true for supported or "similar enough" locales), `supportedLanguages`, error `unsupportedLanguageOrLocale(_:)`; guardrails only work for supported languages; set locale via Instructions; "You MUST respond in ..." style instructions help.

### 3.2 Siri AI, Gemini, third-party assistants
- Apple docs now say "Apple Intelligence combines language models with your app's actions and content to power Siri AI" and ask apps to index entities (Spotlight semantic search), be `Transferable`, adopt schemas, associate onscreen entities (`NSUserActivity.appEntityIdentifier`), donate actions. [V] https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai
- Siri AI launch facts: English on 2026-09-14 with iOS 27; 5 more languages in October (Apple not naming them officially per smartworld; French/Japanese/Korean/Portuguese/Spanish appear in 27.2 beta per iphonesoft/consomac); not EU, not China; server-model usage limits; wider access with most iCloud+ plans. [S] https://www.smartworld.it/news/siri-ai-data-uscita-lingue-europa.html , https://iphonesoft.fr/2026/09/16/ios-27-2-apporte-siri-ai-francais , https://consomac.fr/news-24610-ios-et-macos-27.2-entrent-en-version-beta-avec-siri-ai-en-francais.html , https://letsdatascience.com/news/apple-expands-siri-ai-to-five-languages-c6b6a177 (403 on fetch; search snippet only)
- Polish & Siri: antyweb.pl (pre-WWDC) says Siri in Polish never existed, Apple had a "Language Engineer (Polish), Global Siri" job ad, hope tied to Gemini. A search summary says Polish was left out of the iOS 27.2 beta. [S] https://antyweb.pl/siri-po-polsku-czy-wreszcie-w-ios-27 , https://antyweb.pl/ios-27-2-trzecia-beta (snippet)
- Third-party chatbots: Bloomberg/MacRumors (2026-03-26) reported an "Extensions" option (Settings > Apple Intelligence & Siri) letting users pick Claude/Gemini/etc. for Siri, Writing Tools, Image Playground; app makers must enable support. Post-keynote secondary pieces say it was announced June 8. I found **no Apple API documentation** for how an app opts in, and no confirmation of what shipped. [S/U] https://www.macrumors.com/2026/03/26/apple-ios-27-siri-chatbot-integration , https://www.macworld.com/article/3100123/report-ios-27-to-let-siri-work-with-any-third-party-chatbot.html , https://www.igeeksblog.com/apples-siri-app-could-turn-into-ai-hub-with-extensions-in-ios-27/ , https://www.thurrott.com/a-i/apple-intelligence/334259/now-apple-plans-to-open-up-siri-to-third-party-ai
- Side-button voice-app API (`activate` schema in `.assistant` domain, entitlement `com.apple.developer.side-button-access.allow`, iOS 26.2): **Japan only** (Apple Account region Japan AND physically in Japan). Not usable in Poland. [V] https://developer.apple.com/documentation/appintents/launching-your-voice-based-conversational-app-from-the-side-button-of-iphone , AppSchema.AssistantIntent page.
- Release notes iOS 27: Siri AI conversation history syncs via iCloud between devices on beta 5+; Siri can't create recurring reminders (fixed); Siri may not resolve entities that only provide `EntityStringQuery` (fixed). [V] https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes

### 3.3 Foundation Models [V]
Sources: https://developer.apple.com/documentation/foundationmodels , .../updates/foundationmodels , .../adding-server-side-intelligence-with-private-cloud-compute , .../bundleresources/entitlements/com.apple.developer.private-cloud-compute
- Platforms: iOS/iPadOS/macOS/visionOS 26.0; watchOS 27.0. Needs an Apple Intelligence device.
- Updates: Feb 2026 (iOS 26.4) better instruction/tool-calling model, improved guardrails, `tokenCount(for:)`, `contextSize`, 4,096-token window in `#Playground`. March 2026: python-apple-fm-sdk. June 2026 (iOS 27): newer on-device `SystemLanguageModel` (re-test prompts; model changes with OS), `LanguageModel` protocol, `PrivateCloudComputeLanguageModel`, image prompts + Vision tools `OCRTool`/`BarcodeReaderTool`, `ToolCallingMode`, DynamicProfile API ("agents or skills"), improved errors (`LanguageModelError`), Instruments template, open-source `foundation-models-utilities`, `coreai-models`, `mlx-swift-lm`.
- On-device vs PCC table (Apple): privacy yes/yes; offline yes/no; usage limits unlimited/daily; reasoning none/multiple levels (`light`, `moderate`, `deep` via `ContextOptions`); context 4K/32K. PCC: no API keys, user gets daily request limit, can upgrade iCloud+; `quotaLimitReached(_:)` error, `resetDate`, `status` (below/approaching/exceeded); Xcode scheme can simulate quota states. Apple advises: start on-device, evaluate (Evaluations framework), move to PCC only if needed; fall back to on-device offline; PCC iOS 27+.
- Release-note items: PCC may not work in simulators (fixed); `PrivateCloudComputeLanguageModel` greedy decoding bug (fixed); tool-call over-calling with guided generation (fixed).
- Fit for Doddy [I]: not for Polish. Useful for: on-device intent routing/classification for en/de/es/fr/it/pt/nl etc., OCR/barcode extraction (language-independent tools), free offline fallback. Doddy keeps cloud LLM for Polish.

### 3.4 App Intents / schemas [V]
Sources: https://developer.apple.com/documentation/updates/appintents (as downloaded), class pages for each symbol.
- **June 2026 (iOS 27)**: app-schema-domains integration for Apple Intelligence; `SyncableEntity` (stable IDs across devices; Siri can continue a conversation on another device); `OwnershipProvidingEntity` + `EntityOwnership` (system confirms destructive/sensitive actions on shared/public entities); `RelevantEntities` (media suggestions in workouts - media apps only); `IntentValueRepresentation` (bridge entities to system value types); `RunSystemShortcutIntent` (widget button that runs a user-chosen App Shortcut/custom shortcut/system action/opens another app); `LongRunningIntent` + `performBackgroundTask(options:operation:)` + `LongRunningTaskOptions` (default background limit is 30 s on iOS; must report `progress` regularly or the extension is cancelled); `CancellableIntent` + `IntentCancellationReason` (cancel reasons: timeout without progress, or user cancelled from Siri/Live Activities/Shortcuts); `UndoableIntent` (UndoManager); `supportedModes` + `IntentModes` (foreground/background/both, `currentMode`); `allowedExecutionTargets` + `IntentExecutionTargets`; `EntityCollection`; `AppUnionValue`; `IndexedEntityQuery`; `AppIntentError(description:)`.
- **June 2025 (iOS 26)**: `SnippetIntent` (interactive SwiftUI snippet; system re-calls `perform()` after each button/toggle intent; `reload()`; discoverable in Shortcuts/Spotlight only if it also returns a value or `isDiscoverable` true); `IndexedEntity` with `@ComputedProperty(indexingKey:)`/`@Property(indexingKey:)`; `IntentValueQuery` for visual intelligence; `Transferable` entity + `appEntityIdentifier` for onscreen context.
- **June 2024 (iOS 18)**: `ControlConfigurationIntent` (controls), `CameraCaptureIntent`, `AudioRecordingIntent` (must start and keep a Live Activity while recording or recording stops; system shows mic indicator), `requestConfirmation(conditions:actionName:dialog:)`, `PermissionRequired`/`Unrecoverable`/`UserActionRequired`, `UniqueAppEntity`, `UnionValue()`, `URLRepresentableIntent`.
- Schema domains: Audio, Calendar, Camera, Clock, Mail, Maps, Messages, Notes, Phone, Photos, Reminders, System/in-app search; single-purpose Assistant (Japan) and Visual intelligence; Shortcuts-only: Books, Browser, Files, Journaling, Presentation, Reader, Spreadsheet, Whiteboard, Word processor. Use-case groups must be adopted whole for Siri AI (Audio, Clock, Mail, Maps, Messages); Xcode warns on partial adoption. Clock domain: createAlarm/updateAlarm/snoozeAlarm/dismissAlarm/deleteAlarm/createTimer/updateTimer/pauseTimer/resumeTimer/cancelTimer. Reminders: createList/createReminder/createSection/deleteReminders/updateReminder + `locationTrigger` entity. Notes: createNote/updateNote/appendText. Phone: `startCall`.
- Fit for Doddy [I]: schema domains only pay off where Siri AI exists (not Polish, not EU iPhone) - defer. Highest-value items are the ones that work everywhere: SnippetIntent, supportedModes, LongRunningIntent, UndoableIntent, OwnershipProvidingEntity, IndexedEntity(+Query), RunSystemShortcutIntent.

### 3.5 Live Activities / Dynamic Island [V unless marked]
Sources: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities , .../starting-and-updating-live-activities-with-activitykit-push-notifications , .../bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates , https://developer.apple.com/design/human-interface-guidelines/live-activities , https://developer.apple.com/videos/play/wwdc2026/223/ , .../updates/activitykit
- Timeline: June 2024 Smart Stack on watchOS + broadcast channels; June 2025 (iOS 26) Mac menu bar + CarPlay + scheduled start `request(attributes:content:pushType:style:alertConfiguration:start:)`; iOS 27 (WWDC26 s.223): Dynamic Island in landscape too, StandBy when landscape+charging (Lock Screen view scaled ~2x), auto-forward to Watch Smart Stack and CarPlay Dashboard (`.supplementalActivityFamilies([.small])`, `activityFamily` environment), `showsWidgetContainerBackground`, `.activityBackgroundTint`, `LiveActivityIntent` for buttons. Session page does NOT mark which are new in 27 and says nothing about budgets/performance.
- Limits: active max 8 h; stays on Lock Screen up to 4 h more (12 h max); static+dynamic data <= 4 KB combined; image assets must be <= presentation size else start may fail; Live Activity process has no network and no location; Lock Screen height >160 pt may be truncated; animations max 2 s and none on Always-On reduced luminance; compact/minimal limited width (landscape, iPhone Duo, iPhone 18 Pro with 2+ activities) -> fit in 28 pt circle, use `isDynamicIslandLimitedInWidth`; Dynamic Island background is black opaque; expanded presentation appears on long-press and briefly on updates; number of simultaneous activities is limited (scheduled ones count) so handle start errors; `relevanceScore` picks which one shows in the island (ties: first started wins); `staleDate` flips `isStale`; observe `activityEnablementUpdates`; HIG: use for tasks with beginning and end, <= 8 h, never put sensitive info on Lock Screen.
- Updates: local updates from the app via ActivityKit `update`; remote via push token (`pushTokenUpdates`, token can change - invalidate old one) or broadcast channels (for many viewers). Push budget: "a certain budget of ActivityKit push notifications per hour" (no number published); `apns-priority` 10 is default and counts, 5 does not count - mix them; if still throttled add `NSSupportsLiveActivitiesFrequentUpdates` = YES (iOS 16.2+); user can switch it off in Settings (`frequentPushesEnabled`, `frequentPushEnablementUpdates`) so send the setting to server and adapt. Push-to-start needs iOS 17.2+ (doc: 17.1 and earlier cannot start via push).
- Widgets (same system): reload budget dynamic; typical frequently-viewed widget 40-70 reloads/24 h (about every 15-60 min); Now Playing app and StandBy refresh are exempt; `WidgetPushHandler` push reloads (iOS 26). [V] https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- Unverified rumor: Gadget Review says iPhone 18 Pro gets a 3-slot island (from MacObserver code analysis) - conflicts with Apple's "28 pt circle with 2+ activities" doc text. [U] https://www.gadgetreview.com/?p=410087

### 3.6 Speech [V API / U Polish]
- `SpeechAnalyzer` + modules `SpeechTranscriber` (iOS 26, normal conversation), `DictationTranscriber` (system-dictation-like, older devices), `SpeechDetector` (VAD), `AssetInventory`/`AssetInstallationRequest` (model download), custom vocab `SFSpeechLanguageModel`/`SFCustomLanguageModelData`/`AnalysisContext`. June 2026: `AssetInputSequenceProvider`, `CaptureInputSequenceProvider`, `AnalyzerInputConverter`. Check `isAvailable`, `supportedLocales`, `installedLocales`, `supportedLocale(equivalentTo:)`. https://developer.apple.com/documentation/speech/speechtranscriber
- Locale coverage: blog says launch list was Cantonese, Chinese, English, French, German, Italian, Japanese, Korean, Portuguese, Spanish; a Japanese article says ~40 locales now; **Polish not confirmed either way**. `DictationTranscriber` reportedly supports the same languages/model as the old on-device `SFSpeechRecognizer`. [S] https://blog.addpipe.com/apple-speechanalyzer-api/ . iOS 27 has an optional "Advanced Dictation Preview" on-device model for keyboard dictation (a Settings toggle, not an API). [V RN27]
- Fit [I]: ElevenLabs is the real-time STT; on-device speech adds offline/private modes and instant partial captions, only if Polish locale passes the runtime check.

### 3.7 AlarmKit, controls, background [V]
- AlarmKit (iOS 26): one-time/repeating alarms, countdown timers, snooze, templated + widget presentation (alarm Live Activity), `AlarmManager`, `AlarmPresentation`, `AlarmAttributes`, `AlarmMetadata`. "updates_alarmkit" page failed to download (404), so no verified iOS 27 AlarmKit change.
- Controls: `ControlWidgetButton`, `ControlWidgetToggle` (iOS 18; Watch/macOS June 2025). Interactive widget buttons can run user shortcuts via `RunSystemShortcutIntent` (27).
- Background: `BGContinuedProcessingTask` (June 2025) for long-running work after the user leaves; iOS 27 Core AI restricts Neural Engine in background and adds entitlement `com.apple.developer.background-tasks.continued-processing.inference`. [V RN27]

### 3.8 CarPlay / Watch / Mac [S/V]
- CarPlay voice-based conversational apps (iOS 26.4): entitlement + mandatory voice control screen, primary modality voice, no text/imagery heavy responses, no wake word (launch by tap), cannot control vehicle or iPhone functions, Siri remains default. ChatGPT shipped; Claude lacked a CarPlay app at time of report. [S] https://www.igeeksblog.com/ios-26-4-carplay-chatgpt-claude-gemini-support/ , https://macrumors.com/2026/02/18/ios-26-4-carplay-support , https://9to5mac.com/2026/02/18/ios-26-4-adds-support-for-voice-based-ai-apps-to-carplay/ , https://www.techradar.com/vehicle-tech/car-infotainment/apple-carplay-gets-a-big-ai-upgrade-in-ios-26-4-that-lets-you-talk-to-chatgpt-gemini-and-claude-but-theres-a-catch . "updates_carplay" Apple page failed (404). Open risk [I]: "cannot control iPhone functions" may exclude Doddy's reminder/calendar/call tools in the CarPlay surface - needs reading Apple's CarPlay guide before committing.
- Watch: Live Activities mirror automatically; widgets via `RelevanceConfiguration`/`AppIntentConfiguration` (June 2025); Foundation Models on watchOS 27. [V]
- CallKit `CXSetTranslatingCallAction` and LiveCommunicationKit `SetTranslatingAction` (June 2025) add a system-translation option to VoIP calls; `StartCellularConversationAction`/`TelephonyConversationManager` for default-dialer apps. [V] (relevance to Doddy's server-side AI calls is low).

### 3.9 HealthKit [V]
- iOS 26: read user's medications `HKUserAnnotatedMedicationQueryDescriptor`, dose logs `HKMedicationDoseEventType`; iOS 18: `HKStateOfMind`, `HKPHQ9Assessment`, `HKGAD7Assessment`; iOS 27: workout zones, menopause types, permission flow where user grants limited or full history. Health data = special-category data (GDPR art. 9); keep on device, explicit consent, no diagnosis/dose advice.

### 3.10 Shortcuts: iOS 27 and the trigger catalogue
- iOS 27 (beta-5 splash): Describe a Shortcut, Use Model with broad world knowledge (web), Unified Automations (automation built into the shortcut, incl. shared). Search snippets also mention new Screenshot/notification/keyboard triggers [S/U]. Use Model has On-Device and cloud options; On-Device failed for some output types (fixed in RN27). Focus automations migrated from iOS 26 were broken (fixed). https://matthewcassinelli.com/ios-27-beta-5-whats-new-in-shortcuts/ , https://9to5mac.com/2026/03/31/ios-27-could-give-apples-shortcuts-app-a-powerful-new-capability/
- Apple's trigger list (Setting triggers page): Wi-Fi Network (specific or any), Bluetooth Device (connect), Focus on/off, Low Power Mode on/off, Battery Level (equals / rises above / falls below), Charger connected/disconnected, NFC Tag (only tag ID matters; works on iPhone XS and later, even when Shortcuts is not foreground per a secondary source), App opened/closed, Airplane Mode. Time of Day, Alarm, Sleep, Arrive/Leave, CarPlay, Messages/Email, Wallet, Sound Recognition exist too [I from training; not on the snippet I read]. https://support.apple.com/guide/shortcuts/apde31e9638b/ios , https://www.techradar.com/features/6-iphone-automations-that-are-apples-best-kept-secret , https://www.howtogeek.com/442760/how-to-create-automations-on-an-iphone-or-ipad/
- Back Tap: Settings > Accessibility > Touch > Back Tap, double or triple tap, can run a Shortcut. [S] https://leapp.nl/en/blogs/iphone/tikken-op-de-achterkant-van-je-iphone
- Limit [I]: an app cannot silently install automations; the user must tap "Add". Shortcut import links (`shortcuts://import-shortcut...` / iCloud share link) are from my memory, not re-verified. Whether a shared iOS 27 shortcut carries its automation trigger on import needs a device test.

---------------------------------------------------------------------------
## 4. Capability table (capability -> concrete Doddy feature -> iOS -> effort)

| Capability | Concrete Doddy feature | iOS | Effort |
|---|---|---|---|
| Live Activity landscape/StandBy/mirroring, `isDynamicIslandLimitedInWidth`, `.supplementalActivityFamilies([.small])` | Talking activity that survives narrow islands; "night-stand Doddy" in StandBy; free Watch Smart Stack + CarPlay Dashboard presence | 27 | S-M |
| Scheduled Live Activity (`start:`) | 07:00 briefing, bedtime wrap-up, medication window, "leave now" | 26 | S-M |
| `SnippetIntent` | Action Button / Spotlight shows an interactive result card (confirm / undo / snooze) without opening the app | 26 | M |
| `OwnershipProvidingEntity`, `requestConfirmation(conditions:...)`, `UndoableIntent` | System-level confirm for BLIK drafts, deletes, calls, shared family lists; undo after "done" | 27 (conditions 18) | M |
| `supportedModes`, `LongRunningIntent`, `CancellableIntent`, `BGContinuedProcessingTask` | Document analysis, big uploads, call set-up continue after Action Button press; clean cancel | 27 / 26 | M |
| `IndexedEntity`, `IndexedEntityQuery` | Memories, lists, people in Spotlight; Siri AI/visual search can find them | 18 / 27 | M |
| `RunSystemShortcutIntent` | Widget with a user-chosen action button (open banking app, run recipe) | 27 | S |
| Visual Intelligence `IntentValueQuery` | Camera Control search -> "do I have a manual / warranty / note for this?" | 26 | M |
| CarPlay voice-based conversational app | Doddy in the car, Polish voice, hands-free briefing | 26.4 | L |
| Foundation Models (on-device) | Free offline router/summariser/extractor for supported locales; OCR + barcode tools for receipts/labels | 26 / 27 | M |
| `PrivateCloudComputeLanguageModel` | 32K-context memory consolidation with `moderate`/`deep` reasoning, free, daily quota, needs entitlement | 27 | M |
| `LanguageModel` + Core AI / `mlx-swift-lm` | Own small on-device model (Polish-capable) behind Apple's session API - research spike | 27 | L [I] |
| `SpeechAnalyzer`/`SpeechTranscriber`/`DictationTranscriber`/`SpeechDetector` | Offline voice notes, instant captions, privacy mode (if Polish locale present) | 26 | M |
| HealthKit medication + State of Mind | Dose-logged check + AlarmKit nag; mood journal | 26 / 18 | M |
| Shortcuts recipes (Unified Automations) | In-app "Recipes" gallery with importable shortcut+automation packs and Describe-a-Shortcut prompts | 27 | S-M |
| `WidgetPushHandler`, `WidgetAccentedRenderingMode` | Server-triggered widget refresh; Liquid Glass tint | 26 | S |
| Siri AI app schemas (Clock/Reminders/Notes/Phone/Calendar) | "Wake me at 7" lands in Doddy alarms - English/non-EU users only | 27 | L, defer |
| Siri "Extensions" (third-party chatbot) | Doddy selectable as Siri's AI - no public API found | 27 | U |
| Side-button `activate` schema | Japan only - ignore | 26.2 | n/a |

---------------------------------------------------------------------------
## 5. Fifteen iPhone tricks Doddy could package for ordinary people
Doddy explains by voice, deep-links to the right Settings/Shortcuts screen, ships importable recipes, and proactively suggests at the right moment. The user always taps the final "Add" (iOS does not let apps create automations silently). Labels show the trigger's verification.

1. **Bedside NFC "Good night"**: tap tag -> AlarmKit alarm, tomorrow's first event, Sleep Focus, one-line "anything to remember?". [V NFC trigger]
2. **Car-dash NFC "Driving mode"**: Doddy voice-only, reads messages/calendar, hands-free calls. [V]
3. **Charger-connected wrap-up** after 21:00: tomorrow agenda + 1-line day memory. [V Charger trigger]
4. **Leave/Arrive check**: leaving home -> "keys, wallet, meds, charger?" from what you forgot before; arriving at shop -> shopping list. [S Arrive/Leave; V Reminders `locationTrigger`]
5. **Focus-aware Doddy**: Driving = voice-only short answers; Sleep = silent; Work = work reminders only. [V Focus trigger]
6. **Wi-Fi context switch**: office Wi-Fi -> work mode; home Wi-Fi -> backup/sync. [V]
7. **Bluetooth/CarPlay commute briefing**; on disconnect "remember where I parked". [V Bluetooth trigger; disconnect I]
8. **Low-battery buddy**: <20% -> enable Low Power Mode + draft "phone dying, I'm at X" to a chosen contact (approval required). [V Battery trigger; LPM action I]
9. **Mindful pause**: opening a chosen social app -> Doddy asks "what do you need here?" [V App trigger]
10. **Travel pack**: Airplane Mode off in a new country -> emergency number, currency/tip, 5 phrases, translator ready. [V Airplane trigger; content I]
11. **Back Tap 2.0**: double = talk, triple = "remember this screen" (screenshot -> OCR -> memory); 20-second guided setup (Accessibility > Touch > Back Tap). [S]
12. **Action Button menu**: one pre-built Shortcut with Choose-from-Menu: Talk / Quick note / Translate / Photo to memory. [I]
13. **Point-and-find**: Visual Intelligence / Camera Control -> find manual, receipt or warranty in memory. [V API]
14. **StandBy night stand**: landscape + charging shows Doddy Live Activity (next alarm, tomorrow's first event, big talk tap). [V s.223]
15. **Medication nudge**: HealthKit dose log check + AlarmKit nag if not logged; shared with a caregiver only on explicit consent. [V API names]
Bonus: **Screenshot trigger** (reported new in iOS 27) -> Doddy extracts events/phone numbers/receipts. [S/U]; **Describe-a-Shortcut prompt writer** (Doddy writes the sentence the user pastes). [S]

---------------------------------------------------------------------------
## 6. Dynamic Island / Live Activity performance facts (Apple) + engineering inference
Apple-stated [V]: see 3.5 (8 h/12 h, 4 KB, image <= presentation size, no network/location, 160 pt, 2 s animations, no AOD animation, 28 pt circle, priority 5 vs 10, frequent updates key + user switch, relevanceScore, staleDate, activity count limits, widget 40-70 reloads/day).
Inference [I] (Apple has no "jank checklist"; I could not find one):
- Janky causes most likely: oversized images (can fail start), >2 s or custom looping animations, layout jumps between compact/expanded because content is re-created instead of animated, text truncation in narrow islands, bursts of high-priority pushes that get throttled (updates appear late/batched).
- For a voice session the app is alive: use local `update` for state changes (no APNs budget), coalesce updates (e.g. state changes only; show audio level with an `Text(timerInterval:)`-style system-driven view or a looping SF Symbol effect rather than pushing 10 updates/s) [I], keep ContentState tiny, one `relevanceScore` strategy, end the activity promptly, handle `areActivitiesEnabled` false and start-time errors.
- Measure with MetricKit (`MetricManager`, hitch ratio) and Instruments on a device; test on iPhone with narrow island and in landscape.

---------------------------------------------------------------------------
## 7. Could not verify / gaps
- Final shipped form and API of Siri "Extensions" for third-party chatbots; only press. No Apple doc found.
- Whether Siri AI will reach Polish or EU iPhone; current evidence says no/not yet.
- SpeechTranscriber/DictationTranscriber Polish support: run `supportedLocales` on a device.
- Apple pages that returned 404 or non-JSON: updates for AlarmKit, CarPlay, Translation; "WWDC26 updates" overview; HIG Dynamic Island page. So no verified iOS 27 changes for those.
- No numeric Live Activity push budget exists in Apple docs; session 223 had no performance advice.
- New Shortcuts triggers in iOS 27 (Screenshot, notification, keyboard): snippets only (TechRepublic fetch blocked 403).
- CarPlay conversational-app rules come from press, not Apple's CarPlay Developer Guide.
- Shortcut import deep links and shared-automation behaviour: from memory, needs a device test.
- Camera Control/Visual Intelligence availability in EU/Poland and on which iPhones: not checked.
- AirPods, Action Button, Back Tap, Lock Screen: no new developer API found in the sources I read.
- The 3-slot Dynamic Island on iPhone 18 Pro is rumor only.

---------------------------------------------------------------------------
## 8. Sources
Apple primary (fetched 2026-10-23):
- https://developer.apple.com/documentation/updates/appintents , /activitykit , /foundationmodels , /speech , /widgetkit , /healthkit , /callkit , /livecommunicationkit , /backgroundtasks , /usernotifications (downloaded as JSON via developer.apple.com/tutorials/data mirror)
- https://developer.apple.com/documentation/foundationmodels and subpages (languages, Private Cloud Compute, entitlement)
- https://developer.apple.com/documentation/speech , .../speechtranscriber
- https://developer.apple.com/documentation/alarmkit
- https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai , .../app-schema-domains and domain pages (assistant, clock, notes, phone, reminders, visual-intelligence), SnippetIntent, AudioRecordingIntent, IntentModes, LongRunningIntent, CancellableIntent, UndoableIntent, OwnershipProvidingEntity, SyncableEntity, RelevantEntities, RunSystemShortcutIntent
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
- https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates
- https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- https://developer.apple.com/design/human-interface-guidelines/live-activities
- https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes
- https://developer.apple.com/videos/play/wwdc2026/223/
- https://support.apple.com/en-us/121115
- https://support.apple.com/guide/shortcuts/apde31e9638b/ios
Secondary:
- https://www.smartworld.it/news/siri-ai-data-uscita-lingue-europa.html
- https://iphonesoft.fr/2026/09/16/ios-27-2-apporte-siri-ai-francais
- https://consomac.fr/news-24610-ios-et-macos-27.2-entrent-en-version-beta-avec-siri-ai-en-francais.html
- https://letsdatascience.com/news/apple-expands-siri-ai-to-five-languages-c6b6a177 (snippet)
- https://antyweb.pl/siri-po-polsku-czy-wreszcie-w-ios-27 , https://antyweb.pl/ios-27-2-trzecia-beta (snippet)
- https://www.macrumors.com/2026/03/26/apple-ios-27-siri-chatbot-integration
- https://www.macworld.com/article/3100123/report-ios-27-to-let-siri-work-with-any-third-party-chatbot.html
- https://www.igeeksblog.com/apples-siri-app-could-turn-into-ai-hub-with-extensions-in-ios-27/
- https://www.thurrott.com/a-i/apple-intelligence/334259/now-apple-plans-to-open-up-siri-to-third-party-ai
- https://matthewcassinelli.com/ios-27-beta-5-whats-new-in-shortcuts/
- https://9to5mac.com/2026/03/31/ios-27-could-give-apples-shortcuts-app-a-powerful-new-capability/
- https://www.techrepublic.com/article/news-ios-27-ai-shortcuts-automations/ (snippet; fetch blocked)
- https://www.igeeksblog.com/ios-26-4-carplay-chatgpt-claude-gemini-support/
- https://macrumors.com/2026/02/18/ios-26-4-carplay-support
- https://9to5mac.com/2026/02/18/ios-26-4-adds-support-for-voice-based-ai-apps-to-carplay/
- https://www.techradar.com/vehicle-tech/car-infotainment/apple-carplay-gets-a-big-ai-upgrade-in-ios-26-4-that-lets-you-talk-to-chatgpt-gemini-and-claude-but-theres-a-catch
- https://blog.addpipe.com/apple-speechanalyzer-api/
- https://www.techradar.com/features/6-iphone-automations-that-are-apples-best-kept-secret
- https://www.howtogeek.com/442760/how-to-create-automations-on-an-iphone-or-ipad/
- https://leapp.nl/en/blogs/iphone/tikken-op-de-achterkant-van-je-iphone
- https://www.gadgetreview.com/?p=410087 (rumor)
