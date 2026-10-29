# Kalibracja prądu SRP-1

Wymagany komplet: KOMA 1.6.2, pomiarowy 3.4.1, konsolka 2.6.1,
sterownik 2.6.1. Stare wersje zachowują zwykłe pomiary, ale nie udostępniają
całej obsługi kalibracji. Numer VIN i profile procesorów nie są nadawane
ani kasowane przez tę aktualizację.

## Aktualizacja z GitHuba

1. W KOMA wybierz **Sprawdź aktualizacje**, pobierz wydanie 1.6.2 i potwierdź
   instalację systemową. Zachowaj dotychczasową aplikację i jej dane.
2. Połącz aplikację z własnym SRP-1 przez Bluetooth. Wejdź w **Firmware**.
3. Aktualizuj kolejno pomiarowy do **3.4.1**, konsolkę do **2.6.1**,
   a na końcu sterownik do **2.6.1**.
4. Dla każdego celu wybierz aktualizację z GitHuba, pobierz właściwą paczkę,
   uruchom **Start Wi-Fi**, połącz telefon z siecią OTA sterownika i prześlij
   paczkę na SD. Dokończ zatrzymanie Wi-Fi/powrót do BLE zgodnie z ekranem.
5. Wybierz paczkę z SD, sprawdź cel i wersję, użyj **Zastosuj**.
   Poczekaj na zakończenie i wykonaj **Restart** wskazany przez aplikację.
6. Potwierdź odczytaną wersję przed rozpoczęciem następnego celu.
7. Po komplecie sprawdź **Parametry → Kalibracja** w aplikacji oraz
   **Kalibracja** w menu konsolki.

Paczki firmware są podpisane i zaszyfrowane, przeznaczone dla sprawdzonego
kompletu SRP1-2. Zwykłe OTA zapisuje nieaktywny slot programu i zachowuje NVS.
Nie używaj pierwszego uruchomienia ani pełnego kasowania pamięci do tej aktualizacji.

## Parametry

Przed kalibracją ze wzorca wyłącz **Parametry → Rejestr → Detekcja prądu**
i poczekaj na zakończenie bieżącej rejestracji oraz zapisu. Dopiero wtedy podaj
stabilny sygnał wzorcowy. Po zakończeniu kalibracji przywróć poprzednie ustawienie
detekcji. Sam pomiar napięcia i prądu pozostaje dostępny przy wyłączonej detekcji.

- **Korekta wskazania / Skala I**: 50,00–150,00%, domyślnie **100,00%**.
- **Korekta zera / Zero I**: od -500 do +500 mA, domyślnie **0 mA**.
  Dodatnia wartość jest odejmowana od wskazania; wynik RMS nie spada poniżej zera.
- **Kalibracja ze wzorca / Wzorzec I**: przy stabilnym sygnale podaj prąd
  zmierzony miernikiem wzorcowym, 50–30000 mA. Sterownik wylicza nową skalę,
  uwzględniając bieżącą korektę zera. Wynik poza zakresem jest odrzucany.
- **Przywróć kalibrację fabryczną / Reset kalibracji**: przywraca 100,00% i 0 mA.
  W aplikacji wymaga potwierdzenia. Na konsolce ustaw TAK i zatwierdź.

Na konsolce wpisanie skali cyframi oznacza pełne procenty, np. **105** oznacza
**105,00%**. Strzałki pozwalają na krok **0,01 punktu procentowego**.
Korektę ujemną można ustawić strzałkami. ENTER zatwierdza pole, wyjście z menu
wykonuje zwykły trwały zapis konfiguracji. Odrzucenie lub błąd zapisu pojawia się
w komunikacie konsolki; wtedy odśwież i sprawdź wartości.

Aplikacja czeka na odpowiedź przyjęcia i trwałego zapisu, a następnie pokazuje
osobno, czy pomiarowy potwierdził zastosowanie. Nie traktuje samego wysłania
komendy jako sukcesu. Odśwież ekran, jeżeli pozostaje oczekiwanie na potwierdzenie.

Zmiany są blokowane podczas trwającego procesu, rejestracji i finalizacji.
Wspólne źródło ustawień jest w sterowniku. Zwykły reset ustawień użytkownika
zachowuje kalibrację. MAC pomiarowego jest zapisany wraz z kalibracją;
po wymianie procesora należy jawnie przywrócić i ponownie sprawdzić kalibrację.
Wymiana samego czujnika również wymaga jej sprawdzenia.

## Rejestry i zgodność

Nowe pliki KREG zawierają kopię skali, korekty zera i identyfikację pomiarowego.
Wykres narostu korzysta ze skali danej sesji. Nadal jest estymacją z surowego ADC;
korekta zera RMS nie jest przesunięciem chwilowego przebiegu.
Stare rejestry zachowują poprzednie przeliczenie.

Dotychczasowe współczynniki i charakterystyka małych prądów pozostają bazą.
Neutralna kalibracja zachowuje dotychczasową skalę; nie włączono starego,
nieużywanego offsetu 26 mA. Kalibrację należy sprawdzić na kilku wartościach
prądu i używanych częstotliwościach — jeden punkt nie potwierdza całego zakresu.

W tym zadaniu nie wgrywano firmware na urządzenia. Kontrola po fizycznej
instalacji i porównanie z miernikiem wzorcowym pozostają po stronie użytkownika.
