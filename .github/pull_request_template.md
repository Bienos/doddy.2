## What changes for the user
<!-- One or two sentences. Screenshots or CI island pictures for anything on screen. -->

## Area
- [ ] voice
- [ ] messages
- [ ] home / screens
- [ ] island / widgets / controls
- [ ] servers
- [ ] CI / tooling
- [ ] docs only

## Risk
- [ ] Touches entitlements, Info.plist, Xcode specs, Xcode Cloud scripts, deploy config, `secrets/`, `voice-agent/`, a migration, CI or agent rules: the `sensitive-paths` check needs the `owner-approved` label (an agent adds it to its own pull request after saying why each file changes; decision `2026-11-08-agents-merge-their-own-pull-requests`)
- [ ] Needs a server deploy or a live voice agent change before or after the app ships (say which, in order)
- [ ] Behind a flag (name, and its default)

## Evidence
<!-- Commands you ran and their results. Say "not compiled" when the app wasn't built. -->
- Ran:
- Not run, and why:
- To check on a device:

## Decisions and rules
<!-- ADR number(s) if this makes a product or architecture decision; constitution rule IDs (DOD-xx, UX-xx) it covers. -->
