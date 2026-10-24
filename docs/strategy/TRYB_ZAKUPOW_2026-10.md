# Doddy na zakupach: propozycja trybu zakupów (24 paź 2026)

Wersja robocza do decyzji właściciela. **Nic z tego nie jest zbudowane.** Makiety i przykładowy raport: `design/shopping-mode-v0.1/` (wszystkie ceny w nich są zmyślone i tak oznaczone). Research ze źródłami i datami: `docs/research/2026-10-24/research_shopping_offers.md`, `research_shopping_payments.md`, `research_shopping_leaflets.md`. Oznaczenia jak w `DODI_PLAN_2026-10.md`: **[V]** sprawdzone na stronie źródłowej, **[S]** źródło wtórne, **[I]** wniosek własny.

## Brief właściciela (24 paź)

Tryb zakupów: Doddy znajduje dowolną rzecz i najtańszą opcję, czyta gazetki (Biedronka i inne), robi krótki raport PDF w stylu Doddy'ego tanim modelem, użytkownik mówi, co jest dla niego najważniejsze; później płatność w aplikacji (Apple Pay, BLIK). Ma być prosto.

## 1. Najważniejsze wnioski

1. **Trzy rzeczy, nie jedna:** *Gazetki* (najtaniej w tym tygodniu i koszyk: jeden sklep czy dwa), *Znajdź mi to* (dowolna rzecz, 3 propozycje, raport) i *Kup i pilnuj* (przejście do sklepu, alert o spadku ceny).
2. **Gazetki na start bez wspólnej bazy.** Kaufland, Carrefour i inne blokują automaty, agregatory nie mają API, a wspólny indeks wszystkich gazetek bez licencji przypomina sprawę *CV-Online* (TSUE) [V/I]. Etap 1: odczyt na żądanie z oficjalnych gazetek Lidla, Biedronki, Dino i Rossmanna, reszta jako link; licencja od agregatora w etapie 2.
3. **Większość infrastruktury już jest:** sprawy w tle na serwerze (ADR-570, wyłączone), jedna zgoda na wszystkie wyszukiwania sprawy, wynik w stałym schemacie z regułą „żadnej ceny bez strony”, push, szyfrowanie, karty zgody, pamięć z „Zapamiętać?”. Nowe są: wynik „zakupy”, sprawdzian ceny w kodzie, baza gazetek, pilnowanie cen, ekrany i raport.
4. **Sklepy blokują boty** (Allegro, x-kom, Media Expert, RTV Euro AGD; Amazon.pl i Ceneo blokują boty Claude w robots.txt) [V]. Samo wyszukiwanie i pobieranie stron Anthropic nie wystarczy. Potrzebne jest jedno porządne źródło ofert: **Google Shopping przez dostawcę API** (SearchApi ok. 3–4 $ za 1000 zapytań, SerpApi 10–25 $) [V], a strona sklepu służy do sprawdzenia ceny, kiedy się da.
5. **Publiczne API ofert Allegro nie istnieje** od 16 wrz 2026, a regulamin zabrania pokazywania ofert Allegro w konkurencyjnych serwisach [V]. Allegro wchodzi pośrednio (Google Shopping) albo przez link partnerski.
6. **Płatność w aplikacji: nie w pierwszej wersji.** Rzeczy fizyczne nie mogą iść przez zakupy w aplikacji Apple (3.1.3(e)) [V]; zbieranie pieniędzy klienta i płacenie sklepowi to usługa płatnicza wymagająca licencji KNF [V/I]. Protokoły „zakupu przez asystenta” są w wersjach testowych: Stripe (Polska na liście, karty i Apple Pay, **bez BLIK-a**) [V], Google tylko USA/CA/AU [V], OpenAI wycofało Instant Checkout w marcu 2026 [V]. BLIK dla asystentów to pilotaż (PayU, 14 wrz 2026) [V]. Żaden polski sklep nie przyjmuje jeszcze zakupów od zewnętrznych asystentów [I].
7. **Raport PDF nie potrzebuje modelu do składania pliku.** Tani model (Haiku 5.5: 0,10 $ / 0,50 $ za milion tokenów [V]) pisze tylko krótkie zdania do stałych pól; iPhone składa PDF z szablonu. Koszt pliku: 0 zł, a każdy raport wygląda tak samo.
8. **Koszt:** pytanie o gazetki ok. 0,01 $ (odczyt 1–3 wycinków); z licencją i wspólną bazą ułamek grosza, a czytanie wszystkich gazetek ok. 3–13 $ miesięcznie plus licencja; „Znajdź mi to” ok. 0,10–0,15 $ (do 0,45 $ z ponowieniami) [I, z cen V].

