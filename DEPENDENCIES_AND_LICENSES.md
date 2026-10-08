# Dependencies and licences — M0

## Shipped in the app
**None.** The app and `DoddyCore` import only Apple system frameworks (`SwiftUI`, `UIKit`, `Foundation`).
No third-party Swift packages, no network SDKs, no analytics, no fonts.

## Development tooling (not shipped, not linked)
| Tool | Used for | Licence | Note |
|---|---|---|---|
| Swift 6.3.3 Linux toolchain (swift.org) | package build/tests during authoring | Apache-2.0 w/ runtime exception | downloaded over HTTPS; its `.sig` was fetched but **GPG signature not verified** |
| XcodeGen 2.44.1 | generating the Xcode project | MIT | `brew install xcodegen`; also built on Linux once to validate `project.yml` |
| Xcode / iOS SDK | app build | Apple developer terms | not available when M0 was written |

## Candidates for later milestones (NOT added)
| Candidate | Milestone | Status |
|---|---|---|
| GRDB.swift (SQLite, FTS5) | M1 | ADR-003 proposes it; add only with M1 and review its licence (MIT) and release at that time |

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
