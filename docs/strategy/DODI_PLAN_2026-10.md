# Dodi: lista funkcji, koszty, cennik i wejście na rynek (24 paź 2026)

Wersja robocza do decyzji właściciela. Pełne źródła i daty: `docs/research/2026-10-24/`. Oznaczenia: **[V]** sprawdzone na stronie źródłowej, **[S]** źródło wtórne, **[I]** wniosek własny. Nic poniżej nie jest zbudowane ani sprawdzone na telefonie, chyba że tak napisano. Zgodnie z konstytucją Dodiego: żadnych funkcji, które wymuszają poczucie winy, udają uczucia albo robią coś na zewnątrz bez zatwierdzenia dokładnej treści.

## 1. Najważniejsze wnioski

1. **Wyspa się zacinała z konkretnych powodów** (ADR-604, poprawione w kodzie): callback „Dodi mówi / myśli" z ElevenLabs nigdy nie odpalał, więc wyspa stała na „Listening" i nigdy się nie rozwijała; aktualizacje wyspy ustawiały się w kolejkę; fale na Home szły w 120 Hz. Nie sprawdzone na telefonie.
2. **Koszt to prawie wyłącznie opłata platformy ElevenLabs: 0,08 $ za minutę połączenia na każdym planie [V]**, LLM to ok. 0,0065 $/min (ok. 7%). Zmiana modelu w ElevenLabs prawie nic nie oszczędza. Oszczędza dopiero własny „kaskadowy" potok (STT + tani LLM + TTS): ok. 0,024–0,034 $/min, czyli o ok. 60–70% taniej [I, wymaga testu polskiego głosu].
3. **Apple nie wesprze Dodiego po polsku**: Apple Intelligence w iOS 27 ma 16 języków bez polskiego, Siri AI jest po angielsku i nie jest na iPhone'ach w UE [V/S]. Dla polskiego użytkownika przewagą Dodiego jest własny „mózg" w chmurze; wejścia to Action Button, Back Tap, NFC, widgety, linia telefoniczna, nie „Hey Siri".
4. **Darmowa wersja musi być prawie bez chmury**: ok. 1 minuta głosu na użytkownika miesięcznie średnio [I].
5. Konkurencja pokazuje, co działa: **Tolan** (głosowy kosmita, tryb rodzinny) zebrał 30 mln $ w paź 2026 [S]; **Poke** (agent w iMessage) kupił Cognition [S]; OpenAI **wycofało Pulse**, zostawiło zadania zaplanowane przez użytkownika [S].

## 2. Pełna lista funkcji

Wysiłek: S (dni), M (1–2 tyg.), L (miesiąc+). Plan: Free / Mate / Pro. „Jest" = już w repo (nie sprawdzone na telefonie, poza oznaczonymi w STATUS.md).

### A. Wejście jednym ruchem
| Funkcja | Stan / pomysł | Wys. |
|---|---|---|
| Action Button, Back Tap, Control Center, ekran blokady | jest | |
| Dynamic Island z całym Dodim i falami | jest, właśnie naprawiane | |
| **Dodi w StandBy, poziomo, na Watch i w CarPlay** (Live Activity w iOS 27 odbija się na Watch Smart Stack, pasku menu Maca i CarPlay) [V] | nowe, tanie | S–M |
| **Tag NFC „Dobranoc" / „Samochód"** (alarm + jutrzejszy plan + tryb Sen; po wejściu do auta poranny brief) | nowe | S |
| Widget z przyciskiem do dowolnego skrótu (`RunSystemShortcutIntent`, iOS 27) [V] | nowe | S |
| Camera Control / wizualne wyszukiwanie: „wskaż aparatem, znajdź instrukcję / paragon" (Visual Intelligence `IntentValueQuery`) [V] | nowe | M |
| **„Zadzwoń do Dodiego"**: polski numer Twilio podłączony do tego samego agenta ElevenLabs; hasło przed dostępem do pamięci; 2,90 $/mies. + ok. 0,09 $/min [V] | nowe | M |
| CarPlay „voice-based conversational app" (iOS 26.4, wymaga zgody Apple) [S] | później | L |
| Wejście głosem „Hey Siri" po polsku | **niemożliwe teraz** (Siri AI bez polskiego) | |