## 2. Jak to działa (makiety: `design/shopping-mode-v0.1/index.html`)

### A. Gazetki
1. „Gdzie w tym tygodniu najtaniej masło, pampersy czwórki i kawa?” (głos albo Wiadomości).
2. Wynik: najniższa cena z **warunkami** (aplikacja sklepu, limit sztuk, data końca) i ceną za kg/l, w linijce pod spodem najtańsza bez warunków i inne sklepy; data gazetki i godzina odczytu; każda cena ma stronę gazetki, z której pochodzi; sieci, których nie sprawdzono, są wymienione z linkiem do gazetki.
3. Koszyk z listy: najtańszy jeden sklep, najtańsza para sklepów i ile to oszczędza. **Sumy liczy kod**, nie model. Doddy nie namawia na objazd za kilka złotych. Rozpisanie na listy po karcie z ich treścią.

### B. Znajdź mi to
1. Jedno pytanie: „Co jest najważniejsze? Stuknij po kolei” (cisza, cena, gwarancja…). To jest „opisz, co najważniejsze” z briefu.
2. Karta „Przekazać to Doddy'emu?” z dosłownymi słowami użytkownika: istniejąca sprawa (ADR-570), jedna zgoda obejmuje wyszukiwania tej sprawy i nic więcej; nic nie jest kupowane ani wysyłane.
3. W tle: postęp na ekranie blokady (Live Activity, nowe), push bez treści sprawy (jak dziś).
4. Wynik: **trzy propozycje** (mój wybór według kolejności użytkownika, najtańsza, jedna ponad budżet z dopłatą na wierzchu), przy każdej cenie sklep, dostawa i godzina sprawdzenia; przyciski Kup w sklepie, Raport PDF, Pilnuj ceny.
5. Raport PDF (2 strony A4): słowa użytkownika, kolejność, wybór z powodem, tabela 4 ofert, „jak wybierałem”, na co uważać, odrzucone i dlaczego, **czego nie wiem**, co dalej, źródła z godziną otwarcia. Przykład: `design/shopping-mode-v0.1/report/raport-przyklad.pdf`.

### C. Kup i pilnuj
1. **Etap 1:** „Kup w Media Expert” otwiera stronę sklepu w aplikacji; płaci się tam (Apple Pay, BLIK, karta). Doddy zapisuje „przekazane do sklepu”, nigdy „kupione”. Link partnerski oznaczony przy przycisku.
2. **Etap 2:** „Daj znać, jak spadnie poniżej 1800 zł”: tylko powiadomienie, nigdy zakup; kilka sprawdzeń dziennie, koniec po 30 dniach albo na „przestań”; utworzenie po karcie z dokładną treścią (to zmiana po stronie serwera).
3. **Etap 3:** arkusz Apple Pay w Doddym ze sklepem jako sprzedawcą, tylko ze sklepami podłączonymi przez protokół zakupów; zgoda na dokładny koszyk; „zamówione” dopiero po potwierdzeniu sklepu (webhook), inaczej „nie wiem, sprawdź maila od sklepu, nie ponawiam”.

## 3. Infrastruktura

