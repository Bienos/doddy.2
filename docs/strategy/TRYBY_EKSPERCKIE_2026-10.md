# Tryby eksperckie: jak research z 24 paź pasuje do repo i do innych sesji

Wersja robocza do decyzji właściciela, 24 paź 2026. **Nic z tego nie jest zbudowane.** Research właściciela: `docs/research/2026-10-24/research_expert_modes_PL.md` (przepisany z `DODDY_Research_PL.pdf`, który leży obok). Ten plik porównuje go z tym, co już jest w repo, z decyzjami właściciela (ADR) i z pracą innych sesji z 24 paź. Oznaczenia: **[V]** sprawdzone dziś na stronie źródłowej, **[S]** z innej sesji lub dokumentu w repo, **[I]** wniosek własny. Nie jest to porada prawna ani medyczna.

Zasada pierwszeństwa: tam, gdzie PDF mówi co innego niż decyzja właściciela zapisana w ADR, obowiązuje ADR, dopóki właściciel go nie zmieni.

## 1. Najkrócej

1. **Architektura z PDF w większości już jest w repo jako zasady.** Model tylko proponuje, kod sprawdza, narzędzia wykonują; zapis zewnętrzny po zgodzie na dokładną treść; `unknownOutcome` nigdy nie jest sukcesem; treść maili i stron to dane, nie polecenia (konstytucja, `docs/architecture/TOOLS_AND_ACTIONS.md`, ASK-01). PDF jest z tym zgodny i nie wymaga nowej platformy (sam to mówi).
2. **Spora część rankingu P0 do P2 jest już zbudowana** (przetestowana w CI lub na danych testowych, nigdy na telefonie): listy głosem bez duplikatów, Kalendarz i Przypomnienia przez EventKit, odczyt tekstu ze zdjęcia na iPhonie, **odczyt Gmaila i szkice przez Composio** (ADR-096 do 103), kalkulatory, zakupy etap 1 (gazetki, oferty, koszyk, przejście do sklepu w Safari). Szczegóły w sekcji 2.
3. **Trzy kolizje z decyzjami właściciela** (sekcja 3): liczenie kalorii (ADR-620: domyślnie bez liczb), czytanie gazetek (ADR-609: na żądanie z 4 sieci), kolejność HealthKit (ADR-620: tryb sportowy zaczyna się od Apple Health). Do tego PDF powołuje się na nieaktualną propozycję Gmaila (ADR-120).
4. **Inne sesje dodają rzeczy, których PDF nie ma** (sekcja 4), najważniejsza: **API Stravy od 1 cze 2026 zakazuje użycia jej danych w jakiejkolwiek aplikacji AI** (sesja „Sport mode”, ADR-620, niescalone).
5. **Nowe w PDF i nigdzie w repo:** faktury (Fakturownia/inFakt/KSeF), przepływ jadłospis → lista zakupów, wspólny kształt „pakietu umiejętności” i kontraktu wyniku, ekran „Dlaczego tak?”, 15 testów akceptacyjnych, karty ćwiczeń, inne tryby (dokumenty, podróże, nauka, finanse, urzędy).

## 2. Co z PDF już jest w repo

