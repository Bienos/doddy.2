# Homepage vision (only the chosen option is kept)

**20 Oct 2026 (ADR-548):** options A to F and H were deleted on the owner's instruction; only `g-sort-thursday.html` (round 3, chosen) and its shared CSS and screenshots remain. The text below is the original brief and mentions the deleted files; read them with `git show f7eedf0:design/website-homepage-vision/<file>`.

# Homepage vision: round 3 (G, H), round 2 (D, E, F), round 1 (A, B, C)

**Status: design proposal, not live.** Round 1 (A, B, C) was turned down by the owner on 14 October as boring: layouts, not ideas. Round 2 is below; A to C stay in the folder as the record.

## Round 3: the big asks (owner brief, 14 October, second pass)

Rounds 1 and 2 were turned down: "none is relevant". The owner's answers to three questions: the homepage talks first to **18 to 30, phone-first** and to **AI-curious early adopters**; the first five seconds should feel **simple**, then **"this character is great"**, then **"ha, that's me"**; what killed the six designs was **the use cases**: parking and oat milk undersell it.

So round 3 starts from what the repo says Doddy will actually do (`voice-agent/tools.json`, 60 tools; `voice-agent/phone/`; the two published blog posts): read Gmail and Outlook aloud and draft the reply; find the free hour, book it and say when to leave; find the file in Drive or the page in Notion; run Shortcuts by voice; translate face to face; `propose_plan`, one sentence into one card with several changes and one tap; routines by name; and a phone number any phone can call to reach your notes (spec'd, ADR-152/172, not live). The trust edge for the AI-curious comes from the agents post: asks first, never sends, buys or deletes, says "I don't know".

Built **phone-first** (base CSS is 390 px; desktop widens it). Icons for mail, calendar, maps, docs, lists, translator, Shortcuts, phone, reminders and notes are drawn as ink symbols in the props sheet's style (`icons.svg.partial`), the same exception ADR-468 made for the five objects.

| | Hook | What the page says | Sections |
|---|---|---|---|
| G | `g-sort-thursday.html` **Say it once. Tap once. Done.** | The hero is one spoken sentence ("sort Thursday out…") next to the one card it becomes: five changes across Calendar, Maps, Messages and Lists, one "Do these (5)". | The big asks (six cards, apps stamped on each, swipe row on phones) · The agent you'd let near your inbox (most agents vs Doddy) · Lost your phone? Borrow one. Call him · Meet Doddy · join |
| H | `h-read-me-my-morning.html` **"Doddy, read me my morning."** | The hero is the briefing itself, in Doddy's handwriting: weather and jacket, calendar and when to leave, two emails, reminders, the list, a birthday, then one question that becomes one card. | Then, all day (six timed asks: Drive and Notion, translator, calendar and a text, parking and leaving, the phone line from Mum's landline, Shortcuts and routines) · Why you'd let him (four rules) · join |

**Recommendation: G.** Its hero is the product's one real trick, `propose_plan`, shown rather than described, and "Say it once. Tap once. Done." is the simplest line any round has produced. H is warmer and more "that's me", but a morning briefing sits close to the 08:45 moment on "What can Doddy do?"; if H wins, that moment should change. Both keep the one honest line and the link to the day page.

**Furthest-out claims, for the owner's eye:** the phone line (spec only, needs Twilio and the messaging server), the translator answering back on its own ("unless you stop me"), the Drive and Notion answers combining two sources in one reply, and routines by name. Everything else maps to a tool that exists today, in testing.