| Gdzie | Element | Stan |
|---|---|---|
| iPhone | Głos i Wiadomości, karty zgody, pamięć „Zapamiętać?” | jest |
| iPhone | Ekrany Najtaniej, Koszyk, 3 propozycje, Pilnuję | nowe |
| DoddyCore | Liczenie koszyka (czysta funkcja: najtańszy 1 sklep, para, wszystkie; testy na Linuksie) | nowe |
| iPhone | Raport PDF z szablonu SwiftUI z zatwierdzonego wyniku | nowe |
| iPhone | Strona sklepu w aplikacji (Safari), zapis `handed_off` | nowe |
| serwer `server/messaging` | Sprawy w tle, zgoda z digestem, worker, push, szyfrowanie | jest (`ERRANDS_ENABLED=0`) |
| serwer | Wynik „zakupy”: oferty z ceną, walutą, sklepem, dostawą, GTIN, godziną i poziomem pewności (`shop_page` / `listing`) | nowe |
| serwer | Sprawdzian ceny: kod pobiera stronę oferty i czyta cenę z danych schema.org; bez tego cena spada do „z listy” albo znika | nowe (zaostrza dzisiejszą regułę, która sprawdza tylko, czy URL był w przebiegu) |
| serwer | Gazetki na żądanie: pobranie oficjalnej gazetki, zawężenie stron, wycinki do Haiku, walidacja; nic nie zostaje. Etap 2 (z licencją): baza ofert (sieć, produkt, gramatura, cena, cena za kg/l, warunek, ważność, strona, czas odczytu, pewność) | nowe |
| serwer | Pilnowanie cen: tabela, harmonogram, push, wygasanie | nowe |
| na zewnątrz | Oferty: SearchApi/SerpApi (Google Shopping, `gl=pl`), potem feedy partnerskie (Webepartners, Tradedoubler, Admitad) | nowe |
| na zewnątrz | Gazetki: oficjalne strony Lidla, Biedronki, Dino i Rossmanna; licencja od agregatora w etapie 2 (sekcja 4) | nowe |
| na zewnątrz | Claude Haiku 5.5 (czytanie stron i gazetek, krótkie zdania), Sonnet 5.5 (wybór i „dlaczego”) | nowe; sprawy dziś idą na Opusie 5.5 |

Zasady egzekwowane w kodzie, nie w promptcie (konstytucja): cena tylko ze strony, którą przebieg otworzył (DOD-02); koszyk liczony w kodzie; zgoda na dokładną treść przed każdą zmianą (DOD-07, ASK-01); „zamówione” tylko po potwierdzeniu dostawcy, „nieznane” nigdy nie jest sukcesem i nie jest ponawiane (DOD-08); treść stron i gazetek to dane, nie polecenia; żadnego „tylko dziś, kup teraz” (DOD-10); prowizja nie zmienia kolejności i jest oznaczona.

## 4. Skąd dane

**Oferty sklepów** (szczegóły: `research_shopping_offers.md`): v1 Google Shopping przez jednego dostawcę API + sprawdzenie strony oferty w kodzie; v1.1 feedy partnerskie (dane na licencji i przychód). Pomijamy API Allegro (brak wyszukiwania ofert, zakaz w regulaminie), skrobanie i Amazon (do czasu kwalifikujących się sprzedaży).

**Gazetki** (szczegóły: `research_shopping_leaflets.md`):

