# "What can Doddy do?" — Phase 2 design brief

Paste this into a new Claude Code session on `Bienos/doddy.2`. It continues the mockup work in `design/website-what-can-doddy-do/` (Phase 1, ADR-468). Mockups only. No production code, no change under `site/`, no deploy.

---

## 01 — Your role

Act as the same award-winning digital creative studio from Phase 1: Executive Creative Director, Senior Digital Product Designer, Interactive Experience Designer, Character Animation Director, UX/UI Designer, Motion Design Specialist, Frontend Creative Developer, Brand Strategist, Visual Storytelling Director. Add one more chair: a **Design QA lead** whose only job is to catch anything on the new page that contradicts the live homepage.

You have three jobs, in this order:

1. **Make the moments land.** Take the approved page and present each of the ten moments in a cooler, more alive way, without redesigning the page.
2. **Prove it belongs on doddy.lol.** Audit the new page against the live homepage, element by element, and fix every drift.
3. **Improve the whole site.** Homepage and new page together: what to change, why, in what order. Mock up the top changes.

Then stop for approval.

## 02 — Read these first, in this order

- `design/website-what-can-doddy-do/README.md` — Phase 1: discovery, the three directions, the recommendation (Direction A), the review rounds, the open decisions.
- `design/website-what-can-doddy-do/COPY.md` — the approved words. Headline, supporting line, every moment's lines and cards. Do not rewrite copy; propose edits separately if a line fights the design.
- `design/website-what-can-doddy-do/mockups/src/*.html`, `mockup.css`, `site.css`, `build.mjs`, `render.mjs` — the mockup sources and the render pipeline. Reuse them.
- `design/website-what-can-doddy-do/png/` — the Phase 1 renders. 05 (full desktop page), 10 (full phone page), 15 (showcase alternatives) matter most.
- `site/index.html`, `site/styles.css`, `site/tokens.css`, `site/blog.css`, `site/README.md` — the live homepage. https://www.doddy.lol is this folder served as is; verify that with one fetch before you trust it.
- `CLAUDE.md` (the character-art rule, 2026-10-11), `docs/product/PERSONALITY_SETTINGS.md` (how Doddy talks), the feature truth table in `prompts/LANDING_PAGE_DESIGN.md` (what the page may claim).
- The owner's asset pack is already cut into `design/website-what-can-doddy-do/assets/` (poses, scenery, props, effects, faces) with provenance in the README. Use only that. If a pose or scene is missing, say so; never redraw, recolour or generate Doddy.

## 03 — Decisions already made (do not reopen)

- Direction **A, "a day with Doddy"**: a vertical story from 08:45 to 23:30, ten taped scene cards, Doddy travelling between them, an object ring in the hero that doubles as a picker.
- Headline **"What can Doddy do?"** with the handwritten beat **"Quite a lot, actually."** and the line "Ten random moments from an ordinary day, and what a mate in your pocket does with them."
- The ten moments and their copy as in `COPY.md`, including the 23:30 plan card and the three honesty labels (Built · In testing · Later, maybe). Only saved notes is Built.
- Tab label "What can Doddy do?", second after "How it works", route `/what-can-doddy-do/`, the blog's active-state rule.
- Recommended showcase treatment: **the scene card plays in three beats as you scroll** (mockup 15, frame 1). This brief applies it.

If you believe one of these is wrong, say so in one paragraph of the review and carry on with the decision as made.

## 04 — Job 1: make the moments land

Design the page as it would actually move, inside the approved layout.

**Every moment as a three-beat storyboard.** For each of the ten moments, three frames of the same card: the problem (Doddy arrives, the prop reacts), the ask and the beat (your bubble, Doddy's pose swap, his line writing on in handwriting), the fix (the app's card slides in, the receipt stamp lands). Use the pack's poses so each moment has its own entrance: walk, run, tiptoe, pop-in, jump, turn. Timings, easing and the reduced-motion fallback on each frame. Frame three is the static page.

**The hero as a scene.** Idle, hover and selected states for the seven objects already exist (mockup 06). Add: Doddy's reaction per object (pose plus one handwritten line), the object drop-in on page load, and what happens on a phone where there is no hover.

**Doddy between moments.** The travel strip is a dotted line and a walk frame today. Make it a sequence: he walks, runs, stops to look at something, and once per visit does something unexpected (the pack has sneaky crouch, one-leg balance, yawn, shush). Define where each surprise sits and the rule that keeps them rare.

**Time of day.** Propose one quiet device that makes the day feel like a day as you scroll: a light shift on the paper from morning to night, a small handwritten clock that updates with the current moment, or the pack's night scenery for the late moments. Pick one, mock it up, say why not the others.

**The day strip.** It reuses the film's chapter buttons. Show the current-moment state on scroll and the phone version with snap points.

**Two "wow" additions, no more.** Ideas that make someone send the page to a friend, in the notebook language, cheap to build. Examples to beat: the homepage-to-page crossing from mockup 11; a replay button that lets Doddy do the whole day in ten seconds; the final moment where the day's loose ends come back as the plan card. Reject your own weak ideas in one line each.

**A motion spec sheet** on one board: durations, easings, what moves (transform and opacity only), what never moves (text), frame rates for the pack's strips, the reduced-motion table, and the budget (nothing over 1.8 s, nothing loops, one thing at a time).

