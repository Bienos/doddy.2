# Doddy motion bible v1.3

## Laws

1. Doddy never teleports; pose changes have visible anticipation and follow-through.
2. Motion explains system state and is not decorative loading camouflage.
3. Facial recognition survives stretch and motion.
4. Listening is reactive to real microphone levels only after permission; don't suggest recording when inactive.
5. Waiting states explain what is happening, and allow cancel/retry.
6. Errors interrupt politely; successes settle physically.
7. Prefer low-energy idle motion; respect Reduce Motion.

## Motion tokens

| Interaction | Duration | Curve | Notes |
|---|---|---|---|
| Button acknowledgement | 120ms | easeOut | no blocking delay |
| UI cards | 240ms | easeInOut | preserve spatial continuity |
| Character gesture | 420ms | cubic-bezier(.2,.8,.2,1) | anticipation/overshoot |
| Character state settle | 680ms | spring-like | only when meaningful |
| Blink | 90ms close + 90ms open | sharp | randomize pauses in production |
| Walk cycle | 720ms loop | linear with spline limbs | SVG demo GIF is illustrative |
| Listening audio response | 30-60fps | low-pass level smoothing | measured, opt-in mic signal |

## State model

IDLE > INVOKED > LISTENING > UNDERSTANDING > THINKING > SPEAKING / ACTIONING > SUCCESS / ERROR > IDLE. Any state can be INTERRUPTED by a user cancel action.

## Animation production backlog

Create production Rive rigs, review key poses in context, optimize mobile performance and perform accessibility testing. GIF examples in this package demonstrate style, not production-ready rigging.
