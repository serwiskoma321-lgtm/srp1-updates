# SRP-1 — czas narostu i ustawienia widoku rejestrów

KOMA **1.6.5+116** (Android i Windows), sterownik **2.6.7**.
Użytkownik sam pobiera i instaluje. Nie aktualizować pomiarowego ani konsolki.

## Zmiany

- KOMA automatycznie pamięta wybrane wykresy i ich kolejność, wysokość oraz
  tryb wykresy/tabela. Jeden ostatni układ dla kolejnych rejestrów i osobny dla
  porównań. Telefon i komputer zapisują własne preferencje. Dostępny reset widoku.
- Czas narostu uwzględnia dwa przeplatane kanały ADC, oprócz dotychczasowego
  dzielnika zapisu próbek. Sterownik zapisuje poprawione znaczniki czasu w KREG.
- Nagłówek KREG zawiera częstotliwość łączną ADC, liczbę kanałów, dzielnik,
  rozmiar bufora, średnią i wersję modelu czasu. Parametry są pobierane na
  początku sesji; próbkowanie/dzielnik nie mogą zmienić się przed jej zapisaniem.
- Aplikacja używa czasu z pliku, niezależnie od późniejszych ustawień urządzenia.
  Szczegóły próbkowania są pod przyciskiem informacji na ekranie narostu.
  Krótkie zakresy na osi są opisane w milisekundach.
- Parametry → Data: przycisk ustawia pełną lokalną datę i czas z telefonu lub PC.
  Sterownik sprawdza kalendarz, wykonuje jeden zapis RTC i odsyła potwierdzenie.
  Zegar konsolki korzysta z dotychczasowego odczytu czasu ze sterownika.
- Zachowane wcześniejsze poprawki finalizacji rejestracji, szybkiego przesyłu
  Wi-Fi oraz niebieskiej/czerwonej sygnalizacji konsolki.

## Kolejność aktualizacji i sprawdzenie

1. W KOMA na telefonie i komputerze wybierz **Sprawdź aktualizacje** i zainstaluj
   aplikację **1.6.5+116**. Dane i ustawienia pozostają w katalogach aplikacji.
2. Połącz KOMA ze sterownikiem. Firmware → Sterownik → Sprawdź/wybierz:
   wybierz **2.6.7**, pobierz paczkę, prześlij ją przez Wi-Fi na SD i zastosuj
   aktualizację. Poczekaj na zakończenie zapisu i restart; sprawdź wersję.
3. Dodaj np. moc czynną do wykresów, wyjdź i otwórz je ponownie. Sprawdź również
   po ponownym uruchomieniu KOMA. Preferencje telefonu i Windows są niezależne.
4. Wykonaj nową rejestrację z narostem: odstępy odpowiadające blokom około
   100 ms powinny teraz zajmować około 100 ms zamiast 50 ms. Otwórz informację
   o czasie narostu i sprawdź zapisany dzielnik. Zmiana ustawień po rejestracji
   nie może zmienić czasu w tym rejestrze. Sprawdź dwa kolejne starty i zapis SD.
5. Przy zatrzymanej rejestracji użyj Parametry → Data → Ustaw bieżącą datę i czas;
   sprawdź potwierdzenie oraz wskazania czasu urządzenia i konsolki.

## Starsze pliki i zakres sprawdzenia

Starsze KREG pozostają czytelne. Bez metadanych próbkowania aplikacja opisuje
czas narostu jako niezweryfikowany i nie zgaduje parametrów z bieżącej konfiguracji.
Nie przepisuje starych plików i nie mnoży automatycznie ich czasu. Poprawiona
skala czasu dotyczy NOWYCH rejestrów zapisanych przez sterownik 2.6.7.
Pionowe znaczniki granic bloków pozostają w przebiegu jak dotychczas.

Sprawdzono kompilacje, testy obliczeń/formatu KREG/CRC i odczyt pliku utworzonego
przez rzeczywisty kod sterownika w parserze KOMA. Testy aplikacji i regresji
transmisji/finalizacji/RGB zaliczone. Nowa paczka nie została automatycznie
wgrana na sprzęt; fizyczny test rejestracji i aktualizacji wykona użytkownik.
Poprzednie paczki sterownika pozostają w wykazie do ewentualnego powrotu.