| PDF | Stan w repo | Gdzie |
|---|---|---|
| L1 Smart Shopping List, „Dodaj mleko dwa razy” bez duplikatu (test 6) | **Zbudowane:** `add_to_list` i 4 inne narzędzia list na żywym agencie; duplikat otwartej pozycji nie jest dodawany; cofnięcie 8 s; receipt na ekranie | `docs/implementation/LISTS_STATUS.md` (ADR-216) |
| „Brak internetu → listy lokalne działają” (test 13) | **Zbudowane:** listy nigdy nie opuszczają iPhone'a | jw. |
| Stan, id i cofnięcie każdej zmiany listy (4.3) | **Zbudowane:** Undo, receipt, dziennik „Co Doddy zrobił” | jw., `ActivityLog.swift` |
| Kalendarz/Reminders przez EventKit (P1) | **Zbudowane** (CI, nie na telefonie): odczyt, dodanie, przesunięcie, usunięcie po stuknięciu; Google Calendar działa przez EventKit, jeśli jest dodany w iOS | `docs/implementation/APPLE_CONNECTIONS.md` (ADR-566 do 569) |
| Skaner paragonów, etykiet i kodów (P0) | **Częściowo:** tekst ze zdjęcia czytany na iPhonie (Vision, wybór zdjęcia przez Apple); **brak** kodów kreskowych i paragonów jako danych | jw. |
| Gmail P2: najpierw odczyt i wyszukiwanie; szkice, nigdy auto-wysyłka | **Zbudowane, testowane tylko na danych testowych:** Połączone aplikacje przez Composio (ADR-096 do 103): `check_email` (`gmail.readonly`; nadawca, temat, czas, 140 znaków podglądu) i `draft_email` (szkic po zgodzie związanej z SHA-256 dokładnych argumentów, `outcome_unknown` bez ponawiania); od ADR-485 (18 paź) także wysyłka, odpowiedź, przekazanie i kosz, każde dopiero po karcie zgody (ASK-01). To spełnia „osobną zgodę na wysłanie” z PDF; każde narzędzie ma własny przełącznik, domyślnie wyłączony; treść maila to informacja, nie polecenie. Strażnik repo dopuszcza też szkic w Outlooku i Todoist. Na iPhonie dodatkowo szkic maila lub SMS-a otwierany w Mail/Wiadomościach | `DECISIONS.md` ADR-096 do 103 i 485, `backend/src/tools/catalog.ts`, `voice-agent/tools.json` |
| Obliczenia deterministyczne (7.3 pkt 5) | **Częściowo:** `calculate`, `convert_units`, `convert_currency` (ADR-575); sumy koszyka liczy kod (`BasketSolver`, ADR-610); brak kalkulatorów kcal, makro, VAT | `DECISIONS.md` ADR-575, ADR-610 |
| L2 ceny tylko z prawdziwego źródła, z datą | **Zbudowane** (CI, nie na żywo): oferta bez narzędzia uruchomionego przez kod nie dostaje karty; cena ze strony sklepu tylko ze strukturalnych danych; etykieta `listing` / `shop_page` i godzina | ADR-607, ADR-608 |
| L3 checkout tylko z partnerem; fallback = link do sklepu | **Zbudowane:** „Kup w …” otwiera stronę sklepu w Safari, zapis „Otworzono stronę”, nigdy „kupiono”; płatność w aplikacji dopiero w etapie 3 po opinii prawnika | ADR-610, `docs/research/2026-10-24/research_shopping_payments.md` |
| Router intencji, wiele trybów jednego agenta | **Częściowo:** tryby Rozmowa i Zadanie (ADR-571), tryb tłumacza z własnymi regułami (ADR-574), sprawy w tle na serwerze (ADR-570) | `docs/product/`, `DECISIONS.md` |
| Proposal → zgoda → wykonanie → receipt; `unknown` → sprawdź stan, nie ponawiaj (test 9, 15) | **Zasada w kodzie** dla istniejących narzędzi (operationId, digest, receipt) | `TOOLS_AND_ACTIONS.md`, konstytucja |
| `memory_update_proposal` | **Zasada:** zapis pamięci tylko po propozycji i zgodzie („opt-in save proposal”); nigdy „zapamiętałem” bez sprawdzonego zapisu | `docs/architecture/AI_RUNTIME.md`, konstytucja (`docs/trust/`) |
| Dane z maili/stron to nie instrukcje (test 10) | **Zasada w prompcie i w kodzie:** ADR-102 (treść maila to informacja; zapis i tak wymaga stuknięcia), konstytucja; sprawdzone tylko na danych testowych | `docs/trust/`, ADR-102 |
| AI Act art. 50, RODO art. 9, App Review 5.1.2(i) | **Opisane** w planie i w researchu sportowym | `docs/strategy/DODI_PLAN_2026-10.md` sekcja 6 |

## 3. Kolizje z decyzjami właściciela

