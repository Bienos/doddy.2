# Sekcja „Zakupy" w Doddym: research i opcje do wyboru (11 lis 2026)

Propozycja. **Nic z tego dokumentu nie jest zbudowane, zgłoszone ani podpisane.** Odpowiada na brief właściciela z 11 lis 2026: sekcja e-commerce, w której mówisz „znajdź mi to", dostajesz trzy produkty do porównania z prawdziwymi cenami, możesz ustawić powiadomienie o cenie, a Doddy zarabia na programach partnerskich; do tego pytanie, czy pomagać w płaceniu.

Źródła: trzy badania w sieci z 11 lis 2026 (polskie sklepy i programy partnerskie; globalne API i płatności; UX i zachowania kupujących) oraz kod i dokumenty repo. Oznaczenia: **[P]** przeczytane u źródła, **[S]** tylko prasa lub strona trzecia, **[N]** niesprawdzone, **[Repo]** z kodu lub wcześniejszych dokumentów. Linki do źródeł są w sekcji 9.

## 1. Co już jest w Doddym [Repo]

Większość silnika istnieje. Brakuje jednego miejsca, szybkiej odpowiedzi, ekranu porównania i podpisanych programów.

| Część | Stan | Gdzie |
|---|---|---|
| „Znajdź mi to": zadanie zakupowe, trzy propozycje (najlepsza, najtańsza, premium), tylko ceny potwierdzone na stronie sklepu | Zbudowane i przetestowane na serwerze; działa jako zadanie w tle (minuty, nie sekundy); nie widziane na telefonie | `docs/implementation/SHOPPING.md`, `server/messaging/src/shopping/` |
| Pilnowanie ceny: jedno powiadomienie, gdy potwierdzona cena spadnie do Twojej kwoty; 4 odczyty dziennie przez 30 dni | Zbudowane, **wyłączone na serwerze** (`WATCHES_ENABLED=0`); nie ma narzędzia głosowego | `docs/implementation/SHOPPING_WATCH.md` |
| Linki partnerskie: dopisywane po wyborze propozycji, więc prowizja nie zmienia kolejności (test to sprawdza) | Mechanizm jest; **żaden program nie jest podpisany**, więc nic nie zarabia | `shopping/affiliate.ts`, `docs/strategy/AFFILIATE_NETWORKS_PROPOSAL_2026-11.md` |
| Gazetki: „Najtaniej w tym tygodniu", koszyk | Włączone 10 lis 2026 | `SHOPPING.md` 2 |
| Kupowanie przez Doddy'ego | Zaprojektowane, reguły bezpieczeństwa w kodzie; **nic nie jest podłączone, nic nie da się kupić** | `docs/implementation/SHOPPING_CHECKOUT.md` |

Słabe strony dzisiejszego rozwiązania: oferty pochodzą z Google Shopping (Serper), a duże sklepy często blokują odczyt strony, więc część cen zostaje „niepotwierdzona" i nie jest pokazywana; nie ma zdjęć; wynik przychodzi po minutach; trzy propozycje są schowane w wyniku zadania.

## 2. Co ustalił research

### 2.1 Skąd brać produkty i ceny w Polsce

