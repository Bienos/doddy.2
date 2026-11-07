# Doddy: przegląd funkcji i gotowości do pierwszej wersji (7 listopada 2026)

Zestawienie zrobione z kodu (nie tylko z dokumentów) na gałęzi `claude/elegant-bell-te82es` = stan po #195 (merge magical-cray + ciche połączenia, ADR-731). Cztery przejścia: aplikacja iPhone (`DoddyApp/`), narzędzia głosowe (`voice-agent/`), serwery (`backend/`, `server/`, `gateway/`, `web/`, `site/`) i pakiet `DoddyCore`. Uzupełnione o `STATUS.md`, `docs/OWNER_QUEUE.md`, `docs/product/V1_SCOPE.md`, `docs/implementation/GO_LIVE_CHECKLIST.md` i `docs/security/SECURITY_REVIEW.md`.

**Legenda stanu** (najważniejsza kolumna w tabelach):
- **urządzenie** – zapisane jako działające na iPhonie właściciela (ostatni taki build: `ce02763`, 11 października; od 20 października nic nie ma zapisanego sprawdzenia na telefonie),
- **CI** – kompiluje się i przechodzi testy w hostowanym jobie na Macu, nigdy nie widziane na telefonie,
- **nie skompilowane** – plik sam o sobie mówi `NOT COMPILED` (pisany bez Xcode) i nie było jeszcze builda,
- **serwer** – wymaga działającego serwera Doddy'ego (Render/Vercel) i jego przełączników,
- **placeholder** – kod oznaczony jako niedokończony lub zablokowany.

---

## 1. Czym jest Doddy w jednym akapicie

Głosowy „kumpel w kieszeni” na iPhone'a: rozmawiasz z nim (ElevenLabs, alternatywnie OpenAI Realtime), a on zapisuje notatki i listy, przypomina, zmienia kalendarz i przypomnienia, ustawia budziki, stopery, liczy, tłumaczy, sprawdza pogodę i Wikipedię, czyta gazetki promocyjne polskich sieci, zleca sobie zadania w tle (research, zakupy), pisze dokumenty, obsługuje Gmaila/Outlooka/Notion/Todoist/Drive, dzwoni za Ciebie (Twilio + ElevenLabs), i to wszystko pod zasadą ASK‑01: **nic nie zmienia bez kliknięcia karty z dokładną treścią**. Pamięć jest lokalna (SQLite), opcjonalna kopia zaszyfrowana na serwerze. Do tego Messages (pisemny czat z Claude), Files, Dynamic Island, widżety, Siri, Share Sheet, Face ID lock.

Skala: ~52 tys. linii Swift w aplikacji, ~53 tys. w DoddyCore (+39 tys. testów), 4 serwisy Node/TS, 102 narzędzia głosowe, 20 migracji SQLite w telefonie, 16 na serwerze wiadomości.

---

## 2. Funkcje aplikacji iPhone (z punktu widzenia użytkownika)

### 2.1 Rdzeń: rozmowa głosowa

| Funkcja | Co można zrobić | Gdzie | Stan | Uwagi |
|---|---|---|---|---|
| Rozmowa głosowa | Tapnij Doddy'ego na Home, mów; on zapisuje, szuka, działa przez 102 narzędzia; karta potwierdzenia przy każdej zmianie | ElevenLabs (domyślnie) / OpenAI Realtime; token z `doddy-voice-token` (Vercel) | urządzenie (ElevenLabs, do 16 X); OpenAI nigdy na telefonie | `VoiceSessionController.swift` ma 4 597 linii. Wymaga Sign in with Apple (Debug: bez logowania) |
| Rozmowa w Dynamic Island | Action Button / Control uruchamia Doddy'ego w wyspie bez otwierania aplikacji | telefon | CI | `TalkInIsland.swift`, ADR-632 |
| Pulsowanie wyspy głosem | Wyspa „oddycha” głośnością jego głosu, także poza aplikacją | telefon | CI (ADR-683) | Nikt nie sprawdził kosztu baterii ani czy iOS animuje 0,6 s beaty |
| Przerwanie telefonem | Krótkie przerwanie wznawia, długie kończy i proponuje kontynuację | telefon | CI (ADR-695/696) | |
| Zerwanie połączenia | Home mówi „Chwila, nie słyszę Cię” + ostatnie słowa jako szkic notatki | telefon | CI (ADR-687, 700) | |
| Tłumacz | Twarzą w twarz lub „słuchaj”; nic nie zapisuje bez Copy/Save w 5 min | telefon + głos | urządzenie (raz się wywalił: „Translator activation failed”) | V1_SCOPE sugeruje Hide; druga osoba nie zgadza się na nagrywanie |
| Czytanie notatki na głos | Głos iOS, offline | telefon | CI | |
| Próba rozmowy (rehearsal) | Doddy gra rozmówcę przed prawdziwym telefonem | OpenAI Realtime bez narzędzi | CI | po polsku |
| Osobowość | Suwaki: głos, tempo, styl | telefon | CI | |
| Transkrypt | Jeden tap z paska na Home | telefon | CI (ADR-727) | |

