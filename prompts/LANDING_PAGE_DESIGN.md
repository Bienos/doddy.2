# Prompt — Doddy landing page (creative, connected to the app)

Copy everything below the line into Claude Code (or another design/build agent) working in `Bienos/doddy.2`.
The prompt is self-contained, so it also works in a design tool if you paste the token and asset sections with it.

---

## Role

You are a senior brand designer and front-end engineer. Design and build **one creative, single-page landing site** for **Doddy — "Your mate in your pocket."** The page has two jobs:

1. Explain **who Doddy is** (the character: a warm, hand-drawn mate with a personality).
2. Explain **what the Doddy app does** (an iPhone app where you save the details that matter and find the exact original later, and can talk to Doddy by voice).

The site must be **connected to the app**: it should feel like the app's front door, use the app's own design system and character, show the app's real screens and copy, and send people into the app. Someone who lands on the site, then opens the app, should feel they never changed places.

## Read first (repository sources of truth)

Before designing, read these and follow them over anything in this prompt if they conflict:

- `CLAUDE.md`, `docs/design/CANONICAL_DESIGN_DIRECTION.md`, `docs/design/BRAND_AND_CHARACTER.md`
- `design/interface-v1.2/docs/DESIGN-SYSTEM.md`, `MOTION-AND-STATES.md`, `ONBOARDING-AND-PERSONAL-HOME.md`
- `design/interface-v1.2/previews/*.png` (the Pocket Notebook look) and `design/interface-v1.2/index.html` (the browser prototype)
- `Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift` (the tokens the app actually uses)
- `DoddyApp/Features/Home/HomeView.swift`, `DoddyApp/Features/Onboarding/FirstHelloView.swift` (the app's real copy)
- `docs/product/PRODUCT_REQUIREMENTS.md`, `docs/implementation/M1_STATUS.md`, `docs/implementation/V1_VOICE_STATUS.md` (what is actually built)

## What Doddy is (the story to tell)

- **The character:** a hand-drawn stick figure with a round head, tall oval eyes, a warm lopsided smile, black-ink line body, mitten hands, oversized trainers, an orange backpack and a basketball. A capable "side-quest fixer": notices the small frictions in your day, helps first, jokes about everyday inefficiency, never about you. Calm and plain when things are serious. No guilt, clinginess, fake feelings or "I missed you".
- **The app's core promise:** *Tell Doddy before you forget; find the original later.* You choose what gets saved. Doddy keeps your exact words, shows where and when each note came from, lets you correct it without losing the original, and lets you export or delete anything.
- **Honesty is part of the brand:** Doddy is an AI, not a person, and says so. It never invents a memory and says "I couldn't find that" when it can't.

## Feature truth table (the page must match this exactly)

| Capability | Status | How the page may present it |
|---|---|---|
| Save a detail by typing (exact text kept, source + date) | Built, simulator-tested | Core feature, present tense |
| Search your notes and get the original back, "couldn't find it" when there's no match | Built, simulator-tested | Core feature, present tense |
| Edit (original kept), copy, export JSON/text, delete one / delete all | Built, simulator-tested | Core feature, present tense |
| Notes stored only on the iPhone, no account | Built | Present tense |
| Talk to Doddy by voice (foreground only, via ElevenLabs, asks before saving) | Built, **not yet verified on a real iPhone** | "In testing" / "Early access" label, never "available now" |
| Reminders, calendar, messages, other apps, Back Tap / Dynamic Island companion, always-listening | **Not built** | Only in a clearly labelled "Later, maybe" section, or leave out |
| App Store availability | **Not released** | CTA is "Join the waitlist / early access", never "Download on the App Store" |

Never show fake ratings, download counts, press logos, testimonials or user numbers. If you need social proof, use none.

## Creative concept

**"The pocket notebook that talks back."** The whole page is a warm paper notebook you flip through. Doddy lives on the page as an ink drawing and walks you through the app's real loop as you scroll. Each section is a "page" of the notebook with a short handwritten heading and a real app screen beside it.

Scroll story (each beat pairs one Doddy pose with one real app state):

1. **Hero — "Hey. I'm Doddy."** Doddy (`approaching` pose) arrives on the paper, settles 4 px, waves (`waving`). Headline in the handwritten display face, subline in the reading face: "Your mate in your pocket. Tell me the stuff you don't want to forget; I'll hand you the exact note back later." Primary CTA: **Join early access**. Secondary: **See how it works** (anchor scroll). An iPhone frame on the right shows the real First Hello screen.
2. **The problem — "A little less to carry."** Short, funny, relatable: the parcel-locker code, the book Marta recommended, the size of the shoes your kid needs. Doddy `holding-coffee` / `relaxing`. Hand-drawn orange underline on one phrase only.
3. **Save it — "Tell Doddy."** Phone shows the Capture screen; type-on animation of "The parcel locker code is 1234" → Save → a "Saved" receipt appears only after the stamp. Doddy `memory-card` pose. Caption: "Saved means saved. If it fails, your draft stays put."
4. **Find it — "Ask later."** Phone shows Memories search for "book Marta" → one result with the original text, source and date. Doddy `reading` / `pointing`. Then a second mini-beat: search for something never saved → "I couldn't find that in your saved memories." Caption: "Doddy shows you the original. If it isn't there, Doddy says so."
5. **Talk to Doddy — "Or just say it."** Labelled **In testing**. Phone shows the Voice screen with the real status words (Connecting…, Listening, Thinking…, Speaking). Doddy `listening` pose. Caption: "Talking only happens while the screen is open. Doddy asks before saving anything you said."
6. **You're in charge — "Your notes, your call."** Edit with original kept, export, delete one, delete all. Doddy `fist-bump`. Plain-language privacy: notes stay on your iPhone, no account; voice goes to ElevenLabs only during a conversation; Doddy is an AI, not a person.
7. **Meet the character — "Who's Doddy?"** A playful sketchbook spread: 4–6 poses (`basketball-dribble`, `running`, `working-laptop`, `walking-with-coffee`, `sitting`) with one-line personality notes ("Fixes side quests." "Jokes about the queue, never about you." "Goes quiet when it matters."). Optional: hover/tap a pose to flip it like a page corner.
8. **Later, maybe** (optional, small, clearly labelled not built): reminders, other languages. No dates, no promises.
9. **Final CTA — "Come say hey."** Doddy `basketball-shot` (the ball arcs into the CTA button). Waitlist form (email only), plus "Already testing? Open Doddy" deep-link button. Footer: AI disclosure, privacy link, contact, © line.

## Visual system (must match the app)

Use the app's **Pocket Notebook** tokens as CSS custom properties, with light and dark themes. Do not invent new colours. Do not use the historical `assets/brand_candidate` palette.

| Token | Light | Dark | Use |
|---|---|---|---|
| `--ink` (readingInk) | #171715 | #FFF7E9 | Body text, headings, primary button fill |
| `--canvas` | #FFF7E9 | #171F29 | Page background (warm paper / night) |
| `--orange-cue` | #F58A24 | #F58A24 | Underlines, dots, the backpack and ball. **Decoration only, never body text** |
| `--secondary-text` | #655F56 | #C5BCAD | Supporting copy |
| `--quiet-surface` | #F5EAD8 | #252E39 | Cards, inputs |
| `--separator` | #DFD5C6 | #414953 | Rules, notebook lines |
| `--accent-text` | #A64B00 | #FFB56B | Orange-ish text that must stay readable |
| `--confirmed` | #326746 | #97CEA6 | "Saved" receipt, with text and icon |
| `--error` | #A3342E | #FFAAA1 | Form errors, with text and icon |

- **Type:** reading face = system UI stack (`-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif`) to match the native app's Dynamic Type. Handwritten display face only for short headings (2–3 lines max); the browser prototype uses Caveat (OFL, bundled in `design/interface-v1.2/assets/`). Load it from Google Fonts or the bundled OFL file; do not add any other font binaries.
- **Texture:** subtle paper grain and faint ruled notebook lines (CSS, not heavy images). A margin line on the left of each section. Hand-drawn orange underlines and circles as SVG strokes that "draw on" when the section enters view.
- **Spacing and shape:** 4/8/12/16/24/32 scale; radius 18 for buttons, 16 for inputs/cards; primary buttons at least 54 px tall; tap targets at least 44×44.
- **Feel:** calm, editorial, warm, funny in small doses. Lots of paper, very little chrome. The character never covers text.

## Character and screen assets (connected to the app)

- **Character:** use only the SVGs in `design/interface-v1.2/assets/doddy-pose-*-v1.3-r1.svg` (light and dark variants; swap with the theme — `walking-with-coffee` has a light version only, so use it on light sections or pick another pose in dark mode). Inline them as SVG so strokes can animate. Mark them decorative (`aria-hidden="true"`) unless a pose carries meaning, then give it a short alt text.
- **App screens:** show the real app, not invented UI. Preferred: fresh simulator screenshots of the native app (First Hello, Home, Capture, Saved receipt, Memories search, No match, Memory detail, Voice, Settings → privacy). Until those exist, use `design/interface-v1.2/previews/*.png` and label the section "Design preview" in small text. Use the app's real copy (e.g. "Hey. I'm Doddy.", "A little less to carry.", "Save a useful detail. Find it when you need it.", "Talk to Doddy", "Nothing saved yet. You choose what stays.").
- Put the iPhone frame in CSS/SVG you draw yourself. Do not use Apple's device artwork or the App Store badge.

## How the site connects to the app

1. **One design system.** Generate the site's CSS variables from the same values as `CandidateTokens.swift` (a small script in `tools/` that reads the token table and writes `site/tokens.css` is ideal). If a token changes in the app, the site follows.
2. **Same character, same copy.** Pull poses from the same asset folder the app uses; reuse the app's actual headings and disclosure sentences word for word.
3. **Calls to action into the app.**
   - "Join early access" → email waitlist form. Form posts to a placeholder endpoint defined in one config value (`WAITLIST_URL`); with no endpoint configured it shows an honest "Waitlist opens soon" message. No third-party trackers.
   - "Open Doddy" → a deep link (e.g. `doddy://home`) with a fallback to the waitlist if the app isn't installed. Note in the handoff that the app must register this URL scheme (and later Universal Links with an `apple-app-site-association` file) — do not modify the app in this task.
   - Leave a clearly marked slot for a future TestFlight / App Store link; keep it hidden until a real URL exists.
4. **Same truth.** The landing page's claims are checked against the feature truth table above. The AI disclosure and privacy wording match `FirstHelloView.swift` / `HomeView.swift`.
5. **Smart App Banner ready:** include a commented-out `<meta name="apple-itunes-app" ...>` to enable when the app has an App Store ID.

## Motion

- Follow `MOTION-AND-STATES.md`: short, one-shot moves (arrive 320 ms ease-out, confirm 380 ms), no endless idle loops, no fake progress bars.
- Scroll-linked: Doddy changes pose per section (cross-fade between poses), orange strokes draw on, the phone screen swaps state in sync with the section.
- `prefers-reduced-motion: reduce` → static poses, no scroll-linked movement, everything readable immediately. Content and CTAs never wait for an animation.

## Technical constraints

- Static site in `site/` (plain HTML + CSS + a small amount of vanilla JS, or Astro if you need components). No backend, no analytics, no cookies, no external scripts beyond fonts.
- Mobile-first: works at 320 px wide with no horizontal scroll; phone frame stacks under the text on small screens.
- Performance: inline critical CSS, lazy-load screens below the fold, total page under ~1 MB excluding fonts.
- Accessibility: WCAG 2.1 AA contrast (bright orange never used for text), semantic headings in story order, visible focus states, keyboard-reachable CTAs, labelled form field with text error messages, `lang="en"` (structure ready for a Polish version).
- SEO basics: title "Doddy — your mate in your pocket", meta description, Open Graph image made from a Doddy pose on paper.
- Do **not** deploy, buy a domain, create accounts or connect a real waitlist service. Build locally and hand off.

## Copy voice

- Short, warm, plain English, a little funny about everyday stuff ("the parcel locker code you'll need in exactly four minutes"). Never sarcastic toward the reader.
- Concrete over clever. Each section: handwritten heading (2–5 words) + one or two sentences + the real screen.
- Say what Doddy can't do as plainly as what it can.
- Banned: "revolutionary", "never forget anything again", "remembers everything", "your AI best friend", "always there for you", any claim of real-time listening, any made-up stats.

## Deliverables

1. `site/index.html`, `site/styles.css`, `site/tokens.css`, `site/main.js`, `site/assets/` (copied poses + screens), Open Graph image.
2. `tools/` script that generates `tokens.css` from the app tokens (or a documented manual step if a script isn't practical).
3. `site/README.md`: how to preview locally, where the `WAITLIST_URL` and deep-link settings live, which screens are real vs design previews, and the app-side work needed for the deep link.
4. Screenshots of the page at 390 px (light and dark) and 1440 px, plus one with reduced motion.

## Acceptance checklist (check every line before you finish)

- [ ] Every feature claim matches the truth table; voice is labelled "In testing"; nothing says "Download on the App Store".
- [ ] Colours come only from the token table; no orange body text; contrast checked.
- [ ] Only `design/interface-v1.2/assets` poses used; theme swaps light/dark poses.
- [ ] App screens are real screenshots or labelled "Design preview".
- [ ] AI disclosure ("Doddy is an AI, not a person") and the on-device / ElevenLabs privacy sentence appear on the page.
- [ ] Waitlist form works without an endpoint (honest message) and with a configured one.
- [ ] "Open Doddy" deep link has a fallback.
- [ ] 320 px, keyboard-only and reduced-motion runs checked; report what you actually ran and what you didn't.
- [ ] Nothing deployed or published.

When done, report: files changed, what the page shows, what you checked and how, what still needs the owner (final brand approval, real screenshots, waitlist provider, domain, App Store ID), and stop.
