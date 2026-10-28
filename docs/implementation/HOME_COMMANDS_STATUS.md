# Home control by voice (HomeKit): status

Owner, 28 Oct 2026: "connection to Apple HomeKit so someone can set up Doddy by command", read as: say "turn off the living room lamp" or "run Good night" and Doddy does it through HomeKit.

## Built (DoddyCore, platform-agnostic)
`HomeCommand.swift` and `HomeCommandTests.swift`:
- A model's request (`HomeProposal`) is resolved against what HomeKit reports (`HomeSnapshot`) to one exact accessory or scene, or to `ambiguous`, `notFound`, `refused` or `unreachable`. Doddy never picks between two matches.
- Only lights, outlets and fans can be switched. Locks, garage doors, security systems, cameras and doorbells are refused in code, whatever the model asks.
- The card text comes from HomeKit's names; the person's tap is bound to the command by a SHA-256 digest of the exact payload (ASK-01).
- Only `HomeOutcome.confirmed` yields "done". `unknown` says the home may or may not have changed and is never retried.

## Voice tool `control_home` (28 Oct 2026)
- In DoddyCore: `VoiceToolRequest.controlHome`, its parsing (`action` on, off or scene; `name`; `room`), `VoiceConnection.home`, the catalog row (card, approval `.card`), `AskFirst` (`.ownPayloadCard`: the app shows the exact resolved accessory), the activity line, the Polish names, and refusal while driving.
- In `voice-agent/tools.json` and `instructions.md`, with `elevenlabs_tool_id: "not_synced"`. `scripts/voice_agent_spec.py check` passes (101 tools). **The live agent is unchanged**; it needs the owner's yes to the exact text.
- In the app, only honest stubs so it still compiles: the Home connection is never allowed, it is in no Settings group, and the tool answers "unavailable: controlling the home isn't in this version yet".

## NOT built
- The HomeKit client (`HMHomeManager`) that reads the snapshot and runs the command, the Connections › Home row and its place in a group, the permission sheet, and the approval card.
- Needs the HomeKit entitlement, so a paid Apple team (not the free `project-iphone` build) and the `NSHomeKitUsageDescription` text in all ten languages.
- The live ElevenLabs agent is unchanged and needs the owner's yes to the exact tool text.

## Checked
Ran: `voice_agent_spec.py check`, the forbidden-capability guard, the platform specs and the string-catalog check (all pass). **Not run:** `make test-core` and the app type-check (no Swift in this session), the Xcode build, a device. Every Swift edit was made without a compiler.

## Next step
Write the HomeKit client and the approval card in the app, add the Home row to Connections, then run `make test-core` and the hosted Mac job.