### 2.2 Pamięć (lokalna, SQLite/GRDB)

| Funkcja | Co można zrobić | Stan | Uwagi |
|---|---|---|---|
| Notatki | Zapis, edycja, poprawki z historią (rawText nigdy nie ginie), pin, tagi, prywatne (za Face ID) | urządzenie (przez głos) | rdzeń produktu, jedyna rzecz z dowodem działania na telefonie |
| Szukanie | Leksykalne bez diakrytyków + „po znaczeniu” (embeddingi on‑device) | zbudowane | progi „po znaczeniu” to zgadywanka, V1_SCOPE: Hide |
| Zdjęcia w notatce | Picker/aparat Doddy'ego, odczyt tekstu i kodów kreskowych na telefonie | CI | |
| Notatki głosowe | Nagranie do 5 min, transkrypcja on‑device, propozycja to‑do | zbudowane, nigdy nie nagrane | drugi tor mikrofonu; ADR-695 ma to rozwiązać |
| Listy | Listy, szablony, ilości, lista „w domu”, skaner kodów (Open Food Facts), karta do udostępnienia | zbudowane / CI | |
| Tryb zakupów | Lista na Lock Screen z odhaczaniem (Live Activity) | zbudowane, nigdy nie uruchomione | ryzyko App Review (`LiveActivityIntent`) |
| Listy współdzielone | iCloud/CloudKit | CI, wyłączone w runtime | V1_SCOPE: Cut (płatny team, kontener, schema Production) |
| Przypomnienia o notatce | Czas lub miejsce, „dzwoń jak budzik” (AlarmKit, iOS 26) | zbudowane | miejsce = lokalizacja = V1_SCOPE Hide |
| Import | Google Keep, pliki tekstowe, z przeglądem i cofnięciem | zbudowane, nigdy na prawdziwym Takeout | |
| Backup | Zaszyfrowany plik z hasłem (AES‑GCM), restore nie nadpisuje | zbudowane, nigdy wykonany | |
| Export / usuń wszystko | JSON, tekst, Markdown; delete‑all czyści też serwer, zadania, nagrania | CI | |
| Co Doddy zrobił + Undo | Dziennik zmian, Undo 24 h | zbudowane | wymóg konstytucji (receipts) |
| Co Doddy wie | Nauczone fakty i rutyny, edycja/usuwanie/export | zbudowane, ekrany nigdy nie uruchomione | M6: po becie, żeby nie zakłócać wyników |
| Porządki (Tidy up) | Tygodniowa propozycja usunięcia duplikatów | zbudowane | |
| Spotlight | Notatki w wyszukiwarce iPhone'a, domyślnie off | zbudowane | |
| DODDY Capture (nagrania) | Nagrywanie spotkań z przycisku/Siri/Action Button/wyspy, transkrypcja on‑device, biblioteka | **nie skompilowane** (`RecordingCoordinator`, `DoddyCaptureLiveActivity`) | brak AI do streszczeń (`UnavailableRecordingIntelligence`) |

### 2.3 Kalendarz, przypomnienia, dzień

| Funkcja | Co można zrobić | Stan |
|---|---|---|
| Apple Kalendarz / Przypomnienia / Kontakty | Czytanie i zmiany głosem, każda zmiana za tapem; powtarzanie; „wolne okna”; przenoszenie przypomnień; Undo | zbudowane |
| Karta „Dziś” | Reszta dnia z Kalendarza i Przypomnień na Home | CI |
| Budziki i minutniki | AlarmKit (iOS 26+): dzwonią w Silent/Focus, odliczanie na Lock Screen; na starszym iOS zwykłe powiadomienie | CI, nigdy nie zadzwoniły |
| Stoper | Odlicza w górę, Lock Screen + wyspa, 3 narzędzia głosowe | CI |
| Focus timer | Odliczanie + Live Activity; filtr Focus iOS | zbudowane |
| Poranny check‑in / wieczorne podsumowanie / tygodniowy przegląd / plan tygodnia | Powiadomienia lokalne, cisza 22–07 | zbudowane, nigdy nie zadzwoniły |
| Urodziny | Roczne powiadomienia z Kontaktów | zbudowane |
| Kiedy wyjść (Leave by) | Czas dojazdu z Apple Maps + powiadomienie | CI (lokalizacja) |
| Parking | Jedno miejsce, widżet, quick action | zbudowane |
| Budżet powiadomień | Pilnuje limitu 64 pending iOS | częściowo (własne harmonogramy go nie pytają) |

