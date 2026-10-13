# "What can Doddy do?" — website page mockups

**Status: design proposal, awaiting the owner's choice. Nothing here is live.** No production page was built, `site/` is untouched, nothing was deployed. The mockups are HTML files rendered to PNG with headless Chromium so they can be reviewed at real sizes (1440 px desktop, 390 px phone).

Brief: a new tab on doddy.lol that shows what it feels like to have Doddy in your pocket, through everyday situations, without explaining the technology. Three directions, twelve mockups, one recommendation, then stop for approval.

## Where to look

| | File |
|---|---|
| Review gallery (all mockups with notes) | `index.html` |
| The words on the page, one place to edit them | `COPY.md` |
| Rendered mockups | `png/` |
| Mockup pages (open in a browser) | `mockups/*.html` |
| Sources the pages are built from | `mockups/src/` and `mockups/src/partials/` |
| Styles | `mockups/site.css` (copy of the live site's tokens + styles), `mockups/mockup.css` (the new page's components) |
| Artwork used | `assets/` (see Provenance below) |

## Phase 1 — Discovery: what doddy.lol actually is

The live site at https://www.doddy.lol/ is the repository's `site/` folder, served as is. A fetch on 2026-10-13 differed from `site/index.html` in two copy lines only (which voice provider is named first). So the design language was read from the source, not guessed:

- **Light-only "editorial notebook"**: paper `#FFF7E9`, ink `#171715`, orange cue `#F58A24`, secondary text `#655F56`, quiet surface `#F5EAD8`, separator `#DFD5C6`, accent text `#A64B00`, confirmed green `#326746`, error `#A3342E` (`site/tokens.css`, generated from the app's `CandidateTokens.swift`). The mockups use these tokens and no others.
- **Type**: Bricolage Grotesque for headings (the brand speaking), Caveat only for Doddy's own lines and the wordmark, the system face for reading. Both web fonts load from Google Fonts on the live site; the mockups link them the same way. No font binaries are committed.
- **Patterns the mockups reuse unchanged**: the sticky nav with the handwritten wordmark and the ink "Join early access" button; the faintly ruled hero paper; the tilted device frame; the taped paper card around the film; the rotated "scraps"; the film's chapter buttons; pills ("iPhone app, in early testing", "In testing"); paper panels with 36 px radius and the warm corner glow; the join panel with the waitlist form; the "Later, maybe" block; the footer.
- **Navigation today**: How it works · Meet Doddy · Take a shot · Blog · Privacy, plus the button. Below 820 px the links are hidden; there is no phone menu at all. The blog marks its tab with `aria-current="page"` (ink text, orange underline), which the new page reuses.
- **Character art**: the live site still shows the v1.3 SVG poses, but CLAUDE.md (2026-10-11) says new Doddy art comes only from the owner's `DODDY-Numbered-Video-Assets-v01` pack. The mockups follow that rule; see Provenance.

### What the product can do today (the labels the page must use)

From `prompts/LANDING_PAGE_DESIGN.md` (feature truth table), `docs/implementation/V1_VOICE_STATUS.md`, `docs/product/PERSONALITY_SETTINGS.md` and the live site's own "Later, maybe" paragraph:

| Shown on the page as | What it means | Covers |
|---|---|---|
| **Built** | Works in the app now, simulator-tested | Saving a note in your exact words; finding it again with date and source; "I couldn't find that in your saved memories" when nothing matches; edit, export, delete |
| **In testing** | Built, being tried on real iPhones, not yet verified for release | Voice conversation (ElevenLabs agent); read calendar and add events; reminders; timers; lists; Apple Maps hand-off; message and email drafts (Doddy never sends); contacts; weather (Open-Meteo); Wikipedia look-ups; English/Polish switching; plans (one card for 2–5 changes with tick boxes, `propose_plan`); personality settings (humour, reply length, tone, mood; quick picks Doddy's default / Focused / Playful) |
| **Later, maybe** | Not built, no dates promised | Translating other people; choosing a restaurant for you; Android |

Every change in the app goes through a card with Add / Save / Open and nothing happens until the tap; the receipt is read back afterwards. The scenes show exactly that pattern. No ratings, download counts, testimonials or App Store buttons appear anywhere (the brief's own rule, and the site's).

## Phase 2 — Creative concepts

### The long-list (20 situations, 10 kept)

| # | Situation | Hero object | Capability shown | Label | In the mockups |
|---|---|---|---|---|---|
| 1 | You're late. Again. (08:45) | alarm clock | calendar read-out, a "running late" draft | In testing | kept |
| 2 | Jacket or no jacket? (09:10) | coffee cup | weather for where you are | In testing | kept |
| 3 | The awkward text (10:20) | phone | message draft with funnier / shorter / more confident | In testing | kept |
| 4 | What should we eat? (13:00) | note card | search handed to Apple Maps; cheap / best rated / different | In testing (picking for you: later) | kept |
| 5 | Lost in translation | suitcase | English/Polish today; translating others not built | Later, maybe | kept, shown as a concept |
| 6 | Explain it like I'm five (15:30) | book | plain explanation, Wikipedia named as the source | In testing | kept |
| 7 | My brain has left the chat (18:45) | speech bubble | saved note found in your exact words, with receipt | **Built** | kept, the anchor scene |
| 8 | The shopping bag (20:15) | shopping bag | shared list, add with Undo | In testing | kept |
| 9 | Don't let me forget (22:30) | calendar | reminder card, Add, read back | In testing | kept |
| 10 | Sort tomorrow out (23:30) | pencil | one plan card with a tick box per change (the app's `propose_plan`) | In testing | kept; replaced "Be more sarcastic" after the 13 Oct review |
| 11 | Where did I park? | | save "parked on B2", find it later | Built | CTA scrap |
| 12 | Pasta timer, nine minutes | | timer card with Start | In testing | CTA scrap |
| 13 | Call Mum. Actually call her. | | contact lookup, Call button | In testing | CTA scrap |
| 14 | Plan my evening | | one card for 2–5 changes with tick boxes | In testing | CTA scrap |
| 15 | The tin above the fridge | | the homepage's own example note | Built | already on the homepage |
| 16 | Marta's book | | note found | Built | appears as a floating note in scene 7 |
| 17 | Locker 4471 | | note found | Built | appears as a floating note in scene 7 |
| 18 | Hey Doddy, hands full | | wake word on the Dynamic Island | In testing, not device-verified | dropped: can't be shown honestly yet |
| 19 | The Polish grandmother | | language switch mid-conversation | In testing | folded into 5 |
| 20 | Sunday night, "what did I say I'd do?" | | notes + reminders together | mixed | dropped: two features in one, muddy |
| 21 | Be more sarcastic (23:30) | basketball | the personality quick picks | In testing | shown in the first round; the owner asked for something different |

Scenes were chosen for usefulness, relatability, humour and whether the pack has scenery and a pose for them. Doddy's lines follow the character rules in `docs/product/PERSONALITY_SETTINGS.md`: answer first, one dry beat, jokes about the situation and never about the user, no sarcasm at the user (which is why the 20:15 line lost its "so no excuses" in review).

### Three directions

| | A · Doddy's daily chaos | B · Doddy's little world | C · Got a problem? Ask Doddy. |
|---|---|---|---|
| Shape | One scroll from 08:45 to 23:30; each moment is a taped scene card with Doddy, a line, and the app's card | A paper map of ten places; click a place, Doddy walks there, the situation plays | One screen: Doddy, a row of problem chips, an iPhone showing the scripted conversation |
| What carries it | Editorial storytelling and Doddy travelling down the page | Exploration and surprise | Speed and polish |
| Hero | Doddy in a ring of seven objects; objects double as chapter links | The map itself, under a centred headline | Headline, chips, Doddy, phone |
| Uses the pack's scenery | all ten 16:9 scenes | as place tiles | not in the hero |
| Phone | Natural: the page is already a vertical story | Weakest: the map becomes a two-column grid of places, the "world" feeling goes | Good: chips then phone |
| Build cost | medium: static sections, one scroll-spy, pose swaps | high: hit areas, walking paths, two layouts | low |

## Phase 3 — The mockups

| # | Required output | File(s) in `png/` |
|---|---|---|
| 01 | Existing homepage with the new tab | `01-homepage-nav-1440.png`, `01-homepage-nav-390.png`, `01-homepage-nav-390-menu.png` |
| 02 | New page hero, Direction A | `02-hero-a-1440.png`, `02-hero-a-390.png` |
| 03 | New page hero, Direction B | `03-hero-b-1440.png`, `03-hero-b-390.png` |
| 04 | New page hero, Direction C | `04-hero-c-1440.png`, `04-hero-c-390.png` |
| 05 | Full desktop page, recommended direction | `05-full-page-1440.png` (1440 × 10399) |
| 06 | Interactive scenario selection | `06-scenario-selection-1440.png` |
| 07 | Expanded everyday scenario | `07-expanded-scenario-1440.png` |
| 08 | Doddy's interaction states | `08-character-states-1440.png` |
| 09 | iPhone conversation demonstration | `09-iphone-conversation-1440.png` |
| 10 | Mobile version of the complete page | `10-mobile-full-page-390.png` (390 × 14930) |
| 11 | Navigation and transitions | `11-navigation-transitions-1440.png` |
| 12 | Final CTA and footer | `12-cta-footer-1440.png` |
| 13 | Headline options for the hero (added after review) | `13-headline-options-1440.png` |
| 14 | Copy deck: every line of the ten moments (added after review; editable in `COPY.md`) | `14-copy-deck-1440.png` |
| 15 | Showcasing a moment: the current card and four alternatives (added after review) | `15-showcase-alternatives-1440.png` |
| 16 | Phase 2 · full page at 1440, every moment in three beats | `16-full-page-beats-1440.png` (1440 × 14022) |
| 17 | Phase 2 · the same at 390 | `17-full-page-beats-390.png` (390 × 23941) |
| 18 | Phase 2 · the hero as a scene: load, idle, hover, selected, phone taps, one reaction per object | `18-hero-scene-1440.png` |
| 19 | Phase 2 · Doddy between moments (walk, run, stop to look, sit, wave) and the surprise rule | `19-between-moments-1440.png` |
| 20 | Phase 2 · time of day: the paper sun (chosen), the margin clock and night scenery (rejected) | `20-time-of-day-1440.png` |
| 21 | Phase 2 · motion spec sheet | `21-motion-spec-1440.png` |
| 22 | Phase 2 · two additions worth sending to a friend, and what lost | `22-wow-1440.png` |
| 23 | Phase 2 · consistency audit, with before/after crops (`png/crops/`) | `23-consistency-audit-1440.png` |
| 24 | Phase 2 · one Doddy for the whole site: the homepage's poses mapped to the pack, three options | `24-character-art-1440.png` |
| 25 | Phase 2 · site improvements: three tiers, share cards, the blog nav | `25-site-improvements-1440.png` |
| 25a | Phase 2 · the homepage proposal (top five applied) at 1440 and 390 | `25a-homepage-proposal-1440.png`, `25a-homepage-proposal-390.png` |

### Headline options (mockup 13)

The owner asked for alternatives to "Life's complicated. Doddy isn't. Usually." without a redesign. Eight options, each in the same shape (brand line in Bricolage, one handwritten beat in Doddy's voice, a supporting line):

| # | Headline | Handwritten beat | Supporting line | Angle |
|---|---|---|---|---|
| 0 | Life's complicated. Doddy isn't. | Usually. | From forgotten plans to awkward messages, meet the little guy who helps you figure things out. | the brief's line, as mocked up |
| 1 | What can Doddy do? | Quite a lot, actually. | Ten random moments from an ordinary day, and what a mate in your pocket does with them. | answers the tab the visitor clicked. **Chosen by the owner (13 Oct), with "random" added.** Now in every hero. |
| 2 | Forgot something? | Doddy didn't. | He remembers the thing you said last week, reads your day out loud, and drafts the text you keep deleting. In your words, not his. | leads with the one built feature |
| 3 | Small stuff, sorted. Big stuff, | calmly. | Doddy is funny about the little problems and plain about the serious ones. Here's a day of both. | the character's rule |
| 4 | Clever with your problems. | Hopeless with umbrellas. | A little guy who can read your calendar, draft the awkward reply and find the pierogi place, and still can't decide on a jacket. | the brief's contradiction; the joke is on Doddy |
| 5 | Late. Hungry. Lost. | Sorted. Mostly. | From the 08:45 alarm to the 22:30 reminder: the little things Doddy helps with, and the ones he's still learning. | reads like the homepage scraps |
| 6 | A mate in your pocket. | Here's what he does all day. | Scroll through one ordinary day. Every scene says what's built, what's in testing, and what's later, maybe. | continues the brand line |
| 7 | Your day has twelve small problems. | He likes those. | The side-quest fixer: notices the small frictions, helps first, jokes second, and asks before he changes anything. | Doddy's point of view |

The owner chose option 1 and asked for "random" in the supporting line; mockups 02 to 05 and 10 carry it. Option 2 claims memory, which is the built feature, so it is the safest claim. Options 4 and 5 are the funniest and still honest. Option 1 is the plainest and ties the page to its nav label. Any of them drops into the hero unchanged.

### Copy review, 13 October (mockup 14 and `COPY.md`)

The owner reviewed the ten moments. Changes made:

| Moment | Change |
|---|---|
| 08:45 | kept |
| 09:10 | Doddy's line now says "17 degrees" |
| 10:20 | the message being replied to is shown: a paper bubble from Alex in the scene ("Yesterday was fun :)") and a quoted line on the draft card; the ask is "Help me reply to this…" |
| 13:00 | "near the centre" instead of "nearby"; Doddy's line ends "Opening Maps."; the card search is "cheap pizza near the centre" |
| Abroad | easier example: a kiosk asks "Sur place ou à emporter?", Doddy gives "Eat in or take away?" |
| 15:30 | new metaphor: keys and a keyring instead of a coin |
| 18:45 | a precise, common place: "Trattoria Nonna, Hoża 9" (made up) for Ola's birthday, with "book the table by the window" |
| 20:15 | "Added to the list. Ola can see it too." (the old line joked at the visitor) |
| 22:30 | Doddy asks "Morning or evening?"; the card offers Morning 10:00 / Evening 19:00 before Add; the phone mockup matches |
| 23:30 | replaced by **Sort tomorrow out**: one plan card, tick box per change, Do these (3), each step read back. Scenery: the study; pose: shush; prop: pencil |

### Showcasing a moment (mockup 15)

The owner likes the scene cards and asked whether a moment could be shown in a cooler way. Five treatments of the 08:45 moment, all inside the same page:

| # | Treatment | For | Against |
|---|---|---|---|
| 0 | The scene card as mocked up | one picture, fast, cheap, works as a still | the brief's four beats land at once |
| 1 | **The same card playing in three beats on scroll** (recommended upgrade) | tells problem → Doddy appears → the joke → the help in order; pose swaps and three CSS moves; once per visit, about 1.8 s; frame 3 is the static and reduced-motion fallback | a little scroll logic per card |
| 2 | Three-panel comic strip | the brief's beats literally; very shareable as an image | a third pose and line per moment; panels get small on phones |
| 3 | Scene plus the phone as proof | clearest about what the app does | busiest frame; wants the real screens once they exist |
| 4 | Flip card, problem on the front, fix on the back | a small reward for curiosity; natural on phones | ten flip cards are tidier but less of a story |

Recommendation: keep the card, add treatment 1. It changes nothing in the layout and makes each scene a tiny story.

## Phase 4 — Review and recommendation

**Recommended: Direction A, with C's problem picker folded into its hero and B's scenery as the backdrops.** That is what mockups 05 to 12 show.

Why A:

1. **Instant understanding.** The headline, Doddy, and seven recognisable objects are on screen together; a visitor sees "everyday problems, a character, a phone app" before scrolling. C does this slightly faster; B does it slowest, because a map asks to be explored before it explains.
2. **Continuity with the site.** The homepage is already a scroll story with taped paper cards, handwritten asides and chapter buttons. A reuses every one of those components; the new page reads as the next page of the same notebook. B introduces a new kind of surface (a map) and C is fine but generic.
3. **Phones.** Most traffic will come from TikTok and Instagram links on phones. A stacks naturally (mockup 10). B loses its idea on a phone.
4. **Shareability.** A gives people ten small scenes and lines to screenshot and send; the day structure is a story people retell ("the 08:45 one is me").
5. **Honesty is easy to keep.** Each moment has one label and one caption; the one built feature (saved notes) gets the anchor scene at 18:45, and the "Later, maybe" scene is shown as a concept in the same voice.

What A takes from the others: C's "pick a problem" becomes the object ring, so the page is still a picker for the impatient; B's places are the scene backgrounds, so the little world exists without the map's cost.

Trade-offs to accept:

- A is long (ten moments). The day strip and the object ring are the cure, and the page can ship with six moments and grow.
- A needs a little scroll logic (current chapter, Doddy's travel between moments). All of it is progressive enhancement over a plain page; without JavaScript or with reduced motion it is a static page with the same content.
- The humour is in the copy, so the copy needs the owner's ear before build.

### Navigation decision

- Label **What can Doddy do?** (sentence case like the other items), second position after "How it works": the homepage answers how, the new page answers what.
- Route **`/what-can-doddy-do/`**, a folder with an index page, like `/blog/`.
- Active state: the blog's existing `aria-current="page"` rule (ink text, orange underline).
- Phone: the site currently has no menu at all below 820 px. The proposal adds a 44 px menu button that opens a paper sheet with the six links; the new one carries Doddy's face. The site owner may prefer to keep the phone nav as it is and rely on the footer; the mockups show both states.
- Transition from the homepage (mockup 11): Doddy pops out of the tab, runs right, an ink wipe, and he lands in the new hero ring. Under 1.5 s, a plain link underneath, and skipped entirely with reduced motion.

### Motion and accessibility rules (from mockups 06 and 08)

Still images only: pose swaps, CSS transforms and opacity; walk and run frames at 8 fps for travel. No canvas, video or rig, because the pack has none. `prefers-reduced-motion`: no travel, no drift, no bubble pop; poses still swap. Objects are links, 116 px on desktop and 70 px on phones; labels are visible on tap. Doddy never covers text; bubbles are real text, not images. Colours are the site's own, so contrast is as already checked on the homepage.

## Product accuracy, in one place

- Scenes are **scripted**; every one says so in its caption.
- **Built**: only the saved-notes scene (18:45) and the memory phone (09 C). Its lines, dates and "Your typed note" source match the app's real receipt model.
- **In testing**: everything the voice agent does through a card. The phone mockups show the real pattern (card, tap, read back, "What Doddy did"). The status words Listening / Speaking are the app's own.
- **Later, maybe**: translation (shown as a concept and labelled), picking restaurants for you, Android.
- Nothing claims the voice is verified on a real iPhone, no ratings, no downloads, no App Store button, no testimonials.
- The "What's real today" panel sits above the final CTA so the honesty beat lands before the ask.

## Provenance of the artwork

Rule (CLAUDE.md, 2026-10-11): only the owner's `DODDY-Numbered-Video-Assets-v01` pack (Google Drive folder `1inLT9oV7wx7UM4P6nxP8yU1-29JV0_ee`). Everything in `assets/` comes from it, with two documented exceptions below.

| Folder | Source in the pack | What was done |
|---|---|---|
| `assets/poses/*.png` (16 poses, 640 px wide) | `doddy-extra-poses-expressions-v02/…/01-transparent-poses/*.png` (1024 × 1536), downloaded 2026-10-13 | Lanczos downscale only. Checked against `docs/design/UPLOADED_MEMORY_ASSETS.md`: listening `96375303…`, shush `69fa189d…`, shrug `c68edf3c…`, fist pump `c7a1fd15…` match the hashes recorded there. `wave.png` is frame 4 of `016_doddy_wave_v01.png` (`817a2b87…`) cut with the repo's own `tools/whole_doddy/cut_wave.py`. |
| `assets/poses/walk_3.png`, `walk_7.png`, `run_2.png`, `jump_3.png` | the app's `DoddyMotion_*` image sets (ADR-313), themselves cut from the pack's 012/014/015 sheets | copied at @3x |
| `assets/scenery/*.jpg` (17 scenes, 1600 px) | `doddy-complete-scenery-16x9-v06/` (1920 × 1080 PNG) | downscale, JPEG |
| `assets/props/*.png` | `010_doddy_props_v01.png` (alpha sheet) | each prop cropped to its alpha bounds |
| `assets/fx/*.png` | `011_doddy_fx_v01.png` (alpha sheet) | as above |
| `assets/faces/*.png` | `004_doddy_expr_front_v02.png` (flat sheet) | circular crops |
| `assets/site/` | the live site: the four app screens, `poster-v2.jpg`, and the eleven v1.3 pose SVGs | mockup 01 (today's homepage as it is), mockup 24 (the pose comparison) and mockup 25a (the homepage proposal, which swaps them for the pack) |

Exception 1: five everyday objects the pack has no prop for (alarm clock, suitcase, calendar, shopping bag, speech bubble) are drawn as inline SVG in `mockups/src/partials/symbols.html`, in the props sheet's own ink `#080808`, cream `#FCF4E4` and orange `#FC6800`. They are objects, not Doddy; if the owner would rather have them drawn by the pack's illustrator, they are five symbols to swap.
Exception 2: mockup 01 shows the v1.3 SVG pose because the live homepage does; replacing it is a separate owner decision already listed in `site/README.md`.

Nothing was redrawn, recoloured or generated. The 16 pack poses, the scenery and the sheets are the owner's concept art; the pack's README calls them references to be redrawn and rigged, so the real page would want the owner's sign-off on using them as final web art.

## How to rebuild the renders

```sh
cd design/website-what-can-doddy-do/mockups
node build.mjs                      # src/*.html + partials -> mockups/*.html
npm i playwright                    # or symlink the global one into ../node_modules
NODE_PATH=$(npm root -g) node render.mjs --fonts <dir>   # -> ../png/*.png
```

Phase 2 adds three tools under `mockups/tools/`: `gen16.py` writes the three-beat page from the approved copy; `gen25a.py` writes the homepage proposal from a read of `site/index.html`; `crop.mjs` screenshots one element of a page for the audit's before/after pairs (`FONTS=<dir> node tools/crop.mjs <page> <selector> <out.png>`).

`--fonts` points at a local cache of the two Google Fonts (the CSS plus woff2 files, kept outside the repository per CLAUDE.md); without it the renderer fetches them from Google Fonts. The script fails loudly if a font didn't load, if a page scrolls sideways, or if the console logs an error. Last run 2026-10-13, Chromium 1194: 17 renders, no issues.

## Decisions (Phase 1 list, closed 13 October)

The owner delegated these on 13 October ("do what you think would match best"). The studio's calls, each with its reason:

1. **Direction A**, as recommended (reuses every homepage component, stacks on phones, one honesty label per scene).
2. **Tab "What can Doddy do?"**, second after "How it works", route `/what-can-doddy-do/`, the blog's active-state rule.
3. **Add the phone menu, on every page.** Without it, Blog and the new page are unreachable on phones except through the footer; most visitors arrive on phones.
4. **All ten moments ship**, in the day's order; none is cut. The copy is approved as in `COPY.md`.
5. **The pack's scenery and poses are the web art**, and the five drawn objects stay (they are objects, not Doddy, in the props sheet's own colours).
6. **"Lost in translation" stays** as a labelled concept: it is the honest line in the day and the funniest beat.
7. **The homepage-to-page crossing stays** as drawn (mockup 11): a progressive enhancement over a plain link, skipped with reduced motion.
8. **Each moment plays in three beats** (mockup 15, frame 1), now built out in 16 and 17.
9. **The copy deck stands** with the one claim corrected (08:45).

## Phase 2 (13 October, second brief) — making the moments land, the audit, the site

Decisions from Phase 1 stand (Direction A, the headline, the ten moments and their copy, the tab and route, the scroll-played scene card). Phase 2 applies them and adds three jobs. Nothing under `site/` changed; the homepage work is a proposal (mockup 25a) built from a read of `site/index.html` by `mockups/tools/gen25a.py`.

### Job 1 — the moments

- **Every moment in three beats** (mockups 16 and 17, generated by `mockups/tools/gen16.py` from the approved copy): beat 1 the problem (Doddy's entrance from a pack strip, the time writing itself, the prop reacting), beat 2 the ask and the beat (your bubble, his pose swap, his line revealing word by word), beat 3 the fix (the app's card sliding up, a stamp landing on it). Beat 3 is the static page and the reduced-motion page. Entrances: walk (08:45, 18:45), pop-in (09:10), tiptoe (10:20), run (13:00, 20:15), jump (away), turn (15:30, 23:30), sit (22:30). Each frame carries its timings and its reduced-motion line.
- **The hero as a scene** (18): load (pop-in, objects dropping in clockwise, wave, the scribble), idle (still, by rule), hover or focus (object lifts, label, Doddy swaps pose and line), selected (he runs out of the ring and the page scrolls), phone first tap and second tap. Seven reactions, one per object, each a pack pose and one line.
- **Between moments** (19): walk, run, stop to look, sit; and one surprise per visit from four (sneaky crouch behind the 18:45 card, one-leg balance on the path, yawn before 22:30, shush beside the honesty panel), with the rule that keeps them rare: one per visit seeded by date, never before two moments, never within 2 s of another move, never on the hero, the join panel or over text.
- **Time of day** (20): the paper sun. The homepage's hero glow sits behind each scene card and travels down the day: high and bright at 08:45, overhead at 13:00, low and faint at 22:30, gone at 23:30. Two custom properties per section, no script, nothing to fall back from. The 22:30 scene moves to the pack's moonlit hills. Rejected: a handwritten clock in the margin (says the time three times, needs a margin phones don't have) and night scenery for the late moments (the 16:9 set has one night scene; darkening a day scene would mean recolouring the owner's art).
- **Motion spec** (21): budget (1.8 s longest, no loops, one thing at a time, once per visit), what moves (transform and opacity on still frames) and what never does (text, layout, scenery, colour), the site's own easings, every duration, the pack's strips at 8 fps, triggers, preloading, reduced motion, no-JavaScript and phones.
- **Two additions** (22): (1) the hero follows the visitor's clock: the pill says "It's 07:50 where you are", Doddy's pose and line match the hour, "Start the day" becomes "Start at 08:45"; (2) "Send this one to…": a handwritten share line under every moment that opens the system share sheet with a one-line text and a link to that moment, plus a sign-off note after 23:30. Rejected, one line each, on the board: the ten-second replay, the crossing as a wow, the loose-ends callback, the pigeon, a Polish toggle, scroll-speed games, pull-to-wake, a composed share card.

### Job 2 — the audit (23) and the character art (24)

Twenty-three rows. Verdicts: 12 same · 2 extensions · 6 drifted · 4 contradictions.

| Drifted (fixed in the mockups) | Fix |
|---|---|
| Display size overridden; handwriting larger than the brand face | the homepage's `.display`; the beat at 0.92 em |
| Scene card 28 px / 10 px; object tiles 4 / 20 px corners; honesty panel 28 px | the film card's 30 px / 12 px; the scraps' 4 / 14 px; the privacy panel's 36 px, padding and warm corner |
| Footer missing the Google Analytics sentence and button | restored |
| App screens labelled "Scripted demonstrations" only | "Design preview of the app, scripted conversations" (the homepage's words first) |
| Sections padded less than the homepage's | the homepage's rhythm |
| One claim overreached: "Moves the next thing back twenty minutes" (the agent adds events, it does not move them) | proposed copy edit, applied: "Nothing in your calendar changes unless you tap Add." |

| Contradicts | Which page changes |
|---|---|
| Phone nav: the homepage has no menu, the new page proposes one | the homepage (25a at 390): the same menu everywhere |
| "Later, maybe" paragraph duplicated from a second source | the new page: removed; the honesty panel links to the homepage's list |
| Character art: v1.3 SVGs on the homepage, the pack on the new page and in the app | the homepage (24, 25a); owner decides |
| Page head: canonical and `og:url` point at doddy-eight.vercel.app; the new page has no title, description or image | both: doddy.lol everywhere, the new page's own head (25 · 2 and 11) |

Before/after crops for every visible row are in `png/crops/` (taken with `mockups/tools/crop.mjs` from the Phase 1 build and the Phase 2 build, same selectors).

**Character art (24):** every homepage pose mapped to the pack: four exact (wave, dribble, fist pump, listening), five nearest with a prop beside him (kneeling inspect for the memory card, shrug for pointing, leaning + coffee cup, cross-legged + laptop, one-leg balance for relaxing), two waiting on cuts (the basketball sheet's shooting frame; a pack pose for the canvas court). Recommended: **A, swap the homepage to the pack now.** B (keep both) is defensible only if the pack is the one being retired; C (v1.3 on the new page) breaks the rule and the app. The swapped hero is mockup 25a.

### Job 3 — the site (25, 25a)

Twenty items in three tiers, each with the visitor outcome and a cost. Must fix: one Doddy; the share and search addresses on the Vercel host (checked live: `canonical`, `og:url`, `og:image`); no phone navigation; the stale "voice hasn't been tested on a real iPhone" line (the voice status records a real conversation on 9 October; the owner confirms); the duplicated "Later, maybe"; scene text alternatives; contrast and handwriting sizes checked (no change). Quick wins: the hand-off (hero link "What Doddy does all day", three moments after How it works); one nav for three pages (the blog's drops "Take a shot" today); the hand-off back; the new page's head and share image; game order; the fold at 1440 × 900; font preload. Bigger: the performance plan (WebP at two sizes, one moment preloaded, 250 KB before the first scroll, 1.2 MB for the day), simulator screens, domain, privacy policy and fonts, Polish, the homepage's section order for social visitors, the blog's place.

**Top five, mocked:** 1 one Doddy and 3 the phone menu and 8 the hand-off are mockup 25a (1440 and 390); 2 and 11 the share cards and 9 the blog nav are on mockup 25.

### Proposed copy (not approved)

Phase 2 adds words. None are in `COPY.md`'s approved section; all are listed under "Proposed copy (Phase 2)" there: seven hero reactions, four surprise lines, one stop-to-look line, six clock pills and lines, ten share lines, the sign-off note and ten share texts, the calendar claim edit, the homepage teaser heading and lede, the hero link label, the film link, and (if option A) "orange backpack" in the Meet copy.

### Verification

`node render.mjs` over all 33 renders on 13 October (headless Chromium 1194): every web font a page uses loaded, no horizontal scroll at 390 px, no console errors. The font check now asks only for fonts a page actually uses (a board with no handwriting never requests Caveat). Not checked: real Safari, VoiceOver, any live interaction (there is still no JavaScript).

### Decisions (Phase 2 list, closed 13 October)

Made by the studio on the owner's delegation; each applied to the mockups where it changes what is shown.

1. **Character art: A.** The homepage swaps to the pack (mockups 24, 25a). The five nearest-pose swaps stand; the basketball sheet's shooting frame and a pack pose for the court game are build tasks.
2. **The homepage proposal: all five.** The hero's second link goes to the new page ("What Doddy does all day"); the film keeps its own link in its section. Three moments after How it works, the phone menu, one nav for three pages, the footer link.
3. **Phones: beat 3 only, with tap-to-play.** The card is the page; a "Play the scene" chip plays beats 1 and 2 above it, then reads "Replay". Mockup 17 shows the first moment playing and the rest at rest; the page drops from about 24 000 to 18 000 px at 390.
4. **The surprise rule: in. The idle blink: no.** The hero holds still until touched; nothing loops.
5. **Both additions: in.** The hero follows the visitor's clock; every moment has a share line. The share image is a crop of the page's own art.
6. **The copy: approved by delegation** (`COPY.md`, "Copy added in Phase 2").
7. **The voice line:** the proposal (25a) shows "Voice is being tried on real iPhones now."; the site README rule stands, so the owner confirms it at build.
8. **Canonical host: https://www.doddy.lol/**, where the site already answers (the live fetch redirects there).

## Phase 5 — Stopped here

Not done, on purpose: no page under `site/`, no nav change on the live site, no JavaScript for the interactions, no deployment, no Vercel change, no analytics events. The homepage proposal (25a) is a generated mockup, not an edit to `site/index.html`. The next step after approval is a build milestone: the page folder, the nav item on the homepage and blog templates, the scroll logic, the reduced-motion paths, a Playwright check at 1440 / 390 / 320 like the homepage has, and the CSP review (the page adds no new hosts).

## Constitution evidence log

| Rule | How the mockups respect it | Enforcing code | Tests run | Gaps |
|---|---|---|---|---|
| DOD-02 honesty over agreeableness | Every scene labelled Built / In testing / Later, maybe; captions say "scripted demonstration"; no fake metrics | none (design files) | visual review of all renders | labels must be wired to a single source of truth at build time |
| DOD-03 character without false humanity | Doddy's lines claim no feelings; "Doddy is an AI, not a person" in the footer and hero fine print | none | copy reviewed against `PERSONALITY_SETTINGS.md` | owner's copy pass pending |
| Actions need explicit approval; "done" only on confirmation | Phone and scene cards show Add / Open / Save and a read-back receipt; Doddy never sends | none | none | the real screens may differ; captions say so |
| Memory is explicit, never invented | The built scene finds a note the user typed, with date and source | none | none | none |
| Character art from the owner's pack only | see Provenance | `cut_wave.py` reused; hashes checked | hashes compared for four poses and the wave sheet | five drawn objects are an exception to confirm |
| Phase 2: still images only, reduced motion first-class, nothing loops | motion spec (21); every frame carries its reduced-motion line | none (design files) | renders at 1440 and 390, no sideways scroll, fonts loaded | timings are a spec, not measured in a browser |
| Phase 2: no new claims | the audit's claims row; one line corrected to match the agent's tools | none | ten moments checked against `V1_VOICE_STATUS.md` | the voice-testing line on the homepage waits on the owner |

Nothing in this folder is "implemented", "tested on a device" or "privacy guaranteed". It is a proposal.
