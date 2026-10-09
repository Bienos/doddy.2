# Doddy video asset kit — image-generation prompts

**Status:** proposed working document. Nothing here is approved brand art. Outputs from these prompts are **concept / reference art** until an owner or illustrator reviews them and redraws production files.

**Purpose:** a complete, copy-paste prompt pack for generating the assets needed for short vertical videos where Doddy appears (a) as a 2D cartoon in real-world footage and (b) in his own hand-drawn "Pocket Notebook" world.

**Tool:** written for ChatGPT image generation, but works with any image model that accepts reference images. Every prompt is fully written out so it can be run as-is, by a person or by another AI agent working through the list in order.

---

## 0. Before you start

### 0.1 Blocking decision
Two different "v1.3" brand packs exist (see `docs/design/BRAND_AND_CHARACTER.md`). Pick one master before publishing any video. Until then, everything generated here is internal only.

### 0.2 Reference images to attach
Attach these in the **same message** as the setup prompt (section 1). Image models follow what they see far better than what they read.

| # | File |
|---|---|
| 1 | `design/ios-ready-asset-catalog/DoddyCharacter.xcassets/Doddy_waving.imageset/Doddy_waving_light@3x.png` |
| 2 | `design/ios-ready-asset-catalog/DoddyCharacter.xcassets/Doddy_walking.imageset/Doddy_walking_light@3x.png` |
| 3 | `design/ios-ready-asset-catalog/DoddyCharacter.xcassets/Doddy_sitting.imageset/Doddy_sitting_light@3x.png` |
| 4 | `design/ios-ready-asset-catalog/DoddyCharacter.xcassets/Doddy_pointing.imageset/Doddy_pointing_light@3x.png` |
| 5 (optional) | `design/interface-v1.2/previews/08-motion-storyboard.png` (shows five poses side by side) |

### 0.3 Working rules
1. Use **one chat** for the whole kit so the character lock stays in context. If the chat gets long and Doddy starts drifting, start a new chat and repeat section 1 with the references.
2. Send **one prompt per message**.
3. Check every output against the QA checklist (section 12) before saving it.
4. Save accepted images using the naming convention (section 13).
5. Do not commit generated images to this repo until their provenance has been reviewed (see `docs/design/ASSET_FONT_AND_RIGHTS_HANDOFF.md`).

### 0.4 What these outputs are and are not
- **They are:** model sheets, expression and mouth references, pose keys, background concepts, transition storyboards, composite tests.
- **They are not:** layered, rig-ready production files. Image models return flat images with no layers. Anything that will be animated must be traced or redrawn to vector, using the existing layered SVGs in `design/interface-v1.2/assets/` as the base.
- **Product honesty:** videos must not present unbuilt features (memory, voice, system integration) as working product. Story and concept videos must read as such.

---

## 1. Setup prompt — character lock (send first, with the references)

```
I'm building a production asset kit for my cartoon character "Doddy" for short vertical videos. The attached images are the official character. Every image you make in this chat must match them exactly. Before each image, re-read these rules:

CHARACTER LOCK — DODDY
- Hand-drawn stick figure with a big round head (head diameter ≈ 30% of total height).
- Head: perfect circle, cream fill #FFF7E9, thick black ink outline #171715.
- Face: two small vertical oval black eyes, ONE small arched eyebrow, only above the eye on the viewer's right (the asymmetry is part of his look), a simple warm curved smile. No nose, no ears, no hair, no cheeks.
- Body: one single black line for the spine, slightly curved. Arms and legs are thin single black lines with soft bends at elbows and knees. Same line weight everywhere, rounded line ends. No torso shape, no clothes.
- Hands: small cream mitten hands (#FFF7E9) with a black outline, a thumb and simple finger lines.
- Feet: oversized cream low-top trainers with a black outline, laces drawn as short lines, a sole line.
- Accent colour: orange #FF6A00, used ONLY sparingly (motion tick marks, props). Never on his body.
- Style: flat colour, clean ink lines with a slight hand-drawn wobble. No gradients, no shading, no 3D, no texture on the character, no glow.
- Never add text, logos, signatures or watermarks unless I ask.

Default background: plain warm paper #F8F4EB, or transparent when I say "transparent".
If anything I ask conflicts with the lock, keep the lock and tell me.
Reply "Ready" and wait for my first sheet.
```

