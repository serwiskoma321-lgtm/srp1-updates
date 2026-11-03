# SRP-1 — poprawka pamięci OTA i uzgadniania SPI

**Sterownik2.6.9**. Aktualizacja tylko sterownika, do samodzielnego wgrania.
Pomiarowy pozostaje **3.4.3**, konsolka2.6.2, KOMA1.6.5+116 bez zmian.
Nie wgrywano ani nie resetowano urządzeń automatycznie. Komputer zostaje włączony.

## Zgłoszenie i ustalenia

Log z telefonu: paczka pomiarowego409812B poprawnie pobrana, przesłana na SD
w3,259s i zweryfikowana. Instalacja zatrzymana przed transmisją: TASK_FAIL,
0B, nie można utworzyć zadania aktualizacji. Użytkownik następnie potwierdził,
że ten sam pomiarowy instaluje się przez sterownik2.6.7, a nie przez2.6.8.
Brak stosownego bloku RAM jest hipotezą wspartą kodem; log nie zawierał
pomiaru pamięci dokładnie w chwili pierwotnej odmowy. Nie przedstawiać jej
jako bezpośrednio zmierzonej przyczyny na urządzeniu.

## Poprawka

- Żądanie aktualizacji sterownika lub pomiarowego jest kolejkowane.
  Nie zwalnia buforów ani nie tworzy zadania w kontekście polecenia BLE.
- Na początku następnego obiegu procesu pomiarowego, po powrocie poprzedniego
  cyklu, ponownie sprawdzany jest brak rejestracji i oczekującego zapisu SD.
  Dopiero wtedy zwalniane są bufory64 320B i przydzielany stos16 384B OTA.
  Nie zmniejszano stosu i nie zmieniano układu OTA/NVS ani obsługi PSRAM.
- Tryb serwisowy pozostaje aktywny aż do zakończenia zadania i poprawnego
  odtworzenia buforów. Sprzątanie stosu przez zadanie idle może się opóźnić;
  wtedy odtworzenie buforów ponawia się co500ms, bez powrotu do pomiarów
  z pustymi wskaźnikami i bez restartu urządzenia w tej ścieżce.
- Błąd tworzenia zadania zawiera kod, pamięć wolną, największy blok pamięci
  wewnętrznej i żądany stos. Te liczby są w tekście błędu istniejącego raportu
  KOMA oraz po USB. Dodatkowe pola otaWorker* są dostępne przez BLE.
- Znacznik nowego protokołu przeniesiono z nagłówka konfiguracyjnego do
  rzeczywistej ramki normalnej. Test poprzedniej wersji obejmował pętle
  transferu, lecz nie pełny konstruktor tej ramki; nowy test wykonuje go wprost.
  To osobny błąd, nie przyczyna TASK_FAIL występującego jeszcze przed SPI OTA.
- Ramka diagnostyczna po transferze zachowuje te same znaczniki. Poll OTA
  jawnie potwierdza stary koniec/bufor i nie dziedziczy START z poprzedniej
  transmisji. Powtórne APPLY pozostawia QUEUED, zanim zadanie wystartuje.
- Polecenia diagnostyczne pozostają obsługiwane także podczas oczekiwania
  na odtworzenie buforów; nie trzeba wracać do pomiarów, aby odczytać przyczynę.
- Pozostają poprawki domykania rejestracji, ponowień, pełnych15360 próbek,
  skali czasu, sygnalizacji i szybkiego przesyłu Wi-Fi.

Wersja2.6.8 wycofana z aktywnych propozycji aktualizacji, pozostaje w historii.
Sterownik2.6.7 pozostaje aktywną opcją powrotu. Paczki innych procesorów bez zmian.

## Wgrywanie i test użytkownika

1. Przy zatrzymanych pomiarach wybierz w KOMA Firmware → Sterownik →
   Sprawdź/wybierz → **2.6.9**, pobierz, prześlij na SD i zastosuj.
2. Jeżeli obecny2.6.8 odmówi uruchomienia również własnej aktualizacji,
   wróć do sprawdzonego2.6.7 dotychczas używaną metodą i z niego wgraj2.6.9.
3. Po restarcie sprawdź sterownik2.6.9 / pomiarowy3.4.3. Do samego zastosowania
   poprawki NIE trzeba ponownie wgrywać pomiarowego. Paczka3.4.3 jest już na SD.
4. Żeby sprawdzić zgłoszoną ścieżkę OTA, ponownie zweryfikuj istniejącą paczkę
   pomiarowego na SD i wykonaj jego aktualizację. Sprawdź koniec transferu,
   restart, odczytaną wersję oraz powrót do zwykłych odczytów i kolorów LED.
5. Wykonaj kilka kolejnych rejestracji z narostem, również dłuższą/pełny bufor.
   Sprawdź domknięcie sesji, gotowość do kolejnego startu i zapis na SD.
   Przy problemie wyeksportuj nowy raport OTA lub pozostaw USB do diagnostyki.

## Diagnostyka i weryfikacja

Log USB: [OTA_WORKER] target, before=heap/largestInternal,
released=heap/largestInternal, stack, restored/restore_wait.
BLE: otaWorkerState, otaWorkerHeapBefore, otaWorkerLargestBefore,
otaWorkerHeapReleased, otaWorkerLargestReleased, otaWorkerStackBytes,
otaWorkerCreateResult, otaWorkerRestoreAttempts.

Test rzeczywistej funkcji uruchamiania odtwarza brak spójnego bloku16KiB:
stara kolejność odmawia, nowa zwalnia bufory i startuje. Osobno testowane są:
błąd alokacji, opóźnione sprzątanie stosu/odtwarzanie buforów, oba cele OTA,
odmowa równoczesnego żądania i ochrona rejestracji, która zacznie się po
zakolejkowaniu. Konstruktor pełnej ramki SPI testuje zwykłą pracę, ACK końca
i nagłówek konfiguracyjny. Dotychczasowe10 kontroli regresji również zaliczone.
Sprawdzono kompilację, zgodność źródeł, rozmiar slotu, podpis i pobieranie.
Test fizyczny użytkownika pozostaje do wykonania po samodzielnej instalacji.
