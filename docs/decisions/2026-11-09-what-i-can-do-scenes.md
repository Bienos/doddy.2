# What I can do shows each feature as a scene

- **Date:** 2026-11-09
- **Decided by:** owner, in Polish: "zrób to lepsze tą animację … i bardziej kreatywnie pokaż te funkcje co on robi … i usuń ten przykład na dole"; asked how: "Karuzela scen".
- **Status:** accepted
- **Replaces:** in `CapabilitiesSheet`, the ink storyboard at the top (ADR-380's use of `PanelStory.ink` there) and the "An example: lost keys" section (`PanelStory.keys`). The storyboards' pictures stay in the catalog (the art previews use them).

## Decision
- At the top of Home › ••• › What I can do, `AbilityCarousel`: one scene per feature the build lists (the same `WhatICanDo.rows`), swiped sideways, moving on every 4.5 seconds until the person swipes or taps a dot.
- Each scene: a speech bubble with something you could say ("Powiedz na przykład: „Przypomnij mi jutro o 8, żeby zadzwonić do mamy.”", `WhatICanDo.example`, typed for Messages), Doddy in a pose from the owner's pack (`WholeDoddy_*`; talking frames `VoiceDoddy_talking_*` for Talk) floating gently, the feature's sign, its name, what it does, and its status in words from `WhatICanDo`.
- Below: the opening paragraph, the feature rows that open each feature, and What leaves this iPhone, as before.
- Reduce Motion: no moving on, no floating, nothing pops in. "Hide Doddy's pictures": the sign only. VoiceOver reads each scene as one sentence: name, what it does, the example, the status.

## Consequences
- An example is how you could ask, never the person's data and never a claim that it was done; the status next to it stays honest (calls still say "Not tried on a real call yet").
- The scene colours are system tints at low opacity on `Theme.quietSurface`; the orange sign uses `Theme.orangeCue`.

## Evidence
`WhatICanDoTests` (Linux). The SwiftUI view is not compiled or seen here; the hosted Mac job compiles it, and no picture of it has been taken.