---

## 2. Model sheet

### 2.1 Turnaround
```
Create a character turnaround sheet of Doddy: front, three-quarter, side profile and back view, standing in a neutral relaxed pose, all four at the same height and evenly spaced on one horizontal baseline. Faint light-grey horizontal guide lines at head top, shoulders, hips and feet so proportions can be compared. Plain warm paper background #F8F4EB. Landscape 3:2. No text.
```

### 2.2 Size comparison (sets his real-world scale)
```
Create a size comparison sheet: Doddy standing next to everyday objects drawn as simple grey line drawings — a smartphone standing upright, a takeaway coffee cup, a ballpoint pen and a human hand. Doddy is 12 cm tall, so he is slightly shorter than the upright phone and a little taller than the coffee cup. Doddy stays fully on-model in black ink and cream. Plain warm paper background. Landscape 3:2. No text.
```

### 2.3 Line and colour spec
```
Create a style spec sheet for Doddy: one large front view of Doddy on the left; on the right, four colour swatches as flat circles — ink black #171715, cream #FFF7E9, orange #FF6A00, warm paper #F8F4EB — and three sample strokes showing his line weights: head outline (thickest), limbs, face details (thinnest). Plain warm paper background. Landscape 3:2. No text other than the four hex codes under the swatches.
```

---

## 3. Expressions

### 3.1 Expression sheet
```
Create an expression sheet of Doddy: 12 head-and-shoulders close-ups in a 4×3 grid, same size and angle (front). Expressions in reading order: neutral, happy, big laugh, curious, thinking (eyes looking up), surprised, "oops" (awkward smile), proud, focused (narrowed eyes), confused, sleepy, gentle reassuring smile. Only the eyes, eyebrow(s) and mouth change — head shape, line weight and colours stay identical. Plain warm paper background. Square 1:1. No text.
```

### 3.2 Three-quarter expressions
```
Create a second expression sheet of Doddy, same 12 expressions in the same order, but every head turned to a three-quarter view facing right. Same 4×3 grid, same sizes. Plain warm paper background. Square 1:1. No text.
```

---

## 4. Lip-sync and blinks

### 4.1 Mouth chart
```
Create a lip-sync mouth chart for Doddy: 9 identical front-facing heads in a 3×3 grid, neutral eyes, only the mouth changes. Mouth shapes in reading order: rest (closed smile), A/I (open wide), E (wide, with one teeth line), O (round), U (small pucker), M/B/P (lips pressed flat), F/V (top line over bottom lip), L (open with a tongue line), W/Q (small round). Simple black-line mouths matching his style — no lips, no teeth detail beyond a single line. Plain warm paper background. Square 1:1. No text.
```

### 4.2 Blink sequence
```
Create a blink sequence for Doddy: 4 identical front-facing heads in a row — eyes open, half-closed, closed (two short curved lines), half-closed. Everything else identical. Transparent background. Landscape 4:1.
```

### 4.3 Eye directions
```
Create an eye-direction sheet for Doddy: 9 identical front-facing heads in a 3×3 grid with a neutral smile; only the eye position changes — up-left, up, up-right, left, centre, right, down-left, down, down-right. Plain warm paper background. Square 1:1. No text.
```

---

## 5. Hands

```
Create a hand reference sheet of Doddy's cream mitten hands (#FFF7E9, black outline, same style as the reference), 12 hands in a 4×3 grid, each with a short piece of black arm line: open palm, wave, fist, point, thumbs up, peace sign, OK sign, relaxed, gripping (holding a cup), holding a phone, open grabbing, fist bump. Transparent background. Square 1:1. No text.
```

---

## 6. Props