| PDF | Decyzja właściciela | Co proponuję |
|---|---|---|
| Tryb żywienia liczy bilans, kcal i makro (3.1, 3.3) | **ADR-620, decyzja 3** (gałąź `claude/sport-mode-research`, niescalona): domyślnie porady bez liczb; liczenie kalorii i białka wyłączone, dopóki osoba go nie włączy i nie przejdzie krótkiego sprawdzenia w kodzie (18+, BMI ≥ 18,5, brak sygnałów zaburzeń odżywiania); nigdy poniżej spoczynkowego zapotrzebowania ani 800 kcal, deficyt do ok. 500 kcal/dzień | Tryb żywienia z PDF bierze ADR-620 jako domyślne ustawienie. Jadłospis i agregacja składników działają bez kalorii; liczby tylko po włączeniu. Test 3 z PDF dalej obowiązuje. |
| L2: brak API Biedronki nie może być obchodzony „ukrytym, podatnym na awarie scrapingiem” (4.1) | **ADR-609:** gazetki czytane na żądanie z oficjalnych stron 4 sieci (Biedronka, Lidl, Dino, Rossmann), jawny `DoddyBot/1.0`, robots.txt i `Content-Signal: ai-input=no` szanowane, blokada nigdy nie jest obchodzona, nic nie jest przechowywane ani wspólne | **Moim zdaniem nie ma sprzeczności co do zasady:** ADR-609 nie jest ukryty i nie obchodzi blokad. Jest za to „podatny na awarie” (adapter na każdą sieć). PDF mówi o pełnym koszyku, którego repo nie robi. Proponuję zapisać w ADR-609, że to świadomy wyjątek, a licencja od agregatora (etap 2 strategii zakupów) jest docelową drogą. |
| HealthKit jako P1, po trenerze (8) | **ADR-620, decyzja 1:** tryb sportowy zaczyna się od Apple Health, WorkoutKit i głosu; do Claude idzie tylko krótkie podsumowanie policzone na iPhonie, po wyraźnej zgodzie (decyzja 2) | Trener z PDF w pierwszym kroku działa na danych podanych głosem (test 11), HealthKit zaraz po nim, jak w kolejności z ADR-620. Pełne próbki zdrowotne nie wychodzą z telefonu. |
| Linki do `blob/main/...` (7) | W repo nie ma gałęzi `main`; domyślna to `claude/loving-dirac-uuxoux` | Poprawione w wersji markdown na ścieżki w repo. |
| PDF opiera Gmail i kalendarz na `CONNECTED_APPS_PROPOSAL.md` (6, 7) | **ADR-120:** ta propozycja jest nieaktualna; zbudowano Połączenia (EventKit, kontakty) i Połączone aplikacje przez Composio (ADR-073 do 082, 096 do 105) | Gmail z PDF nie jest nowym projektem, tylko sprawdzeniem istniejącego (prawdziwe konto zamiast danych testowych, weryfikacja Google dla zakresu `gmail.readonly`, zakresy, które od ADR-485 obejmują też wysyłkę). |
| „Skaner paragonów” jako P0 | Chmurowe odczyty obrazów to nowe użycie chmury AI (CLAUDE.md, zasada 6); ADR-609 zgodził się na Haiku tylko dla gazetek | Paragony i etykiety najpierw na iPhonie (Vision, VisionKit), chmura dopiero po zgodzie właściciela. |

## 4. Co dodają inne sesje (24 paź)

### Tryb sportowy (gałąź `claude/sport-mode-research`, ADR-620, niescalona, tylko dokumenty)

Research: `docs/research/2026-10-24/research_sport_mode.md` na tamtej gałęzi. Dodaje do PDF:
- **Strava:** API Policy od 1 cze 2026 zakazuje danych Stravy w jakiejkolwiek aplikacji AI, także w oknie kontekstu modelu (§5.3); zakaz analityki, cache ponad 7 dni, pośredników i cudzych serwerów MCP [S]. **Oura** (umowa z 8 cze 2026): AI tylko przez MCP Oury [S]. PDF tego nie ma, a to zamyka najprostszą drogę do danych z zegarków.
- **HealthKit działa na darmowym koncie Apple**, a WorkoutKit wysyła treningi na Apple Watch bez aplikacji na zegarek [S].
- **wger** jako baza ćwiczeń z licencjami CC przy każdej pozycji (spełnia warunek PDF „nie pobierać atlasów bez licencji”); ExerciseDB i free-exercise-db ryzykowne [S].
- **Zasady do wymuszenia w kodzie**, ostrzejsze niż w PDF: stały komunikat przy czerwonych flagach („przerwij; w nagłym wypadku 112”), którego model nie zmienia; bieg najwyżej 10% dłuższy niż najdłuższy z 30 dni; żadnych procentów ryzyka kontuzji; PAR-Q+ jest chroniony prawem autorskim, logikę ACSM 2015 można wdrożyć [S].
- **MDR:** nie obiecywać „rehabilitacji kolana” ani „wykrywania arytmii”, żeby nie wejść w wyrób medyczny [S].
- **Zdjęcia posiłków:** ok. 36% średniego błędu energii u dużych modeli; pokazywać jako edytowalny zakres [S].

### Tryb sportowy, kroki 1 i 2 (gałąź `claude/sport-mode-health`, ADR-621 i 622, niescalona, kod)

