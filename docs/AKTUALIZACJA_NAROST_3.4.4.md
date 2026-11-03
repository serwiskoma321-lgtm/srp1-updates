# SRP-1 — bezpieczeństwo narostu, pomiarowy3.4.4

Aktualizowana jest wyłącznie paczka **pomiarowego3.4.4**.
Sterownik pozostaje **2.6.9**, konsolka **2.6.2**, KOMA **1.6.5+116**.
Nie wgrywano ani nie resetowano podłączonych urządzeń.

## Poprawki

- Nowa rejestracja zeruje wszystkie siedem liczników próbek, flagi analizy,
  czasy reakcji i surowy bufor. Nie nadpisuje bufora czekającego na transfer.
- Każdy zapis próbki i znacznika granicy bloku sprawdza pojemność bufora.
  Przy zbyt długim naroście (np. dzielnik1) zachowany zostaje mieszczący się
  początek przebiegu. Dalsza analiza progów trwa, bez zapisywania poza pamięcią.
  Nie zwiększono pojemności ani nie zmieniono kroku czasu/kalibracji.
- Koniec pomiaru jest zgłaszany również po próbie, która wykryła prąd, ale
  nie osiągnęła początkowego progu narostu. Nie udaje się gotowego narostu,
  jeśli nie zapisano żadnych jego próbek. END pozostaje do potwierdzenia.
- Przekroczenie końcowego progu w pierwszych trzech zapisanych próbkach
  nie może dać ujemnego indeksu ani zostać pomylone z brakiem narostu.
- Przekroczenie czasu oczekiwania SPI nie anuluje transakcji sprzętowej.
  Poprawka zachowuje jej deskryptor i blokuje ponowne użycie buforów, aż
  sterownik SPI faktycznie odda zakończoną transakcję. Wcześniej pamięć była
  zwalniana mimo trwającego DMA. Gdy master nie nadaje, zadanie SPI nadal
  czeka; ADC i diagnostyka USB działają osobno. Nie jest to mechanizm
  anulowania uszkodzonego/odłączonego łącza.
- Deskryptory SPI są w pełni inicjalizowane; pole flags wcześniej nie
  miało przypisanej wartości. Nieudane przekazanie deskryptora do zadania
  zwalnia lokalną kopię, której sprzęt jeszcze nie otrzymał.
- Diagnostyka USB: CAPTURE_BEGIN (dzielnik/pojemność), RISE_CLIPPED
  (pierwszy odrzucony indeks/pojemność/blok/dzielnik), SPI_DELAY
  (błąd oczekiwania/czas w tickach/numer transakcji). BOOT w polu b
  zawiera przyczynę resetu ESP-IDF. Dotychczasowe END_SUMMARY pozostaje.

## Co ustalono, a co wymaga próby

W ostatniej odczytanej sesji sterownik potwierdził zapis KREG i CSV po
przekroczeniu30s oczekiwania na koniec/narost. Sam zapis SD trwał347ms.
Dzielnik był2. Nie odczytano treści tych plików ani pełnego przebiegu
zdarzenia od startu. Nie przypisujemy historycznej awarii do jednej
udowodnionej przyczyny: poprawiono realne błędy odtworzone testami kodu.

Testy wykonują rzeczywiste funkcje analizy i sterowania sesją z kontrolą
granic pamięci:100 kolejnych krótkich prób, siedem bloków dla dzielnika2,
przepełnienie dla dzielnika1 i mniejszego bufora, brak progu narostu,
wyłączony narost i ochrona oczekującej transmisji. Test rzeczywistego
zadania SPI sprawdza wielokrotne przekroczenie czasu przed prawidłowym
zakończeniem oraz błąd kolejkowania. Dodatkowo regresje obu końców SPI,
SD, OTA, Wi-Fi, sygnalizacji i kalibracji. Testów sprzętowych tej wersji
nie wykonywano; użytkownik zainstaluje paczkę i je przeprowadzi.

## Aktualizacja i test

1. Zakończ pomiary. W KOMA → Firmware → Pomiarowy → Sprawdź/wybierz
   wybierz3.4.4, pobierz, prześlij na SD przez Wi-Fi i zastosuj.
2. Po zakończeniu zrestartuj pomiarowy zwykłą procedurą aplikacji
   i odczytaj wersję. Sterownika, konsolki ani aplikacji nie aktualizuj.
3. Wykonaj co najmniej5 kolejnych krótkich i jedną dłuższą rejestrację
   z narostem, początkowo przy obecnym dzielniku2. Sprawdź narost w każdym
   pliku oraz powrót zielonej diody i możliwość następnej rejestracji.
4. Jeśli ponownie długo świeci czerwony, pozostaw urządzenia włączone
   i zachowaj log obu USB od początku próby. Sam zielony po30s nie
   potwierdza poprawnego narostu — sprawdź wynik rejestru/REG_STATUS.
5. Poprzedni pomiarowy3.4.3 pozostaje do wyboru jako powrót. Układ
   partycji OTA/NVS, podpisy i przypisanie do MAC pozostają takie same.

Paczka przeznaczona dla pomiarowego zestawu SRP1-2. Prywatnych źródeł,
kluczy, konfiguracji Wi-Fi ani logów urządzeń nie dołączono do publikacji.