### 6.1 Main prop sheet
```
Create a prop sheet for Doddy's world, drawn in his exact ink style (black #171715 outline, cream #FFF7E9 and orange #FF6A00 fills, flat, no shading): a smartphone with an orange case and a small heart on the screen, a takeaway coffee cup, an open laptop, an orange basketball, a small orange backpack, an open notebook, a pencil, and a memory card shaped like a small index card with an orange heart. Each prop separated with space around it. Transparent background. Square 1:1. No text.
```

### 6.2 Doddy wearing the backpack (optional — only if the backpack becomes part of his look)
```
Create a turnaround of Doddy wearing the small orange backpack from the prop sheet: front, three-quarter, side and back views on one baseline. The backpack straps are thin black lines over his shoulders. Everything else stays on-model. Plain warm paper background. Landscape 3:2. No text.
```

### 6.3 Effects and motion marks
```
Create an effects sheet in Doddy's ink style: orange #FF6A00 motion tick marks (3 short dashes) in four directions, a small dust puff (cream with black outline), speed lines, a sparkle burst, a sweat drop, a question mark, an exclamation mark, a small heart, and a pencil-scribble cloud. Each separated with space. Transparent background. Square 1:1. No other text.
```

---

## 7. Animation key poses

Each sheet is one action. Poses sit on a shared ground line, with light-grey frame numbers under each pose.

### 7.1 Walk cycle
```
Create a walk-cycle key pose sheet for Doddy in side view facing right: 8 frames in one row on a shared ground line — contact, down, passing, up, contact (other leg), down, passing, up. Arms swing opposite to the legs. The big trainers stay the same size in every frame. Light-grey frame numbers 1–8 under each pose. Plain warm paper background. Wide 3:1.
```

### 7.2 Idle breathing loop
```
Create an idle breathing loop for Doddy in front view: 4 frames in one row on a shared ground line. Tiny up-down settle: frame 1 neutral, frame 2 slightly lower (knees softly bent), frame 3 neutral, frame 4 slightly taller. Changes are subtle. Light-grey frame numbers 1–4. Plain warm paper background. Wide 2:1.
```

### 7.3 Run cycle
```
Create a run-cycle key pose sheet for Doddy in side view facing right: 6 frames in one row on a shared ground line — contact, down, push-off, flight (both feet off the ground), contact (other leg), flight. Body leans forward, arms pump with bent elbows, orange motion ticks behind him only in the flight frames. Light-grey frame numbers 1–6. Plain warm paper background. Wide 3:1.
```

### 7.4 Jump
```
Create a jump sequence for Doddy in three-quarter view: 5 frames in one row on a shared ground line — anticipation crouch, take-off stretch, peak (arms up, happy face), landing squash (knees bent deep), recovery standing. Light-grey frame numbers 1–5. Plain warm paper background. Wide 3:1.
```

### 7.5 Wave
```
Create a wave sequence for Doddy in front view: 5 frames in one row — arm down, arm rising, hand up open, hand tilted left, hand tilted right. Small orange motion ticks near the hand in frames 4 and 5. Happy face throughout. Light-grey frame numbers 1–5. Plain warm paper background. Wide 3:1.
```

### 7.6 Sit down
```
Create a sit-down sequence for Doddy in side view facing right: 5 frames in one row — standing beside a simple cardboard box, looking back at the box, bending knees, lowering, sitting relaxed on the box. Box drawn in the same ink style. Light-grey frame numbers 1–5. Plain warm paper background. Wide 3:1.
```

### 7.7 Turn around
```
Create a turn-around sequence for Doddy: 5 frames in one row on a shared ground line — front, three-quarter right, side right, three-quarter back, back. Neutral pose, same height in every frame. Light-grey frame numbers 1–5. Plain warm paper background. Wide 3:1.
```