### 2.4 Messages, Files, Web

| Funkcja | Co można zrobić | Gdzie | Stan |
|---|---|---|---|
| Messages | Pisemny czat z Doddym (Claude Haiku), dyktowanie mikrofonem, zdjęcie z pytaniem (zmniejszone, nie zapisywane), karty plików/zadań/rozmów telefonicznych | `doddy-messaging` `POST /v1/assistant/ask`, `ASSISTANT_ENABLED` | serwer; dyktowanie wywalało appkę (naprawione 29 X) |
| Kopia wątku na serwerze | Zaszyfrowana, bez zdjęć, tylko do odczytu w Doddy Web | `doddy` `PUT /v1/web/messages` | `ServerThreadSync` **nie skompilowane**; polityka prywatności o tym nie mówi |
| Files | Pliki zrobione przez Claude na serwerze (deck, Word, Excel, PDF; tydzień), nagrania, recapy rozmów; Quick Look | `GET /v1/web/documents` | **nie skompilowane** (`FilesView`, `CallRecapSection`) |
| Doddy Web | Przeglądarka: logowanie kodem z telefonu, Home, Messages, Documents, Apps, Activity, Logbook, Memory, Chat (Claude z cytatami), Settings/sesje | `backend/` + `web/` (React), https://doddy-yaci.onrender.com | serwer; Logbook/Memory/Messages czekają na flagi `IPHONE_SENDS_*=false` |
| Pamięć na serwerze | Dwa przełączniki (notatki, rozmowy), ekran zgody, „usuń wszystko na serwerze” | `backend/` `/v1/web/memory/*`, klucz `DODDY_MEMORY_KEY` | CI (SwiftUI), reguły testowane na Linuksie |

### 2.5 Zakupy i zadania w tle

| Funkcja | Co można zrobić | Gdzie | Stan |
|---|---|---|---|
| Gazetki („Najtaniej w tym tygodniu”) | Szuka w gazetkach 16 sieci (Biedronka, Lidl, Dino, Rossmann, Aldi, Żabka, Action, CCC, Deichmann, Delikatesy, Komfort, Leclerc, Lewiatan, Maxi Zoo, Natura, zooplus); cena za sztukę/kg, realna obniżka vs 30‑dniowe minimum, flagi (apka/karta/kaucja), koszyk podzielony na sklepy, „Z mojej listy”, „Moje sklepy” (Apple Maps), „Przypomnij w dniu”, PDF raport, linki „szukaj dalej” (Allegro/Ceneo), linki partnerskie (żadnego programu nie podpisano) | `doddy-messaging` `POST /v1/deals/search`, `DEALS_ENABLED=1`, Claude Haiku czyta strony obrazkowe | serwer, live od 25 X; **żadne prawdziwe wyszukanie nie przeszło na serwerze** (koszt ~0,21–0,40 zł szacowany) |
| Zadania (errands) | „Znajdź mi X” / research w tle; Opus z web_search/web_fetch; wynik jako karta w Tasks; dla zakupów tylko ceny potwierdzone na stronie sklepu (Serper + strona) | `doddy-messaging` `/v1/errands`, `ERRANDS_ENABLED=1`, limity 10/os., 30/serwer dziennie | serwer, live od 27 X; wynik czeka w Tasks bo push dopiero co włączony |
| Pilnowanie ceny | Serwer sprawdza stronę sklepu ~4×/dzień przez 30 dni, jeden push gdy cena ≤ próg; max 5 | `WATCHES_ENABLED` (domyślnie 0) | serwer, wyłączone |
| Checkout (etap 3) | Reguły bezpieczeństwa w `Checkout.swift`, **nic nie można kupić** | – | design + testy, brak dostawcy, prawnika, ekranu |
| BLIK | Karta przelewu na telefon, wysyłasz w swoim banku; Doddy nigdy nie wysyła pieniędzy | telefon | CI |

### 2.6 Telefon, SMS, połączenia

