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
- In `voice-agent/tools.json` and `instructions.md`, `scripts/voice_agent_spec.py check` passes (101 tools). **On the live ElevenLabs agent since 28 Oct 2026** (owner: "Tak dodaj"; tool `tool_9101m626b83yfsyr5d68zckqjnqd`, version `agtvrsn_6201m626c2wyf72v4nrr3xtpfszk`, rollback `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh`; log in `voice-agent/README.md`). The tool list only: the live prompt has no `control_home` line yet.
- The app side is below.

## The app side (ADR-658)
- `Infrastructure/Connections/HomeKitClient.swift`, the only file that imports HomeKit: reads the primary home's lights, outlets, fans and user-made scenes; writes one power characteristic then reads it back; runs one scene. Scenes that touch anything but a light, outlet or fan are left out. `access()` and `request()` create the `HMHomeManager` (which is what makes iOS ask) only after Allow has been tapped once.
- The controller resolves the proposal, shows a `.home` card with HomeKit's own name, and runs it on the tap. Decline answers `declined:`. The reply prefixes (`changed:`, `not changed:`, `failed:`, `unknown:`) are the ones the activity log already reads.
- Settings › Connections › Home, with its description; the `NSHomeKitUsageDescription` prompt (English, Polish and eight machine drafts); the HomeKit entitlement in the four shipping entitlements files; the guard.

## Still to do
- **Owner:** a paid Apple team (the free-team build has no HomeKit); a native read of the nine-language prompt.
- **Device checks:** the prompt after Allow; a light switched and read back; a scene; an ambiguous name; an unreachable accessory; a scene containing a lock being absent; the multi-home case (only the primary home is used).
- No app unit test with a fake `HomeControlling` yet.

## Checked
Ran: `voice_agent_spec.py check`, the forbidden-capability guard (with its new HomeKit rules), the platform specs and the string-catalog check (all pass). **Not run:** `make test-core`, the app type-check (no Swift in this session), the Xcode build, a device. Every Swift edit, `HomeKitClient.swift` included, was made without a compiler or the HomeKit SDK.

## Next step
Run `make test-core` and the hosted Mac job, fix what the compiler finds in `HomeKitClient.swift`, then a device run.
