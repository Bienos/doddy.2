# Translation review notes (2026-10-13)

Eight languages were machine-translated in one pass, each by a separate Claude agent following `TRANSLATION_PROMPT.md`: Spanish (es), German (de), French (fr), Simplified Chinese (zh-Hans), Japanese (ja), Brazilian Portuguese (pt-BR), Italian (it) and Croatian (hr). **Every one is a draft.** None has been seen on a device or read by a native speaker (ADR-234 applies). This page lists what each agent said it was least sure about, so a reviewer starts there. Numbers like `#539` are the line numbers `python3 -I tools/l10n_batch.py show <code> --all` prints; they are the position in the sorted `l10n/pl.json`.

## Decisions for the owner (all languages)

1. **The emergency number: decided.** The owner chose "your local emergency number" (2026-10-13). The privacy line (#120, #1320 before the change) and the translator mode in the voice prompt and tool spec now say that instead of "112", in English and in all nine tables. The live ElevenLabs agent still has "call 112" in its prompt until the owner syncs it; the OpenAI voice reads the new text from the app.
2. **The example phone number** in two strings (#735, #1035) was changed to a local-looking number by the Chinese, Japanese and Portuguese agents, and kept by the others. It is only an example.
3. **The tagline "Your mate in your pocket."** (#1310) stays in English in every language, as `BRAND_GUIDELINES.md` 3.8 requires until the owner approves a transcreated line.
4. **"Hey Doddy"** stays in English everywhere. The spoken wake word is English; the screens around it are translated.
5. **Feature names** (Morning check-in, Evening wrap-up, Weekly look-back, Weekly tidy-up, Shopping mode, Connections) each got a different invented name per language. Pick them once with a native speaker, then the other screens follow.
6. **The Siri phrases** (`*_shortcuts.json`) must be read aloud to Siri on a device. The ones with a list name inside (`${list}`) are the riskiest in Chinese and Croatian.

Answers on 2026-10-13: Japanese ぼく, Croatian gender handling and the Siri read-aloud test were accepted as they are (the Siri test still has to be done on a device). The three new Settings strings for the language picker ("App language", "Same as this iPhone" and the footer) were written by the same agent that made this page, not by the translation agents, and need the same native review.

## Added 20 October 2026 (ADR-556, Brand Guidelines V2.2)

Written by the agent that applied the guide, not by the translation agents; the same native review applies:

- "Working on it…" (the voice screen's pending state, was "Thinking…") in all nine tables.
- The microphone prompt now opens with "To hear you, Doddy needs the microphone."; each `<code>_infoplist.json` got that sentence in front of its existing text.
- "Development build. Doddy is an AI assistant…" is the same string with "Doddy" instead of "DODDY".
- Spoken, not in the tables (DoddyCore `WakeGreeting`): the Polish opening lines "Cześć, tu Doddy. Co ci chodzi po głowie?" (first conversation) and "Jestem. Co słychać?" (after that). A Polish speaker should say them aloud; "Co ci chodzi po głowie?" is meant as the informal "What's on your mind?".

## Added 21 October 2026 (ADR-570, tasks handed to Doddy)

Polish only, written by the agent that built the Tasks screens; the other eight languages show these in English until they are translated. The same native review applies:

- "Tasks" is "Sprawy" (the owner's word for what you hand Doddy), "Your tasks" "Twoje sprawy", "No tasks yet." "Jeszcze nie ma spraw."
- "You said" became the gender-neutral "Twoje słowa".
- The budget line is "Budżet: „…”" with "mieści się", "przekracza" or "nie wiadomo".
- The task list's intro, the result card, Home's "Gotowe: %@" / "Nie udało się dokończyć: %@" card and the error lines in `ErrandsModel`.
- Not in the tables: the failure explanations come from DoddyCore (`ErrandFailureCode.explanation`) in English.

## Added 22 October 2026 (ADR-579 to 581: Action Button, Settings, Terms)

- 73 new Polish lines, machine-written, for the Settings groups and pages, the Action Button choice and the "Before we start" step. The other eight tables have none: those rows show in English there.
- **Check first:** "Przełączniki" for iOS's Action Button › *Controls* and "Przycisk czynności" for the Action Button: use exactly the words Polish iOS shows. "Regulamin" for Terms & Conditions and "Polityka prywatności" for the Privacy Policy, to match the website's Polish legal pages (`site/pl/terms/`, `site/pl/privacy/`) and the lawyer's wording. "Akceptuję Regulamin" on the unticked box.
- 31 Polish lines and 23 lines in each other table were removed with the Settings paragraphs they translated.

## Per language

**French (fr).** Uses non-breaking spaces before `? ! : ;` and inside « ». Unsure: "Receipts" → "Confirmations" (#782); "is now due" (#1357); "Item" → "Objet" (#449); "Way" → "Moyen" (#1233); "Focusing" (#384); "Grounded" → "Posé" (#405). Terms: memories = souvenirs; Morning check-in = Point du matin; Evening wrap-up = Bilan du soir; Weekly look-back = Retour sur la semaine; Shopping mode = Mode courses; Focus = Concentration (also Doddy's own focus timer); "Hey Siri" = « Dis Siri ».

**Portuguese, Brazil (pt-BR).** Unsure: "Mood" → "Ânimo" (#535, to avoid a clash with "Humour" → "Humor"); "Taken off" → "Retiradas" (#1010); "Way" → "Modo" (#1233); "Remind me…" → "Me lembre…" (#796 to #798); "Hey Doddy" kept; "mate" → "companheiro". Terms: Morning check-in = Check-in da manhã; Evening wrap-up = Fechamento do dia; Weekly look-back = Retrospectiva da semana; Back Tap = Toque na Parte Traseira; Keychain = Chaves; Delete = Apagar.

**Japanese (ja).** Doddy speaks as ぼく (#24, #351, #407, #487, #887, #1326): confirm this suits the character. Unsure: "Doddy doesn't use these until you say they are" (#269); "nudge" → ナッジ (#818, #1054); "Starts in" → 開始言語 (#988); "Receipts" → 実行の記録 (#782); Focus → 集中, iOS Focus → 集中モード (#381 to #384); サーバー versus Apple's サーバ. Terms: Connections = 連携; memory = 記憶; note = メモ; Morning check-in = 朝のチェックイン; Evening wrap-up = 夜のまとめ; Shopping mode = 買い物モード.

**Italian (it).** Unsure: "Added %lld to %@." → "Aggiunti %lld a %@." (#57, wrong agreement when the count is one); "Morning check-in" → "Punto del mattino" (#539); "Weekly look-back" → "Bilancio settimanale" (#1236); "Weekly tidy-up" → "Riordino settimanale" (#1238); "Grounded" → "Posato" (#405); "capture screen" → "schermata di acquisizione" (#289); "Pinned" → "Fissate" (#744); "Overdue" → "Scaduto" (#718). Terms: memory = ricordo; item = voce; Connections = Collegamenti; Shopping mode = Modalità spesa; iOS Focus = Full Immersion, Doddy's timer keeps "Focus".

**Croatian (hr).** Doddy is declined (Doddyja, Doddyju, Doddyjem, Doddyjev); Siri phrases say "aplikaciju Doddy" to avoid declining the app name. Gender is unknown for "(shared)" → "(dijeljeno)" (#0), "Added by %@" → "Dodao/la:" (#58) and "Ticked by %@" → "Označio/la:" (#1145): decide how to handle it. Unsure: "practical, curious mate" → "tip" (#273); "Got it." → "Jasno." (#404); "Grounded" → "Staložen" (#405); "nudge" → "poticaj" (#818, #1054); "Steady" → "Ujednačeno" (#991); "What you told me" (#1256). Terms: memory = sjećanje; note = bilješka; list = popis; passphrase = lozinka; passcode = šifra; Shopping mode = Način kupnje; Connections = Veze.

**Chinese, Simplified (zh-Hans).** Unsure: "A little less to carry." → 少操一点心 (#15); "Code" → 验证码, assumed to mean an SMS code (#172); "Morning check-in" → 早间概览 (#539); "Routine" → 例行流程 (#844); "Remind me at" → 提醒我于 (#798); Focus and Focused both → 专注 (#381, #383); "Name" → 名称 (#550); "Something else" → 其他内容 (#965). Terms: memory = 记忆; note = 笔记; list = 清单; Connections = 连接; passphrase and passcode both → 密码 (they should differ); Copy = 拷贝; Share = 共享. The Siri phrases with `${list}` (shortcuts #1, #12, #22) need a read-aloud check.

**Spanish (es).** Informal "tú"; Doddy is "él". Unsure: "Way" → "Modo" (#1233, no context); "is now due %@" (#1357, the article depends on what fills the placeholder); "unfinished note from %@" (#406, #1287); "Listening for you" → "Atento a tu voz" (#497); "Doddy's opening" → "Entrada de Doddy" (#300, #301); "Your voice note" → "Tu nota dictada" (#1329); "This evening" → "Esta tarde" (#1111); High, Low, Medium → Alto, Bajo, Medio, assumed to be the humour setting (#413, #515, #523). Terms: memories = Recuerdos; Morning check-in = Repaso de la mañana; Evening wrap-up = Cierre del día; Weekly look-back = Resumen semanal; Weekly tidy-up = Limpieza semanal; Shopping mode = Modo compra; Ask Doddy = Pregunta a Doddy; Dynamic Island = Isla Dinámica (Apple's Spanish marketing keeps "Dynamic Island"); Focus = Concentración for Doddy's timer and "modo de concentración" for iOS; passphrase = contraseña.

**German (de).** Informal "du"; Doddy is never declined ("von Doddy"). Unsure: "Face to face" → "Zu zweit" (#363); the "(Doddy asks for: %@)" fragments are bare nouns (#9, #1344 to #1354); "capture screen" → "Erfassen-Bildschirm" (#289, #716); "Receipts" → "Bestätigungen" (#782); "Commitment" → "Zusage" (#174); "Intention" → "Vorhaben" (#434); "Grounded" → "Bodenständig" (#405); "Steady" → "Stetig" (#991); "Never this" → "Nie wieder" (#562); "Way" → "Art" (#1233); "is now due %@" → "ist jetzt fällig: %@" (#1357); "Home" left as "Home" (#414). A final pass shortened 45 labels for German's length. Terms: memories = "Gemerktes" (one = "Eintrag"), because a reminder is "Erinnerung"; Memory on calls = Gedächtnis bei Anrufen; Back Tap = Auf Rückseite tippen; Notifications = Mitteilungen; Undo = Widerrufen; event = Termin; Morning check-in = Morgen-Check-in; Evening wrap-up = Tagesabschluss; Weekly look-back = Wochenrückblick.

## What to do with this page

A native reviewer works through one language at a time with `python3 -I tools/l10n_batch.py show <code> --all`, fixes lines with `merge`, then runs `python3 -I tools/build_strings_catalog.py` and commits. Privacy texts and the AI disclosure first (ADR-234). Record who reviewed which language and when, here, before anyone writes "supported".

## Website (landing page, ADR-460)

One agent per language made each table (`l10n/site/<code>.json`, 187 strings). Each reported the lines it was least sure of; the owner decides the open ones.

**Decisions for the owner**
1. **"A mate in your pocket"** (film chapter 1:05, and the same phrase in the description and lead of What can Doddy?) stays in English in every language. Decided by the owner on 2026-10-14. `build_site_i18n.py --check` fails if a table translates it.
   - Owner decisions on 2026-10-14: the Chinese pages are standard Mandarin in simplified characters (zh-Hans), and the website uses 列表 for "list" throughout (the app's table still uses 清单; decide if they must match). Brazilian Portuguese uses você everywhere. The Polish translation stays as it is. No native review for now. The admin page is outside translation (internal, noindex).
2. **Length in buttons.** "Join early access" is the header button and is long in several languages (Portuguese, German, Polish, French). The header wraps onto a second row on phones in five of them. Shorter wording needs an owner decision, because the same key also appears in the hero and the footer.
3. **"In testing" and "Later, maybe"** are translated for meaning, not word for word (German "Testphase", Italian "In test"). Say if the English words should stay.
4. **Polish parcel locker: changed.** "Paczkomat" is InPost's trademark, so the Polish page now says "skrytka na paczki" (parcel locker). Check the wording reads naturally.
5. **The emergency line and the early-access wording** need the same native read as the app (see the app sections above).

**Per language, the lines to check first**
- **Spanish:** "Pregúntale más tarde" (Ask later); "Corrígelo o olvídalo"; "Pedir acceso anticipado" is a third longer than the English; jokes "Qué va. Lo habría apuntado." and "De nada.".
- **German:** "Später" drops "ask"; "Nicht speichern" is 50% longer; "Überspringen" (Skip) is about three times the English; "Am Ring abgeprallt", "Zisch", "Nur Netz" are the basketball lines; "phone" became "iPhone" in two sentences.
- **French:** "Plus tard"; "Corriger ou oublier"; "Sur le cercle."; "Jeu de mémoire" for the memory game.
- **Chinese (Simplified):** waitlist is 候补名单 while early access is 抢先体验; "不用谢" for "You're welcome."; the chapter title stays in English (decided 2026-10-14), and the page title keeps the English tagline.
- **Japanese:** 事前登録 for the waitlist; "Doddyのほうが人より得意です" for "better at this than the rest of us"; "Saved means saved." lost its wordplay.
- **Portuguese (Brazil):** "Mais tarde" drops "ask"; "Lançar por mim" for "Shoot for me"; "Inscreva-se no acesso antecipado" is long for a button.
- **Italian:** "Iscriviti in anticipo" drops "access"; "Carte del memory"; "Tira per me".
- **Croatian:** "Zatraži rani pristup" for early access; "Pitaj poslije" for "Ask later"; "Preskoči" (Skip) is longer than the English.
- **Polish:** "Dołącz do wczesnego dostępu" is about 60% longer; "Później" drops "ask"; "Poziom B2" may read as a language level; "...and Polish alongside English" states Polish support as in testing, so check it does not read as available.

**Terms for a native reviewer:** Doddy's pronoun in each language (the app's table decides); "mate" as the app translates it (companion, Begleiter, compañero, tip, compagnon); "receipt" (Bestätigung, potwierdzenie, Tiques, justificatif); "wake word" (palabra de activación, not in the app's table); "Blog" with the English note "(English)" in brackets after it.

## Seven texts back in English after ADR-546 (20 Oct)

ElevenLabs became the default voice (ADR-546), so seven privacy texts that named OpenAI first were rewritten. English and Polish were rewritten; the microphone prompt was rewritten by hand in all nine languages. For **de, es, fr, hr, it, ja, pt-BR and zh-Hans** the old translations of these seven texts were removed, because swapping the two company names would have left pronouns such as "darauf" or "a ella" pointing at the wrong company. Until retranslated they show English. New English keys (first 90 characters):

- `Both voices go to ElevenLabs, or OpenAI if you switch Home's voice to it to be translated.…`
- `Doddy is an AI, not a person. Notes are kept on this iPhone, and because Memory on calls i…`
- `Doddy is an AI, not a person. Notes stay on this iPhone; while a conversation is open they…`
- `Optional. When set, it's sent to ElevenLabs, or OpenAI if you switch Home's voice to it wi…`
- `Stored on this iPhone with your memories, but separately: forgetting these doesn't delete …`
- `Talking sends these reminders and list names to ElevenLabs, or OpenAI if you switch Home's…`
- `While you talk, your voice, this conversation, your saved notes, your list names (and a li…`

## Doddy on the web (ADR-600, 22 Oct 2026)
- **App:** 22 new strings for Settings › Doddy on the web have Polish written by the agent (`l10n/pl.json`, the last lines). The other eight languages show them in English until `tools/l10n_batch.py` is run for them.
- **Web app:** `web/src/i18n/messages.ts` holds the whole page in Polish (default) and English, Polish written by the agent. A native speaker should read the sign-in steps and the safety line first ("Wpisuj kod tylko tutaj…"), since they are what stops someone being talked into reading their code out. Receipt summaries and connected-app descriptions come from the server in English on both.

- **Ask Doddy now names Anthropic (ADR-587, 22 Oct):** the consent dialog, the Ask screen's footer, the Settings footer and two new status lines ("Needs Doddy's server", "On, through Doddy's server") were rewritten in all nine languages by the agent, and the Polish privacy summary now says Anthropic instead of OpenAI. Read the consent first: its last sentence ("How long Anthropic keeps them isn't something Doddy can verify") is the retention claim the owner has not checked. The long privacy paragraph in Settings is still English-only in every language.

## Legal pages in Polish (22 Oct 2026)

`site/pl/terms/index.html` (Regulamin) and `site/pl/privacy/index.html` (Polityka prywatności) were written in Polish by the agent that wrote the English drafts, not by a translation agent and not with `tools/l10n_batch.py`. **They need a native Polish speaker and the lawyer** before the draft banner comes off; the pages say so themselves. Legal text is never machine-translated into the other eight languages: their footers link to the English pages, labelled "(English)" in each language (`Terms` and `Privacy Policy` in `l10n/site/<code>.json`, also unreviewed).

Check first:
- Legal terms: "Regulamin" for Terms and Conditions; "administrator", "inspektor ochrony danych", "umowa powierzenia przetwarzania", "prawnie uzasadniony interes" and the RODO article references in the legal-bases table.
- Apple's own Polish names: "Zaloguj się przez Apple" (Sign in with Apple), "Ruch i sprawność" (Motion & Fitness), "pęk kluczy" (Keychain), "Mapy Apple".
- Tone: informal "Ty" with capitals (Twoje, Ciebie), as in the app; gendered past forms are masculine ("jeśli korzystałeś"), which a reviewer may want to make neutral.
- App labels quoted in English because the Polish app still shows them in English: "What leaves this iPhone", "Delete Doddy voice account", "Sign out of voice", "Ask again before sharing voice". Once the app translates them, the pages should use the Polish labels.
- The Siri phrase is quoted from `l10n/pl_shortcuts.json` ("Zapytaj aplikację Doddy, co mam zapisane").

## Timers ring through AlarmKit (ADR-650, 24 Oct 2026)

- **The alarm permission prompt** (`NSAlarmKitUsageDescription`) now names timers: "Doddy sets an alarm or a timer only when you ask and tap Set alarm or Start…". The nine translations in `l10n/*_infoplist.json` were rewritten by the agent from the earlier ones, reusing each table's words for Set alarm, Start and Alarms. Not reviewed by a native speaker.
- **Four Polish lines in `l10n/pl.json`:** the Start card's "It rings even in Silent mode or a Focus…" and the three timer button intents. Agent-written.
- **Timer and focus notification text** is in DoddyCore (`TimerCopy`, Polish and English only, like the other notifications): "Czas minął", "Minutnik na 10 min skończył odliczanie.", "Koniec skupienia", "Minęło 25 min skupienia.", buttons "Zatrzymaj", "Powtórz", "Pauza", "Wznów". Agent-written; a Polish speaker should read them.

## Ringing reminders, the weekly plan, quiet hours (ADR-651, 24 Oct 2026)

Twenty-one new Polish lines in `l10n/pl.json`, agent-written: the "Ring like an alarm" switch and its notes ("Dzwoń jak budzik", "Dzwoni jak budzik, także w trybie cichym"), the weekly plan's screen and Settings section ("Plan na tydzień", "Twój tydzień\nprzed Tobą", "Nic zaplanowanego", "Prywatna notatka"), the quiet-hours sentence in Settings › Check-ins and reminders, and "Jutro". Notification and alarm words are in DoddyCore: "Nowy tydzień · Zerknąć, co Cię czeka?", "Za 10 min", "Zatrzymaj", "Przypomnienie Doddy'ego". The other eight languages show these in English until translated.
