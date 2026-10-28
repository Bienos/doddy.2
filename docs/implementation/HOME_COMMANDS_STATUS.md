# Home control by voice (HomeKit): status

Owner, 28 Oct 2026: "connection to Apple HomeKit so someone can set up Doddy by command", read as: say "turn off the living room lamp" or "run Good night" and Doddy does it through HomeKit.

## Built (DoddyCore, platform-agnostic)
`HomeCommand.swift` and `HomeCommandTests.swift`:
- A model's request (`HomeProposal`) is resolved against what HomeKit reports (`HomeSnapshot`) to one exact accessory or scene, or to `ambiguous`, `notFound`, `refused` or `unreachable`. Doddy never picks between two matches.
- Only lights, outlets and fans can be switched. Locks, garage doors, security systems, cameras and doorbells are refused in code, whatever the model asks.
- The card text comes from HomeKit's names; the person's tap is bound to the command by a SHA-256 digest of the exact payload (ASK-01).
- Only `HomeOutcome.confirmed` yields "done". `unknown` says the home may or may not have changed and is never retried.

## NOT built
- The HomeKit client (`HMHomeManager`), the Connections › Home switch and the permission sheet row, the approval card, the voice tool `control_home` in `voice-agent/tools.json`, and `VoiceConnection` / `VoiceToolRequest` wiring.
- Needs the HomeKit entitlement, so a paid Apple team (not the free `project-iphone` build) and the `NSHomeKitUsageDescription` text in all ten languages.
- The live ElevenLabs agent is unchanged and needs the owner's yes to the exact tool text.

## Checked
Nothing was run: this session has no Swift or Xcode, so `make test-core` is the first run. No device test.

## Next step
Wire `control_home` into the voice tools, with the same ask pattern as `read_steps`, and write the HomeKit client in the app.
