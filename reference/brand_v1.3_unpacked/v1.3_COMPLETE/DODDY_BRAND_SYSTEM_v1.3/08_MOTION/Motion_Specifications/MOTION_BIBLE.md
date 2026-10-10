# Doddy Motion Bible v1.3

Motion communicates state, not decoration. Acknowledge invocation instantly, interrupt immediately, transform existing visual elements spatially, and stop animation in idle states.

| Motion | Duration | Timing | Meaning |
|---|---:|---|---|
| Invoke acknowledgement | 100–140ms | ease-out | Input received |
| Character entrance | 240–320ms | expressive spring | Doddy available |
| Blink | 100–160ms | stepped / direct | Life without distraction |
| Listening response | 60–100ms frames | actual audio envelope | Actual microphone signal, **not simulated** |
| Thinking transition | 220–320ms | ease-in-out | Reasoning or tool state |
| Speak gesture | 120–260ms | audio-synchronised | Doddy speaking |
| Success | 260–450ms | spring 0.75 damping | Confirmed completion |
| Error reset | 180–260ms | sharp ease-out | Failed state |
| Exit | 180–260ms | ease-in | Surface recedes |
| B-ball bounce | 800–1100ms | gravity-inspired | Character storytelling only |

## State narrative

Invocation→listening→understanding→thinking/tool→answer/action preview→explicit confirmation→success or recoverable error. An animated flourish is *not* evidence that a tool action succeeded.

## Platform constraints

Dynamic Island and Live Activities are system-controlled and activity-scoped, not a permanent arbitrary companion. Back Tap cannot be silently configured by the installed app. Siri replacement/permanent overlay must not be promised. Animations should adhere to iOS background, Live Activity and reduced-motion rules.

## Accessibility

Respect Reduce Motion: replace travel/transforms with short fades and text labels. Offer pause for repeated animations; never loop flashing strokes. Maintain listening/thinking/speaking labels independent of animation.

## Demo inventory

- `Doddy_blink_demo.gif`: actual finite blink.
- `Doddy_basketball_bounce_demo.gif`: actual bouncing basketball prop.

All remaining animations are storyboard specifications in v1.3, not rendered animation files.