### B. Pamięć i porządek
| Funkcja | Opis | Wys. |
|---|---|---|
| Zapis z menu „Udostępnij": zrzut, link, paragon → notatka ze źródłem | rozszerzenie jest, dopracować | S |
| **Skarbiec paragonów i gwarancji** z przypomnieniem o końcu terminu zwrotu | nowe | M |
| Notatki w Spotlight (`IndexedEntity`) | nowe | M |
| Provenance, poprawki, eksport, usuwanie, Face ID | jest | |
| Przygotowanie do wizyty i notatka głosowa po wizycie | nowe | M |
| Zadania dłuższe niż 30 s (analiza dokumentu) bez zrywania (`LongRunningIntent`, `BGContinuedProcessingTask`) | nowe | M |

### C. Codzienność
| Funkcja | Opis | Wys. |
|---|---|---|
| **Zadania zaplanowane przez użytkownika** („w dni robocze 7:30 przeczytaj mój dzień"), lista, pauza, godziny ciszy | to przetrwało po wycofaniu Pulse [S]; zamiast „kanału wiadomości" | M |
| Poranny brief jako zaplanowana Live Activity (iOS 26 API) [V] | nowe | S–M |
| Gmail „co wymaga mojej uwagi": tylko szkice, bez wysyłki | część jest | M |
| Pisma urzędowe po polsku (reklamacja, wypowiedzenie) jako szkic | nowe | S |
| Tracker subskrypcji z paragonów + szkic rezygnacji | nowe | M |
| Obserwator ceny: tylko alert, nigdy zakup | nowe | M |
| BLIK: prośba o zwrot, dzielenie rachunku (szkic, Dodi nigdy nie wysyła) | rozszerzenie jest | S |
| Tłumacz, kalendarz, przypomnienia, alarmy, listy, zakupy | jest | |

### D. Rodzina
| Funkcja | Opis | Wys. |
|---|---|---|
| **Krąg rodzinny**: wspólne listy i przypomnienia, zgoda per element | napęd wzrostu Tolana [S] | L |
| Linia telefoniczna dla rodzica bez aplikacji + cotygodniowe podsumowanie, które rodzic zatwierdza | wymaga numeru z A | M |
| Przypomnienia o lekach bliskiej osobie głosowo, za jej zgodą | nowe | M |
| Własne „szturchnięcia" („zadzwoń do babci w niedzielę"), nigdy poczucie winy | nowe | S |

### E. Praca i sprawy do załatwienia
| Funkcja | Opis | Wys. |
|---|---|---|
| **Zlecenie „porównaj oferty"**: Dodi dzwoni do 3 firm, tabela; brak odpowiedzi = „nieznane" | rozszerza „call cases" | M |
| Nagrywanie spotkań z banerem zgody | jest (Capture) | |
| Numer zwrotny dla rozmów Dodiego, streszczenie poczty głosowej | nowe | M |
| Zadania w tle (errands) | jest, wyłączone | |

### F. Zdrowie i dobrostan (opcjonalne, wrażliwe dane)
| Funkcja | Opis | Wys. |
|---|---|---|
| Leki: przypomnienie przez AlarmKit + `HKMedicationDoseEventType`; „wzięłam" to słowo użytkownika | nowe | M |
| Notatki o nastroju (prywatne, ścieżka kryzysowa 112) | nowe | M |
| Oddech, timer skupienia | jest | |

