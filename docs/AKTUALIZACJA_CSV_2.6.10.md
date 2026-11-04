# SRP-1 — kompletny CSV i buforowany zapis SD

**Sterownik2.6.10**, do samodzielnego zainstalowania. Pomiarowy pozostaje
**3.4.4**, konsolka2.6.2 i KOMA1.6.5+116. Niczego nie wgrano automatycznie.

## Zgłoszenie i ustalenia

W uchwyconej próbie narost13018 próbek przeszedł poprawnie w880ms.
Finalizacja na SD trwała3943ms. Czerwony obejmował transfer i zapis/kontrolę,
łącznie około5s, bez przekroczenia limitu ani brakującego potwierdzenia.
Binarny KREG potwierdził komplet próbek i CRC. Tekst danych narostu do CSV
miał natomiast1391 znaków wobec minimum26035. Podczas próby rezerwacji78115B
pozostało8988B heap. Wynik alokacji i dopisywania String był ignorowany,
a kontrola pliku porównywała go do już niepełnego tekstu.

## Co zmieniono

- Dane CSV są generowane bez dużego wiersza/serii/narostu w RAM. Stałe
  bufory512B obsługują zapis i odczyt. Każde formatowanie i każda operacja
  zapisu muszą się udać. Kontrolowane są granice narostu i jego terminator.
- Po zapisie ponownie generowana jest każda oczekiwana wartość, porównywana
  bajt po bajcie z kartą. Kontrolowane są liczby wartości zwykłych, próbek
  narostu i bajtów. Nie ma porównania do potencjalnie uciętego String.
- Metadane wiersza są zamrożone na oba przebiegi kontroli. Format CSV,
  precyzja liczb i podział narostu na kolumny po5000 wartości pozostają.
- Częściowy zapis nadal jest ponawiany od pierwotnej pozycji, bez podwójnego
  wiersza i bez ponownego tworzenia już potwierdzonego KREG.
- KREG zapisuje i odczytuje większe porcje512B zamiast osobnej operacji
  dla każdej próbki8B. Zachowano identyczny format, kolejność wszystkich
  próbek, metadane oraz kontrolę całego nagłówka i CRC obu bloków.
- Przy błędzie zapis nie jest potwierdzany. RAM pozostaje, ponowienia są
  ograniczone, czerwona dioda i blokada kolejnego startu pozostają aż do
  prawidłowego zamknięcia. TELEMETRIA może działać w czasie finalizacji.
  Mały bufor zapisu nie jest kolejką dla drugiej jednoczesnej rejestracji.
- Log USB [CSV] raportuje liczbę bajtów, zwykłych wartości, próbek narostu
  i wynik weryfikacji. Dotychczasowy REG_STATUS pozostaje dostępny.

## Testy

14 kontroli regresji. Test rzeczywistego writer-a CSV odczytuje niezależnie
wszystkie13018 i15360 wartości narostu oraz599 próbek zwykłych. Sprawdza
podział kolumn, brak dużych rezerwacji String, błędy SD/odczytu, naprawę
częściowego wiersza/nagłówka i kolejne zapisy bez duplikatów.

Test rzeczywistego starego i nowego writer-a KREG porównuje całe pliki
bajt po bajcie:599 zwykłych próbek i15360 narostu,156592B. Wynik identyczny,
CRC poprawne. Liczba wywołań write/read spadła z15962 do306 dla każdego
kierunku. Błąd częściowego zapisu oraz uszkodzenie nagłówka i różnych
fragmentów danych nadal uniemożliwiają opublikowanie pliku.

Test rzeczywistej blokady startu potwierdza oczekiwanie podczas zapisu i
po pracy zadania SD, aż do odebrania wyniku przez finalizator. Testy
OTA, pamięci, Wi-Fi, sygnalizacji, kalibracji i narostu także zaliczone.
Sprawdzono końcową kompilację, zgodność źródeł, podpis i wykaz KOMA.
Nie mierzono czasu tej wersji na urządzeniu. Mniej operacji FS nie jest
deklaracją określonego mnożnika przyspieszenia na rzeczywistej karcie.

## Instalacja i sprawdzenie

1. Zakończ bieżące pomiary. W KOMA → Firmware → Sterownik → Sprawdź/wybierz
   wybierz2.6.10, pobierz, prześlij na SD i zastosuj aktualizację.
2. Po restarcie potwierdź sterownik2.6.10 i pomiarowy3.4.4. Tylko sterownik
   wymaga nowej paczki. Poprzedni2.6.9 pozostaje w wykazie do powrotu.
3. Wykonaj kilka kolejnych prób, również dłuższą z pełnym naro­stem.
   Poczekaj na zieloną diodę przed następną rejestracją.
4. Sprawdź obecność i kompletność danych w CSV oraz KREG. Przy obu USB
   zachowaj log [CSV], [KREG_SHADOW], [AUTO_FINALIZE] i [SESSION].
5. Przy błędzie pozostaw urządzenie włączone do diagnostyki. Ponowienie
   zachowanego RAM jest dostępne istniejącym REG_RETRY po usunięciu przyczyny.

Ta aktualizacja naprawia nowe zapisy. Nie odtwarza automatycznie brakujących
wartości w starych CSV; pełny KREG poprzedniej próby pozostaje osobnym plikiem.
Partycje OTA/NVS, kalibracja i przypisanie paczki do MAC są zachowane.
Nie dołączono prywatnych źródeł, kluczy ani logów sprzętu do publikacji.
