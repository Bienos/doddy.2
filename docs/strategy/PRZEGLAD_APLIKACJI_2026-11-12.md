# Przegląd: zakupy i gazetki, Wiadomości, Ustawienia, rozmowy, radar (12 lis 2026)

Odpowiedź na brief właściciela z 12 lis 2026 („zrób review gazetek typu Lidl z sekcji zakupów i znajdź opcje, jak to usprawnić", plus Wiadomości, Ustawienia, głos, radar, rozmowy i przycisk ekranu).

**Skąd są wnioski.** Kod repo i logi serwera `doddy-messaging`, odczytane przez API Rendera 12 lis (tylko liczby i kody, bez słów). Część o aplikacji to **lektura kodu**: nic nie było kompilowane ani oglądane na telefonie, więc „jak to wygląda" to wniosek z kodu. Odwołania `plik:linia` są ze stanu `main` z 12 lis.

## 0. W skrócie

| Obszar | Główny problem | Co zrobione w tej gałęzi | Co dalej |
|---|---|---|---|
| Gazetki | Każde wyszukiwanie czyta gazetki od nowa: ~24 s, 6–9 z 10 sklepów pada, ~115 tys. tokenów na wyszukiwanie | **Katalog gazetek:** serwer czyta gazetki raz dla wszystkich, w tle, co 6 h; wyszukiwanie odpowiada z bazy (decyzja `2026-11-12-leaflet-catalog`). Wyłączony do czasu `DEALS_CATALOG_ENABLED=1` | Włączyć i wdrożyć (OWNER_QUEUE 43); potem ekran listy zakupów i porównania (sekcja 1.5) |
| „Znajdź mi to" (np. słuchawki Apple) | Zadanie zakupowe padało błędem 400 przy drugim zapytaniu do modelu | **Naprawione:** narzędzia nie zmieniają się w trakcie zadania; błąd zapisuje się w logu z typem i miejscem | Wdrożyć razem z katalogiem; jedno pole wyszukiwania, które samo wybiera gazetki albo sklepy internetowe |
| Wiadomości | Brak powiadomienia o wyniku; karty chowają się pod transkrypcją; całość przerysowuje się przy każdej zmianie | Nic (aplikacja) | Osobny PR: powiadomienie lokalne, przewijanie do karty, wydzielone wiersze, opis pliku |
| Ustawienia i głos | Wybór głosu był jeszcze w Ustawieniach (Głos › Głos i osobowość › Głos); „Głos" trzy poziomy w głąb | **Wybór głosu usunięty** (decyzja `2026-11-12-one-voice`): Doddy ma jeden głos, zostają tempo, ekspresja i „Zaczyna w" | Osobny PR: spłaszczyć strony, „Konto" i „Rozmowy" na pierwszą stronę |
| Rozmowy telefoniczne | Jedna długa lista: PIN, weryfikacja, przełączniki i historia w trzech miejscach; żargon (Twilio, koszt w USD) | Nic | Hub z trzema kartami: „Zadzwoń do Doddy'ego", „Doddy dzwoni do mnie", „Doddy dzwoni w moim imieniu" |
| Przycisk ekranu | Systemowa ikona nagrywania bez podpisu, obok •••, nie pokazuje, czy udostępnianie trwa | Nic | Podpisana kapsułka „Pokaż ekran" / „Doddy widzi ekran · Zatrzymaj" |
| Radar | Alerty obiecują coś, czego serwer nie robi (wyłączone); głos odsyła do starej nazwy; dubel z „Wiadomościami dnia" | Nic | Ukryć „Daj znać…" do włączenia alertów, połączyć z Wiadomościami dnia, karta na Home |

## 1. Zakupy i gazetki

### 1.1 Jak to działa dziś

- „Najtaniej w tym tygodniu" (`DoddyApp/Features/Shopping/DealsView.swift`) wysyła produkty do `POST /v1/deals/search`. Serwer (`server/messaging/src/deals/service.ts`) **przy każdym wyszukiwaniu** czyta na żywo gazetki do 16 sieci w 25 sekund: dane sieci, a strony-obrazki przez Claude Haiku, tylko pod kątem produktów z zapytania.
- Koszyk (jeden sklep, dwa sklepy, każdy produkt najtaniej) liczy już `BasketSolver` w DoddyCore, w groszach, bez modelu. **Logika koszyka jest dobra; problemem są dane pod nią.**
- „Znajdź mi to" (`ShoppingHubView.swift`) to osobne zadanie w tle: Claude szuka ofert (Google Shopping przez Serper i strony sklepów) i potwierdza cenę na stronie sklepu.

### 1.2 Co pokazują logi serwera

| Kiedy (UTC) | Sieci | Padło | Przeczytane strony | Tokeny wejścia | Czas |
|---|---|---|---|---|---|
| 10 lis 22:15 | 10 | 9 | 209 | 24 601 | 24,0 s |
| 11 lis 08:13 | 10 | 7 | 173 | 113 230 | 23,4 s |
| 11 lis 08:26 | 10 | 6 | 210 | 116 417 | 23,8 s |

Biedronka sama ma ~97 stron i nie mieści się w czasie (`image_failed,time,pages_over_cap`). Każde wyszukiwanie płaci za czytanie gazetek od nowa, a i tak dostaje odpowiedź z 1–4 sieci na 10. Pamięć podręczna stron z 11 lis oszczędza pobieranie, ale nie czytanie, bo czytnik szuka tylko produktów z zapytania, więc jego odczytu nie da się użyć dla następnej osoby.

**„Znajdź mi to": słuchawki Apple.** Jedyne zadanie zakupowe w logach (11 lis, 23:21 UTC) padło po 14 sekundach: `shopping request failed … error: api_400`, potem `failure: provider_error`. Pierwsze zapytanie do modelu przeszło (3 wyszukiwania, 1 pobranie), drugie dostało 400. Przyczyna, zgodna z dokumentacją API: Claude Haiku 5.5 i Opus 5.5 odrzucają bloki „myślenia" odesłane po zmianie listy narzędzi, a kod po każdym zapytaniu obniżał `max_uses` narzędzi wyszukiwania do tego, co zostało w budżecie. Wniosek wynika z dokumentacji i wzorca w logu; prawdziwe zapytanie do API nie było tu wykonane. Ten sam mechanizm był w zwykłych zadaniach (Opus 5.5).

### 1.3 Co zrobiłem w tej gałęzi (serwer, przetestowane)

1. **Katalog gazetek** (`server/messaging/src/deals/catalog.ts`, migracja 028, decyzja `2026-11-12-leaflet-catalog`):
   - Co 6 godzin serwer czyta 11 sieci (Biedronka, Lidl, Dino, Aldi, Żabka, Delikatesy Centrum, E.Leclerc, Komfort, Lewiatan, Natura, Action), **całe strony, raz dla wszystkich**.
   - Każda strona jest czytana raz na gazetkę; kolejne skany czytają tylko nowe strony, więc są prawie darmowe.
   - Wyszukiwanie bierze te sieci z bazy: bez pobierania i bez czytania stron. Oferty buduje ten sam kod co dotąd, więc kontrakt, sprawdzenia, warunki („z aplikacją", „2+1") i koszyk się nie zmieniają.
   - Rossmann, CCC, Deichmann, Maxi Zoo i zooplus szukają po produkcie, więc dalej są czytane na żywo.
   - Sieć bez świeżego katalogu też jest czytana na żywo, jak dotąd.
   - Koszt (szacunek, bez pomiaru): około 1,40 $ tygodniowo, niezależnie od liczby wyszukiwań. Dziś to ~0,014 $ za każde wyszukiwanie (116 tys. tokenów wejścia i 4 tys. wyjścia po cenach Haiku 5.5).
   - Prywatność się poprawia: strony idą do modelu tylko z nazwą sieci, a nie z produktami osoby. Katalog nie trzyma niczego o żadnej osobie.
   - **Włączenie:** `DEALS_CATALOG_ENABLED=1` na `doddy-messaging` i wdrożenie (OWNER_QUEUE 43).
2. **Naprawa „Znajdź mi to"** (`server/messaging/src/errands/budget.ts`): `max_uses` jest stałe przez całe zadanie, a budżet wyszukiwań liczy kod. Odmowa API trafia teraz do logu z typem i ścieżką parametru (bez treści), więc następny taki błąd będzie widać od razu. Test regresji sprawdza, że dwa zapytania jednego zadania wysyłają identyczne narzędzia.

### 1.4 Dlaczego „słuchawki Apple" nic nie dawały, i co z tym zrobić

Są trzy osobne powody:

1. **Błąd 400 w „Znajdź mi to"**: naprawiony (1.3, punkt 2), działa po wdrożeniu.
2. **Gazetki spożywcze rzadko mają AirPodsy.** Jeśli wpisało się je w „Najtaniej w tym tygodniu", odpowiedź „nic nie pasuje" jest prawdziwa. Ekran powinien wtedy zaproponować „Szukaj w sklepach internetowych" (to samo zadanie co „Znajdź mi to"), zamiast zostawiać same linki do Allegro i Ceneo.
3. **Dopasowanie wymaga pierwszego słowa.** „słuchawki Apple" nie dopasuje produktu „Apple AirPods Pro 2" bez słowa „słuchawki" (`server/messaging/src/deals/match.ts`, `matchScore`: pierwsze słowo musi się znaleźć). Do zrobienia: krótka lista synonimów marka→rzecz w `categories.ts` (AirPods → słuchawki), testowana jak reszta matchera.