Ta sama sesja po decyzjach z ADR-620 zbudowała (testy DoddyCore na Linuksie; nie skompilowane w Xcode, nie na telefonie):
- **Krok 1 (ADR-621):** ekran Ustawienia › Połączenia › Sport i zdrowie › Apple Health; tylko odczyt ostatnich 7 dni (treningi, sen z fazami, tętno spoczynkowe, HRV, VO₂ max); nic nie wychodzi z iPhone'a; strażnik repo pozwala na HealthKit tylko w jednym pliku i zabrania zapisu.
- **Krok 2 (ADR-622):** „Jak mi poszedł tydzień?”: dokładny tekst podsumowania (bez surowych próbek, do 2000 znaków) trafia do pola w Wiadomościach po osobnej zgodzie; wysyła dopiero stuknięcie, więc zgoda dotyczy dokładnej treści. Głosem jeszcze nie, bo głos idzie przez ElevenLabs z modelem Google, a ADR-620 pozwolił tylko na Claude.

To pokrywa „HealthKit po zgodzie” (P1 z PDF) i część przeglądu postępów trenera. Wywiad, plan i dziennik treningów z PDF jeszcze nie istnieją, a test 11 (bez zgody na HealthKit działa na danych podanych ręcznie) czeka na nie.

### Lista przy sklepie i stoper (gałąź `claude/stopwatch-and-shop-list`, „ADR-621”, niescalona, kod)

Przypomnienie listy przy sklepie mówi, ile rzeczy zostało („Zakupy · 4 rzeczy na liście”, nigdy nazwy), z przyciskiem „Otwórz listę”; do tego stoper liczący w górę z trzema narzędziami głosowymi (tylko w specyfikacji, nie na żywym agencie). Stoi na `claude/notifications-sound-timers` (ADR-612, 613). Pasuje do L1 z PDF i nie koliduje z „Listą zakupów+”, ale dotyka tych samych plików tekstów (`l10n/pl.json`) i strażnika.

**Komplikacja: podwójne numery ADR.** Gałąź sportowa i gałąź stopera nadały ADR-621 różnym decyzjom. Tak samo ADR-612 i 613: na domyślnej gałęzi to linki partnerskie i zasady płatności w zakupach, a na `claude/notifications-sound-timers` (i stojącej na niej gałęzi stopera) dzwoniące minutniki i przypomnienia. Przy scalaniu gałęzie, które scalą się później, muszą dostać nowe numery. Ten dokument używa ADR-630 i 631, żeby nie wejść w zakres 611 do 622.

### Tryb zakupów (domyślna gałąź `claude/loving-dirac-uuxoux`, ADR-607 do 610, etap 1 scalony)

Strategia: `docs/strategy/TRYB_ZAKUPOW_2026-10.md`, research `docs/research/2026-10-24/research_shopping_*.md`. Dodaje do PDF:
- **Allegro:** oprócz braku publicznego API ofert (zgodne z PDF) regulamin zabrania pokazywania ofert Allegro w konkurencyjnych serwisach; Allegro tylko pośrednio albo przez link partnerski [S].
- **Prawo baz danych:** wspólny indeks wszystkich gazetek bez licencji przypomina sprawę *CV-Online* (TSUE C-762/19), dlatego ADR-609 niczego nie przechowuje [S].
- **Agregatory gazetek** (Blix, Ding, Gazetki.pl i inne) nie mają publicznego API; regulaminy zakazują botów [S].
- **Płatność w aplikacji:** rzeczy fizyczne nie przez zakupy Apple (3.1.3(e)); zbieranie pieniędzy dla sklepu to usługa płatnicza z licencją KNF; BLIK dla asystentów to pilotaż [S]. Potwierdza L3 z PDF.
- **Źródło ofert:** Serper (Google Shopping, Polska) jako najtańsze; cena z listy Google oznaczona jako `listing`, a odczytana ze strony sklepu jako `shop_page` (ADR-607, 608) [S]. To odpowiada statusom `verified_at` / `estimate` z PDF.

### Otwarte PR-y z 24 paź i numery ADR (stan 18:50 UTC)

