# Doddy motion v2: reference package

This folder is the source of truth for how Doddy moves. It came out of the v2 motion package (18 Oct 2026). It is design material, not app code.

## What is here

| Path | What it is |
|---|---|
| `BRIEF.md` | The owner's brief, verbatim: the 13 rules, the spot table, travel modes, Home, new behaviours, playful moments, acceptance checks and the numbers table. |
| `DECISIONS.md` | Calls already made where the brief contradicted itself or the layout (tab-hop cap, brace threshold, mic button, and so on). |
| `reference/prototype.html` | The live prototype. Open it in a desktop browser (it loads the JS files next to it). Every gesture, event and study is there, with a live readout and live rule checks. |
| `reference/engine-core.js` | Constants (`L` layout in pt on a 390 × 844 canvas, `M` timings), the spring integrator, flight path maths, mock list data. |
| `reference/engine.js` | The whole behaviour engine: surfaces, hops, re-targeting, fades, riding, step-across, scroll riding and lily-pad hops, shuffle, brace, duck, gaze and noticing, thinking, welcomes, sitting, playful moments, the per-frame acceptance checks. |
| `reference/scripts.js` | The scripted studies (02, 09, 09b, 12, 14, 16, N1–N15, RM, J journey) as deterministic timelines. |
| `reference/rig.js` | The stand-in stick-figure rig used for the simulations. **Simulation art only. Never ship it, trace it or derive app art from it.** App art comes only from the owner's pack (see the repo's CLAUDE.md). |
| `reference/stage.html` | The headless harness the clips were rendered from (`setupStudy(id)`, then `app.stepFrame()` 60 times a second). |
| `telemetry/*.json` | What the renderer measured in each clip: every hop (crouch, flight, contact time, squash, scale), tab commit times, contact gaps, clear-zone checks, braces, listening frames. Use these as golden numbers when porting. `timing.json` gives each clip's first and last on-screen change. |

The rendered MP4s (clean and annotated) and the review page live with the owner, outside the repo.

## Numbers that matter most

- Hop: crouch 80 ms (140 from sitting, 40 after a landing or from a surface moving his way, 0 when his surface is about to drop away); flight `T = clamp(220 + 0.4·D + 0.2·|Δy|, 260, 420)` ms; apex `clamp(12 + 0.08·D, 16, 32)` pt, or `clamp(6 + 0.04·D, 10, 18)` when stepping down more than 40 pt; contact squash 2.2–4.4 pt; settle spring 0.30/0.60.
- Tab hops land no later than 484 ms after the tap: tab-hop flights are capped (`DECISIONS.md`).
- Mid-air re-target: `clamp(180 + 0.5·D, 200, 360)` ms, total air ≤ 520 ms, never faster than 1,200 pt/s on average.
- Size: 1.4× on Home only; `scale = s0 + (s1 − s0) × smoothstep(0.15, 0.9, progress)`, in the air or while invisible.
- Reduce Motion: 120 ms fade out, one invisible frame for placement, 180 ms fade in; eyes still lead.
- Springs (response s / damping): eyes 0.15/0.85, face turn 0.20/0.90, crouch 0.12/1.00, slide-through 0.28/0.70, surface dip 0.22/0.50, weight response 0.25/0.55, lean 0.20/0.85, head roll 0.24/0.80, arm 0.35/0.75, pointing 0.41/0.85, panel open 0.42/0.88, collapse 0.34/0.95, page push 0.36/1.00.
- Brace: support's mean acceleration over 100 ms above 24,000 pt/s², released after 120 ms below 8,000 (the brief's 3,000 fires on every ordinary ride; see `DECISIONS.md`).

## Art the stand-in rig covers for

In the brief's priority order: gaze set (pupils that move independently, blink, eyes closed in contentment); squint on touch; two shuffle step poses; sitting cross-legged; sitting on an edge with legs hanging; stretch (arms up, on toes); brace (arms out); listening (glove at the ear); optional thinking (glove at the chin). Check the owner's pack for each before asking for new drawings.