| Funkcja | Co można zrobić | Gdzie | Stan |
|---|---|---|---|
| Powiadomienia push + SMS | Weryfikacja numeru (Twilio Verify), testowy update, usuwanie danych | `doddy-messaging`, APNs od 3 XI | **push nigdy nie sprawdzony end‑to‑end** |
| Pisz z Doddym (SMS) | SMS z własnego zweryfikowanego numeru → odpowiedź Claude, ≤600 znaków, bez narzędzi | Twilio webhook `/webhooks/twilio/sms` | serwer; webhook i numer SMS nie ustawione |
| Zadzwoń do Doddy'ego / niech zadzwoni | Numer, PIN, kopia pamięci (zaszyfrowana, bez prywatnych), notatki z rozmów | ElevenLabs agent „Doddy (phone)”, Twilio | **żadne połączenie nigdy nie odbyło się**; numer `+3726360658` ma tylko Voice |
| Rozmowy, które Doddy wykonuje za Ciebie | Brief → zatwierdzenie → Doddy dzwoni (agent bez żadnych narzędzi) → przejęcie → recap + koszt; „ciche” (ADR-730): mały znacznik na Home, recap w Files, transkrypt tylko dla właściciela | `doddy-messaging` `/v1/call-cases/*`, `TASK_CALLS_KILL_SWITCH`, `CALL_TRANSCRIPT_PHONE_NUMBERS` | `ActiveCallBadge` **nie skompilowane**; nigdy nie zadzwoniono |

### 2.7 Sport, zdrowie, dom

| Funkcja | Co można zrobić | Stan |
|---|---|---|
| Apple Health | Ostatnie 7 dni (treningi, sen, tętno), tylko odczyt; „zapytaj o ten tydzień” do Messages lub głosem po osobnej zgodzie | CI; brak w buildzie free‑team |
| Plan treningowy | Bieganie/siła z silnika reguł po pytaniach bezpieczeństwa; żaden model nie pisze planu | CI |
| Dziennik treningów | Serie, ciężar, powtórzenia, samopoczucie, przegląd tygodnia | CI |
| Kroki | Motion & Fitness, `read_steps` | zbudowane |
| HomeKit | Światła, gniazdka, wentylatory, sceny; bez zamków | **nie skompilowane**, wymaga entitlementu płatnego teamu |

### 2.8 Konta online (przez serwer i Composio)

| Usługa | Narzędzia | Stan |
|---|---|---|
| Gmail | czytanie, szkic, odpowiedź, wysyłka, forward, archiwum, kosz (9) | zbudowane, **nigdy na prawdziwym koncie**; scope'y Gmaila wymagają weryfikacji Google |
| Outlook | poczta (8) + kalendarz i zaproszenia (6) | jw. |
| Google Calendar | odczyt, dodanie, zmiana, usunięcie, odpowiedź na zaproszenie | jw. |
| Google Drive | szukanie plików, nowy Doc | jw. |
| Notion | szukanie, czytanie, nowa strona, dopisanie, kosz | jw. |
| Todoist | lista, dodaj, zrób, przenieś, zmień nazwę | jw. |
| Web search / news / miejsca | Monid | **urządzenie** (jedyna funkcja online z dowodem, 11–14 X) |
| ask_claude / make_document | Claude Sonnet na serwerze: streszczenia, przepisanie, plany, dokumenty (pptx/docx/xlsx/pdf przez Skills) | serwer |
| Parcele InPost | Śledzenie numerem, domyślnie off | CI, nie widziane na urządzeniu |
| Faktury inFakt / KSeF | Klucz w Keychain, karta faktury, reguły KSeF, dane nabywcy z VAT/CEIDG | **placeholder** (`createVerified = false`, nic nie jest wysyłane) |
| Following (śledzenie tematów) | Historie wydawców za tematami, bez AI; „śledź CPK” głosem | serwer `POST /v1/news/feed` |
| Codzienne newsy | Digest pisany przez Haiku (GNews + RSS), push lub SMS | serwer; V1_SCOPE: Cut (GNews free nie do komercji) |

### 2.9 Powłoka, prywatność, wejścia

| Funkcja | Stan | Uwagi |
|---|---|---|
| Welcome „Jeden poranek w Warszawie” (5 rozdziałów) + arkusz logowania | CI | sceneria oznaczona PLACEHOLDER; Face ID/Google/email to tylko UI, prawdziwy jest tylko Apple |
| Akceptacja regulaminu, wprowadzenie, „Co umiem”, scena otwarcia | CI | |
| Face ID lock, prywatne notatki, cover w app switcherze | CI (ADR-723) | nigdy na urządzeniu |
| „Co opuszcza ten iPhone” | CI (ADR-721) | budowane z realnych przepływów |
| Ustawienia: 4 grupy, 14 wierszy | CI | pola developerskie w Debug |
| Sposoby otwierania: Back Tap (z testem), Action Button, Control Center, Siri | Back Tap: urządzenie (9 X) | |
| Siri / App Shortcuts (10/10): Talk, Stop listening, Record, Save, New note, Find, Ask what I saved, Add to list, Read list, Tick | zbudowane | |
| Widżety: Pinned notes, Next reminder, Parking, List (konfigurowalny, tick), Talk, New note, Doddy resting (StandBy) + 4 Controls | CI | tick z widżetu z zimnego startu nietestowany |
| Live Activities (6): rozmowa, tryb zakupów, rozmowa‑za‑Ciebie, narzędzia (focus/readAloud/stopwatch), nagrywanie, budzik | CI / Capture nie skompilowane | |
| Share Sheet „Zapisz w Doddy” | CI | tylko odkłada do App Group |
| Quick actions ikony | zbudowane | |
| Języki: PL domyślnie, EN + 8 maszynowych (de, es, fr, hr, it, ja, pt‑BR, zh‑Hans) | CI | żaden native nie czytał; V1_SCOPE: schować 8 |
| iPad (sidebar), Watch, Mac | iPad CI; Watch/Mac **wstrzymane** (ADR-572) | V1_SCOPE: iPhone‑only |

