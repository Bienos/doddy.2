# Dependencies and licences

## Shipped in the app
| Package | Version | Licence | Used for |
|---|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.9.0 (exact in `Packages/DoddyCore/Package.swift`, locked in its `Package.resolved`) | MIT | SQLite access, migrations, FTS5 (M1, ADR-003) |
| [swift-crypto](https://github.com/apple/swift-crypto) (+ swift-asn1) | 3.15.1 (exact in `Packages/DoddyCore/Package.swift`, locked in its `Package.resolved`) | Apache-2.0 | **Linux only**: the CryptoKit API for testing the encrypted backup (ADR-222) in CI. The iPhone app uses Apple's CryptoKit and doesn't link it |
| [ElevenLabs Swift SDK](https://github.com/elevenlabs/elevenlabs-swift-sdk) | 3.3.1 (exact pin in `project.yml`) | MIT | Voice conversations with the ElevenLabs agent (V1) |
| [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) | 2.19.0 (exact pin in `project.yml` since 7 Nov 2026; the ElevenLabs SDK itself asks for ≥ 2.10.0) | Apache-2.0 | Real-time audio transport used by the ElevenLabs SDK. Also a direct dependency of the app since ADR-207, so the app can set its audio session and a conversation survives other apps' sound |
| [LiveKit WebRTC](https://github.com/livekit/webrtc-xcframework) (via LiveKit) | 150.7871.04 (exact in LiveKit 2.19.0's `Package.swift`) | MIT for the package; WebRTC itself is BSD-3-Clause | Prebuilt WebRTC framework that carries the call audio |
| [LiveKit FFI](https://github.com/livekit/livekit-ffi-xcframework) (via LiveKit) | 0.13.1 (exact in LiveKit 2.19.0's `Package.swift`) | Apache-2.0 | Prebuilt LiveKit library that the LiveKit SDK links |

LiveKit's manifest also names swift-protobuf (its own tests only) and swift-docc-plugin (its documentation only). Neither
is linked into the app. `Config/Package.resolved` (committed) locks every Swift package the app resolves to an exact
commit: seven remote packages, the six in the table above plus swift-asn1 1.7.3 (swift-crypto's dependency)
(`docs/decisions/2026-11-07-reproducible-app-builds.md`). DoddyCore is a local package and isn't pinned there. The
Mac CI job fails when Xcode resolves something else.

Everything else is Apple system frameworks (`SwiftUI`, `UIKit`, `Foundation`, `AVFAudio`, system SQLite). No analytics,
no crash reporting, no fonts. Of these packages, the ElevenLabs voice session (while it is open) is the only network
connection. (Picovoice Porcupine and ios-voice-processor, for the "Hey Doddy" wake word, were removed on 20 Oct 2026, ADR-549.)

## Doddy's server (`backend/`, server-side only, never in the app)
Pinned exactly in `backend/package.json`; full tree locked in `backend/package-lock.json`.

| Package | Version | Licence | Used for |
|---|---|---|---|
| [@composio/core](https://www.npmjs.com/package/@composio/core) | 0.22.0 | ISC | Composio SDK: Connect Link, connection status/ownership, revoke/delete, and running the online-account tools (Google Calendar, Gmail, Outlook, Google Drive, Notion, Todoist) |
| @composio/client (via @composio/core) | 2.0.0-rc.8 | Apache-2.0 | HTTP client used by the SDK (note: a release-candidate version chosen by the SDK, not by Doddy) |
| [zod](https://zod.dev) | 3.25.76 | MIT | Runtime validation of config, requests and provider results (also the SDK's peer dependency) |
| [pg](https://node-postgres.com) | 8.23.1 | MIT | Postgres client for the hosted database (`DATABASE_URL`, ADR-525) |
| pg-pool, pg-protocol, pg-types, pg-connection-string, pgpass (via pg) | 3.14.0, 1.16.1, 2.2.0, 2.14.1, 1.0.5 | MIT | Parts of `pg` |
| [@electric-sql/pglite](https://pglite.dev) | 0.5.8 | Apache-2.0 | In-process Postgres (WebAssembly) for tests, mock mode and local development (ADR-525) |
| typescript (dev) | 5.9.3 | Apache-2.0 | Type-checking against the SDK's real declarations |
| @types/node (dev) | 22.20.5 | MIT | Node type definitions |
| @types/pg (dev) | 8.23.0 | MIT | `pg` type definitions |

**Payments (x402, 2026-10-12) added no dependency.** The Coinbase wallet adapter (`backend/src/payments/coinbase.ts`) is
plain REST with Node's built-in `node:crypto` (Ed25519 and ES256 JWTs), and the seller client uses `node:https`. Coinbase's
`@coinbase/cdp-sdk` (MIT) was deliberately not added: it pulls in viem, the Solana libraries and axios, which is a lot of
unreviewed code on a path that moves money. The cost is that the request format is written by hand from Coinbase's published
docs and SDK source and has **not been run against the real service**; revisit if that proves brittle. Coinbase's
`@x402/*` packages (Apache-2.0) were not used either: the buyer side is one file of about 300 lines (`payments/x402.ts`), and Doddy needs its own address checks regardless.

Runtime: Node.js 22. The backend no longer uses `node:sqlite` (ADR-525). `@composio/core`
declares `engines.node >= 22.22.3`; the authoring environment ran Node 22.22.0 — all tests passed, but use ≥ 22.22.3.

## Messaging server (`server/messaging/`, server-side only)
Pinned exactly in `server/messaging/package.json`; locked in its `package-lock.json`. Runtime: Node.js 22 (`engines.node >= 22.12`).

| Package | Version | Licence | Used for |
|---|---|---|---|
| [@anthropic-ai/sdk](https://www.npmjs.com/package/@anthropic-ai/sdk) | 0.128.0 | MIT | Claude calls: replies in Messages, the shopping errand, reading leaflet pages for deals, the answer card after a task call |
| [fastify](https://fastify.dev) | 5.12.8 | MIT | HTTP server |
| @fastify/formbody | 9.0.1 | MIT | Reading Twilio's form-encoded webhook bodies |
| @fastify/rate-limit | 11.2.1 | MIT | Request rate limits |
| fast-xml-parser | 5.11.1 | MIT | Checking the TwiML ElevenLabs returns for task calls before it is rebuilt |
| pg | 8.23.1 | MIT | Postgres client |
| zod | 4.6.7 | MIT | Validation (zod 4 here; `backend/` and `web/` use zod 3) |
| twilio (dev) | 5.13.1 | MIT | Tests only: checks Doddy's own Twilio signature code against the official library |
| typescript, @types/node, @types/pg (dev) | 5.9.3, 22.20.5, 8.23.1 | Apache-2.0, MIT, MIT | Type-checking |

## Doddy Web (`web/`, runs in the browser, served by `backend/`)
Pinned exactly in `web/package.json`; locked in `web/package-lock.json`.

| Package | Version | Licence | Used for |
|---|---|---|---|
| react, react-dom | 19.2.9 | MIT | The interface |
| react-router | 7.18.4 | MIT | Pages |
| zod | 3.25.76 | MIT | Checking the server's replies |

Build and test only (not in the built page): vite 7.3.7, @vitejs/plugin-react 5.2.0, typescript 5.9.3, vitest 4.1.12,
jsdom 27.4.0, @testing-library/dom 10.4.2, @testing-library/jest-dom 6.9.1, @testing-library/react 16.3.3,
@testing-library/user-event 14.6.8, @playwright/test 1.56.1, and @types/node, @types/react, @types/react-dom. All MIT
except typescript and Playwright (Apache-2.0).

## Website (`site/`, Vercel functions)
| Package | Version | Licence | Used for |
|---|---|---|---|
| [@vercel/blob](https://www.npmjs.com/package/@vercel/blob) | 2.8.0 | Apache-2.0 | Storing waitlist sign-ups (`site/api/waitlist*.js`) |

## No third-party runtime packages
`gateway/` (not used by the app since ADR-587; dev only: typescript 5.7.2, @types/node 22.10.2) and `server/voice-token/`
use Node's built-in modules only.

## Development tooling (not shipped, not linked)
| Tool | Used for | Licence | Note |
|---|---|---|---|
| Swift 6.1 Linux toolchain (swift.org) | `Packages/DoddyCore` tests on Linux | Apache-2.0 w/ runtime exception | CI's `swift` job uses the official `swift:6.1-noble` image. On 7 Nov 2026, 6.1.3 ran `make test-core`: 2416 tests, 0 failures. 6.1.0 crashes while compiling DoddyCore, so use 6.1.3 or newer. Toolchains downloaded by hand (6.3.3 earlier, 6.1.0 and 6.1.3 on 7 Nov) came over HTTPS; their **GPG signatures were not verified** |
| XcodeGen | generating the Xcode project | MIT | `brew install xcodegen` on your own Mac. CI and Xcode Cloud install version 2.46.0 from its GitHub release file after a SHA-256 check (`scripts/install_xcodegen.sh`). 2.44.1 was built on Linux once to validate `project.yml` |
| Xcode / iOS SDK | app build | Apple developer terms | Xcode 26.6 on the `macos-26` runner, pinned in `.github/workflows/ios.yml` and `project.yml` (`xcodeVersion`) |
| Node.js 22 | servers, Doddy Web and site tests | MIT | every `package.json` but `site/`'s sets `engines`; CI uses `actions/setup-node` with `22` |

## Candidates for later milestones (NOT added)
| Candidate | Milestone | Status |
|---|---|---|
| (none pending) | | GRDB was added in M1 |

## Fonts
No font binaries in the repository or app (pack policy). The UI uses system fonts with Dynamic Type.
Inter and Caveat (SIL OFL) appear only as notices in `docs/legal/fonts/` (moved there on 20 Oct 2026 when
`design/interface-v1.2` was deleted, ADR-548); using Caveat in the app needs an owner decision and a licence check.

## Artwork
`DoddyApp/Resources/Assets.xcassets` no longer contains the candidate-art imagesets `Doddy_waving`,
`Doddy_approaching`, `Doddy_listening` and `Doddy_memory_card` (generated PNG exports of SVGs, not
illustrator-approved, rights review not done). They were removed on 20 Oct 2026 (ADR-547): nothing loaded
them by name, because `CandidateCharacterView` already draws the owner's pack poses. The app's character
art is the owner's `UploadedDoddy_*` and `WholeDoddy_*` pack (`docs/design/UPLOADED_MEMORY_ASSETS.md`); the
rights review of the pack is still an open owner decision (see `DECISIONS.md`).

## Voice samples

Removed on 12 Nov 2026 with the choice of voice (decision `docs/decisions/2026-11-12-one-voice.md`): the six
`DoddyApp/Resources/VoicePreviews/voice-preview-*.mp3` clips (speech generated on 2026-10-10 with ElevenLabs
`eleven_v4`, ADR-122) are no longer in the app.