### 1.5 Jak to powinno działać dla użytkownika (propozycja)

**Jedno wejście.** Home › ••• › Zakupy, na górze jedno pole „Czego potrzebujesz?" i przycisk „Z mojej listy". Kod rozpoznaje, czy to zakupy codzienne (katalog gazetek, odpowiedź od razu), czy rzecz do porównania w sklepach internetowych („Znajdź mi to", wynik w tle). Słowniki rodzajów sklepów już są (`specialty.ts`, `categories.ts`). Przy produktach „pomiędzy" pokazujemy oba wyniki: gazetki od razu, sklepy internetowe w tle.

**Lista zakupów → gdzie iść.** Odpowiedź ma trzy zakładki, liczone już dziś przez `BasketSolver`:
- **Jeden sklep:** gdzie kupisz najwięcej za najmniej, z sumą i „brakuje: X".
- **Dwa sklepy:** tylko gdy oszczędność przekracza Twój próg.
- **Każdy produkt osobno:** lista produkt → najtańszy sklep → cena, a pod każdym produktem pozostałe sklepy w jednej linii.

Dotknięcie produktu otwiera jego kartę: wszystkie oferty, warunki, „ważne do", „podobne, ale nie to samo".

**Przełączniki w jednym miejscu** („Ustawienia zakupów", pod przyciskiem z suwakami, nie trzy ekrany głębiej):
- Moje sklepy (już jest, `MyShopsView`).
- Aplikacje i karty, których używam (już jest).
- Drugi sklep tylko od X zł oszczędności (już jest).
- Pokazuj ceny tylko na dziś albo także te od jutra.
- Nowe: „Odśwież moje sklepy". Po włączeniu katalogu nie jest potrzebne, chyba że sieć nie jest w katalogu.

**Co daje katalog, a czego nie było:**
- Przeglądanie bez pytania: „Promocje tygodnia w Lidlu", według kategorii.
- Obserwacja produktu z listy, np. „daj znać, gdy masło będzie poniżej 5 zł". Sprawdzana w katalogu, bez dodatkowego czytania.
- Głosem: odpowiedź w sekundę zamiast 25 s.

**Głosem.** `find_deals` zostaje. Gdy wynik jest pusty dla rzeczy niespożywczej, Doddy proponuje „Znajdź mi to" (karta z dotknięciem, jak dziś).

### 1.6 Kolejność prac w zakupach

1. Wdrożyć tę gałąź i włączyć katalog (właściciel, OWNER_QUEUE 43). Przeczytać logi pierwszych skanów: tokeny na stronę, ile stron każdej sieci.
2. Serwer: synonimy marka→rzecz; pole „kiedy przeczytane" w odpowiedzi (opcjonalne, wymaga zmiany kontraktu).
3. Aplikacja: jedno pole w Zakupach, trzy zakładki odpowiedzi, „Szukaj w sklepach internetowych" przy pustym wyniku. To praca na Macu: tu nie da się skompilować SwiftUI.
4. Obserwacja ceny z katalogu (serwer + powiadomienie).

## 2. Wiadomości

1. **Brak powiadomienia, gdy wynik zadania trafia do Wiadomości.**
   - Wynik zapisuje się w wątku tylko przy `ErrandsModel.refresh()`, a to wywołuje się tylko przy powrocie aplikacji na pierwszy plan (`RootView.swift:277-281`).
   - Jedynym powiadomieniem jest push z serwera, który nie przychodzi bez klucza APNs (OWNER_QUEUE 8), bez tokenu urządzenia albo bez zgody.
   - Push nie ma `content-available`, więc aplikacja nie budzi się, żeby zapisać wynik.
   - Na pierwszym planie baner się pokazuje, ale nic nie odświeża wyniku.
   - `ThreadInbox.save` nie wysyła lokalnego powiadomienia.
   - **Poprawka:** lokalne powiadomienie przy dopisaniu wyniku, gdy Wiadomości nie są otwarte; `refresh()` przy dotknięciu i przy pushu; odpytywanie co ~30 s, gdy zadanie trwa, a aplikacja jest otwarta; `content-available` w pushu zadania; Doddy mówi „dam znać" tylko wtedy, gdy powiadomienia są włączone (`Errand.swift:986` obiecuje to bez sprawdzenia).
2. **Karta dodana, ale niewidoczna.**
   - W rozmowie głosowej karty są pod transkrypcją, a każde nowe zdanie przewija na dół do ostatniej linii (`VoiceView.swift:389-391`). Karta ląduje więc pod krawędzią ekranu.
   - Część kart w ogóle nie wyskakuje: przypomnienia, listy, zmiany, BLIK, faktury (`HomeConversation.resultsToShow`).
   - Gdy otwarte są Wiadomości (pełny ekran), karta z rozmowy prawdopodobnie nie może się pokazać (do sprawdzenia na telefonie).
   - **Poprawka:** znacznik końca po ostatniej karcie i przewijanie do niego przy każdej nowej karcie; uzupełnić `resultsToShow`; pokazywać kartę z najwyższego otwartego ekranu.
3. **Przycina się.**
   - Wiersze są funkcjami w jednym ogromnym `body` (`MessagesView.swift`, 1235 linii), więc każda zmiana przerysowuje cały wątek.
   - Pliki są odpytywane co 6 albo 30 s i podmieniają stan nawet bez zmiany.
   - Wykrywanie linków tworzy `NSDataDetector` przy każdym rysowaniu.
   - Oś czasu jest sortowana przy każdym rysowaniu.
   - **Poprawka:** osobny `MessageRow: Equatable`; pamięć linków i osi czasu w modelu; podmiana stanu tylko przy zmianie.
4. **Opis do pliku lub prezentacji.**
   - Dziś jest tylko „Here it is: „X"" albo sama nazwa pliku. Prezentacja z telefonu nie dostaje nawet dymka.
   - **Poprawka:** pole `summary` w `ThreadDocument`, które nie wymaga migracji, bo idzie do JSON. Wypełniane z prośby osoby albo z tytułów slajdów; najlepiej z krótkiego opisu, który Doddy podaje w `make_document` / `make_presentation`.
   - Zmiana opisu narzędzi na żywym agencie wymaga zgody właściciela.

## 3. Ustawienia i głos

- **Wybór głosu był jeszcze w aplikacji; usunięty 12 lis** (polecenie właściciela, decyzja `2026-11-12-one-voice`).
  - Droga była: Ustawienia › Głos › „Głos i osobowość" › Głos (`VoiceChoiceView`). Sześć głosów z próbkami, wysyłanych do ElevenLabs jako nadpisanie głosu.
  - Teraz: zostają tempo, ekspresja i „Zaczyna w"; głos wybrany wcześniej nie jest już wysyłany, a próbki (~540 KB) są usunięte.
- „Głos" jest trzy poziomy w głąb, a każdy z tych ekranów nazywa się Głos. Języki są dwa i w dwóch miejscach. Konto jest rozbite między „O aplikacji" i „Głos › Konto". „Rozmowy telefoniczne" siedzą w Powiadomieniach.
- **Propozycja pierwszej strony:**
  - Konto
  - Głos (jedna strona)
  - Pamięć Doddy'ego
  - Połączenia z aplikacjami
  - Rozmowy telefoniczne
  - Powiadomienia
  - Wygląd i język
  - Prywatność
  - O aplikacji

  Nagłówek o pamięci zastąpić neutralnym. Kafelki z symbolami także na stronach wewnętrznych.

## 4. Rozmowy telefoniczne

- Dziś to jedna długa lista (`CallsSettingsView.swift`), w kolejności:
  1. weryfikacja numeru, która przenosi na inny ekran;
  2. PIN;
  3. „Odbieraj";
  4. pamięć;
  5. „Rozmowy za Ciebie";
  6. „Doddy dzwoni do Ciebie";
  7. SMS-y;
  8. eksport;
  9. historia.
- Wynik „Zadzwoń teraz" pojawia się na samym dole, pewnie poza ekranem.
- Rozmowa „w Twoim imieniu" to około 4 ekranów, ponad 8 pól i okno potwierdzenia, które obiecuje sterowanie z ekranu blokady, choć Live Activity jest wyłączona.
- Żargon: „Twilio przyjęło połączenie", „serwer wiadomości Doddy'ego", koszt w USD z czterema miejscami po przecinku.
- **Propozycja: hub z trzema kartami.**
  - **Zadzwoń do Doddy'ego:** lista kontrolna: numer zweryfikowany ✓, PIN ✓, odbieranie ✓, potem duży przycisk.
  - **Doddy dzwoni do mnie:** teraz albo o godzinie; wynik od razu na karcie.
  - **Doddy dzwoni w moim imieniu:** jedno pole „Do kogo i po co", resztę uzupełnia Doddy; pokazuje kartę do zatwierdzenia z dokładną treścią (zasada konstytucji o zatwierdzaniu dokładnej treści zostaje).
  - PIN, pamięć, SMS-y i eksport idą do „Opcji". Koszt w USD znika z widoku użytkownika. Historia w jednym miejscu.

## 5. Przycisk ekranu podczas rozmowy

- Dziś to systemowy przycisk nadawania (`RPSystemBroadcastPickerView`) z ikoną nagrywania, bez podpisu, tuż obok •••.
- Wygląda jak „nagrywanie" albo drugie menu i nie pokazuje, czy Doddy widzi ekran.
- Po zakończeniu rozmowy znika, a udostępnianie trwa dalej.
- Czerwony wskaźnik iOS prawdopodobnie nachodzi na pomarańczowy pasek Doddy'ego przy Dynamic Island (do sprawdzenia na telefonie).
- **Propozycja:**
  - Kapsułka z okiem i napisem „Pokaż ekran", która po włączeniu zmienia się w „Doddy widzi ekran · Zatrzymaj". Systemowy przycisk zostaje niewidoczny pod spodem, bo tylko on może uruchomić nadawanie.
  - Kapsułka w dolnym pasku obok Wycisz i Zakończ, nie przy •••.
  - Mały znacznik „udostępniasz ekran" zostaje także po rozmowie.

## 6. Radar

- **Alerty są wyłączone na serwerze** (`RADAR_ALERTS_ENABLED=0`), a przycisk „Daj znać…" i tak jest widoczny i oferuje tylko „Tylko tutaj".
- Śledzenie głosem zapisuje tylko na telefonie i odsyła do starej nazwy „Following" (`NewsFollowVoice.swift:119`).
- Dotknięcie powiadomienia nie otwiera radaru.
- „Wiadomości dnia" w Ustawieniach to drugi, osobny zestaw tematów.
- **Propozycja:**
  - Ukryć „Daj znać…" do czasu włączenia alertów.
  - Poprawić tekst odpowiedzi głosowej i dać „Pokaż" jako następny krok.
  - Kartę „Doddy zauważył" dodać na Home, a powiadomienie ma otwierać radar.
  - Jedno pole słów na temat; połączyć radar z „Wiadomościami dnia".

## 7. Proponowana kolejność (osobne PR-y, jeden temat każdy)

1. **Ta gałąź** (serwer): katalog gazetek i naprawa „Znajdź mi to". Gotowa do PR-a.
2. Wiadomości: powiadomienie o wyniku i przewijanie do kart. Najbardziej odczuwalne; aplikacja, Mac do kompilacji.
3. Zakupy w aplikacji: jedno pole, trzy zakładki, karta produktu.
4. Ustawienia: spłaszczenie stron (wybór głosu już usunięty w tej gałęzi).
5. Rozmowy: hub z trzema kartami.
6. Przycisk ekranu i radar.
7. Wiadomości: wydajność (wiersze, linki) i opis do plików (z narzędziem głosowym, za zgodą właściciela).

## 8. Decyzje właściciela

- **Włączenie katalogu** na serwerze (OWNER_QUEUE 43).
- **Opis do plików:** czy dodać krótki opis do narzędzi `make_document` / `make_presentation` na żywym agencie (zmiana agenta tylko na wyraźne polecenie).
- **Alerty radaru:** włączyć `RADAR_ALERTS_ENABLED` czy schować funkcję do czasu działających pushy (APNs, OWNER_QUEUE 8).

## 9. Co zostało uruchomione

- `npm test` w `server/messaging` z lokalnym Postgresem 16: 935/935, w tym 17 nowych testów katalogu i test regresji błędu 400.
- **Nie uruchomione:** prawdziwy skan katalogu i prawdziwe zadanie zakupowe (brak klucza Anthropic, a na żywych usługach nic tu nie zmieniam); aplikacja nie była kompilowana (brak Xcode); nic nie było oglądane na telefonie.
