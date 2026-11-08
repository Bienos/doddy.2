# App Store presentation v5: six moments with Doddy

Owner request, 8 Nov 2026: improve the App Store presentation (v4, `DODDY_Prezentacja_v4.pdf`) so it matches the real app and gives a concrete reason to try it; then "make it more narrative, more animated, cooler". This folder is the result.

**Status: concept. Every phone screen here is a reconstruction, and every conversation is an example.** Nothing in this folder may go to App Store Connect until each phone screen is replaced by a real screenshot of a feature checked on a device ("Before publishing", below; owner queue item 23).

## Files

| File | What it is |
|---|---|
| `index.html` (+ `story.css`, `story.js`) | The animated presentation: who it's for (three hypotheses), the six scenes, each played on a live phone (situation → start → sentence → result), the five headlines per scene, the App Store series, a simulated product page and search result, and the checklist. Open it through a local server (`render.mjs` starts one) or as the published page. |
| `shots/s1.png` … `s6.png` | The six App Store frames, 1290 × 2796 (iPhone 6.9″). Each carries the label "Rekonstrukcja · przykładowa rozmowa". |
| `shots/web/*.jpg` | The same frames at 645 × 1398 for the page and the PDF. |
| `DODDY_Prezentacja_v5.pdf`, `deck.html` | The same story as six A4 landscape pages (cover, boards 1–3, boards 4–6, headlines, store simulation, before publishing). |
| `render.mjs` | Renders the frames and the PDF and reports overflow, failed requests and fonts: `node design/app-store-v5/render.mjs` (add `--review <dir>` for whole-page pictures and one picture per animation step). |
| `assets/` | Copies of the owner's pack art (`WholeDoddy_*` poses, `DoddyMotion_*` and `VoiceDoddy_talking_*` frames, all cut from DODDY-Numbered-Video-Assets-v01; hashes in `docs/design/UPLOADED_MEMORY_ASSETS.md`), the `DoddyWordmark` SVG and the app icon at 360 px. Nothing was drawn or generated. |

No font files are in the folder: the pages load Bricolage Grotesque, Inter and Caveat from Google Fonts (Brand Guidelines V2.2, ADR-556). Inside the phone, Inter stands in for the system font.

## Where the screens come from

- **CI screen atlas** (ADR-820/821), simulator, 2 Nov 2026: run 41524238017 (walk of about 90 screens, commit 26254d6) and run 41539601647 (conversation cards and the voice Live Activity, commit 22d8d86). These show Home, Messages, Translate, the voice sheet with the note, reminder and other cards, and the island's Listening and Confirm states. The artifacts expire on 2–3 Dec 2026.
- **Code on `main` at 3c12153** for what the atlas can't show: Home while Doddy talks (ADR-595), Messages with a photo and with "From your saved notes" under an answer (`MessagesView.swift`), dictation, the face-to-face translator (`TranslatorViews.swift`), the `+` menu (5 Nov).
- **Words inside the phone** are the app's own Polish strings (`DoddyApp/Resources/Localizable.xcstrings`, `DoddyWidgets/Localizable.xcstrings`, `Translator.swift`). The island keeps "Stop" in every language (ADR-617). Where a string has no Polish yet, the frame leaves it out rather than translating it for the app (list below). One deliberate exception: the translator's middle bar is drawn with "Słucham", where today's code shows the untranslated "Listening"; the page says so.
- **Ad copy stays on the paper**, outside the phone: the situation line, the headline, the sentence bubble, "what to tap", and the notes around the animated phone.

## The six scenes and their headlines

Criteria: concrete, natural, readable in a small preview, 3–7 words; no line that would fit any assistant, no technical jargon, no unproven promise.

