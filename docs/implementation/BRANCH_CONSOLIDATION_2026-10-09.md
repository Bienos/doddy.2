# Branch consolidation — 2026-10-09
Owner request: put the parallel `claude/*` branches onto one branch, keep one version of anything built twice.
Result branch: `claude/brave-keller-f8h6uq`. Base: `claude/nice-albattani-t1yan6` (V1 voice + V2 Back Tap guide, both tried on the owner's iPhone, + V3 Dynamic Island).

## Merged
| Branch | What it brings | Notes |
|---|---|---|
| `nice-albattani` (base, includes `inspiring-einstein`, `stoic-lamport`) | V1 voice, V2 "Talk to Doddy" shortcut + Back Tap guide, knowledge (notes, recent conversations, weather, Wikipedia), V3 Dynamic Island | Kept as is |
| `nice-thompson`, `kind-davinci`, `gifted-hypatia` | Video prompt pack, brand guidelines, "keep the taps quiet" design step | Design step edited 8 imported pack files: manifest refreshed for those only (ADR-091) |
| `dreamy-mayer`, `clever-davinci` | Landing page, waitlist + admin, Vercel analytics, `doddy://` links | URL scheme moved into `Config/Doddy-Info.plist` |
| `nifty-euler` | Brand pick C, voice-agent spec in `voice-agent/`, agent tuning | ADRs renumbered 056–060 |
| `lucid-rubin` | v1.3 brand extracts, `BRAND_INDEX.md` | **Colour switch to `#FF7A00` not kept**: superseded by pick C (ADR-061) |
| `cool-euler` | Personality settings | Sent with the knowledge variables |
| `determined-sagan` | Connections: calendar, reminders, contacts, timers, maps, Shortcuts, drafts | Matches the 14 tools on the live agent. Island says "Confirm in Doddy" for any waiting card |
| `busy-mendel` (token-server commit only) | `server/voice-token`, private agent mode in Settings | Its own V2 commit not taken |
| `keen-cray` | Connected Apps: Google Calendar read-only via Composio (`backend/`) | Guard allows two networking files: token client + Connected Apps transport |
| `cool-rubin` | Introduction questions, personal Home, About you, profile store | Its own Back Tap guide + `OpenDoddyIntent` removed; first use = introduction only (ADR-089) |

## Not merged (still on their branches)
| Branch | Why |
|---|---|
| `vibrant-pasteur` | Third V2 Back Tap guide; duplicate |
| `busy-mendel` V2 commit (`5c10951`) | Duplicate V2. Its **Control Center control** is the one piece no other branch has |
| `upbeat-brown` (V4a) | Same features as `determined-sagan`; its **Today card and local nudges** are not in the merged app |
| `busy-hawking` (M2) | OpenAI "Ask" tab + Supabase gateway: a different direction, needs an owner decision |
| `loving-dirac`, `inspiring-einstein`, `stoic-lamport` | Already contained in the result |

## Verified (Linux, 2026-10-09, Swift 6.1.2, Node 22.22.0)
`scripts/ci.sh --core-only`: pack integrity PASS (259 files), capability guard PASS, voice-agent spec PASS, Swift package tests PASS (122 tests, 0 failures, incl. persistence on real SQLite), token server tests PASS (6), backend type-check PASS, backend tests PASS (73). `swiftc -parse` on all 39 app/widget/test files: PASS (syntax only).

**Not verified:** the iOS app and widget build, unit and UI tests (no Xcode here). Several files were joined by hand (`VoiceSessionController`, `VoiceView`, `SettingsView`, `HomeView`, `RootView`, `DoddyApp`), so expect a few compile fixes on the first Mac build.

## Owner checklist on the Mac / iPhone
1. `make project` then `scripts/ci.sh`; send any compile errors.
2. Voice: a conversation still works and recall finds a saved note.
3. First launch: the introduction shows (no Back Tap step); Home card offers Back Tap; Settings → Back Tap and Siri.
4. Dynamic Island while in another app; "Confirm in Doddy" while a card waits.
5. Settings → Connections: turn on Calendar, ask "what's on tomorrow?".
6. Decide: Control Center control, Today card / nudges, OpenAI Ask tab, and whether Back Tap should be a first-launch step again.
