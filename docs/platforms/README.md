# Platforms: how the code is split

Each platform builds from its own XcodeGen spec into its own Xcode project. Generate on a Mac with `brew install xcodegen`.

| Command | Spec | Project | Contains |
|---|---|---|---|
| `make project` | `project.yml` | `Doddy.xcodeproj` | iPhone/iPad app, widgets, share extension and tests. **This is what ships and what CI builds.** Scheme: `Doddy`. |
| `make project-iphone` | `project-iphone.yml` | `DoddyiPhone.xcodeproj` | The same iPhone/iPad app with no entitlements, so a free Apple team can sign it. Scheme: `Doddy`. |
| `make project-watch ENABLE_WATCH=1` | `project-watch.yml` | `DoddyWithWatch.xcodeproj` | **PAUSED (ADR-572).** `project.yml` plus the Apple Watch app and its complications embedded in the app. Schemes: `Doddy`, `DoddyWatch`. |
| `make project-mac ENABLE_MAC=1` | `project-mac.yml` | `DoddyMac.xcodeproj` | **PAUSED (ADR-572).** Mac menu bar app and desktop widget **only**. Nothing from the iPhone app. Scheme: `DoddyMac`. |

**Apple Watch and Mac development are paused (ADR-572, 21 Oct 2026).** Their source stays in the repo, untouched; only the build wiring is parked. No target in `project.yml`, no CI job and no step of `scripts/ci.sh` builds or tests them, and `make` refuses to generate their projects unless you set `ENABLE_WATCH=1` / `ENABLE_MAC=1`. How to turn them back on: "Re-enabling" in `watch.md` and `mac.md`.

`project-iphone.yml` includes `project.yml` and repeats the app's dependency list. `scripts/check_platform_specs.py`, which runs in `scripts/ci.sh`, fails if the lists drift, if a Watch or Mac target is back in `project.yml`, if the dormant specs drift from it, or if a target sits in the wrong spec.

## Who uses which folder

| Folder | iPhone/iPad | Watch | Mac |
|---|---|---|---|
| `DoddyApp/` app code | ✔ | | |
| `Shared/` (Live Activity attributes, widget snapshot, intents shared with extensions) | ✔ | one file (`Shared/Widgets/WidgetSnapshotFile.swift`) | |
| `DoddyWidgets/`, `DoddyShare/` | ✔ | | |
| `DoddyWatch/`, `DoddyWatchWidgets/` (paused) | | ✔ | |
| `DoddyMac/`, `DoddyMacWidgets/` (paused) | | | ✔ |
| `Packages/DoddyCore` → `DoddyCore` (rules, no UI) | ✔ | ✔ | ✔ |
| `Packages/DoddyCore` → `DoddyPersistence` (SQLite) | ✔ | | ✔ (its own database on that Mac) |
| `voice-agent/`, `server/voice-token/` | ✔ (voice) | | |
| `backend/`, `gateway/`, `server/messaging/`, `site/` | servers and site, not apps | | |
| `web/` (Doddy Web, ADR-585/586; served by `backend/`) | browser app, not an Apple target: `docs/platforms/web.md` | | |

## Rules for changes
- **Work on one platform:** change only its folders. Build its project.
- **Change `Packages/DoddyCore`:** it is used by every platform. Run `make test-core` (or `scripts/ci.sh --core-only`), and say which platforms the change touches.
- **Add a target:** put it in the spec for its platform. macOS targets go only in `project-mac.yml`, and watchOS targets only in `project-watch.yml`, while those are paused. A new dependency of the iPhone app goes in `project.yml`, `project-iphone.yml` **and** `project-watch.yml`; the check script tells you if you forget.
- **The capability guard** (`scripts/check_forbidden_capabilities.sh`) has a rule per platform. For example, the Watch app has no database or network, and the Mac app has no network or microphone.