| PR / gałąź | Co | Numery ADR |
|---|---|---|
| domyślna `claude/loving-dirac-uuxoux` | zakupy etap 1 i 2 (gazetki, oferty, koszyk, obserwowanie cen) | 607 do 614 |
| #135 `claude/notifications-sound-timers` | dzwoniące minutniki i przypomnienia, plan tygodnia | **612, 613** |
| #136 `claude/simpler-settings-files-openai` | „Pliki” zamiast „Wspomnień”, Ustawienia w 14 wierszach, głos OpenAI | **614** |
| #137 `claude/sport-mode-health` | tryb sportowy: Apple Health, podsumowanie tygodnia | 620 do 623 |
| #139 `claude/stopwatch-and-shop-list` | stoper i przypomnienie listy przy sklepie | **621** |
| #140 ten PR | badania trybów, Lista zakupów+ | 630, 631 |

Pogrubione numery się powtarzają: 612 i 613 (domyślna gałąź i #135, różne decyzje), 614 (domyślna i #136) oraz 621 (#137 i #139). Gałąź scalana później musi dostać nowe numery; ten PR się z nikim nie zderza. #136 przebudowuje zakładkę Wspomnień na „Pliki”, więc przy scalaniu warto sprawdzić przełącznik Notatki | Listy, na którym stoi „Lista zakupów+”.

**Nie przeczytane:** transkrypty sesji o strategii rynkowej Dodiego, o silniku cen w sklepach spożywczych (jej gałęzi nie ma na serwerze), o łączeniu z API, o czacie webowym i o Twilio. Dwaj pomocnicy, którzy je czytali, zostali przerwani przez restart sesji i nic nie zwrócili. Strategię rynkową czytałem za to bezpośrednio w repo (`docs/strategy/DODI_PLAN_2026-10.md`).

## 5. Co w PDF jest nowe i warto zachować

- **Faktury i administracja** (P1 Fakturownia/inFakt, P3 KSeF): w repo nie ma nic. Harmonogram KSeF z PDF jest zgodny ze stroną MF [V, ksef.podatki.gov.pl, opublikowane i zmienione 27.04.2026]: wystawianie od 1.02.2026 (sprzedaż > 200 mln zł w 2024) i od 1.04.2026 (pozostali); podatnicy z fakturowaną sprzedażą do 10 000 zł brutto miesięcznie od 1.01.2027; odbieranie w KSeF od 1.02.2026. **Dodatkowo (brak w PDF): kary będą stosowane dopiero od 1.01.2027** [V]. Fakturownia/inFakt to nowi dostawcy zewnętrzni: osobny kamień milowy i zgoda właściciela (CLAUDE.md zasada 6). Co pokazują ich strony [V, dziś]:
  - **Fakturownia:** token API generowany przez użytkownika w aplikacji („Ustawienia → Ustawienia konta → Integracja → Kod autoryzacyjny API”), wysyłany jako Bearer; dodanie faktury przez `POST invoices.json`; OAuth ani przepływ partnerski nie są opisane; limity i plany nie są podane. KSeF łączy się po stronie Fakturowni (certyfikaty, Profil Zaufany, mObywatel lub podpis kwalifikowany), z trybem automatycznym lub ręcznym wysyłki i pobieraniem faktur kosztowych.
  - **inFakt:** wystawianie faktur przez REST API, wysyłka do KSeF i sprawdzanie statusu (także wielu faktur naraz); sandbox; sposób logowania i plany tylko w `docs.infakt.pl` (strona zmieniona 21.05.2026).
  - **Wniosek [I]:** Doddy nie musi łączyć się z KSeF sam (P3 z PDF można pominąć); robi to program księgowy użytkownika. Za to token konta księgowego to dostęp do finansów firmy: trzymać go w Pęku kluczy iPhone'a albo w zaszyfrowanym magazynie serwera, nigdy w logach, z odwołaniem jednym przyciskiem. Sprawdzenie statusu po `unknown` (test 9) jest możliwe w inFakcie przez API statusu.
- **Przepływ jadłospis → lista zakupów** (3.3): łączy tryb żywienia z istniejącymi listami (ADR-216) i koszykiem (ADR-610). `pantry_subtractor` i `unit_normalizer` nie istnieją.
- **Wspólny kształt trybu:** pakiet umiejętności (7.1) i kontrakt wyniku (7.2) z `sources`, `caveats`, `risk_level`, `verified_external_action`. Wynik sprawy zakupowej (ADR-607) ma już podobne pola (źródła, zastrzeżenia, niewiadome), więc kontrakt z PDF może z niego wyrosnąć zamiast zaczynać od zera [I].
- **Ekran „Dlaczego tak?”** ze źródłami i obliczeniami na żądanie (7.3 pkt 4).
- **Karty ćwiczeń z licencją i datą przeglądu** (2.3); research sportowy wskazuje wger jako bazę z licencjami CC (sekcja 4).
- **15 testów akceptacyjnych** (9): 4 są już pokryte zasadami w kodzie (6, 13, 15 i częściowo 9); reszta wymaga nowych trybów.
- **Open Food Facts:** limit z PDF potwierdzony [V, openfoodfacts.github.io, dziś]: 15 odczytów produktu/min/IP, 10 wyszukiwań/min/IP, dane ODbL, zdjęcia CC BY-SA, wymagany własny User-Agent `AppName/Version (email)`. **Wniosek [I]:** przez serwer Doddy'ego wszyscy użytkownicy dzielą jeden adres IP, więc kod kreskowy trzeba sprawdzać z iPhone'a albo z pobranego eksportu bazy, nie przez serwer.

## 6. Proponowana kolejność

Każdy krok to osobny, mały kamień milowy z testami i wymaga „tak” właściciela przed kodem (CLAUDE.md, zasada 2). Kolejność łączy ranking z PDF z tym, co już jest i co właściciel już zdecydował.

1. **Lista zakupów z głosu, rozszerzona:** jednostki i ilości w pozycjach, „co już jest w domu”, kod kreskowy na iPhonie (Open Food Facts z iPhone'a). Opiera się na ADR-216 i ADR-610.
2. **Tryb sportowy:** odczyt Apple Health i tygodniowe podsumowanie są już w kodzie na `claude/sport-mode-health` (ADR-621, 622). Dalej z PDF: wywiad i plan z danymi z głosu (testy 1, 2, 11), czerwone flagi jako stały komunikat w kodzie, dziennik treningów.
3. **Jadłospis → lista:** porady bez liczb (ADR-620), alergie jako dane wrażliwe z osobną zgodą, agregacja składników do istniejącej listy, koszyk z ADR-610.
4. **Wspólny kontrakt wyniku i ekran „Dlaczego tak?”** dla trybów 2 i 3.
5. **Faktury przez Fakturownię lub inFakt** (szkic, podgląd netto/VAT/brutto liczony w kodzie, zgoda, status, `unknown` → sprawdzenie stanu): dopiero po wyborze dostawcy przez właściciela.
6. **Gmail na prawdziwym koncie:** istniejące `check_email` i `draft_email` (ADR-096 do 103) sprawdzone poza danymi testowymi; przedtem weryfikacja Google dla zakresów restricted (odczyt i wysyłka) i sprawdzenie, że każda wysyłka idzie przez kartę zgody (ADR-485).
7. **Bezpośredni KSeF i pełny checkout:** nie teraz.

## 7. Decyzje właściciela (24 paź, ADR-630)

1. **Żywienie według ADR-620:** „Tak, ADR-620”. Jadłospisy i listy bez kalorii i białka domyślnie; liczenie tylko po włączeniu i sprawdzeniu w kodzie.
2. **Gazetki:** „Tak, dopisz”. ADR-609 ma dopisek: świadomy wyjątek od zasady „bez ukrytego scrapingu” z PDF, celem jest licencja agregatora.
3. **Faktury:** „inFakt”. Wybrany dostawca; budowa to osobny kamień milowy, przed kodem zgoda na dokładny zakres, przechowywanie tokenu i tekst prywatności.
4. **Pierwsza budowa:** „Lista zakupów+”: ilości i jednostki, „co już jest w domu”, kod kreskowy na iPhonie z Open Food Facts pytanym z iPhone'a. Plan i stan: `docs/implementation/SHOPPING_LIST_PLUS.md`.

## 8. Czego nie sprawdziłem

- Cen, limitów i planów API Fakturowni i inFaktu (ich strony tego nie podają) ani warunków API InPostu.
- Aktualnego stanu metody `GET /offers/listing` Allegro na stronie dewelopera; zgodne z tym, co znalazła sesja zakupowa (brak publicznego API ofert od 16 wrz 2026 [S, `TRYB_ZAKUPOW_2026-10.md`]).
- Źródeł arXiv o bezpieczeństwie LLM w żywieniu (2401.08420, 2512.04843).
- Czy test ruchu `MotionEvidenceTests.testWithReduceMotionHeFadesAndNeverFlies` jest przypadkowy: padł raz na PR #140 (przeszedł na gałęzi domyślnej); drugi bieg na Macu to rozstrzygnie.