### 7.8 Pop in / pop out
```
Create a pop-in sequence for Doddy: 5 frames in one row — a small black ink dot, the dot bursting into a scribble cloud, Doddy appearing in a stretched cheerful pose with arms up, a small squash settle, Doddy standing and smiling. Orange motion ticks in frame 3. Light-grey frame numbers 1–5. Plain warm paper background. Wide 3:1.
```

### 7.9 Talking gestures
```
Create a talking-gesture sheet for Doddy in front view: 6 poses in a 3×2 grid — explaining with one open palm, counting on fingers, pointing up with an idea, shrugging, both hands on hips, leaning in with a hand cupped to the mouth as if sharing a tip. Mouths open in a mid-sentence shape. Plain warm paper background. Square 1:1. No text.
```

---

## 8. Doddy's own world — "Pocket Notebook"

### 8.1 World style frame (generate first; it sets the look for 8.2–8.6)
```
Create a style frame for Doddy's own world, called the "Pocket Notebook" world: everything is drawn in black ink on warm cream paper #F8F4EB with faint ruled notebook lines, flat colours, sparse orange #FF6A00 accents, hand-drawn line wobble, generous empty space, cosy and calm. Show a wide establishing view: a giant open notebook as the ground, with small sketched buildings, a lamp post and a tree growing out of the page. Include Doddy small in the centre, walking. Vertical 9:16. No text.
```

### 8.2 Location — Doddy's home desk corner
```
Design a background location in the "Pocket Notebook" world style from the previous image: Doddy's home — a cosy desk corner on a giant notebook page, with a lamp, a mug and a tiny shelf of index cards. NO characters — background only. Vertical 9:16; leave the lower-middle third open for Doddy to stand in. No text.
```

### 8.3 Location — basketball court
```
Design a background location in the same "Pocket Notebook" world style: an outdoor basketball court drawn on graph paper, one hoop with an orange rim, a bench, a few sketched trees. NO characters — background only. Vertical 9:16; leave the lower-middle third open for Doddy. No text.
```

### 8.4 Location — coffee corner
```
Design a background location in the same "Pocket Notebook" world style: a small coffee corner with a counter, a coffee machine, a pastry stand and a chalkboard with only doodles on it. NO characters — background only. Vertical 9:16; leave the lower-middle third open for Doddy. No text.
```

### 8.5 Location — memory shelf
```
Design a background location in the same "Pocket Notebook" world style: a tall library bookcase filled with index cards, folders and small boxes, a rolling ladder, a few cards marked with small orange hearts. NO characters — background only. Vertical 9:16; leave the lower-middle third open for Doddy. No text.
```

### 8.6 Location — rooftop at night
```
Design a background location in the "Pocket Notebook" world NIGHT style: charcoal background #16171C, all lines in cream #FFF7E9 instead of black, a rooftop with a railing, a sketched city skyline, a moon, and a few warm orange #FF6A00 lit windows. NO characters — background only. Vertical 9:16; leave the lower-middle third open for Doddy. No text.
```

### 8.7 Night versions of the other locations
Run once for each of: home desk corner, basketball court, coffee corner, memory shelf.
```
Redraw the [LOCATION NAME] background as a night version: charcoal background #16171C, all lines in cream #FFF7E9, a few warm orange #FF6A00 light sources. Same composition, same layout, no characters. Vertical 9:16. No text.
```

### 8.8 Foreground layers (for parallax)
Run after each accepted location.
```
Using the same location, give me only the foreground elements (the objects nearest the camera, such as the desk edge, the bench or the counter front) on a transparent background, positioned exactly where they sit in the full image, so I can layer them over the background.
```

### 8.9 Doddy in the world (placement test)
```
Place Doddy, fully on-model, into the [LOCATION NAME] background: [ACTION, e.g. "sitting at the desk reading a notebook"]. He is in the lower-middle third, at a size where his head is about one-eighth of the frame height. Keep the background unchanged. Vertical 9:16. No text.
```

---

## 9. Moving between the worlds

