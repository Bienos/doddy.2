# Messages: jak łączy się z aplikacją i co Dodi wysyła sam (propozycja, 24 paź 2026)

Do decyzji właściciela. Zbudowany jest tylko pierwszy kawałek E3: Dodi proponuje plik, powstaje po dotknięciu (ADR-606, niesprawdzone na Macu). Reszta nie jest zbudowana. Makiety: https://claude.ai/artifact/CmQEKD2mzAYpMZojFZkmDg (ekrany 3–5). Stan dzisiejszy i decyzje o wyglądzie: `docs/implementation/MESSAGES_IMESSAGE_STYLE.md`.

## Zasady (nie do negocjacji, z konstytucji)

1. **Messages to jedyne miejsce, gdzie Dodi pisze.** Głos zostaje osobno (decyzja z 22 paź).
2. **Dodi nie pisze sam o niczym, czego nie włączyłeś.** Każdy rodzaj ma własny przełącznik, domyślnie wyłączony poza wynikiem zadania, które sam zleciłeś.
3. **Brak nacisku.** Żadnego „tęskniłem", serii, odliczania, zachęt „wróć". Limit i cisza są po Twojej stronie.
4. **Zmiana czegokolwiek (przypomnienie, lista, notatka) tylko po Twoim dotknięciu, z dokładną treścią na karcie.** „Dodano" pojawia się dopiero po odczycie z zapisu; brak potwierdzenia znaczy „nieznane", nigdy sukces.
5. **Ekran blokady nie pokazuje treści.** Powiadomienie mówi tylko, że Dodi ma wiadomość.
6. Dodi mówi, że jest AI, i skąd jest odpowiedź (już jest).

## Co Dodi może wysłać sam

