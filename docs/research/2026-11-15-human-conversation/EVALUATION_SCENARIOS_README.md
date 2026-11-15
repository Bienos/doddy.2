# Specyfikacje testów rozmowy

Zestaw zawiera 120 przypadków: 60 podstawowych i 60 trudniejszych, po 60 przypadków PL i EN. Każdy trudniejszy przypadek zmienia istotny warunek: np. stan narzędzia, kolejność korekty, długość pauzy, referent, uprawnienie, źródło głosu lub dostępność powiadomień. Nie są to wykonane pomiary ani nagrania.

## Jak użyć

1. Wczytaj pojedynczy wiersz JSONL oraz powiązany scenariusz z `dialogue_examples.json`.
2. Odtwórz fixture w kontrolowanym koncie testowym. Zastąp narzędzia atrapami ze wskazanymi wynikami; nie wysyłaj wiadomości i nie kupuj prawdziwych produktów. Zweryfikuj identyfikatory, strefę czasową i stan początkowy.
3. Tester lub harness wypowiada tylko tury użytkownika. Tury asystenta są referencją dla oceny, nie danymi do odtworzenia modelowi. Pauzy, nakładanie mowy i zdarzenia z pola `event` trzeba rzeczywiście zrealizować. Sam tekst nie testuje VAD, echa ani Bluetooth.
4. Uruchom baseline i kandydata z tą samą konfiguracją narzędzi; losuj kolejność i ukryj etykiety wariantów przed słuchaczem. Przebiegi live nie są identycznym replayem audio; rejestruj tę różnicę.
5. Zapisz faktycznie zaobserwowany wynik, znaczniki czasu i ocenę. Zostaw `specified_not_executed`, dopóki próba się nie odbyła. Nie wpisuj danych referencyjnych jako wyniku modelu.
6. Powtórz scenariusze na urządzeniach i trasach audio. Grupuj wyniki po języku, urządzeniu, kategorii i warunkach; nie traktuj 120 scenariuszy jako 120 niezależnych uczestników badania.

## Kryteria i ograniczenia

Semantyczna poprawność i skutek narzędzia to oddzielne kryteria od naturalności głosu. Odpowiedź może brzmieć inaczej niż referencja i zaliczyć test. „Mniej mechanicznie” nie oznacza automatycznie „lepiej”: priorytetem jest poprawny stan zadania, brak fałszywych deklaracji, szacunek dla przerwania i język zgodny z celem.

Ocena naturalności 1–7 jest proponowaną skalą roboczą: 1 = bardzo mechanicznie, 4 = akceptowalnie, 7 = bardzo swobodnie i płynnie. Nie jest tu przedstawiana jako zwalidowany kwestionariusz. Użyj tej samej instrukcji w obu wariantach i nie pytaj wyłącznie o podobieństwo do człowieka.

Budżet 250 ms dla zatrzymania audio po przerwaniu jest propozycją inżynierską. Brak pomiarów oznacza brak dowodu, że obecny DODDY lub którykolwiek dostawca go spełnia. TTFMA mierz od oznaczonego przez testera faktycznego końca tury do pierwszego słyszalnego fragmentu niosącego odpowiedź; samo „mhm” lub sygnał dźwiękowy nie kończy pomiaru. Oznacz niepewność adnotacji końca tury i wszystkie timeouty.

Próby dźwiękowe i nagrania wymagają zgody uczestników oraz minimalizacji danych. Zapis narzędzi powinien używać fikcyjnych kontaktów i treści. Bez audytowalnego event timeline nie da się rozdzielić opóźnienia detekcji końca tury, generacji i odtwarzania.

## Status walidacji plików

Skrypt budujący sprawdza liczbę 60 przykładów (30 PL/30 EN), liczbę 120 unikalnych przypadków oraz poprawność serializacji. To kontrola struktury danych, a nie test DODDY ani wynik badania użytkowników.