### 9.1 Stepping out of the phone
```
Create a 4-frame storyboard strip (vertical frames side by side) of Doddy stepping OUT of a smartphone screen into the real world: 1) Doddy inside the phone screen in his notebook world, 2) his hand and trainer poking out past the screen edge, 3) half in / half out, 4) standing next to the phone on a real wooden desk. Doddy stays flat 2D ink in every frame, even in the real world; the real world is photographic. Light-grey frame numbers. No other text.
```

### 9.2 Page turn
```
Create a 4-frame storyboard strip (vertical frames side by side): 1) a real-world photo of a desk, 2) the corner of the photo curling like a notebook page, 3) the page half turned, revealing the "Pocket Notebook" world underneath, 4) the notebook world fully revealed with Doddy waving. Light-grey frame numbers. No other text.
```

### 9.3 Drawn door
```
Create a 4-frame storyboard strip (vertical frames side by side): 1) Doddy in the notebook world holding a giant pencil, 2) Doddy drawing a door outline in the air, 3) the door opening to show a photographic real-world kitchen beyond it, 4) Doddy stepping through, still flat 2D ink, into the real kitchen. Light-grey frame numbers. No other text.
```

### 9.4 Ink splat wipe
```
Create a 4-frame storyboard strip (vertical frames side by side) of an ink-splat transition: 1) the notebook world, 2) a black ink drop falling into the centre, 3) the splat spreading to cover most of the frame, 4) the splat clearing to reveal a real-world photo with Doddy standing in it. Light-grey frame numbers. No other text.
```

---

## 10. Doddy in the real world

Attach **your own photo** to each prompt. Shoot photos vertically, with nothing in the frame you don't own the rights to (no logos, no people without consent).

### 10.1 Composite test
```
Place Doddy into the attached photo as a flat 2D hand-drawn cartoon, about 12 cm tall, standing [on the desk next to the coffee cup, waving]. Keep him exactly on-model and flat — no 3D, no shading on him. Add only a soft grey contact shadow under his trainers matching the photo's light direction. Do not change anything else in the photo. Keep the photo's aspect ratio.
```

### 10.2 Interaction test (an object in front of him)
```
Place Doddy into the attached photo as a flat 2D hand-drawn cartoon, about 12 cm tall, standing partly BEHIND [the coffee cup], peeking around it with a curious face. The cup correctly covers part of his body. Soft grey contact shadow under his trainers matching the photo's light. Keep him flat and on-model. Do not change anything else in the photo.
```

### 10.3 Pocket pop-out
```
Place Doddy into the attached photo of [a jacket or jeans pocket] as a flat 2D hand-drawn cartoon, climbing out of the pocket: head, one arm and one trainer out, waving with a happy face, small orange motion ticks by his hand. The pocket edge correctly covers his lower body. Keep him flat and on-model. Do not change anything else in the photo.
```

### 10.4 Real-world shot list storyboard
```
Create a 6-panel vertical storyboard (2×3 grid) for a 15-second video, "Doddy finds your keys": 1) a real hallway photo, a keys hook with no keys, 2) Doddy pops out of the phone on a side table, 3) Doddy looking around with a hand above his eyes, 4) Doddy pointing at the keys under a cushion, 5) a human hand picking up the keys, 6) Doddy giving a thumbs up. Real world photographic, Doddy flat 2D ink. Light-grey panel numbers. No other text.
```
Note: this is a story idea only. Doddy does not actually find objects; the video must not imply that as a product feature.

---

## 11. Video templates

### 11.1 Safe-area template
```
Create a vertical 9:16 layout template on plain warm paper #F8F4EB: a thin grey outline marking the central safe area (leave about 14% clear at the top and 20% at the bottom and right side for social media buttons), a small Doddy waving in the lower-left of the safe area, and a large empty space for captions above him. No text.
```

### 11.2 End card (no wordmark yet — the wordmark is not final)
```
Create a vertical 9:16 end card in the "Pocket Notebook" style: warm paper background with faint ruled lines, Doddy in the centre waving goodbye with a happy face, a small orange heart floating above his hand, and a clean empty band in the lower third for a logo to be added later. No text, no logo.
```