- **Jak sieci publikują gazetki** [V]: Lidl (czytnik i PDF, tekst stron i daty w danych), Biedronka (same obrazy stron), Dino (strony z EAN, nazwą i ceną), Rossmann (produkty z EAN, ceną, ceną za jednostkę i „ceną z apką”). Kaufland, Carrefour, Hebe, Intermarché, Pepco i Action blokują automaty; Auchan, Netto i Żabka mają zewnętrzne czytniki.
- **Agregatory** (Blix, Ding i Okazjum Interii, Gazetki.pl, Moja Gazetka, Kimbino, Tiendeo) nie mają publicznego API ani programu partnerskiego na dane, a regulaminy zabraniają kopiowania [V]. Dostęp tylko przez licencję.
- **Prawo** (nie porada prawna): wyszukiwarka, która kopiuje i indeksuje dużą część cudzej bazy, może naruszać prawo do bazy danych (TSUE *CV-Online*, C‑762/19) [V]; **wspólny indeks wszystkich gazetek bez licencji to ten przypadek** [I]. Ceny to fakty, ale zdjęcia i układ gazetki to utwory: bez licencji ich nie przechowujemy ani nie pokazujemy. Wyjątek na eksplorację tekstu i danych (art. 26³ pr. aut., od 20.09.2024) pozwala kopiować do analizy, nie udostępniać [V/I]. Blokad nie obchodzimy.
- **Rekomendacja na etap 1:** odczyt **na żądanie** z oficjalnych gazetek Lidla, Biedronki, Dino i Rossmanna: po pytaniu pobieramy gazetkę, tekstem strony (albo OCR na telefonie) zawężamy do kandydatów, 1–3 wycinki stron idą przez serwer Doddy'ego do Haiku 5.5 (ok. 0,01 $ za pytanie); **nic nie zostaje na serwerze**, żadnej wspólnej bazy. Pozostałe sieci: link do gazetki i „nie sprawdzone”. Równolegle prośba o licencję (Grupa Blix, Interia, Moja Gazetka, Kimbino B2B, Tjek); z licencją w etapie 2 wspólna baza i szybszy koszyk.
- **Jakość odczytu:** modele dobrze czytają cenę główną (88–92% w badaniach), słabo cenę regularną (32–49%), rabat i cenę za jednostkę [V]; polskiego testu brak. Kod sprawdza rachunki (cena za kg z ceny i gramatury, rabat z ceny regularnej), niepewne oznacza; przed startem polski test na ok. 50 stronach.
- **Konkurencja** [V]: Moja Gazetka (4,74, 18 tys. ocen), Blix (4,77), Gazetkowo (4,83), Okazjum (4,67), Listonic (4,75): wszystkie do przeglądania. Tańszy Koszyk (www): 12 sieci, warunki, zamienniki, „8 z 10 rzeczy”; według niego **91% produktów z gazetek jest tylko w jednej sieci** [S], więc porównujemy po cenie za kg/l i podobnym produkcie, a Doddy mówi, gdy porównuje różne marki.

**Omnibus:** od 1 sty 2023 każda ogłoszona obniżka musi pokazywać najniższą cenę z 30 dni przed nią (art. 4 ust. 2 ustawy o informowaniu o cenach) [S]. Doddy porównuje obniżkę z tą ceną, nie z „ceną regularną”. UOKiK ukarał za to Zalando (30,9 mln zł) i Temu (5,9 mln zł), decyzje nieprawomocne [S].

## 5. Płatności

Szczegóły: `research_shopping_payments.md`. Ranking modeli dla małej polskiej firmy:

1. **Kasa sklepu (etap 1, teraz):** bez licencji i bez umów; sklep jest sprzedawcą (zwroty, reklamacje, 14 dni). Minus: płatność nie jest „w Doddym” i Doddy nie dostaje potwierdzenia, więc mówi tylko „przekazane do sklepu”.
2. **Zakup przez asystenta (etap 3):** arkusz Apple Pay w Doddym, sklep jako sprzedawca, potwierdzenie przez webhook pasuje do konstytucji. Doddy jako „Intermediary Party” w umowie Apple (DPLA §3.3.9(C)): pokazuje sklep na arkuszu, nie używa danych płatności do marketingu, ma pisemną umowę z każdym sklepem [V]. Dziś: wersje testowe, brak BLIK-a, brak polskich sprzedawców.
3. **Doddy jako sprzedawca lub portfel: nie robimy.** Licencja KNF albo agent instytucji płatniczej; zwroty, gwarancje, VAT i chargebacki po stronie Doddy'ego.

