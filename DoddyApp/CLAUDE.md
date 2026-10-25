# DoddyApp: the iPhone and iPad app
Read `/STATUS.md`, then `docs/platforms/iphone.md`. It has the feature map (folder → ADR → status doc), so you don't need to read the whole tree.
- **Scope:** iPhone/iPad only. Don't touch `DoddyWatch*` or `DoddyMac*` for an iPhone change.
- **Build:**
  - `make project`, scheme `Doddy`: the shipping build. The Watch and Mac apps are paused (ADR-572) and are not in it.
  - `make project-iphone`, scheme `Doddy`: the same with no entitlements, for a free Apple team (no Apple Health in it).
- **Voice** is `Features/Voice/`, with the agent spec in `voice-agent/`. A voice change can stop calls: check the ElevenLabs conversation log after testing.
- **Rules with no UI** belong in `Packages/DoddyCore`, where they're tested on Linux (`make test-core`).