### Checked (round 3)
Headless Chromium 1194 at 390 and 1440 px: no horizontal scroll (G's "big asks" row scrolls sideways on phones by design), no broken images, both fonts loaded. Not checked: real Safari, VoiceOver, motion.

---

## Round 2: three ideas in the notebook theme

Each is a different *format* from the day-timeline on "What can Doddy do?", so the two pages can't repeat or contradict each other, and each keeps one quiet line linking to that page for "what works today". They link the live `tokens.css` + `styles.css` plus `notebook.css` (paper, tape, rings, stickies), so the theme is the live site's.

| | Idea | What's funny about it | What's visionary about it |
|---|---|---|---|
| D | **Dear Doddy.** An agony column for problems too small to ask anyone else. Letters from "Hungry, Mokotów" and "Typing…, Śródmieście"; Doddy's handwritten replies. Then "Things Doddy will never write back" (his rules as jokes) and a "write your own" letter that becomes the sign-up. | The letters. Everyone has sent "hey" by accident. | Letters can ask for anything: the pharmacy nudge, the Paris kiosk. Doddy answers "I'm still learning this one" where he is. |
| E | **Doddy's notebook.** The page is his notebook, open. Left page: what he's keeping for you (ticked). Right page: what he's getting good at (ticks, dots, empties). Then "My job. By me." (his own job description and a "Not my job" list), house rules as sticky notes, margin doodles. | The job description. "Salary: a cheers now and then." | The right page is the roadmap, drawn as a to-do list, with the honesty built into the tick marks. |
| F | **This time next year.** An album of twelve polaroids from a year that hasn't happened: "The dentist. On time. We don't know how either." One a month, captions by Doddy. Then "Until then" (how it works in three lines) and the film. | Tiny victories treated like trophies. | The whole page is the future, dated, without a single feature name. |

**Recommendation: E, with D's letters as the blog's recurring format.** E is the most on-theme (the product is literally a pocket notebook), it carries the vision and the honesty in one device (ticks vs dots vs empty boxes), and "My job. By me." gives Doddy a voice the current homepage lacks. D is the funniest and would make a great weekly post; F is the most emotional but the album needs twelve strong scenes and the pack has ten sceneries.

### Checked (round 2)
Headless Chromium 1194, 1440 and 390 px: no horizontal scroll, no broken images, both fonts loaded. Two live-stylesheet collisions found and fixed in the mockups: the site's `.cap` has `white-space: nowrap` (renamed to `.pcap` in F) and `.nav-links` is hidden below 900 px (the mockups now show it only above). Not checked: real Safari, VoiceOver, motion.

---

## Round 1 (turned down)

 `site/` is untouched. Owner brief (14 October): stop leading with what Doddy is today, hype people up about what Doddy can be, cut the homepage down, make How it works more creative. Leave the "What can Doddy do?" page as it is.

Open the HTML files in a browser (they load the live site's `tokens.css` and the pack art from `site/assets/day/`). Renders at 1440 and 390 px are in `png/`.

| | Direction | The promise | Feel |
|---|---|---|---|
| A | `a-just-say-it.html` | **Just say it.** A wall of things you'll say to Doddy and what he says back. | Voice-first, conversational, clean |
| B | `b-imagine.html` | **A little less to carry.** Big "Imagine…" scenes from a day where nothing slips. | Cinematic, storybook |
| C | `c-sticker-book.html` | **Your new mate lives in your phone.** An orange hero, a "Doddy can (and will)…" sticker sheet, a three-panel comic. | Loud, social, TikTok energy |

## Recommendation: A, with C's orange for the ask

- A says the product in three words and makes the visitor imagine saying them. The card wall sells possibilities without a status label on every line.
- B is the prettiest but repeats the scene-per-moment format of "What can Doddy do?", which is the repetition we just removed.
- C is the most fun for an 18+ social audience but says the least about why Doddy matters; its sticker sheet and orange join panel are worth borrowing.

## The homepage gets shorter (A)

| Today (12 sections) | Proposed (6) |
|---|---|
| Hero, film, problem, What's real today, How it works, three moments, voice, privacy, Meet Doddy, Take a shot, Remember it, join | Hero, Things you'll say, How it works (three words), film, Meet Doddy, join |

- **What's real today** moves to "What can Doddy do?" only, which already has its truth panel.
- **Voice and privacy** sections become one footer line plus a link to a privacy page (to write).
- **Take a shot and Remember it** move to a small `/play` page linked from Meet Doddy, or stay as one game.

## The honesty line stays

Every direction keeps one quiet line in the footer: "Doddy is an AI, not a person. Your notes live on your iPhone. Early access: some of what you see here is still on its way." The constitution (`docs/trust/`) and CLAUDE.md don't allow unbuilt things to read as shipped; framing them as a vision plus that line keeps the hype honest. Lines like "Remind me when I'm near the pharmacy" and the Paris translation are not built today.

## Art

Poses, props, scenery and effects all come from the owner's pack (`site/assets/day/`). The pack's strip frames (`jump_*`, `run_*`, `wave_2`, `wave_4`, `turn_*`) have a lot of empty canvas and read tiny as single images, so the mockups use the full poses instead.

## Checked

Headless Chromium 1194, 1440 and 390 px: no horizontal scroll, no broken images, Bricolage Grotesque and Caveat loaded, no page errors. Not checked: real Safari, VoiceOver, motion (none is drawn yet).