---

## 3. Narzędzia głosowe: 102 (nie 103, jak mówi README)

Źródło prawdy: `voice-agent/tools.json`. 98 „client tools” (wykonuje aplikacja), 4 „web” (ElevenLabs woła open‑meteo i Wikipedię sam). Poziomy zgody: **R** = od razu (tylko publiczne lookupy), **Y** = tak powiedziane lub tap, **T** = wyłącznie tap na karcie z dokładną treścią.

| Grupa | Narzędzia | Zgoda | Gdzie |
|---|---|---|---|
| Pamięć | search_memories, save_memory, remind_me_about_note | Y/T/T | telefon |
| Listy | add_to_list, add_ingredients, read_list, check_off, remove_from_list, create_list | T (read: Y) | telefon |
| Kalendarz/Przypomnienia Apple | read_calendar, find_free_time, create/change/delete_calendar_event(s), create/change/delete_reminder, move_reminders, undo_last, remind_when_to_leave | Y odczyt, T zmiany | telefon |
| Minutniki/budziki/stoper | set_timer, set_alarm, list_alarms, cancel_alarm, start/stop/check_stopwatch | T / Y | telefon |
| Kontakty/wiadomości/pieniądze | lookup_contact, upcoming_birthdays, draft_message, draft_blik_transfer | Y/Y/T/T | telefon (przekazanie do innej apki) |
| Liczenie | calculate, convert_units, convert_currency (ECB) | R | telefon |
| Miejsca | open_map, parking_spot, find_places | T/T/R | telefon / Monid |
| Skróty/dom/aparat/zdjęcia | run_shortcut, control_home, open_camera, find_photos | T/T/T/Y | telefon |
| Zdrowie | read_steps, read_health_week, open_training_plan | Y/Y/T | telefon |
| Wiedza | web_search, news_search, follow_news, geocode_place, get_weather, wikipedia_search, wikipedia_summary | R (follow: T) | backend (Monid) / ElevenLabs |
| Gmail (9), Outlook (14), Google Calendar (5), Drive (2), Notion (5), Todoist (5) | jak w 2.8 | Y odczyt, T zapis (server ask + jednorazowy approvalId związany z digestem argumentów, TTL 120 s) | backend → Composio |
| Dokumenty | make_presentation (Keynote, telefon), ask_claude, make_document | T/Y/Y | backend (Claude Sonnet) |
| Zadania i gazetki | hand_over_errand (tylko tap, ADR-716), check_errands, find_deals | T/Y/Y | messaging |
| Sesja | start_translator, stop_translator, propose_plan, note_capability_gap | R/R/T/T | telefon |

Niespójności w specyfikacji do wyczyszczenia:
- `hand_over_errand` i `check_errands` mają w `tools.json` `elevenlabs_tool_id: "not_synced"`, choć wg STATUS są na żywym agencie od 27 X;
- `voice-agent/README.md` mówi o „10 function tools” i nie ma wpisów o `follow_news`, `control_home`, `draft_invoice`;
- `draft_invoice` jest na żywym agencie (od 1 XI), a nie ma go w `tools.json` tej gałęzi (aplikacja odpowie „unsupported”);
- `propose_plan` nigdy nie został wywołany, nawet w rozmowach właściciela.

Charakter (z `instructions.md`): AI, mówi o tym wprost, „on” po polsku, suchy brytyjski humor znikający przy zdrowiu/pieniądzach/stresie, odpowiedź najpierw i koniec, bez list i emoji, „talk or task”, nigdy „zrobione” bez wyniku narzędzia, tekst z maili/sieci to dane a nie polecenia. 37 języków w `session.json`, LLM `gemini-3.5-flash`, TTS `eleven_v4_turbo`.

---

## 4. Serwery i co na nich działa