## 05 — Job 2: does it contradict the homepage?

Build a side-by-side audit of the new page against the live homepage. One table, one row per element, four columns: homepage · new page · verdict (same / drifted / contradicts) · fix.

Cover at least: the nav and its active state; the phone nav (the homepage has no menu, the new page proposes one); the wordmark; the type scale and the display weights; the paper, rules and glow; card radii and shadows; the tape; pills and the capability labels; buttons and text links; Doddy's handwriting (where it is used and how big); captions and fine print; the join panel and waitlist form (there would be two on the site); the "Later, maybe" paragraph (it appears on both pages: same words, or one source?); the privacy and "Doddy is an AI" lines; the footer; the film's chapter buttons reused as the day strip; the screens ("Design preview" on the homepage, scripted scenes on the new page); the voice of the headlines ("A little less to carry." against "What can Doddy do? Quite a lot, actually."); and the claims, line by line, against the feature truth table.

Flag the one known contradiction up front and propose the path: the homepage still shows the v1.3 SVG poses, the new page uses the owner's pack. Options: swap the homepage poses to the pack (list the exact replacements and what each loses), keep both for now with a reason, or something better. The owner decides; you recommend.

Fix every "drifted" row in the mockups. For every "contradicts" row, mock up the fix on whichever page should change, and say which.

## 06 — Job 3: improve everything

Audit the homepage with the same eyes and propose improvements for the whole site. Prioritise in three tiers: must fix (contradictions, broken promises, accessibility), quick wins (an afternoon each), bigger ideas (a milestone each). Every item names the visitor outcome it serves. No item may add a claim the truth table does not allow, no social proof, no App Store button.

Look at, at least: the homepage hero and its first ten seconds; whether the film, "Take a shot" and "Remember it" earn their place and their order; the hand-off from the homepage to the new page (a secondary link in the hero? a strip of three moments after "How it works"?); the hand-off back (where the new page sends people: join, the film, the blog); the site map and cross-links; the phone experience end to end (most visitors arrive from TikTok and Instagram links); the footer; page titles, descriptions and share images for the new page; performance (SVG poses on the homepage, PNG scenery on the new page, what the weights are and what to do about them); accessibility (contrast of the orange on paper, focus states, reduced motion, alt text for scenes, the handwriting at small sizes); and the blog's place in all this.

Mock up the top five improvements at 1440 and 390. Keep the rest as a table.

## 07 — Deliverables

Add to `design/website-what-can-doddy-do/`, reusing the pipeline (`src/` partials, `build.mjs`, `render.mjs`, `site.css` unchanged, `mockup.css` extended). Numbering continues from 16.

| # | Output |
|---|---|
| 16 | The full page at 1440 with every moment in its three-beat form (frames side by side under each moment) |
| 17 | The full page at 390, same |
| 18 | Hero as a scene: load, idle, hover or tap, selected, Doddy's reaction per object |
| 19 | Doddy between moments: the travel sequences and the surprise rule |
| 20 | Time of day: the chosen device, with the rejected ones in a row beneath |
| 21 | Motion spec sheet |
| 22 | The two wow additions, mocked up |
| 23 | Consistency audit: the table, plus side-by-side crops of every "drifted" and "contradicts" row before and after |
| 24 | Character art decision: homepage poses today, the pack replacements, what changes |
| 25 | Site improvements: the three-tier table, and the top five mocked up at 1440 and 390 |
| 26 | Updated `index.html` review gallery with all of the above, and an updated `README.md` (what changed, what was decided, what is still open) |

Renders go in `png/`. Run the renderer; it fails on a missing web font, a sideways scroll at 390 px or a console error, and that counts. Commit to the working branch with clear messages. Nothing under `site/`.

## 08 — Rules that do not bend

- Doddy only from the owner's pack, already cut into `assets/`. Nothing redrawn, recoloured or generated. Five everyday objects are drawn line art (see the README); keep them or flag them, do not add more.
- Colours only from `tokens.css`. Type only Bricolage Grotesque, Caveat and the system face, loaded from Google Fonts. No font binaries in the repository.
- Every scene is a scripted demonstration and says so. Labels come from the truth table. Never write "implemented", "tested" or "available now" for a mock.
- Doddy's lines: answer first, one dry beat, jokes about the situation or himself, never at the visitor, no feelings claimed, no joke in a serious moment.
- Still images only: pose swaps, transforms, opacity. No canvas, video or rig. Reduced motion is a first-class path, not a fallback.
- Phones first. Anything that only works with a mouse is incomplete.
- Do not redesign doddy.lol. Extend it. If a homepage change is needed, it is a proposal in Job 3, not a change to `site/`.

## 09 — Success criteria

1. Within ten seconds a visitor knows Doddy is a character and an iPhone app that helps with ordinary days.
2. Nothing on the new page contradicts the homepage; every drift has a fix and a verdict.
3. Each moment reads as a tiny story in the brief's order: problem, Doddy appears, something funny, Doddy helps.
4. Every proposed improvement names the visitor outcome it serves and its cost tier.
5. Someone would send the page to a friend.

## 10 — Then stop

STOP. Do not code the page. Do not touch `site/`. Do not deploy. Present the gallery, the audit, the improvement plan and the open decisions, and wait for approval.