Dzisiejsze szkice przelewów BLIK (ADR-510, ADR-541) zostają osobno i nie są rozszerzane na zakupy.

## 6. Koszty

| Co | Czym | Za jedno | Miesięcznie |
|---|---|---|---|
| Pytanie o gazetki (etap 1, na żądanie) | Haiku 5.5 czyta 1–3 wycinki na sieć; kod sprawdza i liczy | ok. 0,01 $ (4 gr) | 10 $ za 1000 pytań |
| Wszystkie gazetki co tydzień (etap 2, z licencją; ok. 1200 stron) | Haiku 5.5, tryb wsadowy −50% | ok. 0,5 gr za stronę | ok. 3–13 $ + licencja |
| Znajdź mi to | dostawca ofert, sprawdzian w kodzie, Haiku, Sonnet | 0,10–0,15 $ (do 0,45 $) | 100–450 $ za 1000 spraw |
| Raport PDF | szablon na iPhonie | 0 zł | 0 zł |
| Pilnowanie ceny (3× dziennie, 30 dni) | pobranie strony i odczyt w kodzie; dostawca ofert, gdy sklep blokuje | ok. 0 $ | do ok. 0,40 $ za rzecz |

Ceny Anthropic [V]: Haiku 5.5 0,10/0,50 $, Sonnet 5.5 2/10 $, Opus 5.5 4/20 $ za milion tokenów; wyszukiwanie 10 $ za 1000. Tokeny to szacunek [I] do zmierzenia na pierwszych przebiegach.

**Plany:** gazetki w darmowym planie z limitem (np. 30 pytań miesięcznie to ok. 0,30 $; dobrze przyciąga); „Znajdź mi to” z limitem w Best Mate (np. 15 spraw miesięcznie, ok. 1,50–2,25 $), więcej w Pro. **Linki partnerskie** (elektronika ok. 0,5–3%) mogą pokryć koszt wyszukiwania z nawiązką: zmywarka za 1899 zł to ok. 10–55 zł prowizji [S/I].

## 7. Inne pomysły (do dołożenia albo zamiast)

- **Prawdziwa promocja?** Link albo zdjęcie ceny → porównanie z najniższą ceną z 30 dni (S).
- **„Czy to dobra cena?” z aparatu** w sklepie → porównanie z gazetkami w okolicy (M).
- **Lista, która sama się liczy:** stała lista tygodniowa, w czwartek rano jedna linijka z najtańszym sklepem; tylko jeśli użytkownik sam to ustawi (S, po gazetkach).
- **Skarbiec paragonów:** zdjęcie paragonu po zakupie → terminy zwrotu i gwarancji z przypomnieniem (M; jest już w `DODI_PLAN_2026-10.md`, sekcja B).

## 8. Plan

- **Etap 1 (ok. 3–4 tyg. pracy, po decyzjach 1–4):** wynik „zakupy” i sprawdzian ceny na serwerze, dostawca ofert, Sonnet dla spraw zakupowych; gazetki na żądanie dla Lidla, Biedronki, Dino i Rossmanna (reszta jako link) i polski test odczytu na ok. 50 stronach; ekrany Najtaniej, Koszyk, 3 propozycje; liczenie koszyka w DoddyCore; raport PDF z szablonu; przejście do sklepu; narzędzia `find_deals` i `hand_over_errand` z rodzajem „zakupy” w specyfikacji agenta (żywy agent tylko po zgodzie właściciela na dokładny tekst).
- **Etap 2 (ok. 2 tyg.):** pilnowanie cen, „prawdziwa promocja?”, feedy i linki partnerskie z oznaczeniem; licencja na gazetki od agregatora: wspólna baza, szybszy koszyk, więcej sieci.
- **Etap 3 (gdy rynek dojrzeje):** zakup przez asystenta (Stripe po wyjściu z wersji testowej i z polskimi sprzedawcami), BLIK po standardzie dla asystentów; opinia prawnika i umowy ze sklepami.

