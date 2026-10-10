# Build and test — DODDY V2 (M0 shell + M1 local memory + V1 voice + M2 typed assistant)

**Status of this document: written without access to Xcode.** Everything under "Verified on Linux"
was executed (results in [docs/implementation/M0_REPORT.md](docs/implementation/M0_REPORT.md)).
Everything under "Needs a Mac" is **NOT RUN / UNVERIFIED** until someone runs it and records the result.

## Prerequisites

| Need | For | Notes |
|---|---|---|
| Swift 6.0+ toolchain | package tests (any OS) | authored/tested with Swift 6.3.3 (Linux, x86_64) |
| macOS + Xcode (see below) | app build, unit + UI tests | not available when M0 was written |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | generating `Doddy.xcodeproj` | `brew install xcodegen`; dev tool only, not shipped |

Deployment target: **iOS 17.0**, iPhone only (ADR-002 in `docs/architecture/DECISIONS.md`; recorded in
`DECISIONS.md`). Use the current stable Xcode that ships an SDK your account can submit with; the
project uses Swift language mode 6 and needs Xcode 16 or newer at minimum.

## Verified on Linux (no Xcode needed)

```sh
scripts/ci.sh --core-only      # pack integrity + forbidden-capability guard + Swift package tests + gateway tests/typecheck
# or individually:
python3 -I scripts/verify_imported_pack.py
scripts/check_forbidden_capabilities.sh
swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT   # flag needed on Linux only
```

### Gateway (Node, no Xcode, no network, no keys)

```sh
cd gateway && npm install && npm test && npm run typecheck   # 42 tests; see gateway/README.md
```
Needs Node 22+. `ci.sh` runs these when `node` is on the PATH (typecheck only if `npm install` was done).
The gateway has never been deployed or called against the real OpenAI API.

`scripts/ci.sh` **without** flags needs Xcode too; if it cannot run a step it prints `NOT RUN` and exits
non-zero (exit 2 = blocked, 1 = failure, 0 = everything passed). `--core-only` exits 0 only for its own
narrower scope and still prints the iOS step as `NOT RUN`.

## Needs a Mac (UNVERIFIED)

```sh
brew install xcodegen
make project                   # xcodegen generate --spec project.yml  -> Doddy.xcodeproj
xcodebuild -list -project Doddy.xcodeproj
xcodebuild test -project Doddy.xcodeproj -scheme Doddy \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # pick any installed iPhone simulator
# or all of the above plus the Linux-safe steps:
scripts/ci.sh                  # set DODDY_DESTINATION to override the simulator
```

Why `Doddy.xcodeproj` is not committed: no Xcode could open or build a generated project when M0 was
authored, and the architecture notes forbid presenting an unverified project file as working. The
`project.yml` spec **was** run through XcodeGen 2.44.1 on Linux and generated a project (targets,
paths, local package, asset catalog, privacy manifest resolved), but that project has never been opened
in Xcode. After the first successful Mac build, the owner may decide to commit the generated project.

Open points the first Mac run will settle: SwiftUI/UIKit compile errors in `DoddyApp/` (the sources were
only syntax-parsed on Linux, never type-checked), Swift 6 strict-concurrency diagnostics in app code,
simulator name availability, and whether the UI tests' launch-argument defaults behave as written.

## Layout

```
Packages/DoddyCore/          platform-agnostic Swift package (tested on Linux)
  Sources/DoddyCore/           domain types, ports, Unavailable adapters, capability catalog, privacy defaults
  Sources/DoddyDesignTokens/   CANDIDATE colour tokens + WCAG contrast maths (no SwiftUI)
  Sources/DoddyPersistence/    SQLite memory store (GRDB 7.9.0, FTS5)
  Sources/DoddyCore/Assistant/ M2: wire types, error taxonomy, citation verifier, grounding selector,
                               assistant service (retry), gateway client + transport/credential ports
  Tests/                       73 XCTest cases (incl. contract fixtures shared with the gateway)
DoddyApp/                    SwiftUI app target (iPhone): App/, Features/{Home,Capture,Memories,Settings,Onboarding,Voice,Ask}/,
                             DesignSystem/, Infrastructure/ (+ Network/: the only place HTTP is allowed), Resources/
gateway/                     M2 assistant gateway (Vercel functions, plain JS, 42 node tests) - NOT deployed
schemas/fixtures/            wire-contract examples read by both the Swift and the node tests
DoddyTests/ DoddyUITests/    app-level unit and UI smoke tests (NOT RUN without Xcode)
project.yml                  XcodeGen spec (source of truth for the Xcode project)
scripts/                     ci.sh, check_forbidden_capabilities.sh, verify_imported_pack.py
docs/ schemas/ assets/ design/ reference/ prompts/   imported pack (read-only reference; not in the app target)
```

## Secrets and signing

None are needed or present. No signing team, provider key, token or production identifier is committed;
`DEVELOPMENT_TEAM` is blank (choose your own team in Xcode to run on a device). The bundle identifier
`com.bienos.doddy2.dev` is a **development placeholder** pending an owner decision.