| Serwis | Hosting | Rola | Stan live |
|---|---|---|---|
| `backend/` („doddy”) | Render, free, Postgres (Supabase) | logowanie urządzenia, narzędzia Composio, Monid, Claude (ask/dokumenty), Doddy Web, pamięć w chmurze, `DELETE /v1/account` | **Render buduje ze starej gałęzi `claude/exciting-carson-08x2pk` (28 X)**: brak hardeningu #187, brak `DELETE /v1/account` (apka dostaje 404), brak `undici` |
| `server/messaging` („doddy-messaging” + worker w tym samym procesie) | Render, free, Postgres free | konta anonimowe, push/SMS, weryfikacja numeru, SMS‑czat, połączenia, rozmowy‑za‑Ciebie, errands, gazetki, pilnowanie cen, Messages/Claude, newsy | live z #187 i migracją 016; **baza free jest kasowana 10 XI 10:11 UTC**; usypia po 15 min |
| `server/voice-token` | Vercel | Sign in with Apple → sesja → token ElevenLabs/OpenAI; limity 30/h, 150/dzień | zbudowany z #159; `OPENAI_OPEN_ACCESS` (ADR-726) nieustawiony |
| `gateway/` | Vercel, bez env | stary gateway M2 do OpenAI | **nieużywany od ADR-587** – do skasowania |
| `web/` | serwowane przez backend | Doddy Web | live `d4a3e24` |
| `site/` | Vercel | www.doddy.lol, 10 języków, waitlist, blog, drafty Privacy/Terms, admin | live; konto Vercel pokazuje „Account is blocked” na PR‑ach |

Modele: errands `claude-opus-5-5`, zakupy/gazetki/Messages/news `claude-haiku-5-5` (Sonnet dla premium), ask/dokumenty `claude-sonnet-5-5`, chat web `claude-haiku-5-5`, agent głosowy `gemini-3.5-flash`. Limity są w kodzie (dzienne per użytkownik i per serwer, patrz `backend/src/config.ts` i `server/messaging/src/config.ts`), **ale żaden klucz dostawcy nie ma limitu wydatków w panelu** (Anthropic, OpenAI, Monid).

Testy (liczby z kodu, nie uruchomione w tej sesji): DoddyCore 2 211 + Persistence 190 + DesignTokens 9; app unit ~134, UI ~62; backend ~473; messaging ~702 (wymaga Postgresa); voice-token ~49; gateway ~76; web ~135; site ~24. Ostatni zapisany pełny zielony run hostowanego CI to #173/#175 (3 XI); STATUS mówi, że merge magical‑cray (#195) **nie był kompilowany w sesji, która go robiła** (ręczne rozwiązanie konfliktów w `VoiceSessionController`, `AskFirst`, `ToolCatalog`, `DataFlow`), więc build z tej gałęzi jest pierwszym sprawdzeniem.

---

## 5. Co trzeba poprawić przed wypuszczeniem (uporządkowane)

### 5.1 Blokery operacyjne (najpierw, większość tylko właściciel)
1. **10 XI, 10:11 UTC – baza `doddy-messaging-db` zostanie skasowana.** Upgrade na płatny plan. Bez tego znikają konta, numery, zadania, rozmowy, pamięć na rozmowy, watchy, newsy.
2. **Render `doddy` → Branch na domyślną**, deploy. Bez tego hardening (ADR-702–725), kasowanie konta i poprawki web nie są live.
3. **Zbudować aplikację z domyślnej gałęzi i uruchomić na telefonie.** Od 20 X nic nie ma zapisanego sprawdzenia na urządzeniu; sześć plików w tej gałęzi (HomeKit, Capture, Files, CallRecap, ActiveCallBadge, ServerThreadSync) ma w nagłówku „NOT COMPILED”. Zapisywać commit zainstalowanego builda.
4. **Limity wydatków w panelach:** Anthropic (errands na Opusie!), OpenAI, Monid, Twilio alerty, ElevenLabs.
5. **Agent ElevenLabs: authentication OFF**, id w publicznym repo, 1 000 rozmów/dzień – każdy może rozmawiać na Twój koszt. Plan z OWNER_QUEUE #4: drugi agent dla Debug, auth on dla głównego, retencja nagrań (dziś: na zawsze).
6. **Ochrona domyślnej gałęzi** (PR + wymagany check `core`).
7. **Zmiana hasła Supabase** (jest w logu sesji z 19 X). Nie rotować `DODDY_SESSION_SIGNING_KEY` (wyprowadza user id).
8. Xcode Cloud → TestFlight (ADR-697, 15 min one‑time), Push i Sign in with Apple na App ID, klucz APNs (już jest), test pusha end‑to‑end.
9. Vercel: odblokować konto, Firewall rate‑limity na `/api/voice-auth` i waitlist.