| Źródło | Co daje | Zarobek | Dostęp | Werdykt |
|---|---|---|---|---|
| **Convertiser** (polska sieć) | REST API i feedy produktów z wielu sklepów, wyszukiwanie; wprost dla aplikacji mobilnych i porównywarek [P] | Prowizja od sprzedaży; Decathlon do 4,5% [P] | Bezpłatne, osoba lub firma, weryfikacja strony, potem zgoda każdego sklepu | **Najlepsze dopasowanie techniczne** |
| **Tradedoubler** Products API | Wyszukiwanie po słowach i EAN, historia cen, linki ze śledzeniem [P]; RTV Euro AGD (1,5% dla porównywarek, 2,5% dla treści) [P], Empik [P], eobuwie i Modivo [S] | Prowizja od sprzedaży | Konto ze stroną, zgoda każdego programu | **Drugie źródło** |
| **Ceneo** Partner API | Wyszukiwanie jak na Ceneo: najniższa i najwyższa cena, liczba sklepów, ocena, zdjęcie; **bez listy ofert sklepów** [P] | Za kliknięcie ze strony Ceneo do sklepu; stawki tylko w panelu | Tylko dla partnerów; dane wolno używać **tylko do promowania Ceneo** i nie wolno ich zmieniać [P] | Jako wiersz „porównaj wszystkie sklepy na Ceneo", nie jako główne źródło |
| **Allegro** | Wyszukiwanie ofert przez API **zamknięte dla nowych aplikacji** (potwierdzane przez Allegro od 2025 do maja 2026) [P] | Allegro Affiliate Business: wymaga konta Allegro Firma i statusu VAT; stawki w panelu [P] | Aplikacja mobilna nie jest wymieniona jako powierzchnia [N] | **Tylko link „zobacz na Allegro", bez ceny** |
| **Amazon.pl** | Stare API wyłączone 15 maja 2026 [S]; nowe (Creators API) wymaga 10 sprzedaży w 30 dni [P] | Prowizja | Aplikacja z linkami Amazon **nie może mieć śledzenia cen ani alertów** [P, wersja .de i .com; .pl nie czytana] | **Tylko link, i nigdy przy alertach** |
| Google Shopping przez dostawcę (Serper dziś; DataForSEO, SerpApi) | Szerokie pokrycie polskich sklepów | Brak | Samoobsługa; ryzyko prawne (spór Google z SerpApi w toku, wynik nieznany [N]) | Zostaje jako uzupełnienie, z potwierdzeniem ceny na stronie sklepu |
| **Shopify Global Catalog** | Od czerwca 2026 wyszukiwanie we wszystkich sklepach Shopify, filtr kraju dostawy, link do kasy sklepu [P] | 0,3% i tylko na zaproszenie [P] | Samoobsługa, bezpłatne; cena w pamięci najwyżej 10 minut, zakaz automatycznego zbierania [P] | Dobre na małe marki i rynki zagraniczne; duże polskie sklepy rzadko są na Shopify (wniosek, nie pomiar) |
| **Channel3** (agregator dla asystentów AI) | Produkty, oferty z wielu sklepów, historia cen, powiadomienia o zmianie ceny [P] | Linki partnerskie wbudowane; Channel3 zatrzymuje 50% [P] | Samoobsługa; 1000 zapytań miesięcznie za darmo, potem 0,007 $ [P]; „pokrycie poza USA rośnie" | Do sprawdzenia testem 50 polskich zapytań |
| Kelkoo, Skąpiec (Moneteasy), Awin, webePartners | Feedy lub API ofert | Za kliknięcie lub od sprzedaży | Umowa; polskie pokrycie [N] | Później |
| Klarna (API produktów) | 12 rynków Europy, **bez Polski** [P] | — | — | Dopiero przy wyjściu za granicę |

Wnioski:
- **Nie ma jednego źródła** z cenami z wielu polskich sklepów i linkami partnerskimi. Najbliżej jest para Convertiser + Tradedoubler, z Ceneo i Allegro jako linkami.
- Feedy sieci to dane na licencji z gotowym linkiem partnerskim: jedno zgłoszenie daje jednocześnie cenę, zdjęcie, EAN i zarobek.
- Prawie każdy program wymaga **zarejestrowanego wydawcy, działającej strony i zgody na aplikację z asystentem AI**. x-kom w Admitad zakazuje porównywarek, ale dopuszcza „doradzenie produktu w odpowiedzi na pytanie klienta" [S]: to trzeba mieć na piśmie.

### 2.2 Płacenie przez Doddy'ego

- **Żaden dostawca nie oferuje dziś w Polsce zakupu „agent płaci".** OpenAI wycofał Instant Checkout w marcu 2026; kasy Google, Copilota i Mety działają tylko w USA [S]. Visa, Mastercard i AP2 są w pilotażu [S].
- Walmart podał, że zakup w czacie konwertował około 3 razy gorzej niż przejście do sklepu [P, Modern Retail].
- W Polsce BLIK, PayU i Juo przeprowadziły pilotaż zakupu przez agenta AI potwierdzanego kodem BLIK w aplikacji banku [S]. To kierunek do obserwowania, nie produkt.
- Apple: towary fizyczne płaci się poza zakupami w aplikacji (wytyczna 3.1.3(e)); przejście do kasy sklepu jest dozwolone [P].
- Doddy jako sprzedawca albo portfel wymagałby licencji płatniczej [Repo, `SHOPPING_CHECKOUT.md`].