| Rodzaj | Domyślnie | Skąd bierze treść | Uwagi |
|---|---|---|---|
| Wynik zadania w tle, które zleciłeś | włączone | Zadania w tle (errands, ADR-570), dziś karta „Gotowe" na Home | To odpowiedź na Twoją prośbę. Zadania są dziś wyłączone na serwerze |
| Twoje przypomnienia | włączone | Przypomnienia, które sam ustawiłeś | Treść wiadomości = treść przypomnienia, nic dopisanego |
| Zadania zaplanowane przez Ciebie (np. poranny brief 7:30 w dni robocze) | wyłączone | Zadanie, które sam stworzysz; lista, pauza, godziny ciszy | To przetrwało po wycofaniu Pulse u OpenAI; zamiast „kanału wiadomości" |
| Propozycja zapisu po rozmowie głosowej („Warto zachować?") | wyłączone | Dziś karta po rozmowie (ADR-247) | Karta z Twoim dotknięciem, nic nie zapisuje się samo |

**Czego nie ma:** ciekawostek, ofert, przypomnień „że dawno nie rozmawialiśmy", wiadomości o niczym, co nie wynika z Twojego zlecenia.

**Sterowanie** (makieta „Dodi pisze sam"): przełączniki per rodzaj, cisza (domyślnie 22:00–7:00), najwyżej 3 wiadomości od Dodiego dziennie, „Wycisz" jednym dotknięciem w wątku.

## Jak to łączy się z aplikacją

| Miejsce | Zmiana |
|---|---|
| **Home** | Przycisk Messages dostaje znaczek z liczbą nowych wiadomości od Dodiego. Wyspa zostaje tylko dla rozmowy głosowej |
| **Wątek** | Karty do zatwierdzenia (makieta „Karty w wątku"): przypomnienie, lista, notatka, wydarzenie. Te same reguły co w głosie (ASK-01: dokładna treść, jedno dotknięcie) |
| **Notatka / lista** | „Zapytaj Dodiego o tę notatkę" otwiera wątek z tą notatką jako kontekstem |
| **Przytrzymanie dymka** | Dziś: Kopiuj. Dalej: „Zapisz jako notatkę" i „Dodaj do listy" (Twoje dotknięcie) |
| **Udostępnij (share sheet)** | „Wyślij do Dodiego": zrzut ekranu lub link trafia do wątku, Dodi pyta, co z tym zrobić. Rozszerzenie share już istnieje |
| **Siri / Spotlight** | Skrót „Napisz do Dodiego" otwierający wątek |
| **Ustawienia** | Nowy ekran „Dodi pisze sam" w grupie „Ask Doddy" |
| **Prywatność** | Notatki prywatne nigdy nie idą do modelu (jak dziś). Wątek zostaje na iPhonie; po pushu z serwera potrzebna będzie zgoda na kopię wiadomości od Dodiego na serwerze |

## Co to wymaga technicznie

1. **Pisany Dodi z narzędziami propozycji.** Dziś serwer odpowiada tylko tekstem (Claude Haiku 5.5, ADR-586). Dodać narzędzia `propose_reminder`, `propose_list_item`, `propose_note`: model **proponuje**, kod waliduje i sprawdza limity, aplikacja wykonuje dopiero po dotknięciu i czyta wynik z zapisu. Model nigdy nie wykonuje akcji sam.
2. **Wiadomość od Dodiego w wątku bez pytania.** Nowy rodzaj wiadomości w `thread_messages` (nadawca Dodi, źródło: zadanie/przypomnienie) z tym samym odczytem po zapisie; reguły `ThreadRules` (limit dzienny, cisza) testowane na Linuksie.
3. **Dostarczenie:**
   - **Etap lokalny (bez serwera):** przypomnienia i zaplanowane zadania wykonywane przez aplikację zapisują wiadomość do wątku i wysyłają lokalne powiadomienie bez treści.
   - **Etap z serwera:** wynik zadania w tle przychodzi pushem (APNs). Wymaga płatnego konta Apple (GO_LIVE A5) i serwera na płatnym planie Render (dziś darmowy zasypia, baza wygasa 10 lis).
4. **Załączniki od Dodiego** (dokument z `make_document`, PDF): bąbel z podglądem, otwarcie przez arkusz udostępniania. Dokument zostaje linkiem, nie kopiowany do wątku, dopóki nie zdecydujesz inaczej.

## Etapy i wysiłek

| Etap | Co | Wysiłek | Zależności |
|---|---|---|---|
| E1 | Wiadomości od Dodiego z Twoich przypomnień i zadań zaplanowanych (lokalnie), znaczek na Home, ekran „Dodi pisze sam" | M | brak |
| E2 | Karty do zatwierdzenia w wątku (przypomnienie, lista, notatka) + narzędzia `propose_*` na serwerze | M–L | E1; serwer na stałe włączony |
| E3 | Załączniki od Dodiego (dokumenty) i „Wyślij do Dodiego" z menu Udostępnij | M | E2 |
| E4 | Push z serwera: wynik zadania w tle | M | płatne konto Apple, płatny Render |
| E5 | Reakcje, odpowiedź na wiadomość, zdjęcia i notatki głosowe od Ciebie | L | decyzje poniżej |

## Koszt

Tekst jest dużo tańszy niż głos: odpowiedź Haiku to rzędu 0,0006 $ (szacunek z `docs/architecture/WEB_AND_SHARED_PLATFORM.md`), minuta głosu to ok. 0,04–0,09 $. Zachęcanie do pisania tam, gdzie głos nie jest potrzebny, to jeden z najtańszych sposobów obniżenia rachunku. W cenniku plan Free mógłby dostać np. 20 wiadomości dziennie (dziś limit serwera: 100 na konto, 1 000 na serwer). Do potwierdzenia po pierwszym prawdziwym użyciu Claude'a, które jeszcze nie miało miejsca.

## Ryzyka

- Powiadomienia z treścią na ekranie blokady (rozwiązanie: bez treści).
- Wiadomości wrażliwe w pushu przez serwery Apple i Anthropic (rozwiązanie: push niesie tylko identyfikator, treść pobiera aplikacja po odblokowaniu).
- Poczucie nachalności (rozwiązanie: domyślnie wyłączone, limit 3 dziennie, cisza, „Wycisz").
- Zatwierdzanie bez czytania (rozwiązanie: karta zawsze pokazuje dokładną treść; brak automatycznych akcji).
- Zakres: Watch i Mac są wstrzymane (ADR-572), nie dotyczy.

## Decyzje właściciela

1. **Co ma przychodzić samo.** Rekomendacja: wynik zleconego zadania, Twoje przypomnienia, zadania zaplanowane przez Ciebie. Nic więcej.
2. **Limit i cisza.** Rekomendacja: najwyżej 3 dziennie, cisza 22:00–7:00.
3. **Czy pisany Dodi dostaje narzędzia `propose_*`.** Rekomendacja: tak, w E2, tylko z kartą do zatwierdzenia.
4. **Kolejność.** Rekomendacja: E1 → E2 → E3 → E4. E4 czeka na płatne konta (Apple, Render).
5. **Czy kolejne po E3 to reakcje, zdjęcia czy notatki głosowe.**
