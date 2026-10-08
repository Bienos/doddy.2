# Motion storyboard and truthful states

This study uses original static SVGs. No new character acting masters or rigged limb animations were created. Whole-art transforms are optional prototype accents. Timings are creative proposals, not performance benchmarks.

| Beat | Trigger and intention | Visual / timing | Interrupt / reduced motion |
|---|---|---|---|
| Arrive | Shell and input ready; notice then yield | Whole character settles 4 px upward into place, 320 ms ease-out, one shot | Input available immediately; static art under reduced motion |
| Attend | Native future capture-active event; give user the floor | Supplied listening pose; no idle loop or fake live waveform | Stop immediately with capture; static pose + “Listening” text |
| Wait | Accepted operation still pending | Clear pending text; no fictional percent; static useful pose | Cancel before commit; preserve draft; no motion needed |
| Confirm | Verified storage receipt; settle the task | Supplied memory-card pose, 3 px release, 380 ms one shot; explicit confirmed stamp | Reduced motion stays static; never wait for animation to show controls |
| Inspect | User opens matching memory/source | Immediate navigation to exact record; no artificial “discovery” hold | Back works immediately; same layout with no travel |
| Correct | User-authorized revision update committed | Updated current text and version; original remains inspectable | Native failure/conflict keeps draft; no embarrassment performance |
| Recover | Actual failure or unknown outcome | Quiet static posture and plain message; zero comic motion | Failure can retry, unknown offers checking/reconciliation first |
| Yield | User stops voice/session or dismisses | Immediate stopped state; no goodbye performance required | No retention plea; decorative motion cancelled |

## Prototype and native states are different evidence

The prototype simulates a receipt after 350 ms (or 2200 ms in Slow mode). The receipt commits fictional data to an in-memory JS array. It demonstrates the design sequence but does not test SQLite durability or server reliability.

Cancellation increments a token; a late pending mock result is ignored. The draft remains available. Failed saves do not create a memory. Unknown outcomes do not display Saved and do not offer a direct blind retry. Correction increments the demo revision and preserves original text. Clear-all does not reseed examples.

Planned voice states use static waveform bars solely as labeled illustration. No live audio is requested. Native listening must follow actual capture-active state; speaking must follow audio output, not the appearance of a transcript or server tokens.

## Native event contract proposal

Consume a typed presentation state from the app model/coordinator: idle, permissionNeeded, listening, processing, speaking, interrupted, pendingWrite, committed(receipt), failed(error), unknown(operationID). Attach stable session/turn/operation IDs and freshness information at the appropriate service boundary. The renderer never starts an operation, changes a permission or infers a successful side effect.

Existing `MemoryModel`/repository remain authoritative for local memory. A future conversation coordinator owns provider/audio tasks. Store complete original data separately from corrected current text. Do not convert a creative heading such as “Kept for later” into a success condition.

## System-surface boundary

The supplied expanded whole-body activity is a design demonstration. It is not a layout template for all Dynamic Island regions. No always-on companion activity is proposed here. A future useful ongoing task would need measured compact/minimal/expanded/Lock Screen layouts, disclosure controls, deep links, supported App Intents and actual device verification. Sensitive detail contents should not appear on a lock screen by default.
