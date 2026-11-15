# DODDY — Human Conversation Intelligence
## 01. Najważniejsze ustalenia i decyzja

Data weryfikacji: 15 listopada 2026. Język: polski; rynek startowy: Polska. Charakter pracy: przegląd ukierunkowany, analiza kodu i projekt eksperymentów. Nie przeprowadzono odsłuchów DODDY, pomiarów na iPhonie ani badań użytkowników.

**Rekomendacja: najpierw dostroić obecną ścieżkę ElevenLabs i zmierzyć pełną rozmowę. Następnie porównać ją z jednym rozwiązaniem native speech w kontrolowanym eksperymencie. Własny silnik full duplex odłożyć do czasu wykazania konkretnej przewagi.**

Naturalność powstaje na trzech poziomach: brzmienie głosu, sposób budowania wypowiedzi oraz koordynacja rozmowy. Realistyczny głos nie rozwiązuje problemu wchodzenia w słowo, ignorowania korekt ani mówienia o zadaniu jako zakończonym, kiedy nadal trwa.

Najważniejszy cel produktu: użytkownik czuje, że może normalnie powiedzieć, o co mu chodzi, poprawić się i przerwać, a DODDY trafnie odpowiada lub wykonuje zadanie. „Nieodróżnialny od człowieka” nie jest użytecznym głównym KPI.

### Decyzje w kolejności

1. **Rozdzielić pomiary.** Start sesji, koniec wypowiedzi → pierwsza treść i przerwanie → cisza to trzy różne czasy. Nie liczyć „mhm” jako odpowiedzi merytorycznej.
2. **Ustalić bazę na obecnym kodzie i konfiguracji wdrożonego agenta.** Plik w repozytorium nie dowodzi stanu dashboardu. Każda próbka powinna mieć wersję promptu, modelu, głosu, SDK i ustawień turn-taking.
3. **Testować czekanie na niedokończoną myśl.** „Jutro o… chwila… siedemnastej” wymaga innego traktowania niż zamknięte pytanie. Krótszy timeout nie jest uniwersalną poprawką.
4. **Oddzielić potakiwanie od przejęcia głosu.** „Mhm” może nie wymagać zatrzymania; „tak, ale nie jutro” wymaga korekty. Lista ignorowanych słów sama nie rozwiązuje tej różnicy.
5. **Odpowiadać najpierw sednem.** Zwykle jedno–dwa zdania, potem rozwinięcie zgodnie z potrzebą. Nie narzucać limitu każdej odpowiedzi: tłumaczenie i wyjaśnienie wymagają innej długości.
6. **Zachować spójny charakter, zmieniać zachowanie do sytuacji.** Luźny ton w codziennych sprawach, rzeczowy przy błędzie, ostrożny przy niepewności; sarkazm domyślnie wyłączony w sprawach poważnych.
7. **Pamięć pobierać selektywnie.** Szybka odpowiedź może ruszyć bez pełnego archiwum, ale pytanie o osobisty fakt musi poczekać na właściwe źródło. Nigdy nie przykrywać braku pamięci pewnym zgadywaniem.
8. **Zostawić jeden autorytatywny wykonawca zadań.** Przerwanie mowy zatrzymuje audio; odwołanie zamówienia to osobna operacja z własnym statusem.
9. **Eksperyment porównawczy: obecny ElevenLabs kontra GPT-Live lub Gemini Live.** Wybrać jeden challenger po sprawdzeniu dostępu, polskiego, kosztu i zachowania narzędzi. Nie migrować na podstawie demonstracji.
10. **Pełny duplex i generowane backchannele wprowadzać tylko po testach.** Możliwość jednoczesnego słuchania i mówienia jest cechą techniczną; nie dowodzi poprawnej koordynacji społecznej.

### Co potwierdza nauka, a czego nie

Analizy rozmów i przeglądy pokazują znaczenie przewidywania kolejki, wspólnego kontekstu i napraw nieporozumień. Nie wskazują jednego optymalnego opóźnienia dla wszystkich użytkowników. Wyniki dotyczące pozornej ludzkości, fillerów i zaufania zależą od zadania, populacji i sposobu pomiaru. Źródła oraz ograniczenia są w raportach 02–05 i macierzy dowodów.

Dokumentacja API potwierdza dostępność funkcji; deklaracje producenta o latencji lub naturalności nie są niezależnym benchmarkiem DODDY. Proponowane progi w raporcie 10 są kryteriami inżynierskimi do zatwierdzenia po pilotażu, a nie wynikami badań ani obietnicą wydajności.

### Przykład docelowego zachowania

Użytkownik: „Przypomnij jutro o… czekaj, w piątek o piątej, żebym zadzwonił do Marka”.

DODDY czeka na dokończenie i interpretuje korektę jako zastąpienie daty. Jeżeli kontekst nie rozstrzyga pory, pyta: „O piątej rano czy po południu?”. Po poprawnym zapisie: „Ustawione na piątek, siedemnastą”. Przy błędzie: „Nie udało mi się zapisać przypomnienia”. To scenariusz projektowy, nie zapis testu.

### Co dostajesz

Pakiet zawiera 12 raportów, 60 autorskich scenariuszy rozmowy PL/EN, zestaw scenariuszy testowych, macierz źródeł, porównanie technologii, projekt architektury, prompty, rejestr decyzji i krytyczną recenzję. Wnioski odnoszą się do przypiętego stanu repozytorium; szczegóły i granice audytu w raporcie 07.

## Zakres pakietu

72 źródła zewnętrzne, w tym 38 publikacji akademickich; 24 ustalenia z kodu; 60 autorskich dialogów PL/EN i 120 specyfikacji testowych. Szczegółowy zakres lektury, ograniczenia i metodologia są w pełnym ZIP. Nie wykonano testów DODDY ani zmian produkcyjnych.

## Wybrane źródła do wniosków

- [Chiba i Higashinaka: timing i poprawność](https://aclanthology.org/2025.coling-main.249/)
- [Xu, Dai i Yan: eksperyment głosowy](https://pubsonline.informs.org/doi/10.1287/mnsc.2022.03833)
- [ElevenLabs: conversation flow](https://elevenlabs.io/docs/eleven-agents/customization/conversation-flow)
- [OpenAI: GPT-Live](https://developers.openai.com/api/docs/guides/live)
- [PELCRA: SpokesBiz](https://docs.pelcra.pl/doku.php?id=spokesbiz)
