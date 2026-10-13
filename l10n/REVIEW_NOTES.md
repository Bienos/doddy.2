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
1. **"A mate in your pocket"** (film chapter 1:05) is a variant of the tagline. Kept in English in French, Portuguese and Polish; translated in the other languages. Choose one rule.
2. **Length in buttons.** "Join early access" is the header button and is long in several languages (Portuguese, German, Polish, French). The header wraps onto a second row on phones in five of them. Shorter wording needs an owner decision, because the same key also appears in the hero and the footer.
3. **"In testing" and "Later, maybe"** are translated for meaning, not word for word (German "Testphase", Italian "In test"). Say if the English words should stay.
4. **Polish "Paczkomat"** (parcel locker) is an InPost trademark. A generic term may be safer.
5. **The emergency line and the early-access wording** need the same native read as the app (see the app sections above).

**Per language, the lines to check first**
- **Spanish:** "Pregúntale más tarde" (Ask later); "Corrígelo o olvídalo"; "Pedir acceso anticipado" is a third longer than the English; jokes "Qué va. Lo habría apuntado." and "De nada.".
- **German:** "Später" drops "ask"; "Nicht speichern" is 50% longer; "Überspringen" (Skip) is about three times the English; "Am Ring abgeprallt", "Zisch", "Nur Netz" are the basketball lines; "phone" became "iPhone" in two sentences.
- **French:** "Plus tard"; "Corriger ou oublier"; "Sur le cercle."; "Jeu de mémoire" for the memory game.
- **Chinese (Simplified):** waitlist is 候补名单 while early access is 抢先体验; "不用谢" for "You're welcome."; the chapter title is translated, the page title keeps the English tagline.
- **Japanese:** 事前登録 for the waitlist; "Doddyのほうが人より得意です" for "better at this than the rest of us"; "Saved means saved." lost its wordplay.
- **Portuguese (Brazil):** "Mais tarde" drops "ask"; "Lançar por mim" for "Shoot for me"; "Inscreva-se no acesso antecipado" is long for a button.
- **Italian:** "Iscriviti in anticipo" drops "access"; "Carte del memory"; "Tira per me".
- **Croatian:** "Zatraži rani pristup" for early access; "Pitaj poslije" for "Ask later"; "Preskoči" (Skip) is longer than the English.
- **Polish:** "Dołącz do wczesnego dostępu" is about 60% longer; "Później" drops "ask"; "Poziom B2" may read as a language level; "...and Polish alongside English" states Polish support as in testing, so check it does not read as available.

**Terms for a native reviewer:** Doddy's pronoun in each language (the app's table decides); "mate" as the app translates it (companion, Begleiter, compañero, tip, compagnon); "receipt" (Bestätigung, potwierdzenie, Tiques, justificatif); "wake word" (palabra de activación, not in the app's table); "Blog" with the English note "(English)" in brackets after it.
