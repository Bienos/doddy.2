# Post ideas

Each idea has a working title, an opening line, what the post shows, and what has to be true
before it can go out. Everything comes from things that actually happened in this repo. Don't
write a post before its "Ready when" is true.

## Building in the open (the honest-diary series)

### 1. "Doddy said 'I'm saving this' before I'd said yes"
- **Opening:** "The first time Doddy lied to me, it was trying to be helpful."
- **Shows:** Doddy announced a save before the Save card had even appeared. Why words like
  "saved", "added" and "sent" are only allowed after the phone confirms them, and how the line
  became "Confirm on screen if I should save this."
- **Evidence:** `docs/implementation/V1_VOICE_STATUS.md` (first-conversation observations).
- **Ready when:** the new line has been heard on the iPhone.

### 2. "The locker code, take two"
- **Opening:** "Last time I asked Doddy for my locker code, it said it couldn't find it. Here's
  round two."
- **Shows:** The follow-up to the first post: the same question, asked by voice after the
  Polish/English and spoken-number fixes. Publish it whatever the result is.
- **Evidence:** ADR-093, `SQLiteMemoryRepositoryTests.testRecallAcrossLanguagesSpokenNumbersEndingsAndTypos`.
- **Ready when:** the re-test has been done on the phone and written down.

### 3. "Why Doddy can draft your text but never send it"
- **Opening:** "Doddy can find Mum's number, write 'running 10 min late' and open Messages. Then
  it stops."
- **Shows:** Every action is a card you tap: Add, Start, Open in Maps, Open in Messages. Doddy
  never sends a message itself. Calendar and reminder adds are read back before Doddy says
  "added".
- **Evidence:** ADR-063, ADR-065, the tools table in `V1_VOICE_STATUS.md`.
- **Ready when:** calendar, reminders and messages have been tried on a real iPhone. Today the
  site's "Later, maybe" section still lists reminders, so update the site in the same change.

### 4. "What a minute of talking to Doddy costs"
- **Opening:** "Our first real conversation cost about five cents."
- **Shows:** About $0.04 per minute for voice plus the AI model on the current plan, roughly 1.3
  to 2.2 seconds before Doddy starts answering, and why there are caps before anyone else gets
  access.
- **Evidence:** `V1_VOICE_STATUS.md` (the cost and latency of the first conversation).
- **Ready when:** the owner is happy to share cost numbers publicly.

## Product and design

### 5. "Picking Doddy: three drawings, one mate"
- **Opening:** "We had two 'final' versions of Doddy. Both were called v1.3."
- **Shows:** The brand clash, why the redraw won (white sneakers, warm orange on paper), and the
  rule that the character never gets in the way of the task.
- **Evidence:** ADR-056, `docs/design/BRAND_GUIDELINES.md`, the pose SVGs on the site.
- **Ready when:** now. Only use art from `site/assets/poses/`.

### 6. "One morning in Warsaw: making Doddy's first film"
- **Opening:** "75 seconds, one city and a stick figure."
- **Shows:** Behind the scenes of the brand film on the landing page: the idea, what was
  generated and what was drawn, and what got cut.
- **Evidence:** the film commits on the site branch; the owner's production notes.
- **Ready when:** the owner adds the production details. Say clearly which parts were
  AI-generated.

### 7. "Search that shows its work"
- **Opening:** "If Doddy finds a note, it shows you why."
- **Shows:** Every result shows the note, its date, its source and the words that matched. Why
  there's no "smart" guessing. Diacritics are forgiven ("lodz" finds "Łódź").
- **Evidence:** ADR-005, ADR-027, ADR-093.
- **Ready when:** now. A screen recording from the simulator would help.

### 8. "Talk to Doddy without opening the app"
- **Opening:** "Tap the back of your phone twice. Hey, Doddy."
- **Shows:** Back Tap, the Control Center and Action Button control, and the Dynamic Island while
  you're in another app. Be honest that Back Tap is something *you* set up in iOS Settings;
  the app can't do it for you.
- **Evidence:** `V2_SHORTCUT_SETUP_STATUS.md`, `V3_ISLAND_STATUS.md`, ADR-084, ADR-094.
- **Ready when:** each surface has been tried on a device.

## Trust and privacy

### 9. "Your notes, your exit"
- **Opening:** "The most important button in Doddy is Delete all."
- **Shows:** JSON and plain-text export, delete one, delete all, what stays in your iPhone
  backup, and that there's no account.
- **Evidence:** ADR-028, ADR-030, `M1_STATUS.md`.
- **Ready when:** export and delete have been checked on a physical iPhone.

### 10. "Where your voice goes"
- **Opening:** "When you talk to Doddy, your voice leaves your phone. Here's exactly where."
- **Shows:** ElevenLabs runs the conversation, and weather and Wikipedia lookups go out from
  there. Your notes stay on the phone unless Doddy looks one up for you. Also how long
  recordings are kept.
- **Evidence:** ADR-057, ADR-064, ADR-087.
- **Ready when:** the owner has decided on retention (ADR-057). Don't publish while the answer
  is still "kept indefinitely" without saying that plainly.

## How it's made

### 11. "Building an app with an AI coding agent that has to say NOT RUN"
- **Opening:** "Our build script's favourite word is NOT RUN."
- **Shows:** The honesty contract: the check script fails when a step couldn't run, a guard
  blocks code that isn't allowed, and status docs say "not verified" until someone has actually
  checked.
- **Evidence:** `scripts/ci.sh`, `scripts/check_forbidden_capabilities.sh`, the M0 report.
- **Ready when:** now.

### 12. "Basketball on a landing page"
- **Opening:** "Nobody asked for a basketball game on our website. Here it is."
- **Shows:** Why the site has "Take a shot" and "Remember it" mini-games, what they say about
  Doddy's character, and how they were built with no tracking and no third-party scripts.
- **Evidence:** `site/court.js`, `site/memory.js`, `site/README.md`.
- **Ready when:** now.

## Community (needs real input first)

### 13. "What you asked Doddy to remember"
- **Opening:** "We asked people on the waitlist one question: what would you want Doddy to
  remember?"
- **Shows:** Anonymous, grouped themes from the optional waitlist question. Never quote a person
  without asking them first.
- **Ready when:** there are enough answers, and quoting rules are agreed.

### 14. "Doddy, now in Polish" / "Doddy, teraz po polsku"
- **Shows:** Building a bilingual companion, the Polish greeting, and the language detection
  that switched mid-conversation. A good candidate for a Polish version of the blog.
- **Ready when:** Polish has been tested with someone besides the owner.