**Rekomendacja:** teraz nie. Doddy doprowadza do kasy sklepu, a sklep bierze płatność. Wracamy do tematu, gdy Shopify potwierdzi Shop Pay dla kupujących z Polski albo BLIK wyjdzie z pilotażu.

### 2.3 Co sprawia, że ludzie tego używają

- **Dobra cena w chwili kliknięcia.** W teście dostawcy Product.ai asystenci AI mieli błędy w 97% pytań porównawczych, mediana błędu ceny 300 $ [S, metoda nieopublikowana]. Zasada Doddy'ego „cena tylko z odczytu, nigdy od modelu" jest tu przewagą.
- **Polska:** BLIK 72%, paczkomat 83% kupujących online; główne skargi to czas i koszt dostawy [S, Gemius przez Przelewy24]. 61% dorosłych używało AI przy zakupach w ostatnim półroczu [S, SW Research, n=830], z czego połowa do porównywania produktów.
- **Zaufanie:** 68% zakłada, że wyniki AI są pod wpływem reklamodawców [S, ankieta dostawcy]. Wyraźne oznaczenie linku i zasada „prowizja nie zmienia kolejności" są konieczne.
- **Trzy propozycje** mają oparcie: granica dla głosu i dla ekranu telefonu (NN/g: dwie kolumny widoczne naraz, trzecia przesunięciem) [P/S]. Środkowa opcja zyskuje z samego położenia, więc etykiety muszą być uczciwe.
- **Alerty:** nie znaleziono publicznych danych o tym, jak wpływają na powroty użytkowników; trzeba to zmierzyć. Około połowa użytkowników iPhone'a nie zgadza się na powiadomienia [P, Airship], więc o zgodę pytamy przy ustawianiu alertu.
- **Konkurencja lokalna:** Ceneo ma historię cen i alert cenowy; Allegro ma własnego asystenta AI od maja 2026 [S]. Doddy wygrywa, jeśli da tę samą odpowiedź szybciej, głosem, z kilku źródeł naraz i z pamięcią tego, co dla Ciebie ważne.

### 2.4 Prawo i zasady (nie jest to porada prawna)

