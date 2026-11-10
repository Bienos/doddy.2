# "What I can do": the words and the status rules

The screen at Home › ••• › What I can do (decision `docs/decisions/2026-11-09-what-i-can-do.md`). The source of truth is
`Packages/DoddyCore/Sources/DoddyCore/WhatICanDo.swift` (rows and statuses) and `CapabilityIntroduction.swift` (the
opening paragraph); this file is the readable copy of them for review. Change both together.

The words are **product voice** (`docs/design/BRAND_GUIDELINES.md` §3): calm, literal, short, second person for the
reader, "Doddy" in the third person, curly apostrophes, no exclamation marks or em dashes. Doddy speaks in the first
person only in the opening paragraph. The Polish is written for Polish readers (§3.8), with the app's capitalised
Ty forms and no gendered first-person forms.

## Status rules
Worked out from the build, never from prose. A feature the release scope hides isn't listed at all.

| Status | English | Polish | When |
|---|---|---|---|
| Ready | Ready | Gotowe | Notes only: built, tested and used on a phone |
| In testing | In testing | W testach | Built and tested in code, still being tried on real phones |
| Needs setup | Needs setup · this build isn’t connected to Doddy’s server | Wymaga konfiguracji · ta wersja nie ma połączenia z serwerem Doddy’ego | A feature that needs the messaging server, in a build without its address |
| Not tried on a real call | Not tried on a real call yet | Jeszcze niesprawdzone na prawdziwej rozmowie | Phone calls and Calls for you, until a real call is recorded (`WhatICanDo.realCallRecorded`) |
| Not in this version | Not in this version | Nie w tej wersji | The catalog says the code isn't in this build |

## Rows, in order

