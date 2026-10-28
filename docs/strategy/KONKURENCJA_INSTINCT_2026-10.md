# Konkurencja: Instinct a Doddy (notatka, 28 paź 2026)

Notatka do decyzji właściciela, nie plan budowy. Nic tu nie jest zbudowane ani zmienione w kodzie. Fakty o Instinct pochodzą z jego strony, regulaminu i polityki prywatności (czytane 28 paź 2026) oraz z prasy i blogów; te ostatnie oznaczam jako **niesprawdzone**.

## Kim jest Instinct

- **Firma:** Spear Street Technology, San Francisco. Założyciel i CEO Noah Shinn (23 lata, wcześniej Sierra). **Niesprawdzone (prasa):** Series B 250 mln $ przy wycenie 2,5 mld $ (sierpień 2026), Series C 1 mld $ przy 10 mld $ (wrzesień 2026; Sequoia, Benchmark, Coatue). Przychody i liczba użytkowników nieujawnione.
- **Produkt:** osobisty asystent bez aplikacji: piszesz do niego albo dzwonisz. Strona: „can use a phone and computer in the same way that you do”. Przykłady: składniki do przepisu, pociąg, zakupy spożywcze, kwiaty, kort tenisowy. **Niesprawdzone:** iMessage i WhatsApp (regulamin wymienia tylko SMS i telefon), stały komputer w chmurze z przeglądarką i zapisanymi loginami.
- **Dostęp:** na zaproszenie, tylko 18+, działa z USA, prawo Kalifornii i arbitraż, ceny w dolarach, płatności bezzwrotne.

## Co mówią jego dokumenty (źródło pierwotne)

| Temat | Regulamin i polityka prywatności Instinct |
|---|---|
| Działanie w Twoim imieniu | „You authorize the Services to take Actions on your behalf as the Services may deem are responsive to your Input.” Zakupy i zgody na cudze regulaminy wiążą użytkownika „as if entered into directly by you”. |
| Zgoda przed akcją | Nie ma obowiązku. Firma „may implement safeguards, confirmation requirements” i nie gwarantuje, że zapobiegną błędnym akcjom. Polityka ostrzega przed „unintended payments or communications to outside parties”. |
| Odpowiedzialność | „We are not responsible for any unintended Actions”. Limit: 100 $ albo kwota zapłacona w ostatnich 6 miesiącach. |
| Loginy | Może używać „your username and password for third-party accounts”. |
| Trening modeli | Domyślnie tak („evaluate, fine-tune, and train”). Rezygnacja w ustawieniach działa tylko na przyszłość, nie obejmuje treści „flagged for safety review”. Wyjątki: dane z Google Workspace i „Vault”. |
| Odłączenie konta | „disconnecting a third-party integration does not automatically delete data”; usunięcie trzeba zlecić osobno. Okresów przechowywania brak. |
| Dane zbierane | Gmail (treść, jeśli włączysz), klawisze, kliknięcia i kursor, dokładna lokalizacja, głos, płatności, dane zdrowotne. |

**Niesprawdzone (blogi):** skargi, że agent trzymał maile po odłączeniu Google (zgodne z cytatem wyżej) i że wysłał maila bez pytania (zgodne z brakiem obowiązku zgody).

## Porównanie

| | Instinct | Doddy (stan z `STATUS.md`) |
|---|---|---|
| Kanał | SMS i telefon; bez aplikacji | aplikacja iPhone, głos, Dynamic Island, Messages, web; telefon do Doddy'ego zbudowany (S2), nie uruchomiony |
| Sposób działania | ogólny agent w przeglądarce, z loginami | wąskie narzędzia z kodem, zadania w tle na serwerze |
| Zgoda | opcjonalna, „may implement” | zgoda na dokładną treść przed każdym zapisem na zewnątrz; `unknown` nigdy nie jest sukcesem (konstytucja) |
| Pamięć | indeksuje konta, zostaje po odłączeniu | jawna, ze źródłem, na telefonie; usunięcie i eksport |
| Trening na danych | domyślnie tak | brak w projekcie |
| Rynek | USA, angielski | Polska: Biedronka, Lidl, InPost, inFakt, BLIK, polski głos |
| Dojrzałość | produkt z użytkownikami i ogromnym finansowaniem | dużo kodu, prawie nic sprawdzone na urządzeniu; kilka funkcji wyłączonych |

## Wnioski

1. **Nie konkurować zakresem.** Agent z przeglądarką zrobi więcej rzeczy niż lista narzędzi Doddy'ego.
2. **Konkurować zaufaniem**, bo dokumenty Instinct same pokazują lukę: brak obowiązkowej zgody, odpowiedzialność po stronie użytkownika, trening domyślny, dane po odłączeniu. Doddy ma odwrotne zasady w konstytucji. **Warunek:** w marketingu wolno mówić tylko to, co jest w kodzie i przetestowane; dziś większość nie była na telefonie, więc żadnego „gwarantujemy prywatność”.
3. **Lokalność** jest realną przewagą, której Instinct nie ma (działa z USA, w dolarach).

## Co warto podpatrzeć: „po prostu napisz albo zadzwoń”

Doddy ma już kawałki tego kanału, tylko nieuruchomione:

- **Telefon do Doddy'ego (S2, `docs/implementation/S2_CALLS_STATUS.md`):** numer Twilio, agent ElevenLabs „Doddy (phone)”, PIN, odpowiedzi z kopii pamięci za zgodą, „Zadzwoń do mnie”. Nigdy nie było prawdziwej rozmowy.
- **SMS (S1, `docs/implementation/S1_SERVER_STATUS.md`):** tylko w jedną stronę (powiadomienia), ze zgodą `sms-v1` i STOP.

Brakuje rozmowy SMS w obie strony (albo WhatsApp). To byłby nowy kamień milowy i potrzebuje decyzji właściciela przed jakimkolwiek kodem:

1. Czy w ogóle chcemy kanał poza aplikacją? (SMS w Polsce kosztuje, WhatsApp wymaga konta Business i szablonów Meta.)
2. Co przez SMS wolno: tylko pytania i notatki do skrzynki (jak w S2), czy też akcje? Akcje tylko z kartą do zatwierdzenia w aplikacji, nigdy „tak” SMS-em bez powiązania z dokładną treścią.
3. Najpierw uruchomić S2 (telefon), skoro jest zbudowany: Twilio, numer, wdrożenie, jedna prawdziwa rozmowa.

## Źródła

- https://instinct.com/ , https://instinct.com/terms , https://instinct.com/privacy (czytane 28 paź 2026)
- https://aiweekly.co/alerts/instinct-raises-1b-series-c-at-10b-for-personal-ai-agent
- https://siliconangle.com/2026/08/27/consumer-focused-ai-assistant-startup-instinct-reportedly-raising-250m/
- https://pulse2.com/instinct-raises-250-million-at-2-5-billion-valuation-as-ai-assistant-goes-viral-in-silicon-valley/
- https://www.layer3labs.io/guides/instinct-ai-explained
- https://ventos.vc/blogs/what-is-instinct-ai/