- **Omnibus:** porównywarka, która tylko pokazuje ceny innych, nie musi podawać najniższej ceny z 30 dni; musi, jeśli sama ogłasza obniżkę („-20%") [P, wytyczne KE i UOKiK]. Dlatego alert mówi „cena spadła do 1 799 zł", a nie „-20%", i nie powtarzamy procentów ze sklepu.
- **Linki partnerskie** to reklama: oznaczenie po polsku, widoczne przed kliknięciem [P, UOKiK; zastosowanie do aplikacji to wniosek].
- **Apple 4.5.4:** powiadomienia promocyjne tylko za wyraźną zgodą i z wyłącznikiem w aplikacji; **4.2.2:** aplikacja nie może być głównie zbiorem linków, więc zakupy są jedną z funkcji Doddy'ego [P].

## 3. Opcje

| | A. Złożyć to, co jest | B. A + feedy partnerskie (**rekomendowana**) | C. Agregator na skróty |
|---|---|---|---|
| Co to jest | Jedna sekcja „Zakupy": szukanie, trzy propozycje, ekran porównania, lista pilnowanych cen. Dane jak dziś: Google Shopping + odczyt strony sklepu | To samo, plus Convertiser i Tradedoubler jako źródła ofert; Ceneo i Allegro jako wiersze „szukaj dalej" | Channel3 i Shopify Catalog jako źródła |
| Szybkość odpowiedzi | Minuty (zadanie w tle) | Sekundy dla sklepów z feedu; reszta w tle | Sekundy |
| Zdjęcia, EAN, to samo w kilku sklepach | Słabo | Tak | Tak |
| Zarobek | Dopiero po podpisaniu programów | Link partnerski w każdej ofercie z feedu | Channel3: połowa prowizji; Shopify: 0,3% na zaproszenie |
| Pokrycie Polski | Szerokie, ale wiele cen niepotwierdzonych | Sklepy, które nas przyjmą; reszta jak w A | Nieznane, do testu |
| Czego wymaga od właściciela | Włączenia pilnowania cen | Wydawcy (firmy), strony, zgłoszeń i pisemnych zgód | Klucza API |
| Ryzyko | Mało nowego dla użytkownika | Odmowy programów; czas zgód | Zależność od startupu; słabe polskie wyniki |

Płacenie przez Doddy'ego (opcja D) nie jest dziś możliwe w Polsce i zostaje poza zakresem (2.2).

**Rekomendacja: B, budowana w kolejności A → B.** Część A nie czeka na żadną zgodę i daje użytkownikowi całą sekcję. Zgłoszenia do sieci idą równolegle, a feedy dochodzą jako kolejne źródło ofert za tym samym interfejsem (`OfferSource`). Opcję C warto sprawdzić jednym tanim testem (50 polskich zapytań w darmowym limicie Channel3), zanim cokolwiek na niej zbudujemy.

## 4. Jak ma wyglądać sekcja

Projekt według ADR-548 i `design/brand-v2.2/`, tokeny z `DoddyDesignTokens`; postać tylko z paczki właściciela.

**Wejście.** Home › ••• › Zakupy, i głosem („znajdź mi cichą zmywarkę do 2000 zł"). Na górze pole „Czego szukasz?", pod nim: Pilnowane ceny, Ostatnie wyszukiwania, Najtaniej w tym tygodniu (gazetki, bez zmian).

**Jedno pytanie doprecyzowujące, najwyżej.** Gdy brakuje rzeczy, która zmienia wynik (rozmiar, budżet), Doddy pyta raz; inaczej przyjmuje założenie i je pokazuje.

**Trzy karty.** Role: *Najlepszy wybór*, *Najtańszy, który spełnia potrzebę*, *Krok wyżej*. Gdy uczciwie pasują dwa produkty, są dwie karty. Na karcie:
1. zdjęcie (z feedu albo ze strony sklepu; bez zdjęcia, gdy go nie ma) i dokładna nazwa z wariantem;
2. rola i jedno zdanie „dlaczego", odniesione do słów użytkownika;
3. **cena z dostawą do paczkomatu**, pod spodem cena i dostawa osobno; gdy kosztu dostawy nie odczytano: „dostawa: sprawdź w sklepie";
4. sklep, dostępność;
5. „cena sprawdzona 14:32" i skąd (strona sklepu albo feed sklepu);
6. dwa lub trzy parametry ważne w tej kategorii;
7. „+N innych sklepów od X zł";
8. przyciski: Porównaj, Pilnuj ceny, Idź do sklepu; pod przyciskiem oznaczenie linku partnerskiego i „Otwórz bez linku partnerskiego".

**Porównanie.** Wiersze cech, nagłówki produktów przypięte przy przewijaniu, dwie kolumny widoczne, trzecia przesunięciem. Na górze zawsze: cena z dostawą, termin, dostępność. Domyślnie „tylko różnice". Brak danych pokazany jako „sklep nie podaje", nigdy uzupełniany przez model. Na dole po jednym zdaniu na produkt, opartym na wierszach powyżej.

**Głosem.** Doddy mówi, ile znalazł, najlepszy wybór z ceną i sklepem oraz jeden kontrast („najtańsza jest o 180 zł tańsza, ale przyjdzie trzy dni później"), i zadaje jedno pytanie. Reszta jest na ekranie. Nie czyta linków ani informacji o prowizji.

**Alert cenowy.**
1. Start z karty albo głosem („daj znać, jak spadnie poniżej 1500").
2. Karta z dokładną treścią: produkt i wariant, sklep, cena odczytana teraz, Twoja kwota, jak długo i jak często Doddy sprawdza.
3. Zgoda na powiadomienia dopiero tutaj.
4. „Pilnuję" dopiero po potwierdzeniu zapisu przez serwer.
5. Przed wysłaniem powiadomienia ponowny odczyt ceny i dostępności.
6. Lista pilnowanych: wstrzymaj, zmień, usuń. Po wygaśnięciu pytanie o przedłużenie.

Nowe względem dzisiejszego pilnowania: start głosem, zmiana kwoty, pilnowanie produktu w kilku sklepach naraz (po EAN z feedu). Powiadomienie dziś celowo nie zawiera nazwy produktu ani ceny (prywatność na ekranie blokady); czy to zmienić, jest decyzją właściciela.

**Uczciwość widoczna na ekranie.** „Jak wybrałem" jedno dotknięcie dalej; „nie znalazłem aktualnej ceny" zamiast zgadywania; „kupujesz w sklepie, na jego zasadach zwrotu"; żadnych „tylko dziś".

## 5. Zasady, których kod musi pilnować (konstytucja)

- Cena, sklep, link i czas pochodzą z rejestru ofert, nigdy z tekstu modelu (DOD-02). Tak jest dziś; feed staje się drugim dozwolonym źródłem z własną etykietą.
- Link partnerski dopisywany po wyborze; test porównuje wynik z linkiem i bez; strażnik w CI pilnuje, żeby kod wybierający nie importował modułu partnerskiego.
- Treść stron, feedów i wyników wyszukiwania to dane, nie polecenia.
- „Pilnuję" i „zapamiętałem" tylko po potwierdzonej operacji zapisu.
- Doddy reaguje na prośbę i nie wysyła nieproszonych ofert („w Decathlonie jest promocja").
- Żadnych linków Amazon przy czymkolwiek, co ma alert.
- Nic nie kupuje, nie loguje się i nie wypełnia formularzy.

## 6. Kolejność prac

**Krok 0, właściciel, bez kodu (można zacząć od razu):**
1. Zdecydować, kto jest wydawcą (osoba czy firma z VAT). Allegro wymaga firmy; konta w sieciach trudno potem przenieść.
2. Zgłosić się do: Convertiser, Tradedoubler (RTV Euro AGD, Empik, eobuwie), programu partnerskiego Ceneo z prośbą o klucz API, Allegro Affiliate Business (pytanie na afiliacja@allegro.com, czy aplikacja się kwalifikuje). Tekst zgłoszenia jest w `AFFILIATE_NETWORKS_PROPOSAL_2026-11.md` sekcja 7; dopisać pytanie o alerty cenowe.
3. Od każdego programu pisemne „tak" dla aplikacji iOS, rozmowy z AI, głosu i alertów.

**Etap 1 (kod, nie czeka na zgody):** sekcja „Zakupy" z polem pytania, trzema kartami i ekranem porównania zbudowanymi na dzisiejszym wyniku; lista pilnowanych cen w sekcji; narzędzie głosowe do pilnowania ceny (w `voice-agent/`, na żywego agenta tylko po osobnej zgodzie właściciela); zdjęcie i dostawa odczytywane ze strony sklepu, gdy sklep je publikuje; reguły linków z datą ważności i przełącznik „Linki partnerskie" (kroki z propozycji z 1 lis). Do tego włączenie `WATCHES_ENABLED` na serwerze przez właściciela.

**Test bramkowy przed etapem 2:** 50 prawdziwych polskich zapytań przez każde źródło, które przyznało dostęp (i Channel3 w darmowym limicie): ile ma trafny produkt, aktualną cenę, zdjęcie. Wynik decyduje, które źródła wchodzą.

**Etap 2 (po pierwszych zgodach):** Convertiser i Tradedoubler jako `OfferSource`; szybka odpowiedź w sekundach; łączenie tej samej rzeczy z kilku sklepów po EAN; alert na kilka sklepów; wiersze Ceneo i Allegro.

**Etap 3 (gdy będzie ruch):** historia cen z własnych odczytów i „czy to dobra cena"; Shopify Catalog dla małych marek; raporty z sieci; rynki zagraniczne (Klarna).

**Płatność:** osobna decyzja, gdy rynek w Polsce dojrzeje.

## 7. Pieniądze, uczciwie

- Prowizje: elektronika 1–3%, moda i sport 4–12% [P/S]. Wcześniejszy model właściciela dawał około 23 zł miesięcznie przy 1000 użytkowników i 2300 zł przy 100 000 [Repo, same założenia].
- Wypłata zwykle od około 100 zł, z opóźnieniem 2–4 miesięcy; zwroty cofają prowizję [Repo].
- Atrybucja z aplikacji bywa gubiona (Safari, aplikacja sklepu, ciasteczka 24 h u Allegro i x-kom). Dopiero jeden prawdziwy zakup widoczny w panelu sieci pokaże, czy działa.
- Koszt po naszej stronie: feedy i API sieci są bezpłatne; zadanie zakupowe kosztuje wywołania modelu i Serpera; pilnowanie ceny nie używa modelu. Konto Anthropic wciąż nie ma limitu wydatków (`docs/OWNER_QUEUE.md` 2).
- Wniosek: to funkcja, która ma przyciągać i zatrzymywać ludzi, a prowizja ma pokryć jej koszt. Nie należy planować na niej przychodu przed pomiarem.

## 8. Decyzje dla właściciela

1. **Opcja:** A, B (rekomendowana) czy C.
2. **Wydawca:** osoba czy firma z VAT.
3. **Cena z feedu sklepu:** czy wolno ją pokazać z etykietą „cena z feedu sklepu, 14:32" bez odczytu strony. Dziś obowiązuje „tylko cena potwierdzona na stronie sklepu" (ADR-611). Rekomendacja: tak, z ponownym sprawdzeniem przy dotknięciu i przed alertem, bo feed to dane samego sklepu.
4. **Treść powiadomienia:** z nazwą produktu i ceną, czy jak dziś bez nich.
5. **Limity pilnowania:** dziś 5 aktywnych, 30 dni, 4 odczyty dziennie.
6. **Ceneo:** czy przyjmujemy warunek „dane tylko do promowania Ceneo" dla jednego wiersza w wynikach.
7. **Płatność:** potwierdzić, że zostaje przejście do kasy sklepu.
8. **Nazwa sekcji:** „Zakupy" (propozycja).

## 9. Czego nie sprawdzono, i źródła

Nie sprawdzono: rzeczywistego pokrycia polskich produktów w Convertiser, Tradedoubler, Channel3 i Shopify (potrzebny test na żywo); stawek i zasad Ceneo oraz Allegro (są w panelach); czy którakolwiek sieć przyjmie aplikację z asystentem AI i alertami; polskiej wersji zasad Amazon; wyniku sporu Google z SerpApi; czy Shop Pay działa dla kupujących z Polski; raportów Gemius u źródła; stanu serwera wiadomości, od którego zależy pilnowanie cen (`STATUS.md` podaje, że jego baza wygasała 10 lis 2026).

Najważniejsze źródła:
- Allegro: https://developer.allegro.pl/tutorials/lista-metod-rest-api-allegro-yPyaj0wG3C4 · https://github.com/allegro/allegro-api/issues/13394 · https://allegro.pl/regulaminy/regulamin-programu-allegro-affiliate-business-g0jo4xvzWu7
- Ceneo: https://partnerzyapi.ceneo.pl/ · https://pp.ceneo.pl/Brands/ProgramPartnerski/regulamin.pdf
- Convertiser: https://convertiser.com/pl/feedy-api/ · https://help.convertiser.com/pl/kb/weryfikacja-domeny/
- Tradedoubler: https://dev.tradedoubler.com/products/publisher/ · https://directory.tradedoubler.com/pl/programs/118512-RTV-EURO-AGD-PL
- Amazon: https://affiliate-program.amazon.com/help/operating/policies · https://partnernet.amazon.de/help/operating/mobileapps · https://affiliate-program.amazon.com/creatorsapi/docs/en-us/paapiv5-deprecation
- Shopify: https://shopify.dev/docs/agents/catalog · https://shopify.dev/docs/agents/catalog/promoted-placement.md
- Channel3: https://channel3.mintlify.dev/docs/pricing.md · https://channel3.mintlify.dev/docs/commissions.md
- Klarna: https://docs.klarna.com/klarna-search/klarna-agentic-product-protocol/
- Płatności i rynek: https://www.modernretail.co/technology/what-went-wrong-with-chatgpts-instant-checkout/ · https://blog.google/products/shopping/agentic-checkout-holiday-ai-shopping/
- Apple: https://developer.apple.com/app-store/review/guidelines/
- Prawo: https://eur-lex.europa.eu/legal-content/PL/TXT/PDF/?uri=CELEX%3A52021XC1229%2806%29 · https://uokik.gov.pl/download/27128 · https://uokik.gov.pl/influencer-marketing
- Zachowania: https://www.przelewy24.pl/en/news/ecommerce-2025-zakupy-online-trendy-polscy-konsumenci · https://itwiz.pl/juz-61-polakow-korzysta-z-chatbotow-ai-podczas-zakupow/ · https://www.nngroup.com/articles/comparison-tables/ · https://tech.co/news/ai-shopping-assistants-not-ready-holidays