Każdy etap kończy się raportem według `CLAUDE.md` (pliki, zachowanie, testy, czego nie sprawdzono, ryzyka prywatności, decyzje).

## 9. Decyzje właściciela (od najważniejszej)

**Odpowiedzi właściciela z 24 paź 2026** (zapisane w `DECISIONS.md`, ADR-611; numery poniżej): 1 i 2: tak, jak w liście (gazetki na żądanie z 4 sieci, Haiku 5.5 czyta strony). 3: Serper. **4: tylko potwierdzone ceny, a gdy nie ma potwierdzenia, Doddy to mówi** ("daj tylko potwierdzone ceny a jak nie są to powiedz"). **5: karta zgody zostaje.** 6: odpowiedź "tak może być" jest niejednoznaczna (linki partnerskie tak, czy zgoda na rekomendację "nie"); nic nie zbudowano, czeka na doprecyzowanie. **7: Haiku 5.5 dla wszystkich, Sonnet 5.5 dla opcji premium w aplikacji.** 8: odpowiedź "wdrażaj" jest niejednoznaczna (zacząć płatności w aplikacji czy wdrożyć to, co jest); nic nie zbudowano ani nie wdrożono, czeka na doprecyzowanie. 9: bez odpowiedzi.

1. **Skąd gazetki:** na start odczyt na żądanie z oficjalnych gazetek czterech sieci, bez wspólnej bazy; równolegle prośba o licencję (Blix, Interia, Moja Gazetka, Kimbino, Tjek); opinia prawnika od praw do baz danych (sekcja 4).
2. **Nowe użycie AI w chmurze:** Haiku 5.5 czyta wycinki gazetek i strony sklepów (CLAUDE.md, zasada 6: osobna zgoda).
3. **Dostawca ofert i budżet:** SearchApi albo SerpApi; miesięczny limit wydatków i limit na użytkownika.
4. **Cena bez potwierdzenia na stronie sklepu:** pokazywać jako „z listy Google Shopping, 14:02” (niższy poziom pewności) czy usuwać, jak dziś w sprawach.
5. **Gazetki bez karty zgody:** dopisać wyszukiwanie w gazetkach do publicznych wyszukiwań (wyjątek od ASK-01, jak pogoda, ADR-575).
6. **Linki partnerskie:** tak albo nie; jeśli tak, oznaczenie przy przycisku i zasada, że nie zmieniają kolejności.
7. **Model dla spraw zakupowych:** Sonnet 5.5 zamiast Opusa 5.5, z limitem kroków.
8. **Płatność w aplikacji:** odłożona do etapu 3 (rekomendacja); opinia prawnika przed nią.
9. **Plany:** gazetki w darmowym z limitem, „Znajdź mi to” z limitem w Best Mate.

Wciąż otwarte z wcześniej: `ERRANDS_ENABLED=1`, płatny Render (darmowa baza wygasa 10 lis 2026), limit wydatków na kluczu Anthropic.

## 10. Czego nie sprawdzono

Stan z chwili pisania tego dokumentu (przed budową): żaden kod trybu zakupów nie istniał. Etap 1 zbudowano 24 paź 2026 (`docs/implementation/SHOPPING.md`, ADR-607 do 611); nic nie było uruchomione na telefonie ani na prawdziwym API. Nie sprawdzono: jak często prawdziwe strony polskich sklepów mają poprawne dane schema.org z ceną; czy pobieranie stron Anthropic przechodzi przez blokady botów sklepów; jakości odczytu prawdziwych polskich gazetek przez Haiku 5.5 (brak polskiego testu); czy OCR na iPhonie dobrze czyta polskie gazetki; czy Haiku 5.5 obsługuje narzędzia wyszukiwania (sprawdzić w Models API); warunków licencji agregatorów gazetek; opinii prawnej o gazetkach i płatnościach. Ceny dostawców i prowizje z dnia 24 paź 2026, część ze źródeł wtórnych.