| # | Scene | Chosen headline | Rejected (why) |
|---|---|---|---|
| 1 | First conversation: tap Doddy, „Mam 20 minut. Co mogę zrobić na obiad?” | **Obiad w 20 minut? Stuknij i zapytaj.** | Masz sprawę? Powiedz. (any assistant) · Mało czasu na obiad? Powiedz. (doesn't say what to tap) · Twój kumpel w kieszeni. (brand line, not a scene) · Pytasz na głos, masz plan. (promise the screen doesn't show) |
| 2 | Action Button, conversation in the Dynamic Island, „Przypomnij mi odebrać paczkę o osiemnastej.” | **Paczka o 18? Naciśnij i powiedz.** | Przypomniało Ci się? Powiedz od razu. (general) · Przypomnienie bez otwierania aplikacji. (untrue: confirming opens Doddy) · Zajęte ręce? Wystarczy przycisk. (you still tap Add) · Jeden przycisk. Jedno zdanie. (abstract) |
| 3 | „Zapamiętaj: auto stoi na poziomie -2, sektor B”, later „Gdzie zostawiłem auto?” | **Gdzie auto? Odpowiedź z Twojej notatki.** | Gdzie stoi auto? Doddy ma notatkę. (sounds like Doddy's note) · Zapisz poziom. Zapytaj przy powrocie. (no source benefit) · Poziom -2, sektor B. Zapamiętane. (implies saving without consent) · Twoja pamięć zewnętrzna. (any notes app) |
| 4 | Window table in Polish, help in Spanish | **Mówisz po polsku. Kelner słyszy hiszpański.** | Nie znasz słów? Dogadaj się. (general) · Stolik przy oknie, po hiszpańsku. (who speaks?) · Tłumacz na stole, między wami. (set-up, not benefit) · Rozmawiaj bez barier językowych. (cliché) |
| 5 | Photo of an Italian menu, „Który to makaron z grzybami?” | **Menu po włosku? Zrób zdjęcie i zapytaj.** | Nie przepisuj. Pokaż zdjęcie. (no situation) · Zdjęcie karty, odpowiedź po polsku. (less natural) · Pytaj o to, co widzisz. (any assistant) · Rozumie każde menu. (unproven) |
| 6 | Eggs, tomatoes, feta: a dinner idea and one clarifying question | **Jajka, pomidory, feta? Doddy podpowie obiad.** | Z tego, co masz w lodówce. (not concrete) · Trzy składniki, jeden obiad. (reads as a guarantee) · Co ugotować? Wymień, co masz. (weaker in a thumbnail) · Koniec z marnowaniem jedzenia. (unproven) |

Proposed store order: 1, 3, 5, 6, then 2 and 4 only when they qualify. Frame 2 joins once the Action Button path is checked on a phone. **Frame 4 can't be used while the translator is hidden in the beta:** decision `docs/decisions/2026-11-07-release-scope.md` (merged on 8 Nov, after this work started) hides it, along with `start_translator`. The other scenes use features the beta shows: the conversation, notes, Reminders, Messages (behind its own consent) and photos. Parking is hidden too, which is one more reason scene 3 uses a note.

## What is checked, and what isn't

| Scene | Seen in the CI atlas (simulator) | Built in code, no screenshot | Not checked |
|---|---|---|---|
| 1 | Home, the tap target | Talking on Home, Transcript | The conversation itself (CI runs offline) |
| 2 | Island Listening and Confirm (fixture), the reminder card | Action Button control → island | All 16 cases in `docs/implementation/ACTION_BUTTON_ISLAND.md` are NOT VERIFIED on a device |
| 3 | The "Save this note?" card | "From your saved notes" with the note's text and date | Whether "Remember…" yields the note card rather than the parking card; recall quality |
| 4 | Island "Translating" with codes | Face-to-face screen, the Spanish disclosure line | On a device; **hidden in the beta** (release scope) |
| 5 | — | `+` › Take a photo › Messages with the photo above the box; "Photo" in the thread | Menu reading accuracy |
| 6 | — | Dictation in the box, "Not from your notes" label | Answer quality |

## Polish strings missing in the app (found while rebuilding the screens)

Shown in English in a Polish build today; left out of the frames.

- Reminder card: "Doddy checks your open reminders on this iPhone first, so it isn't added twice."
- Ways to open Doddy, Action Button page: "Make the Action Button start a conversation with Doddy.", "Swipe to Controls (Shortcut on iOS 17)…", "Pick Talk to Doddy.", "Under Controls, Talk to Doddy talks in the Dynamic Island…".
- Messages: the intro "If your question is about something you saved…" (a plain `String` passed to `Text`, so never localised) and the disclosure paragraph "Doddy is an AI, not a person. This conversation is saved…".
- Translator: the middle bar's "Listening", "Paused", "Hold a button to talk" are plain `String`s in `TranslatorViews.swift` (`statusText`), so they are never localised; "Doddy said to them: %@"; "They speak".
- ••• menu and voice sheet: "What leaves this iPhone".

Not gaps, checked: the voice sheet's "Listen until I finish" and the "Doddy is listening · Stop listening" pill take their Polish from DoddyCore (`LongTurn`, `ListeningPrivacy`), not from the catalog, and are drawn in Polish.

## Before publishing

1. Build `main` on an iPhone with a voice account, "Ask Doddy" on, Polish. Go through each scene for real and screenshot the result. Swap only the phone screen into the frame; the paper layer stays.
2. Run the device checks: scene 1 (talk on Home, Transcript); scene 2 (Action Button matrix, at least cases 1, 2, 4, 5, 13 and 16, and Show opening the card); scene 3 (note card, recall with the note shown); scene 4 (PL ⇄ ES face to face); scene 5 (a real menu, accuracy on a dozen menus); scene 6 (dictation, answer quality).
3. Fix the missing Polish strings above first, so the real screenshots are Polish throughout.
4. Remove the "Rekonstrukcja" label only from frames whose phone screen is real.
5. Don't claim better conversion. Before launch: five-second and first-click tests with 5–8 people, headline preference tests. After launch: Product Page Optimization in App Store Connect, v4 against v5.
