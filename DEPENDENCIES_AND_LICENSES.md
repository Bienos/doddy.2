# Dependencies and licences — M0

## Shipped in the app
| Package | Version | Licence | Used for |
|---|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.9.0 (exact pin, `Packages/DoddyCore/Package.resolved`) | MIT | SQLite access, migrations, FTS5 (M1, ADR-003) |
| [swift-crypto](https://github.com/apple/swift-crypto) (+ swift-asn1) | 3.15.1 (exact pin, `Packages/DoddyCore/Package.resolved`) | Apache-2.0 | **Linux only**: the CryptoKit API for testing the encrypted backup (ADR-222) in CI. The iPhone app uses Apple's CryptoKit and doesn't link it |
| [ElevenLabs Swift SDK](https://github.com/elevenlabs/elevenlabs-swift-sdk) | 3.3.1 (exact pin in `project.yml`) | MIT | Voice conversations with the ElevenLabs agent (V1) |
| [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) | ≥ 2.10.0 (pulled in by the ElevenLabs SDK; also a direct dependency of the app since ADR-207) | Apache-2.0 | Real-time audio transport used by the ElevenLabs SDK; the app sets its audio session so a conversation survives other apps' sound |

Everything else is Apple system frameworks (`SwiftUI`, `UIKit`, `Foundation`, `AVFAudio`, system SQLite). No analytics,
no crash reporting, no fonts. The only network connection is the ElevenLabs voice session while it is open.

## Connected Apps backend (`backend/`, server-side only, never in the app)
Pinned exactly in `backend/package.json`; full tree locked in `backend/package-lock.json`.

| Package | Version | Licence | Used for |
|---|---|---|---|
| [@composio/core](https://www.npmjs.com/package/@composio/core) | 0.22.0 | ISC | Composio SDK: Connect Link, connection status/ownership, revoke/delete, `GOOGLECALENDAR_EVENTS_LIST` execution |
| @composio/client (via @composio/core) | 2.0.0-rc.8 | Apache-2.0 | HTTP client used by the SDK (note: a release-candidate version chosen by the SDK, not by Doddy) |
| [zod](https://zod.dev) | 3.25.76 | MIT | Runtime validation of config, requests and provider results (also the SDK's peer dependency) |
| typescript (dev) | 5.9.3 | Apache-2.0 | Type-checking against the SDK's real declarations |
| @types/node (dev) | 22.20.5 | MIT | Node type definitions |

Runtime: Node.js ≥ 22.13 for `node:sqlite` (experimental in Node 22; prints an ExperimentalWarning). `@composio/core`
declares `engines.node >= 22.22.3`; the authoring environment ran Node 22.22.0 — all tests passed, but use ≥ 22.22.3.

## Development tooling (not shipped, not linked)
| Tool | Used for | Licence | Note |
|---|---|---|---|
| Swift 6.3.3 Linux toolchain (swift.org) | package build/tests during authoring | Apache-2.0 w/ runtime exception | downloaded over HTTPS; its `.sig` was fetched but **GPG signature not verified** |
| XcodeGen 2.44.1 | generating the Xcode project | MIT | `brew install xcodegen`; also built on Linux once to validate `project.yml` |
| Xcode / iOS SDK | app build | Apple developer terms | not available when M0 was written |

## Candidates for later milestones (NOT added)
| Candidate | Milestone | Status |
|---|---|---|
| (none pending) | | GRDB was added in M1 |

## Fonts
No font binaries in the repository or app (pack policy). The UI uses system fonts with Dynamic Type.
Inter and Caveat (SIL OFL) appear only as notices in `design/interface-v1.2/assets/` for the browser
prototype; using Caveat in the app needs an owner decision and a licence check.

## Artwork
`DoddyApp/Resources/Assets.xcassets` contains two PNG imagesets (`Doddy_waving`, `Doddy_memory_card`)
copied unchanged from `design/ios-ready-asset-catalog/`. They are **candidate art**: generated PNG
exports of SVGs whose provenance file states they are original revisions produced for the design task,
not illustrator-approved, with trademark/rights review not done. They are labelled "Candidate art — not
final" in the UI. Rights review is an open owner decision (see `DECISIONS.md`).

## Voice samples

`DoddyApp/Resources/VoicePreviews/voice-preview-*.mp3` (six clips, ~540 KB) are speech generated on 2026-10-10 with
ElevenLabs `eleven_v4` on the owner's ElevenLabs account, one per voice offered in Settings (ADR-122). They are
**development candidates**: check ElevenLabs' output terms for the owner's plan and the Voice Library terms of the
library voices (Josh, Wiktor) before any release.
