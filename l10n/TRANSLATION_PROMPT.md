# Prompt: translate Doddy's screens into one more language

Copy everything below the line into a Claude Code session opened on this repository (it reads and writes the files itself). Replace `<CODE>` and `<LANGUAGE>` first, for example `de` and `German`. Run it once per language. The language codes are listed at the end of this page.

To use it in a plain chat window instead, run `python3 -I tools/l10n_batch.py show <CODE>` yourself, paste what it prints with the rules below, save the answer to a file and run `merge` on it; repeat until `status` shows nothing missing.

---

You are translating the iPhone app **Doddy** into **<LANGUAGE>** (code `<CODE>`). Doddy is a voice-first memory companion: you talk to him, he remembers things for you, keeps lists and reminders, and never pretends to be a person. Read `docs/design/BRAND_GUIDELINES.md` section 3.8 and `docs/trust/02_BEHAVIOUR_AND_CHARACTER_SPEC.md` before you start.

## Source

- `l10n/pl.json`: every key is an English UI string exactly as it is written in the Swift source; every value is its reviewed Polish translation. The keys are your English source. The Polish values show the intended register and tone; use them as a second reference, not as the source.
- `l10n/pl_infoplist.json`: the eight iOS permission prompts, with the English under `en`.
- `l10n/pl_shortcuts.json`: the 26 Siri phrases.

## How to write the files

Never type a key and never edit the JSON files by hand. `tools/l10n_batch.py` does it, a batch at a time:

1. `python3 -I tools/l10n_batch.py show <CODE> --count 60` prints the next strings still missing: a number, the English as a person reads it (`EN:`), and the Polish (`PL:`).
2. Translate them. Save a JSON object from number to your text to a file in your scratch folder, for example `{"0": " (compartida)", "1": "%@ a las %@. …"}`. Real characters, real line breaks (`\n` inside the JSON string), no `é` escapes.
3. `python3 -I tools/l10n_batch.py merge <CODE> that-file.json`. It writes `l10n/<CODE>.json` and refuses any text that is empty, has different `%` placeholders from the English, or (for Siri phrases) does not name `${applicationName}` exactly once or drops `${list}`; the rest is kept. Redo the refused numbers in the next batch.
4. Repeat 1 to 3 until `python3 -I tools/l10n_batch.py status <CODE>` shows 0 missing for `ui` (1,358 strings). Then do the same with `--table infoplist` (the 8 permission prompts) and `--table shortcuts` (the 26 Siri phrases).

Finish with a short note in the chat: the three counts from `status`, and the numbers you are least sure about so a native speaker can start there.

## Rules that the build enforces

1. **Placeholders stay.** `%@`, `%lld`, `%d` and `%%` must appear in your text exactly as many times, and in the same order, as in the English. No other `%`.
2. **Siri phrases** keep `${applicationName}` exactly once, and keep `${list}` if the English phrase has it. They are what a person says out loud to Siri, so they must sound natural in <LANGUAGE>.
3. **No empty text, no skipped numbers.** If a line is hard, give your best translation and list its number in the note.

## Rules for the text