### G. Zaufanie i bezpieczeństwo (to sprzedaje)
| Funkcja | Opis | Wys. |
|---|---|---|
| **Paragony działań**: szkic → zatwierdzone → wysłane → potwierdzone albo „nieznane" | zgodne z konstytucją | S–M |
| Sprawdzanie oszustw po polsku (fałszywy kurier, BLIK, „wnuczek") | nowe | M |
| Panel uprawnień z jednym dotknięciem odwołania | nowe | S |
| Interaktywne karty zatwierdzeń na wyspie (`SnippetIntent`) i cofanie (`UndoableIntent`) | nowe | M |

### H. Postać i radość (bez manipulacji)
Stany Dodiego z paczki póz (słucha, czeka na zatwierdzenie) jako interfejs, nie uczucia; wyzwania bez karania za przerwę i bez „tęskniłem"; miesięczna pamiątka z zapisanych chwil (zgoda per element); krótkie gry głosowe po polsku.

### I. 15 trików iPhone'a, które Dodi może podać gotowe (użytkownik dotyka końcowego „Dodaj")
1. NFC przy łóżku „Dobranoc". 2. Bluetooth auta: tryb jazdy + „zapamiętaj gdzie zaparkowałem". 3. Po podłączeniu ładowarki po 21:00: podsumowanie dnia. 4. Wyjście/przyjście z domu: „klucze, portfel, leki?". 5. Ton zależny od Focus (Jazda = tylko głos). 6. Zmiana kontekstu po Wi‑Fi (praca/dom). 7. Bateria < 20%: Tryb Niskiego Zużycia + szkic wiadomości „telefon pada" (zatwierdzenie). 8. Chwila namysłu przed otwarciem wybranych aplikacji. 9. Wyłączenie trybu samolotowego za granicą: numer alarmowy, waluta, zwroty, tłumacz. 10. Back Tap 2.0: podwójne = rozmowa, potrójne = „zapamiętaj ten ekran". 11. Jedno menu pod Action Button (rozmowa / notatka / tłumacz / zdjęcie do pamięci). 12. Camera Control: znajdź instrukcję/paragon. 13. StandBy jako nocna lampka z Dodim. 14. Leki z HealthKit + AlarmKit. 15. Zrzut ekranu do pamięci (wyzwalacz w iOS 27 doniesiony, niepotwierdzony [S]).

## 3. Koszt i tańsze modele

Ceny z oficjalnych stron, pobrane 23–24 paź 2026 [V], szczegóły w `research_costs.md`.

| Wariant | $/min głosu | 30 min/mies. | 100 min | 400 min |
|---|---|---|---|---|
| A. ElevenLabs teraz (cena katalogowa 0,08 + LLM 0,0065) | 0,0865 | 2,60 | 8,65 | 34,60 |
| A. tak jak zmierzono (79 s = ok. 0,05 $) | ok. 0,038 | 1,14 | 3,80 | 15,19 |
| B. OpenAI gpt-realtime-2.1-mini (cache trafia / nie trafia) | 0,018 / 0,079 | 0,54 / 2,38 | 1,79 / 7,92 | 7,16 / 31,69 |
| C. Gemini 3.8 Live (najlepiej / planowo / najgorzej) | 0,013 / 0,03 / 0,053 | 0,38 / 0,90 / 1,59 | 1,26 / 3,00 / 5,31 | 5,04 / 12,00 / 21,22 |
| **D1. Soniox STT + gpt-6-luna + ElevenLabs v4 Turbo** | **0,024** (0,034 z LiveKit) | 0,71 | 2,36 | 9,45 |
| D2. Soniox STT + LLM + Soniox TTS | 0,014 | 0,41 | 1,38 | 5,50 |
| E. 40% na urządzeniu, 60% D1 | 0,014 | 0,43 | 1,42 | 5,67 |

Założenia [I]: 45% czasu mówi Dodi, prompt + 92 narzędzia ≈ 9 000 tokenów (do zmierzenia). **Nie zgadza się**: zmierzone 0,05 $ za 79 s jest o połowę niższe niż cena katalogowa; sprawdź w panelu ElevenLabs, zanim cokolwiek zmienisz.

**Rekomendacja:** (1) zostać na ElevenLabs do startu bety; (2) zrobić **test polskich głosów** (STT: Scribe vs Soniox; TTS: ElevenLabs vs Cartesia vs Soniox; cyfry, nazwiska, angielskie słowa), potem zbudować potok D1 na serwerze Node (lub LiveKit); (3) gpt-realtime-2.1-mini i Gemini jako rywale do testu; (4) tanie rzeczy lokalnie bez LLM: minutniki, alarmy, połączenia przez App Intents; **Apple Foundation Models nie obsługuje polskiego, więc nie jest rozwiązaniem [S]**; (5) limity na użytkownika i „naciśnij, żeby mówić".

**Dziesięć sposobów na niższy rachunek** (oszczędność względem A, szacunek [I]): potok D1 −73%; cache promptu w realtime −79% jeśli trafia; koniec rozmowy po 20–30 s ciszy i limit 5 min −5…15%; naciśnij-aby-mówić −20…40% minut; limity użytkownika z dokupowaniem; lokalne proste polecenia −20…40% minut chmury; krótsze odpowiedzi −20…30% części TTS; tańsze STT/TTS po teście polskiego; mniej narzędzi na intencję (tylko opóźnienie i trafność, poniżej 0,003 $/min); Sonnet zamiast Opusa do zadań w tle −50% za token, Batch kolejne −50% [V].

## 4. Co darmowe, co płatne

Punkt wyjścia: `docs/business/MONETIZATION_MODEL_V2.md`, zweryfikowany z rynkiem (`research_business.md`). Przy 0,05 $/min stary plan 60 min w Best Mate daje marżę 46–62%, poniżej celu 50%; **40 min daje 59–70%**. 5% płacących to górny kwartyl; planować **2–3%** [V]. Cena: ChatGPT Go 34,99 zł, Google AI Plus 23,99 zł [S], więc 44,99 zł jest wysoko. Testować **dwie** ceny, nie trzy.

| Plan | Cena | Zawartość |
|---|---|---|
| **Pocket Doddy (Free)** | 0 | pamięć, wyszukiwanie tekstu, listy, przypomnienia, eksport/usuwanie, Face ID; dyktowanie Apple; jednorazowe 3 min głosu na start; bez AI w chmurze |
| **Best Mate** | 34,99–49,99 zł/mies. (test), ok. 349,99 zł/rok | 7 dni próby po pierwszym zapisie (10 min głosu, ok. 0,47 €); potem 40 min głosu/mies. (30 w planie rocznym), 300 odpowiedzi, działania w Kalendarzu/Przypomnieniach |
| Pakiet głosu 30 min | 19,99 zł | dokupienie |
| Pro (po 8–12 tyg.) | ok. 99,99 zł/mies. | 80 min głosu + 10 min „na żywo" + 50 „pomyśl głębiej" |
| Crew (gdy płaci ≥4%) | 79,99 zł | do 6 osób, 80 min wspólnie |
| Founding Mate | 499,99 zł jednorazowo, 500 miejsc | uprawnienia Best Mate, uczciwe użycie (do ok. 39 tys. € netto) |

Nigdy za paywallem: eksport, usuwanie, informacja „to jest AI", komunikaty bezpieczeństwa [I]. Minuty trzymać jako konfigurację serwera, nie w aplikacji. Plan przeciwko benchmarkom [V, RevenueCat 2026]: instalacja → płacący 2,0–2,5%; próba → płatny 25–30%; miesięczny odpływ AI ok. 21%; zwroty ok. 4–5%. Cena dla dużego użytkownika 400 min na obecnym stosie to 34,60 $ miesięcznie, więcej niż abonament, więc limity są konieczne.

Dodatkowe źródła przychodu do rozważenia [I]: rodzinny Crew; sprzedaż w sieci przez Stripe/BLIK (po sprawdzeniu zasad App Review dla wielu platform); partnerstwa z operatorem lub bankiem (nic nie znaleziono, [I]).

## 5. Wejście na rynek: 90 dni (26 paź – 24 sty)

Budżet: oszczędnie ok. 2,5–4 tys. €, rozszerzony 12–16 tys. € [I].
1. **Tyg. 1–4 (1,5–4 tys. €):** zamknąć punkty A4/A5/C1/C2 z `GO_LIVE_CHECKLIST.md` (płatny zespół Apple, identyfikator aplikacji, wyłączenie braku uwierzytelniania agenta, limity wydatków Anthropic); rekord w App Store Connect, Small Business Program (15%), zgłoszenie do wyróżnienia Apple (min. 2 tyg. do 3 mies. wcześniej [V]); poprawić zgodę w liście oczekujących, kolejka poleceń; 3–5 krótkich polskich filmów tygodniowo z postacią (humor, nie poczucie winy); 10 mikrotwórców z TestFlight.
2. **Tyg. 5–8 (0,5–2 tys. €):** zewnętrzny TestFlight 20–24 osoby spoza znajomych, potem 100–300; mierzyć aktywację, rzeczywisty koszt za minutę, opóźnienie pierwszego dźwięku ≤1,2 s; test cen; wywiady.
3. **Tyg. 9–13 (2–6 tys. €), tylko po spełnieniu progów:** premiera 12–19 stycznia (zgłoszenie przed 18 grudnia lub po 28 grudnia [I]); prasa pod embargiem dwa tygodnie wcześniej (Antyweb, Spider's Web, Tabletowo, iMagazine, Telepolis); 10–20 mikrotwórców po ok. 500–3 000 zł; Product Hunt dla linków. Płatna reklama tylko poniżej 20 € za płacącego.
Dalej: rynki anglojęzyczne organicznie, Niemcy po czytaniu przez native speakera, sprzedaż w sieci w USA.

**Progi wejścia/wyjścia (z planu 10 paź):** aktywacja ≥50%, próba → płatny ≥25%, płacący ≥4% w 3. miesiącu.

## 6. Wymogi prawne przed startem
Apple 5.1.2(i): wyraźna zgoda z nazwą dostawcy zanim dane trafią do zewnętrznego AI; 2.5.14 wskaźnik nagrywania; 5.1.1(v) usuwanie konta; 4.8 logowanie; 3.1.2 opis próby i ceny [V]. Unijny AI Act art. 50: poinformować, że to AI (obowiązuje od 2 sie 2026 [S]); zapytać ElevenLabs o oznaczanie audio. RODO: umowy powierzenia (ElevenLabs, OpenAI, Anthropic itd.), DPIA, ustawić retencję agenta zamiast „bez limitu"; rezydencja danych w UE u ElevenLabs tylko w Enterprise [S]. Wiek: kwestionariusz Apple, Declared Age Range, minimum 16 lat [I]. Prawo konsumenckie: polskie warunki, ceny z VAT, 14 dni odstąpienia. **Nagrywanie rozmów telefonicznych i tłumacz: opinia prawnika przed uruchomieniem [I, nie sprawdzone].**

## 7. Decyzje właściciela (w kolejności ważności)
1. Dodać `agent_tool_request` do zdarzeń klienta żywego agenta ElevenLabs (nie ruszałem agenta).
2. Włączyć uwierzytelnianie agenta i ustawić limit retencji nagrań; ustawić limit wydatków na kluczu Anthropic.
3. Zatwierdzić test polskich głosów STT/TTS i budowę potoku D1.
4. Wybrać dwie ceny do testu i zatwierdzić 40 min w Best Mate.
5. Zdecydować o numerze „Zadzwoń do Dodiego" (Twilio) i haśle.
6. Płatny plan Render przed usunięciem darmowej bazy 10 listopada.

## 8. Czego nie udało się sprawdzić
Czy wyspa po poprawce naprawdę mówi „Speaking" i płynie (brak telefonu i Xcode; CI na Macu kompiluje); polska obsługa SpeechTranscriber i głosu systemowego; jakość polskiego TTS u Cartesii i Soniox; powód, dla którego rzeczywisty koszt jest o połowę niższy niż katalogowy; dostępność Apple Messages for Business dla małego dewelopera w Polsce; ceny Claude/Perplexity w PLN; stawka Twilio dla polskich numerów komórkowych i głos na nich; prawo nagrywania rozmów.
