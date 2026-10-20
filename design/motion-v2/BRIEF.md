# Doddy motion brief v2 (owner, 18 Oct 2026)

Verbatim text of the brief. Tables were pasted as one cell per line.

Doddy motion prompt: a world he lives in
18 Oct 2026 · @pat
Your job
Produce Doddy's motion package v2: fixed and new motion studies, a 30-second journey and an updated interactive prototype, all following this brief.
You are the motion director for Doddy, a Polish-first, voice-first iPhone sidekick. The goal is that he feels like he lives in the app. On every screen he stands somewhere sensible, moves as a physical part of the interface and notices what happens. The interface never waits for him.
This brief builds on the v1 motion review of the package "A world he belongs in" (17 Oct 2026). If the review is attached, use it for any number this brief doesn't restate. Where the two disagree, this brief wins; the main change is a larger, more interactive Doddy on Home.
Work in the v1 format: a 390 × 844 pt iPhone canvas, 60 fps, silent, each file labelled as a simulation. Animate motion only and leave product flows, features and copy as they are. Flag every behaviour that needs new drawings and use the stand-in rig until they exist.
Who Doddy is
Doddy is one small line-drawn helper, 96 pt tall. His charm comes from precision and restraint, not constant motion.
The drawing
• Round head 36 pt across including its outline, single-line body and limbs, white cartoon gloves, white laced sneakers.
• Face: two upright oval eyes, a single brow, a smile. Mood shows only in brow and mouth: calm, curious, pleased, concerned.
• Pupils must move on their own, independent of the head. v1 had no gaze drawings, so commission them first.
• Colours: ink #0B0B0B, head fill #FCF8EF, app background cream #F3EDDF, surfaces #EDE4D7, rules #D6D0C2, accent rust #A64B19 (the dot in the "doddy." wordmark).
• Match the look and voice of doddy.lol.
His personality in motion
• A sidekick (pomocnik), not a pet or a friend. He is attentive and useful; he never asks for attention, sulks or begs you to come back.
• Sharp online: in the app he is exact. He lands on the edge, arrives on time and never stands in the way.
• Clumsy offline: a small, endearing wobble is allowed inside a rare playful moment, never during a task.
• Honest always: no listening pose unless the microphone is live, and nothing that looks like sending unless Apple's composer reports it sent.
• Acts only on your tap: he looks and points. He never presses, drags or opens anything himself.
The spaces he lives in (390 × 844 pt)
• Home: his stage. A short stage line, the heading "I'm here." and "Tap Doddy to talk". English copy here is placeholder; the app ships in Polish.
• Talk: the conversation thread above a message composer that rides the keyboard.
• Memories: a scrolling list of saved items, each keeping the user's exact words, with detail pages behind "View original note".
• Draft review: a panel that rises from a strip above the tab bar, like a music mini-player, and collapses back into it. It is not a tab.
• Tab bar: Home, Talk, Memories.
Rules he never breaks
These 13 rules come from the v1 review and override any study, beat or idea below.
1. One Doddy. One instance for the whole app. Never re-created per screen and never two on screen, including inside transitions.
2. The interface never waits. Tab content commits in the tapped frame and finishes within 140 ms. Doddy catches up.
3. Eyes first. Every reaction starts with the pupils at 0 ms (95% there in 88 ms), then the head, then the body.
4. Feet on something real. At rest and while riding, his soles sit on a real edge, within ±2 pt (±1 pt on the composer). He never floats or stands inside content.
5. Free travel is one hop. Crouch, arc, contact, settle. No walk cycles or slides for navigation.
6. Moving surfaces carry him. On a panel, composer, scrolling list or page he moves as part of it, in the same frame.
7. Momentum carries through. A new destination bends his current path. He never stops dead, restarts or pops.
8. Clear zones. His body never covers text, buttons or hit areas: at least 24 pt from Send and "Review ›", 16 pt from links.
9. Stillness is the default. No idle loops. Every reaction has a visible cause, a set length and a cap. One playful moment per session.
10. Honest always. Listening pose only while the microphone is live, with a visible stop control. No "sent" cue unless Apple's composer returns sent. He reads task state and never writes it.
11. He never operates the interface. He looks and points; the user taps.
12. Accessible. Reduce Motion turns his hops into fades (120 ms out, 180 ms in); he still rides what the system moves, without squash, and his eyes still lead. He is hidden from VoiceOver, and anything he invites is a real button.
13. Two sizes, one figure. 96 pt everywhere, 1.4× on Home. His size changes only while he is in the air or faded out.
His world: surfaces, layers and his spot on every screen
The app is a world of edges he can stand on. Every screen offers at least one, so he always has a spot.
What he can stand on
• Ground lines: the Home stage line, list rules, card tops, the source block's top rule, and the tab bar's top hairline ("the rail").
• Moving platforms: the draft panel and strip, the composer while the keyboard moves, scrolling list content, detail pages sliding in.
• Props: a large wordmark (only where its cap height is at least 64 pt) and empty-state headings.
• Edges to hide behind: panel and page edges, for peeking and for being covered.
• Never: the status bar, Dynamic Island, home indicator, keyboard keys, buttons, lines of text or system sheets. Apple's composer, share sheets and alerts simply cover him.
Layers, front to back
1. System keyboard
2. Tab bar
3. Tab rail, where he waits during rapid switching
4. Draft panel and strip
5. Detail pages
6. Tab content
He is drawn just above the surface he stands on, so a page pushed over his spot covers him in place. In the air he takes the higher of the two surfaces' layers.
Clear zone
The box above his spot stays empty: 48 × 108 pt at normal size, 67 × 151 pt on Home. Scrolling lists get a 108 pt bottom inset so their last item can always scroll clear of him.
His spot on every screen
Screen or state
His spot
Position (pt)
If it's gone or blocked
Size
Home
Centre of the stage line
x 195, y 470; line 140 wide
—
1.4×
Talk
Composer top edge, left of Send
x 250; centre never past 284
Tab rail
1.0×
Talk, keyboard up
The same spot, riding the composer
Follows the keyboard
—
1.0×
Draft review open
Panel top edge, right of the grabber
x 250, y 380
—
1.0×
Memories, no draft
First fully visible rule, right end
x 330
Next visible rule, then the rail
1.0×
Memories, draft waiting
Strip top edge, over the gap before "Review ›"
x 250, y 652
—
1.0×
Memories detail page
Source block's top rule
x 330
—
1.0×
Empty Memories
Empty-state heading baseline
Centred
Wordmark perch (rare)
1.0×
Rapid tab switching
Rail under the selected tab
y 724
Strip, if showing
1.0×
He remembers his last spot and what he was looking at on each screen, and returns there.
How he gets around
Every move he makes uses one of the nine ways below; anything else needs its own study and a reason. Items marked NEW are additions in v2.
Hop: all free travel
• Use it for every move between two surfaces that aren't touching.
• Beats: eyes to the destination at 0 ms → crouch 80 ms (hips 5 pt down, lean 3° away) → arc 260–420 ms → contact 60 ms → settle about 280 ms.
• Crouch length: 140 ms from sitting; 40 ms within 340 ms of a landing or from a surface moving his way; 0 ms when his surface is about to drop away, so he leaves before it moves.
• Flight time T = clamp(220 + 0.4·D + 0.2·|Δy|, 260, 420) ms, where D is the distance in pt.
• Apex = clamp(12 + 0.08·D, 16, 32) pt above the higher end. Stepping down more than 40 pt: clamp(6 + 0.04·D, 10, 18), so he doesn't sweep over the new screen.
• Path: constant horizontal speed with a parabolic height. Arms rise in the first 40% of the flight and the legs tuck at the apex.
• Contact: a squash of 2.2–4.4 pt scaled by impact, the surface dips up to 1.5 pt, and he slides through 3–4 pt before settling.
• Aim for where the landing edge will be at touchdown. If that point moves more than 2 pt, re-plan from where he is, keeping his velocity.
Changing his mind in the air
• A new destination mid-flight starts a new path from where he is, with the velocity he has: clamp(180 + 0.5·D, 200, 360) ms.
• Total time in the air stays within 520 ms, but never faster than 1,200 pt/s on average. With less than 160 ms of air left, he lands first and hops on.
• His eyes jump to the new target at once and his face swings through front in about 120 ms.
• During the crouch, a new destination re-aims the hop. If it's where he started, the hop is cancelled and he never leaves the ground.
Ride: moving surfaces
• On the panel, strip, composer, scrolling content or a sliding page, his soles stay on its edge every frame.
• Weight response: he compresses up to 3 pt as the surface accelerates and overshoots once when it stops (spring 0.25/0.55).
• Keyboard: use the system's own duration and curve, and follow interactive dismissal frame by frame.
• If the surface is already speeding away from his destination, he rides until it slows below 150 pt/s, then steps off.
Step across
• When the edge he rides passes another valid surface at the same height, he steps onto it: a 40 ms crouch, and the new surface dips 1.5 pt.
• Example: the review panel collapsing past the composer.
Shuffle (NEW)
• For moving along the same surface by up to 40 pt: a button appeared next to him, Dynamic Type changed, or a clear zone pushes him over.
• Beats: eyes to the new spot at 0 ms → two small steps of 110 ms, the moving foot lifting 3 pt, the planted foot never sliding → settle in 120 ms.
• His face turns halfway toward the move, then back to front. Under 8 pt it's one side-step of 110 ms; over 40 pt he hops.
• Never while his surface is moving; he waits for it to stop.
• Reduce Motion: a 90 ms fade out and a 120 ms fade in.
Scroll riding and lily-pad hops (NEW)
• In a scrolling list he rides his rule as part of the content: same frame, no lag.
• When his rule is about to leave the safe band, he hops to the nearest rule inside the middle 60% of the list, on the side new content comes from. "About to leave" means that within 150 ms his head would pass under the top edge or his feet would sink behind the tab bar or strip.
• Lily-pad hops happen only during slow scrolls (under 300 pt/s), at most one every 1.2 s. If a hop is needed sooner, he goes to the rail instead.
• Faster scrolls, flings and scroll-to-top send him to the rail (or the strip) to wait. Once the list has moved slower than 150 pt/s for 200 ms, he makes one hop to the best rule; if none fits, he stays on the rail.
• Aim at where the target rule will be at touchdown, using the current scroll velocity, and re-plan if it drifts more than 2 pt.
• Rubber-band overscroll gets the weight response only. He never lands on a row that is being touched or swiped.
• Reduce Motion: fade to the new rule or the rail.
• If lily-pad hops read as busy in testing, keep only the rail wait.
Brace (NEW)
• When his surface accelerates hard (over 3,000 pt/s², for example a flicked panel), he adds arms out 25° for balance to the weight response.
• The arms come back once the acceleration drops below 1,000 pt/s². Once per ride; off under Reduce Motion.
Wait on the rail
• Three or more destination changes within 900 ms send him to the rail (or the strip) under the tab selected at that moment.
• Further taps move only his eyes. After 350 ms without a change, he makes one hop to the final spot.
Covered by a page
• A detail page pushed over his spot covers him where he stands, and the pop reveals him in place. The mask follows the real push and pop progress; a pop uncovers the left edge first.
• Arriving on Memories while a detail page is open, he hops onto the page's source rule.
Fade: Reduce Motion
• Every hop becomes a 120 ms fade out, a placement and a 180 ms fade in, with the eyes still turning first. He still rides what the system moves, like the keyboard and scrolling lists, without squash.
• A new destination during the fade-out just moves the fade-in. One during the fade-in fades him out again from where he is, so he never jumps while visible.
• Size changes happen while he is invisible.
Home: bigger and more interactive
On Home the camera moves in: Doddy is 1.4× (134 pt tall) and answers touch. Everywhere else he stays 96 pt.
Size: the camera comes closer, he doesn't grow
• Home size is 1.4×: head 50 pt, 134 pt tall. Test 1.3×, 1.4× and 1.5× in the prototype and keep the largest one people still call "the same little guy".
• Scale the whole drawing, line weight included, so it reads as the camera moving closer rather than a new drawing. Face proportions, timings and squash percentages stay the same; distances in pt scale with him (the crouch becomes 7 pt).
• His size changes only in flight: scale = start + (target − start) × smoothstep(0.15, 0.9, s), where s is flight progress. He takes off at the old size and lands at the new one; a re-target starts from his current scale.
• Every move between a Home surface and any other surface is a hop, never a ride or a step across, so the size change always happens in the air. Example: when the draft strip is tapped on Home, he hops about 90 pt up onto the rising panel, aimed at its touchdown edge, instead of being picked up.
• Reduce Motion: the size switches while he is faded out.
• Why this isn't v1 study 07: 07 zoomed a still pose by 1.9× and read as a zoom. Here each screen has one fixed size, and the change hides inside real travel.
Layout
• The stage line grows to 140 pt wide, with his soles at its centre.
• Keep a 67 × 151 pt clear zone above the stage. The "I'm here." heading starts at least 24 pt below his soles.
• A real "Talk to Doddy" button covers his clear zone plus 12 pt on every side (about 91 × 175 pt) and carries that VoiceOver label. The drawing is never the only hit area.
What he does when you touch Home
Gesture
Where
What Doddy does
Cap
Touch down
On him
Squints and dips 3 pt within 60 ms: he felt it
Every time
Tap
On him
Talk opens and he hops to the composer as the field focuses, shrinking in the air
Every time; a tap always talks
Press and hold, 450 ms or more
On him
Voice, if it can start from Home: listening pose only once capture is live, with a visible stop control; when capture ends he follows the conversation to Talk. Until then it acts as a tap on release
Every time
Finger down or moving
Anywhere else on Home
His eyes follow the finger, then return to you 300 ms after it lifts
Unlimited
Slow stroke across his head, under 600 pt/s
On him
Head rub: eyes close, pleased mouth, head tips 6° with the stroke. Eyes reopen to you 300 ms after the stroke ends
One per 1.5 s; after 5 in a minute he only smiles
Drag on his body
On him
Leans with the drag, feet planted: lean = 12° × tanh(dx ÷ 60 pt); pulling down crouches up to 6 pt, pulling up stretches up to 6%. On release he springs back with one overshoot (0.30/0.55)
Every time
Upward flick, released over 900 pt/s
On him
One hop in place, apex clamp(v ÷ 80, 8, 24) pt × 1.4, landing on the same spot with a pleased mouth
One per 3 s
• A touch that moves more than 10 pt is a drag or a stroke, never also a tap.
• No double-tap: it would delay every tap.
• He never leaves the stage because of a gesture, and nothing on Home can fling him off screen.
Living on Home
• After landing, his eyes go to you after 150 ms.
• Two seconds after settling he breathes three times (0.6 pt × 1.4, 4.2 s period), then holds still.
• At 15 s idle he sits once, cross-legged on the stage line.
• Glances: while idle, one glance every 25–45 s at something real, such as the draft strip when a draft is waiting or the Memories tab when something was saved since the last visit. With nothing to look at, one look-around per visit: eyes left, right, back to you, 1.4 s.
• Glances move the eyes and up to 5° of head, at most three per visit. Off in Low Power Mode; eyes only under Reduce Motion.
• A waiting draft gets one glance when he arrives. He never points at it or nags.
Welcomes: one per day, on Home, once Home is interactive
• Default: eyes to you, then a 5° head roll (200 ms out, 300 ms hold, 240 ms back).
• After 21:00: one slow 280 ms blink and a 3° roll.
• After 3 or more days away: one hop in place (apex 10 pt × 1.4) and a pleased mouth, then the default welcome.
• Reduce Motion: eyes only.
New behaviours that make him live everywhere
He feels present on every screen through attention more than movement. Most behaviours here are eye and posture changes with a visible cause; all are NEW unless marked v1.
Noticing: gaze-only reactions
Event
Where his eyes go
Then
Doddy's reply lands in Talk
The reply's first line, 300 ms
The composer
Something is saved to Memories from a chat
The Memories tab, 400 ms
Back to the screen's focus
A draft appears while he's on another surface
The strip as it rises, 300 ms
Back to the screen's focus
The user drags a panel or sheet
The grabber, for the whole drag
The panel edge on release
An error or offline banner appears
The banner, with a concerned brow while it's up
Calm once it's gone
A detail page slides in over his spot
The incoming page, 100 ms
Covered in place
Typing starts after 3 s idle (v1)
The text, with a 3° head dip, 240 ms
The composer
A message is sent (v1)
Follows the bubble up, with a 4° nod, 280 ms
The screen's focus
• One reaction at a time; the latest event wins within 100 ms.
• Each lasts at most 600 ms. Then his eyes go to the screen's focus, and to you after 1.2 s.
• Screen focus: you on Home, the composer on Talk, the draft's first line in review, the top item in Memories.
• Reduce Motion keeps these, because eye movement is allowed.
Thinking while the reply is coming
• Starts when a message was sent and no reply has appeared within 600 ms.
• Pose: eyes up and to the right, head tilted 4°, held still. No loop.
• Still waiting at 4 s: one slow blink, and his eyes move to the upper left once.
• When the reply starts, his eyes snap to it (88 ms) and his head straightens in 240 ms.
• If the request fails: concerned brow, eyes to the error.
• Once per message. Optional art: a glove at the chin. Reduce Motion: eyes only.
Sitting habits
• Home: sits cross-legged on the stage line after 15 s idle (v1 study 11).
• Draft strip in Memories, after 10 s idle: sits on its top edge over the empty gap before "Review ›", legs hanging in front. He swings them twice (600 ms), then holds still. Needs seated-edge art.
• List rules: he stays standing, because hanging legs would cover the next item.
• Talk: he stands, because the user may type at any moment.
• The rail: he never sits there, because he is waiting.
• Standing up uses the 140 ms crouch before any hop.
Ducking
• Something moving passes within 12 pt above his head, such as a toast or a banner. He crouches 6 pt and looks up (140 ms), holds while it overlaps, and rises in 220 ms.
• If it comes to rest over his clear zone, he shuffles or hops clear instead. Off under Reduce Motion.
Empty states
• Empty Memories: he sits on the empty-state heading's baseline and looks at its button.
• Where a large wordmark exists (cap height 64 pt or more), the perch from v1 study 04 may be that session's playful moment.
Coming back to the app (v1)
• On return he is placed at his current spot. If that spot moved while the app was away, he fades in there over 150 ms. Nothing replays.
Playful moments
Playful moments are rare: one per session, only after at least 8 s of idle, only where the table allows, and never during a task.
• A session starts when the app opens, or when it returns after 30 minutes away.
• Never while the review is open, the keyboard is up or the microphone is on, and never within 2 s of a tap.
• Never triggered by a tap, because a tap always talks.
• Not on a visit that already had the daily welcome.
• All are off under Reduce Motion.
Moment
Where
Beats
Length
Wave (v1 study 15, fixed)
Home
Arm in front of the head, glove at least 5 pt outside the head outline; 1.5 forearm swings in 450 ms
1.1 s max
Stretch (NEW)
Home
Stands up if sitting (140 ms), raises both arms high and rises 3 pt × 1.4 onto his toes over 500 ms, eyes closed for a 200 ms hold, back down in 400 ms. May end in a small wobble: clumsy offline
1.3 s max
Peek (v1 study 06)
Beside a panel edge on Home or Memories
Standing on the panel's base line, he leans head and one glove 14° out from behind its edge (220 ms), eyes on the panel, holds 600 ms, leans back (260 ms). Never ends hidden
About 1.1 s
Trace the source (v1 study 13)
Memories detail page
Only right after the user opens a source: eyes to "SOURCE", then the arm points −35° with the hand at least 12 pt clear of text
1.3 s max
Perch on the wordmark (v1 study 04)
Empty Home or Memories, About
Hops onto the top of a letter's stem and lands seated (60 ms squash). Leaves within 150 ms when the screen needs the space
Holds until needed
Keep, fix and cut from v1
Keep the riding studies, fix every free move, and drop the two studies that need new art or broke the one-figure rule.
Study
Verdict
What changes in v2
01 A quiet welcome
Keep
Stands on the stage line at Home size; pupils move first; once a day
02 One Doddy between tabs
Fix
Replace the walk with the standard hop; UI first; draw a real selected-tab state
03 Ride the rising sheet
Keep
Add the weight response
04 Perch on the wordmark
Rare
Only where the cap height is at least 64 pt; hop in and land seated
05 Hang from a letter
Cut
Needs grip, dangling-leg and release art first
06 Peek behind a panel
Rare
Head and one glove only; never ends hidden
07 Come a little closer
Cut
Replaced by Home's camera-close size
08 Make room for typing
Keep
Centre never past x 284, clear of Send; the system keyboard curve
09 Introduce the draft
Fix
Eyes, then head, then arm; 1.3 s max; editing ends it within 180 ms
10 Keep the draft nearby
Keep
Clear of "Review ›"; a 60 ms squash as the strip settles
11 Settle, then be still
Keep
On a real surface; three breaths, then still
12 Return to his spot
Fix
Crouch, true arc, contact squash, spring settle; Home complete within 300 ms
13 Trace the source
Rare
Only after the user opens the source
14 Travel behind the page
Fix
Stays put while covered; the pop uncovers the left edge first
15 A small invitation
Rare
Arm in front of the head; never on a tap
16 Change direction
Fix
UI commits in one frame; the path bends from his current velocity
17 The 24-second journey
Fix
Replaced by journey v2
All files
Fix
Hard cuts: no cross-dissolve frames between studies
Introduce the draft (09) in full: eyes to the draft's first line at 0 ms, head −8° from 60 ms, arm −40° from 200 ms with the hand at least 12 pt clear of the text. He holds 600 ms, returns in about 260 ms, and his eyes stay on the draft 400 ms more. Once per draft.
What to deliver
Deliver 5 fixed studies, 15 new studies, a 30-second journey and an updated prototype.
Format
• 390 × 844 pt at 2× (780 × 1688 px), 60 fps, silent MP4.
• 4–8 s per study, hard cut in and out, with 0.5 s of stillness at the start and 1 s of rest at the end.
• A clean render of each study, plus an annotated copy with a frame counter and his current surface drawn as a line.
• Name files v2-<number>-<short-title>.mp4 and label each as a simulation.
• Use the stand-in rig wherever final art doesn't exist yet, and say so on the file.
Fixed v1 studies
1. 02 Tab hop
2. 09 Introduce the draft
3. 12 Return to his spot, now arriving at Home size
4. 14 Behind the page
5. 16 Change direction mid-flight
New studies
1. N1 Home size: Talk → Home → Talk; he grows and shrinks only in the air.
2. N2 Home touch: eyes follow a finger, touch-down dip, tap opens Talk.
3. N3 Home play: head rub, drag-lean with spring-back, upward-flick hop.
4. N4 Hold to talk: press and hold; the listening pose appears only with the microphone indicator; he follows to Talk when capture ends.
5. N5 Home life: three breaths, sitting down, one glance at the waiting draft strip.
6. N6 Welcomes: default, after 21:00, back after 3 days (three short clips).
7. N7 Home and review: he hops onto the rising panel, shrinking in the air, then hops back and grows.
8. N8 Shuffle: a microphone button appears in the composer and he side-steps to keep Send clear.
9. N9 Scroll riding: a slow scroll with one lily-pad hop, then a fling, a rail wait and one hop back.
10. N10 Brace: a flicked panel snaps open under him.
11. N11 Thinking: send, the thinking pose, the reply lands.
12. N12 Noticing: a memory is saved and he glances at the Memories tab; an offline banner draws a concerned brow.
13. N13 Sitting on the strip edge.
14. N14 Stretch.
15. N15 Ducking under a toast.
Journey v2: one 30-second take, one Doddy
1. 0.0–1.5 s: Home. Doddy stands at 1.4× on the stage and gives the daily welcome.
2. 1.5–3.0 s: A finger moves over Home and his eyes follow it. It lands on him: touch-down dip, then the tap.
3. 3.0–3.5 s: Talk content swaps within 140 ms. He hops down to the composer, shrinking in the air, and touches down about 0.42 s after the tap.
4. 3.5–7.0 s: The field focuses, the keyboard rises and he rides it. Typing starts and his eyes go to the text.
5. 7.0–7.5 s: Send. His eyes follow the bubble up with a 4° nod.
6. 7.5–9.0 s: No reply yet, so he takes the thinking pose.
7. 9.0–10.0 s: The reply lands and his eyes snap to it. It mentions a saved memory, so his eyes go to the Memories tab for 400 ms.
8. 10.0–11.0 s: A draft becomes reviewable. The keyboard is about to hide, so he steps off at once and hops onto the rising panel.
9. 11.0–12.5 s: He introduces the draft.
10. 12.5–14.5 s: "Review & send" opens Apple's composer, which covers the app. It returns sent: pleased mouth.
11. 14.5–15.5 s: The panel clears away. He rides it down and steps onto the composer as it passes.
12. 15.5–16.5 s: Memories. He hops onto the first rule.
13. 16.5–21.0 s: A slow scroll. He rides his rule, then makes one lily-pad hop. A fling sends him to the rail; when the list stops, he makes one hop to the nearest rule.
14. 21.0–23.5 s: "View original note" opens and the page covers him in place. Back: he is revealed where he stood.
15. 23.5–25.0 s: Home. He hops up to the stage, growing to 1.4× in the air.
16. 25.0–30.0 s: He settles and his eyes go to you. The take ends on stillness.
Prototype update
• Home at 1.4× with a size switch (1.3×, 1.4×, 1.5×) and every gesture from the Home table.
• Memories as a scrolling list of at least 10 items with rules, with scroll riding, lily-pad hops and the rail wait.
• A simulated reply delay, a "saved to Memories" event, an offline banner, a toast, a composer microphone button, and sent, cancelled and failed results from Apple's composer.
• Keep v1's controls: playback 1×, 0.5× and 0.25×, Reduce Motion, flight path, anchors and the live state readout. Add a button per new study, and show scale, surface and scroll velocity in the readout.
Art you'll need
• Gaze: pupils that move, a blink, and eyes closed in contentment. Highest priority.
• Two step poses for the shuffle.
• Sitting cross-legged, and sitting on an edge with legs hanging.
• Stretch: arms up, on his toes.
• Brace: arms out.
• Listening, for voice.
• Optional: thinking, with a glove at the chin.
Acceptance checks
The package passes only if every check below holds in every file and in the prototype.
[ ] Exactly one Doddy in every frame.
[ ] Tab content is complete within 140 ms of every tap; no frame shows the interface waiting for him.
[ ] Whenever he isn't in the air, his soles are within ±2 pt of their surface (±1 pt on the composer).
[ ] Every free move shows a crouch (0–140 ms), a 260–420 ms arc, a 60 ms contact squash and a settle of about 280 ms. Tab hops at normal size touch down 340–484 ms after the tap.
[ ] He is 1.4× only on Home surfaces, and his scale changes only while he is in the air or faded out.
[ ] His clear zone never overlaps text, a button or a hit area: 24 pt from Send and "Review ›", 16 pt from links.
[ ] After three breaths nothing moves without a cause; there are no idle loops anywhere.
[ ] At most one playful moment per session, and none during a task.
[ ] On Home a tap on him always opens Talk, and a touch that moved more than 10 pt never does.
[ ] The listening pose appears only in frames where the microphone indicator is on.
[ ] Under Reduce Motion nothing arcs, squashes, slides or changes size in view: only fades, with the eyes still moving first.
[ ] No scroll ends with him under the top edge, the tab bar or the strip.
[ ] Hallway test with 5 people: at least 4 say he is the same character the whole time at the chosen Home size, and none say they waited for him.
Numbers at a glance
Every timing and spring in one place. Springs are response in seconds / damping fraction; in SwiftUI, duration = response and bounce = 1 − damping.
Channel
Value
Spring
Interface commit
Done within 140 ms of a tap
—
Eyes
95% there in 88 ms
0.15 / 0.85
Face turn
95% there in 128 ms
0.20 / 0.90
Crouch
5 pt in 80 ms; 140 ms from sitting, 40 ms after a landing
0.12 / 1.00
Flight
260–420 ms; re-target 200–360 ms; 520 ms max in the air
—
Landing squash and settle
Peaks at 55 ms, 9% overshoot, settled in 282 ms
0.30 / 0.60
Slide-through
3–4 pt, settled in 264 ms
0.28 / 0.70
Surface dip on landing
Up to 1.5 pt
0.22 / 0.50
Weight response while riding
Up to 3 pt, settled in 231 ms
0.25 / 0.55
Lean
3° away in the crouch, 6° into travel
0.20 / 0.85
Head roll
Welcome 5°, introduce −8°
0.24 / 0.80
Arm gesture
95% in 174 ms; pointing 95% in 240 ms
0.35 / 0.75; pointing 0.41 / 0.85
Review panel opens
95% in 259 ms
0.42 / 0.88
Review panel collapses
95% in 237 ms
0.34 / 0.95
Detail page push and pop
95% in 272 ms
0.36 / 1.00
Keyboard
System duration and curve, about 250 ms
System
Shuffle step (NEW)
110 ms per step, 120 ms settle
—
Drag-lean spring-back on Home (NEW)
One overshoot
0.30 / 0.55
Home size (NEW)
1.4×, changed in flight over smoothstep(0.15, 0.9)
—
Reduce Motion fade
120 ms out, 180 ms in
—
Rapid switching
3 changes in 900 ms; one hop after 350 ms of quiet
—
Breathing
0.6 pt, 4.2 s period, 3 cycles from 2 s after settling
—
Budgets
1 playful moment per session, 1 welcome per day
—