- **Transcreate, don't translate word for word.** Say what the English means, the way a person in that language would say it out loud. Keep the meaning, the facts and the joke mechanism; drop the English idiom. Never translate "mate" literally and never script youth slang.
- **Register:** informal "you" (du, tu, tú, ty, ti…), as the Polish uses *ty*. Doddy is "he". Short sentences. Warm, plain, no exclamation marks the English doesn't have.
- **Names stay in English:** Doddy, iPhone, iPad, Apple Watch, Siri, iCloud, Face ID, Back Tap, Dynamic Island, Live Activity, Action Button, AirDrop, ElevenLabs, OpenAI, Google Keep. Decline "Doddy" only if that language must (as Polish does); otherwise leave it unchanged.
- **Apple's apps and settings use Apple's own names in that language:** Reminders, Calendar, Contacts, Shortcuts, Focus, Settings, Notifications, Control Centre, Lock Screen, Home Screen. Use the names iOS shows in <LANGUAGE>, not a translation of the English word.
- **"this iPhone"** must keep the word *iPhone* unchanged, so the build can swap it for *iPad* on an iPad. Write it so a plain word swap still reads correctly.
- **Length.** Buttons, tabs, titles and anything under about 20 characters must stay short: aim for the English length, never more than about a third longer. Long paragraphs may grow. Never shorten a sentence by leaving a fact out.
- **Privacy, permissions and the AI disclosure** (`l10n/<CODE>_infoplist.json` and every key that says what is sent to OpenAI, ElevenLabs, iCloud or a server, or what stays on the iPhone): translate completely and literally. Do not soften, add or drop a single statement about where data goes. Do not add reassurance the English does not give.
- **Doddy's character:** he is an AI. Never make him claim feelings, flatter the person, or joke in a line about health, money, loss or safety. Keep the honest wording of lines like "I'm not sure" and "That didn't save".
- **Dates, times and numbers** written in English in a key ("7 pm", "Monday") follow the conventions of <LANGUAGE>; `%@` placeholders are filled in by the app and need no change.
- **The tagline "Your mate in your pocket."** is not translated; if it ever appears, keep the English.
- **Consistency:** pick one word for each recurring term and keep it everywhere: note, list, reminder, memory, Talk to Doddy, Hey Doddy, Ask Doddy, What Doddy learned, Connections, Activity, Tidy up, Morning check-in, Evening wrap-up, Weekly look back, Shopping mode. Write your glossary first, then translate.

## When you are done

Run `python3 -I tools/build_strings_catalog.py`, then the same with `--check`. That puts <CODE> into the app's String Catalogs and into `CFBundleLocalizations` in both Info.plists. Commit the three tables, the regenerated `.xcstrings` files and the two plists together. Do not edit the `.xcstrings` catalogs by hand, and do not claim the app shows <LANGUAGE> until it has been run on a device and a native speaker has reviewed it (`l10n/README.md`, steps 3 and 4).

---

## Language codes

Use these as `<CODE>`; they are the codes Xcode and the App Store use. The first eight are the owner's request, then the languages the voice language picker lists, then the rest. The voice itself (OpenAI Realtime) speaks all of them.

| `<CODE>` | Language | Note |
|---|---|---|
| `es` | Spanish (Spain) | `es-419` for Latin America if wanted later |
| `de` | German | |
| `fr` | French | |
| `zh-Hans` | Chinese, Simplified | voice: fine on OpenAI Realtime; no ElevenLabs preset |
| `ja` | Japanese | voice: fine on OpenAI Realtime; no ElevenLabs preset |
| `pt-BR` | Portuguese (Brazil) | `pt-PT` for Portugal; ElevenLabs has one `pt` preset |
| `it` | Italian | |
| `hr` | Croatian | |
| `nl` | Dutch | |
| `sv` | Swedish | |
| `da` | Danish | |
| `nb` | Norwegian Bokmål | the ElevenLabs preset calls it `no` |
| `fi` | Finnish | |
| `cs` | Czech | |
| `sk` | Slovak | |
| `hu` | Hungarian | |
| `ro` | Romanian | |
| `bg` | Bulgarian | |
| `el` | Greek | |
| `sl` | Slovenian | |
| `lv` | Latvian | |
| `lt` | Lithuanian | |
| `uk` | Ukrainian | |
| `ru` | Russian | |
| `tr` | Turkish | |
| `ko` | Korean | voice: fine on OpenAI Realtime; no ElevenLabs preset |
| `ar` | Arabic | right to left: the screens need a layout review first |
| `he` | Hebrew | right to left: the screens need a layout review first |
| `hi` | Hindi | voice: fine on OpenAI Realtime; no ElevenLabs preset |