### 5.2 Decyzje produktowe, bez których nie da się „zamknąć” v1
- **Zakres v1 (`V1_SCOPE.md` od 18 X nadal nieoznaczony, ADR-520 pusty).** Od tamtej pory doszły: gazetki, errands, call cases, Messages, Files, Web, Health, Capture, Following, HomeKit, faktury, parcele. Propozycja poniżej (§6).
- **Jedna obietnica.** Dziś trzy różne (PRD, tagline, hero strony). Hero „Say it once. Tap once. Done.” opiera się na `propose_plan`, które nigdy nie zostało wywołane.
- **Jeden dostawca głosu w becie** (ElevenLabs ma dowody; OpenAI „testing only”). Schować picker.
- **Brak mechanizmu feature‑flag w aplikacji** (tylko `#if DEBUG` i przełączniki w Settings). Żeby „schować” funkcję, trzeba dodać jedną listę w DoddyCore, która usuwa wejścia (wiersz Settings, karta Home, widżet, narzędzie głosowe). To jest pierwszy krok B2 checklisty.
- **Języki:** 8 tłumaczeń maszynowych nikt nie czytał → schować w v1 lub jedna lektura native per język.
- **Bundle ID** to placeholder `com.bienos.doddy2.dev`, wersja 0.0.1 – decyzja przed pierwszym rekordem w App Store Connect.
- iPhone‑only (iPad trudno potem wycofać), Watch i Mac poza v1.

### 5.3 Prawne i zgodność (App Review, RODO, AI Act)
- Privacy i Terms to drafty (noindex, baner „Draft”), bez prawnika, bez nazwy administratora; nie mówią o zdjęciu z pytaniem, kopii Messages na serwerze, nagraniach rozmów.
- Brak adresu supportu i „Zgłoś problem” w Settings; waitlist obiecuje kasowanie bez adresu.
- GA4 na stronie bez zgody (EU), Google Fonts przed zgodą, brak retencji waitlisty.
- Notatki dla App Review: mikrofon, audio w tle, pełny dostęp do Kalendarza, przyciski w wyspie (`LiveActivityIntent`), logowanie; wiek; App Privacy.
- Nieużywany `remote-notification` background mode i `CKSharingSupported` w Info.plist; brak privacy manifestów dla widżetów i Share extension.
- Nagrywanie rozmów telefonicznych (notice `CALL_RECORDING_NOTICE`), nagrywanie drugiej osoby w tłumaczu, affiliate (Tradedoubler/Awin), gazetki (pytania z ADR-664) – wszystko czeka na prawnika.

