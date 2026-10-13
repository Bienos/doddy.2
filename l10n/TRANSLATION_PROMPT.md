# Prompt: translate Doddy's screens into one more language

Copy everything below the line into a Claude Code session opened on this repository (it reads and writes the files itself). Replace `<CODE>` and `<LANGUAGE>` first, for example `de` and `German`. Run it once per language. The language codes are listed at the end of this page.

To use it in a plain chat window instead, attach `l10n/pl.json`, `l10n/pl_infoplist.json` and `l10n/pl_shortcuts.json`, and add: "Work through the table 100 keys at a time, in file order, and answer each batch with JSON only, so the batches can be joined into one file."

---

You are translating the iPhone app **Doddy** into **<LANGUAGE>** (code `<CODE>`). Doddy is a voice-first memory companion: you talk to him, he remembers things for you, keeps lists and reminders, and never pretends to be a person. Read `docs/design/BRAND_GUIDELINES.md` section 3.8 and `docs/trust/02_BEHAVIOUR_AND_CHARACTER_SPEC.md` before you start.

## Source

- `l10n/pl.json`: every key is an English UI string exactly as it is written in the Swift source; every value is its reviewed Polish translation. The keys are your English source. The Polish values show the intended register and tone; use them as a second reference, not as the source.
- `l10n/pl_infoplist.json`: the eight iOS permission prompts, with the English under `en`.
- `l10n/pl_shortcuts.json`: the 26 Siri phrases.

## Output

Write three files, in the same shape as their Polish counterparts:

1. `l10n/<CODE>.json`: an object with **every key from `l10n/pl.json`, copied byte for byte**, mapped to its <LANGUAGE> text. Same key order as the Polish file.
2. `l10n/<CODE>_infoplist.json`: the same keys as `l10n/pl_infoplist.json`, each an object with `"en"` copied unchanged and `"<CODE>"` holding the translation.
3. `l10n/<CODE>_shortcuts.json`: the same keys as `l10n/pl_shortcuts.json`, mapped to the <LANGUAGE> phrase a person would say to Siri.

Write valid JSON, UTF-8, two-space indent, `ensure_ascii` off (real characters, not `é`). No commentary inside the files. Finish with a short note in the chat: how many keys you wrote, and a list of the keys you are least sure about so a native speaker can start there.

## Rules that the build enforces

The build script rejects a file that breaks these, so check them before you finish.

1. **Keys are untouchable.** Copy each key exactly, including its escapes: `\n`, `\"`, `\u{203A}`, `\u{201C}`. Do not fix the English, reorder, drop or add keys.
2. **Values are plain text.** Where a key says `\n`, the value has a real line break. Where a key says `\"`, the value has a real `"` (or the quotation marks that language uses). Where a key says `\u{203A}`, the value has the real character `›`. The Polish file shows this.
3. **Placeholders stay.** `%@`, `%lld`, `%d` and `%%` must appear in the value exactly as many times, and in the same order, as in the key. A value may not contain any other `%`.
4. **Siri phrases** keep `${applicationName}` exactly once, and keep `${list}` if the English phrase has it.
5. **No empty values.** If a line is hard, give your best translation and list its key in the note.

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

Run `python3 -I tools/build_strings_catalog.py --check`. Until the script reads languages other than Polish (see `l10n/README.md`), it will not read your file; say so in the note rather than claiming the app shows <LANGUAGE>. Do not edit the `.xcstrings` catalogs by hand.

---

## Language codes

Use these as `<CODE>`; they are the codes Xcode and the App Store use. The first eight are the owner's request, then the languages Doddy's voice already speaks, then the rest.

| `<CODE>` | Language | Note |
|---|---|---|
| `es` | Spanish (Spain) | `es-419` for Latin America if wanted later |
| `de` | German | |
| `fr` | French | |
| `zh-Hans` | Chinese, Simplified | not in the voice agent yet |
| `ja` | Japanese | not in the voice agent yet |
| `pt-BR` | Portuguese (Brazil) | `pt-PT` for Portugal; the voice agent has one `pt` |
| `it` | Italian | |
| `hr` | Croatian | |
| `nl` | Dutch | |
| `sv` | Swedish | |
| `da` | Danish | |
| `nb` | Norwegian Bokmål | the voice agent calls it `no` |
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
| `ko` | Korean | not in the voice agent yet |
| `ar` | Arabic | right to left: the screens need a layout review first |
| `he` | Hebrew | right to left: the screens need a layout review first |
| `hi` | Hindi | not in the voice agent yet |
