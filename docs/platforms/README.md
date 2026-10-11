# Platforms: how the code is split

Each platform builds from its own XcodeGen spec into its own Xcode project. Generate on a Mac with `brew install xcodegen`.

| Command | Spec | Project | Contains |
|---|---|---|---|
| `make project` | `project.yml` | `Doddy.xcodeproj` | iPhone/iPad app, widgets, share extension, tests, and the Apple Watch app with its complications, embedded in the app. **This is what ships.** Schemes: `Doddy`, `DoddyWatch`. |
| `make project-iphone` | `project-iphone.yml` | `DoddyiPhone.xcodeproj` | The same iPhone/iPad app **without the Watch app**. A Watch compile error can't break it, and it builds faster. Scheme: `Doddy`. |
| `make project-mac` | `project-mac.yml` | `DoddyMac.xcodeproj` | Mac menu bar app and desktop widget **only**. Nothing from the iPhone app. Scheme: `DoddyMac`. |

`project-iphone.yml` includes `project.yml` and only replaces the app's dependency list, without `DoddyWatch`. `scripts/check_platform_specs.py`, which runs in `scripts/ci.sh`, fails if that list drifts from `project.yml`, or if a target sits in the wrong spec.

## Who uses which folder

| Folder | iPhone/iPad | Watch | Mac |
|---|---|---|---|
| `DoddyApp/` app code | ✔ | | |
| `Shared/` (Live Activity attributes, widget snapshot, intents shared with extensions) | ✔ | one file (`Shared/Widgets/WidgetSnapshotFile.swift`) | |
| `DoddyWidgets/`, `DoddyShare/` | ✔ | | |
| `DoddyWatch/`, `DoddyWatchWidgets/` | | ✔ | |
| `DoddyMac/`, `DoddyMacWidgets/` | | | ✔ |
| `Packages/DoddyCore` → `DoddyCore` (rules, no UI) | ✔ | ✔ | ✔ |
| `Packages/DoddyCore` → `DoddyPersistence` (SQLite) | ✔ | | ✔ (its own database on that Mac) |
| `voice-agent/`, `server/voice-token/` | ✔ (voice) | | |
| `backend/`, `gateway/`, `server/messaging/`, `site/` | servers and site, not apps | | |

## Rules for changes
- **Work on one platform:** change only its folders. Build its project.
- **Change `Packages/DoddyCore`:** it is used by every platform. Run `make test-core` (or `scripts/ci.sh --core-only`), and say which platforms the change touches.
- **Add a target:** put it in the spec for its platform. macOS targets go only in `project-mac.yml`. A new dependency of the iPhone app goes in `project.yml` **and** `project-iphone.yml`; the check script tells you if you forget.
- **The capability guard** (`scripts/check_forbidden_capabilities.sh`) has a rule per platform. For example, the Watch app has no database or network, and the Mac app has no network or microphone.