### 5.4 Jakość kodu i architektura (do „optymalizacji”)
| Problem | Gdzie | Propozycja |
|---|---|---|
| `VoiceSessionController.swift` 4 597 linii = dispatcher 102 narzędzi + sesja + audio + karty | `DoddyApp/Features/Voice/` | Wyciągnąć dispatcher per domena (Calendar, Lists, Cloud, Shopping…) do osobnych handlerów z jednym protokołem; sesja/audio osobno. To jest też plik, w którym każdy merge robi konflikty |
| `VoiceView.swift` 2 033, `HomeView.swift` 1 093, `MessagesView.swift` 1 013, `SettingsScreens.swift` 830 | SwiftUI | Podział na podwidoki; łatwiejsze testy UI |
| `MotionEngine.swift` 2 216 linii, jedna klasa z kilkunastoma typami zagnieżdżonymi | DoddyCore/Motion | Podział na Event/Gesture/Reaction/… |
| 186 plików płasko w `Sources/DoddyCore` (z 278) | DoddyCore | Przenieść do folderów domen (Memory, Voice, Tools, Shopping, Reminders…) – nawigacja ważniejsza niż cięcie plików |
| Backend bez migracji (`CREATE TABLE IF NOT EXISTS` w `store.ts`, 20 tabel) | `backend/src/store.ts` | Migracje numerowane jak w messaging, zanim będzie więcej użytkowników |
| `gateway/` martwy od ADR-587 | repo + Vercel | Usunąć kod, projekt Vercel i wpisy w `secrets/manifest.json` |
| Dokumentacja agenta rozjechana z kodem (README „10 tools”, `not_synced`, brak `draft_invoice` w tools.json) | `voice-agent/` | Jedno źródło prawdy + skrypt porównujący live agenta ze spec (`voice_agent_spec.py check` już jest, dodać `diff-live`) |
| Prompt agenta ~6,4 k tokenów za duży (gałąź `new-session-gz7pnp`) | `instructions.md` | Przyciąć; mniejsze opóźnienie i koszt |
| Sesje głosowe startujące podwójnie / „ghost” 30 s | VoiceSessionStarts | Wymaga logu z telefonu po buildzie z ADR-496 |
| `zod` 3 w backendzie (advisory) | `backend/` | upgrade do zod 4 w osobnym PR |
| Niespójne numery ADR między gałęziami, 40+ nieusuniętych gałęzi, 10+ PR do zamknięcia (#92, #104, #71, #77, #63, #116, #124, Studio…) | GitHub | Sprzątanie: zamknąć wymienione w STATUS „Not merged yet” |
| Polskie stringi inline jako słowniki w `ActivityText`/`ActionStatusText` zamiast katalogu | DoddyCore | Przenieść do `l10n/pl.json` |
| Hostowane CI ~50 min (Mac) | `.github/workflows/ios.yml` | #166 (grupy równoległe) do zdecydowania |

### 5.5 Funkcje, które „są”, ale nikt ich nie widział działających
Warto przejść raz na telefonie z listą, zanim pójdzie do testerów (z OWNER_QUEUE #17): Face ID lock + Back Tap + Action Button + Siri + `doddy://recordings`, powiadomienie z przypomnienia, poranny check‑in z prywatną notatką, zlecenie zadania głosem, karta BLIK z wyłączonymi Kontaktami, throttle logowania Apple, pulsowanie wyspy i bateria, dyktowanie w Messages, zdjęcie z pytaniem, pierwsze prawdziwe wyszukanie gazetki, push z errand, Quick Look w Files, OpenAI + Sign in with Apple, VoiceOver i największa czcionka.

---

## 6. Propozycja: co wchodzi do pierwszej wersji live (do zatwierdzenia)

Kryterium jak w V1_SCOPE: ma dowód na telefonie albo działa bez serwera i da się sprawdzić przed betą; wszystko, co „nigdy na urządzeniu i wymaga serwera/dostawcy”, idzie do Hide.

**Ship (beta TestFlight):**
- rozmowa głosowa (ElevenLabs, auth on, Sign in with Apple), wyspa, Back Tap/Action Button/Siri, transkrypt;
- notatki, poprawki, prywatne + Face ID, szukanie leksykalne, zdjęcie w notatce, listy, przypomnienia o notatce (czas), Undo/„Co Doddy zrobił”, backup/export/usuń, Share Sheet, quick actions, widżety read‑only + New note;
- Apple Kalendarz/Przypomnienia/Kontakty głosem, karta Dziś, minutniki/budziki/stoper (iOS 26) z fallbackiem, liczenie/konwersje, pogoda/Wikipedia;
- Messages (Claude Haiku) **jeśli** polityka prywatności to opisze i messaging przejdzie na płatny plan; inaczej Hide;
- poranny check‑in off by default.

**Hide (kod zostaje, brak wejścia i narzędzia na agencie):** gazetki, errands, pilnowanie cen, call cases, SMS/telefon, Following/newsy, konta online (Gmail/Outlook/Notion/Todoist/Drive), make_document/ask_claude, Files, Doddy Web, pamięć na serwerze, Health/plan treningowy, Capture, HomeKit, faktury, parcele, tłumacz, BLIK, propose_plan, tryb zakupów na Lock Screen, przypomnienia o miejscu, Leave by, parking, listy współdzielone, „Co Doddy wie”, szukanie po znaczeniu, import, notatki głosowe, OpenAI picker, 8 języków.

To redukuje v1 do: telefon + `doddy-voice-token` (+ Redis) + strona. Znika zależność od Render, Composio, Monid, Twilio, GNews w becie – i większość pytań App Review.

**Kolejność prac (propozycja):**
1. Tydzień 1: blokery §5.1 (baza, deploy, limity, auth agenta), build na telefonie, zapis commit.
2. Tydzień 1–2: flaga „Hide” w DoddyCore (B2), zdjęcie narzędzi ukrytych z agenta, picker głosu off, 8 języków off, pola dev poza Release, Info.plist (background mode, manifesty).
3. Tydzień 2: pass na urządzeniu wg §5.5 tylko dla Ship; naprawy.
4. Równolegle: prawnik (Privacy/Terms, AI disclosure), adres supportu, strona bez GA przed zgodą, hero strony zgodne z betą.
5. Xcode Cloud → TestFlight → 20–24 testerów z waitlisty, 2 tygodnie, progi z `VALIDATION_AND_METRICS.md`, pomiar realnego kosztu/minutę.
6. Po becie: decyzja o paywallu, odkrywanie Hide po jednej funkcji (najpierw gazetki/errands – mają serwer i testy), refaktor `VoiceSessionController` przed kolejną falą narzędzi.