| Feature (gate) | English: title · what Doddy does · what stays with you | Polish | Opens | Status in this build |
|---|---|---|---|---|
| Talk to Doddy | **Talk to Doddy** · Ask out loud and get a short answer. Doddy can look things up in your notes while you talk. · Your voice is sent only while a conversation is on. What leaves this iPhone shows where. | **Porozmawiaj z Doddym** · Pytasz na głos i dostajesz krótką odpowiedź. W trakcie rozmowy Doddy może zajrzeć do Twoich notatek. · Głos jest wysyłany tylko w trakcie rozmowy. Dokąd, pokazuje ekran „Co opuszcza tego iPhone’a”. | nothing (Talk is on Home) | In testing |
| Notes | **Notes** · Save something in your own words and find it again later. · Only what you save is kept. It stays on this iPhone unless you choose otherwise in Settings. | **Notatki** · Zapisz coś własnymi słowami i znajdź to później. · Zostaje tylko to, co zapiszesz. Zostaje na tym iPhonie, chyba że w Ustawieniach wybierzesz inaczej. | Notes and lists | Ready |
| Lists | **Lists** · Shopping and to-do lists, by voice or by typing. · You decide what goes on them. | **Listy** · Listy zakupów i rzeczy do zrobienia, głosem albo pisząc. · Ty decydujesz, co na nie trafia. | Notes and lists | In testing |
| Reminders and calendar | **Reminders and calendar** · Ask in a conversation and Doddy prepares a reminder or a calendar event. · Nothing is added until you confirm it on screen. | **Przypomnienia i kalendarz** · Poproś w rozmowie, a Doddy przygotuje przypomnienie albo wydarzenie w kalendarzu. · Nic nie zostanie dodane, dopóki nie potwierdzisz tego na ekranie. | nothing (it happens in a conversation) | In testing |
| Messages (`messages`) | **Messages** · Type a question instead of talking. You can add a photo or a file. · Off until you agree to it. Answers come from Claude, through Doddy’s server. | **Wiadomości** · Napisz pytanie zamiast mówić. Możesz dołączyć zdjęcie albo plik. · Wyłączone, dopóki się nie zgodzisz. Odpowiada Claude, przez serwer Doddy’ego. | Messages | In testing, or Needs setup without a server |
| Phone calls (`phoneCalls`) | **Phone calls** · Call Doddy’s number and talk, or let Doddy call you. · Only your verified number gets through, and only after your PIN. Your notes are used only if you allow it. | **Rozmowy telefoniczne** · Zadzwoń na numer Doddy’ego albo pozwól Doddy’emu zadzwonić do Ciebie. · Połączy się tylko Twój zweryfikowany numer i dopiero po PIN-ie. Notatki są używane tylko, jeśli na to pozwolisz. | the Phone calls screen, inside the sheet | Not tried on a real call yet, or Needs setup without a server |
| Calls for you (`callCases`) | **Calls for you** · Doddy rings a business with one question for you, like whether your laptop is ready. · Nothing is dialled until you approve the call card. Doddy says it’s an AI. | **Połączenia za Ciebie** · Doddy dzwoni do firmy z jednym pytaniem od Ciebie, na przykład czy laptop jest już gotowy. · Doddy nie dzwoni, dopóki nie zatwierdzisz karty połączenia. Od razu mówi, że jest AI. | Calls for you, inside the sheet | Not tried on a real call yet, or Needs setup without a server |
| Tasks (`errands`) | **Tasks** · Hand Doddy a bigger job, like comparing flights. Doddy works on it in the background. · Nothing is booked, bought or sent. | **Sprawy** · Zleć Doddy’emu większą sprawę, na przykład porównanie lotów. Doddy zajmuje się nią w tle. · Nic nie zostanie zarezerwowane, kupione ani wysłane. | Tasks | In testing, or Needs setup without a server |
| Cheapest this week (`deals`) | **Cheapest this week** · Doddy reads this week’s shop leaflets and finds the cheapest offers. · Doddy buys nothing. | **Najtaniej w tym tygodniu** · Doddy przegląda gazetki sklepów z tego tygodnia i szuka najtańszych ofert. · Doddy niczego nie kupuje. | Cheapest this week | In testing, or Needs setup without a server |
| Translate (`translator`) | **Translate** · Doddy translates between you and someone who speaks another language. · You start it and you stop it. | **Tłumacz** · Doddy tłumaczy rozmowę między Tobą a kimś, kto mówi w innym języku. · Ty decydujesz, kiedy zaczyna i kiedy kończy. | nothing (it starts from Home's menu) | In testing |

The beta scope (`ReleaseScope.shipping`) lists Talk to Doddy, Notes, Lists, Reminders and calendar, and Messages.
Debug builds list all ten.

## The opening paragraph
English, in a build with voice and reminders: "I'm an AI assistant, not a person. Your notes are kept on this iPhone.
When we talk, your voice and the notes I use go to ElevenLabs to run the conversation. I can add a reminder or a
calendar event and help with a few other apps, but only after you confirm each one on screen. The first time I need
one of your apps, I ask you on screen to allow it. I never send a message myself. Settings › Privacy › What leaves
this iPhone shows everything that is sent, and where."

Polish: "Jestem AI, nie człowiekiem. Twoje notatki są przechowywane na tym iPhonie. Kiedy rozmawiamy, Twój głos i
notatki, z których korzystam, trafiają do ElevenLabs, który obsługuje rozmowę. Mogę dodać przypomnienie albo
wydarzenie w kalendarzu i pomóc w kilku innych aplikacjach, ale każdą rzecz najpierw potwierdzasz na ekranie. Gdy
pierwszy raz potrzebuję którejś z Twoich aplikacji, proszę Cię na ekranie o zgodę. Nigdy nie wysyłam wiadomości. To
zawsze robisz Ty. Ekran Ustawienia › Prywatność › Co opuszcza tego iPhone’a pokazuje wszystko, co jest wysyłane, i
dokąd."

Before this change the paragraph was English in every language, and it pointed to "Settings › What leaves this
iPhone", a path that doesn't exist.

## Examples on the scenes (9 Nov 2026)
Each scene in the carousel (decision `2026-11-09-what-i-can-do-scenes`) shows one thing you could say, under
"Say, for example" / "Powiedz na przykład" ("Type, for example" / "Napisz na przykład" for Messages). The words are in
`WhatICanDo.example`; one short line each, no exclamation marks, never the person's data.

| Feature | English | Polish |
|---|---|---|
| Talk | What’s 15% of 240? | Ile to 15% z 240 zł? |
| Notes | Note: the bike is on level −2. | Zapisz: rower stoi na poziomie −2. |
| Lists | Add milk and bread to the shopping list. | Dopisz mleko i chleb do zakupów. |
| Reminders | Remind me at 8 tomorrow to call Mum. | Przypomnij mi jutro o 8, żeby zadzwonić do mamy. |
| Messages | What’s in this photo? | Co jest na tym zdjęciu? |
| Phone calls | Call me in an hour. | Zadzwoń do mnie za godzinę. |
| Calls for you | Ring the repair shop and ask if my laptop is ready. | Zadzwoń do serwisu i zapytaj, czy laptop jest gotowy. |
| Tasks | Compare flights to Lisbon in May. | Porównaj loty do Lizbony w maju. |
| Cheapest this week | Where’s butter cheapest this week? | Gdzie w tym tygodniu jest najtańsze masło? |
| Translate | Translate, I’m talking to someone in Spanish. | Tłumacz, rozmawiam z kimś po hiszpańsku. |

## Not reviewed yet
The Polish has not been read by a second bilingual reviewer (§3.8). The owner approved the words on 9 Nov 2026 ("narazie ok", OK for now).
