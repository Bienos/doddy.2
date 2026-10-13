# Mac spike report (ADR-433)

> **Update, 2026-10-11:** the owner's review deck chose a native Mac menu bar app first (slide 13). That is now built as a prototype, ADR-435 and `MAC_MENU_BAR_STATUS.md`. The comparison below stays as background.
Date: 2026-10-11. From `prompts/APPLE_PLATFORMS_WATCH_IPAD_MAC.md` Phase 5, run in a Linux cloud session.

**Nothing was built or run on a Mac.** This report comes from reading the code and from Apple's and the packages' own documentation. Every runtime behaviour marked "unknown" needs a Mac. No Mac build setting, entitlement or `#if` was added; the choice of route is the owner's.

## The three routes
| Route | What it is | Rough cost (guess) | Runs on |
|---|---|---|---|
| **A. Designed for iPad** | The iPad app, unchanged, offered on Apple silicon Macs (an App Store Connect setting and a run destination in Xcode) | 0.5–2 days | Apple silicon only |
| **B. Mac Catalyst** | The app target rebuilt for macOS with `SUPPORTS_MACCATALYST` | 1–2 weeks | Apple silicon and Intel |
| **C. Native macOS** | A new macOS app on DoddyCore | 4–8+ weeks | All Macs |

**Recommendation: A first.**
- On an Apple silicon Mac, run the app with Xcode's "My Mac (Designed for iPad)" destination and write down what fails.
- Hide what fails behind `ProcessInfo.processInfo.isiOSAppOnMac`.
- Apple says an iPad app on a Mac reports the iPad idiom. If so, today's `DeviceSupport` already hides Back Tap, shopping mode, the island styles and the tab bar there, and the sidebar (ADR-430) shows instead.
- Go to B only if Intel Macs or Mac-specific behaviour (menus, windows) matter.
- C is not worth it now.

## Feature by feature
"Doc" means Apple's or the package's stated platform list. "Unknown" means it needs a Mac.

| Feature | A Designed for iPad | B Catalyst | C native | Source |
|---|---|---|---|---|
| Voice (LiveKit, ElevenLabs SDKs) | Unknown | Both declare macCatalyst 14 | Both declare macOS 10.15 | Package.swift at pinned versions |
| Hey Doddy (Porcupine) | Unknown (iOS arm64 slice may load) | **Fails to link: no Catalyst slice** in `PvPorcupine.xcframework` | Only through the C dylib and a new wrapper | xcframework Info.plist |
| Live Activities, Dynamic Island, shopping mode | Code checks `areActivitiesEnabled`; unknown | **Not available**: ActivityKit types list iOS only, so ~12 files need gating | None | Apple docs |
| AlarmKit | Unknown | Listed for Catalyst 26 | None | Apple docs |
| Watch link | Unknown (`WCSession.isSupported()`, probably false) | Listed | None | Apple docs |
| Widgets, controls | Unknown whether the iPad extension appears | Catalyst 14 / 18 | macOS 11 / 26 | Apple docs |
| App Intents, Siri, Shortcuts | Unknown | Catalyst 16 | macOS 13 | Apple docs |
| Calendar, reminders, contacts | Unknown | Yes | Yes | Apple docs |
| Place reminders (`UNLocationNotificationTrigger`) | Unknown | Catalyst 10 | **None** | Apple docs |
| Voice memos (on-device speech) | Unknown | Yes | Yes | Apple docs |
| Audio session (`AVAudioSession`) | Unknown | Yes | **None** (rework) | Apple docs |
| Photos, text in photos | Yes | Yes | Yes | Apple docs |
| Face ID lock | Touch ID; unknown | Yes | Yes | Apple docs |
| Shared lists (CloudKit sharing UI) | Unknown | Yes | **No `UICloudSharingController`** | Apple docs |
| Quick actions on the icon | No Home Screen | — | None | Apple docs |
| Back Tap, Action Button, `tel:` | Hidden by idiom (Back Tap); `tel:` unguarded | Hidden by idiom (Back Tap) | n/a | Code |

## Catalyst (B): what would have to change
- **ActivityKit gating:**
  - `Shared/VoiceActivity/*`, `Shared/ToolActivity/*`, `Shared/ShoppingMode/ShoppingActivityAttributes.swift`;
  - `Features/Voice/VoiceLiveActivity.swift` and `NativeIslandBaselineView.swift`;
  - `Features/Tools/ToolLiveActivity.swift`, `Features/Lists/ShoppingModeController.swift`;
  - everything that references these: `VoiceSessionController`, `WakeWordListener`, `IslandStyleView`.
- **Porcupine:** `Features/Voice/WakeWordListener.swift` behind `#if !targetEnvironment(macCatalyst)`, plus a `platformFilter: ios` on the package dependency. Hey Doddy is off on the Mac.
- **Targets:** `DoddyWatch`, `DoddyWidgets` and `DoddyShare` need `platformFilter: ios` in `project.yml` while only the app is built for Catalyst.
- **AlarmKit:** the existing `#if canImport(AlarmKit)` does not exclude Catalyst 26. Whether alarms ring on a Mac is unknown.
- **Entitlements:** a new Mac file with the following. App Group and push naming may also differ on macOS; that needs checking on a Mac.
  - `com.apple.security.app-sandbox`;
  - `network.client`;
  - `device.audio-input`;
  - `personal-information.location`, `.addressbook` and `.calendars`.

## Privacy differences on a Mac
- **Microphone:** the voice and voice memos need the sandbox's audio-input entitlement (B). On A the iOS permission prompt applies; how macOS shows it is unknown.
- **Where the database lives:** in the app's sandbox container on the Mac (A and B), not synced with the iPhone. Notes don't sync between devices (only shared lists do, through iCloud, ADR-263), so a Mac copy starts empty and stays separate. That needs saying in the app before anyone uses both.
- **Location:** a Mac's location is coarser (Wi-Fi). Place reminders and "leave by" may be less accurate (unknown).
- **The watch and the iPhone's widgets** have nothing to do with a Mac copy.

## Native macOS (C): what carries over
- **DoddyCore and DoddyPersistence:** 122 files, about 21.5k lines. They use Foundation, Observation, CryptoKit and GRDB, already declare macOS 14, and run their tests on Linux.
- **The app layer:** 131 files, about 26.4k lines. 53 of them use iOS-only APIs and would need a macOS shell, plus rework of the audio session, place reminders, sharing, widgets and the wake word.

## Needed from the owner
1. Which route, if any. A Mac copy would also need an answer on whether notes should ever sync between devices; today only shared lists do.
2. An Apple silicon Mac with Xcode, to run route A and fill the "unknown" column.