### 11.3 Caption style sample
```
Create a vertical 9:16 frame showing a caption style for Doddy videos: one short caption line "your mate in your pocket" in a clean rounded sans-serif, black #171715 text on a cream #FFF7E9 rounded pill with a thin black outline, sitting in the lower-middle third over a blurred real-world photo. Doddy, small and flat 2D, stands next to the pill pointing at it.
```

---

## 12. QA checklist — check every image before saving

- [ ] Head is a perfect circle, cream fill, thick black outline
- [ ] Two vertical oval eyes and **one** eyebrow on the correct side
- [ ] No nose, ears, hair, cheeks, torso, clothes or extra fingers
- [ ] Limbs are single lines of even weight
- [ ] Hands are cream mittens, trainers are oversized and cream
- [ ] Orange appears only on props and effects, never on his body
- [ ] Flat colour: no gradients, shading, 3D or glow on Doddy
- [ ] No unwanted text, logos or watermarks
- [ ] The requested background is correct (paper or transparent)
- [ ] In real-world shots: Doddy stays flat 2D and has a contact shadow

**Fix-up prompt** when something drifts:
```
Off-model: [describe the problem, e.g. "he has a nose", "the trainers are too small", "the eyebrow is on the wrong side"]. Redo the same image following the character lock exactly. Change nothing else.
```

**Fix-up prompt** when the style drifts after many images:
```
Re-read the character lock and look at the original reference images again. The last few images have drifted [describe how]. Redo the last image matching the references exactly.
```

---

## 13. File naming and storage

Save accepted outputs **outside this repo** (for example in a shared drive) until reviewed:

```
doddy-video-kit/
  01-model/        doddy_turnaround_v01.png, doddy_scale_v01.png, doddy_stylespec_v01.png
  02-expressions/  doddy_expr_front_v01.png, doddy_expr_34_v01.png
  03-lipsync/      doddy_mouths_v01.png, doddy_blink_v01.png, doddy_eyes_v01.png
  04-hands/        doddy_hands_v01.png
  05-props/        doddy_props_v01.png, doddy_fx_v01.png
  06-poses/        doddy_walk_v01.png, doddy_idle_v01.png, doddy_run_v01.png, ...
  07-world/        world_styleframe_v01.png, world_home_day_v01.png, world_home_night_v01.png, world_home_fg_v01.png, ...
  08-transitions/  trans_phone_v01.png, trans_page_v01.png, trans_door_v01.png, trans_ink_v01.png
  09-realworld/    rw_desk_test_v01.png, rw_peek_v01.png, rw_pocket_v01.png
  10-templates/    tpl_safearea_v01.png, tpl_endcard_v01.png, tpl_caption_v01.png
```

Pattern: `<group>_<subject>[_<variant>]_v<NN>.png`. Raise the version number on each accepted regeneration, and never overwrite an earlier version.

---

## 14. Recommended order and minimum kit

1. Section 1 (setup), then 2.1 turnaround → 3.1 expressions → 4.1 mouths → 4.2 blinks
2. 7.1 walk, 7.2 idle, 7.5 wave, 7.8 pop-in
3. 8.1 world style frame → one location (8.2) → its foreground layer (8.8)
4. 9.1 phone step-out
5. 10.1 composite test using your own desk photo
6. 11.2 end card

That's the minimum to storyboard and animate a first 15-second video. Everything else can follow.

## 15. After generation (not covered by these prompts)

- Redraw the accepted model sheet, mouth chart and pose keys as layered vectors, starting from the existing SVGs in `design/interface-v1.2/assets/` (their arm, leg, hand, eye and mouth layers are already separated).
- Rig in After Effects, Rive, Moho or Spine.
- Choose a voice (an actor, or a designed voice you clearly own) and build a small sound kit.
- Shoot real-world footage: vertical 4K, a clean take and a stand-in take for every shot, camera-tracking data for handheld shots.
- Record provenance for every generated image before any of it enters this repo or a public video.
