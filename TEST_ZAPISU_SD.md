# SRP-1 — test szybszego wysyłania firmware na SD

Sterownik **2.6.6-upload-test**, Android **1.6.4-upload-test (113)**.
To opublikowany wariant do porównania na urządzeniu, nie pomiar osiągniętej
prędkości. W tym etapie nie wgrywano nic przez USB ani Wi-Fi.
Konsolka i pomiarowy nie wymagają aktualizacji.

## Co zmieniono

- KOMA z nowym sterownikiem uzgadnia bloki 64 KiB zamiast 4 KiB; przy starszym
  pozostaje 4 KiB. Nie ma stałej 20 ms pauzy po każdym bloku.
- Sterownik zbiera fragmenty TCP do bufora 4 KiB przed zapisem na SD.
- Nadal po każdym żądaniu flush/fsync, close i kontrola rozmiaru poprzedzają
  potwierdzenie. Zmniejszono liczbę tych operacji przez większe żądania;
  nie potwierdza się danych przechowywanych wyłącznie w RAM.
- Aplikacja sprawdza potwierdzony offset i końcowy rozmiar. Po przerwaniu
  wznawia od rzeczywiście zapisanego miejsca; nie od wysłanego bez potwierdzenia.
- Po zakończeniu przesyłania aplikacja pokazuje jego czas. Obejmuje żądania,
  zapis i ponowienia w tej operacji, bez późniejszego restartu/flashowania.
- Odpowiedź sterownika rozdziela czas odbioru, zapisów i commit na SD do logów.
- Druga dioda RGB: pomarańczowa w rejestracji/podtrzymaniu, czerwona podczas
  transferu narostu i końcowego zapisu, także ponowień. Gotowość dopiero po
  zamknięciu sesji. Niebieski serwis zachowuje pierwszeństwo.

## Jak porównać

1. Zainstaluj dołączonyAPK `KOMA-1.6.4-upload-test-113.apk` jako aktualizację.
   Biała ikona i dotychczasowe dane pozostają. TestowyAPK pobiera się z plików
   tego wydania; stabilny kanał „Sprawdź aktualizacje” aplikacji nie jest zmieniany.
2. KOMA → Firmware → Sterownik → Sprawdź/wybierz: wybierz 2.6.6-upload-test.
   Pobierz, prześlij na SD i zapisz pokazany czas. To przesłanie obsługuje jeszcze
   stary program sterownika (mniejsze bloki).
3. Zweryfikuj i zastosuj aktualizację sterownika, poczekaj na restart i potwierdź
   odczytaną wersję 2.6.6-upload-test.
4. Prześlij tę samą paczkę ponownie i porównaj czas. Tym razem oba końce
   obsługują 64 KiB. Do samego pomiaru czasu nie trzeba ponownie stosować firmware.
5. Opcjonalnie sprawdź przerwanie i wznowienie transferu. Po ponownym połączeniu
   rozmiar końcowy i weryfikacja paczki muszą być poprawne.
6. Sprawdź też dwie kolejne rejestracje z narostem i kolory drugiej diody.

## Powrót

- Sterownik 2.6.5 pozostaje aktywny w wykazie KOMA i w poprzednim wydaniu.
  Pobierz/zastosuj go zwykłą procedurą, jeśli chcesz cofnąć wariant testowy.
- APK `KOMA-1.6.3-rollback-114.apk` zawiera poprzedni kod aplikacji. Wyższy
  numer Androida umożliwia instalację na wersję testową bez odinstalowania.
  W samym interfejsie starego kodu może nadal widnieć 1.6.3+112.
- Oba APK mają ten sam podpis co dotychczasowa KOMA. Żaden instalator nie został
  uruchomiony automatycznie. Nie usuwaj danych aplikacji na potrzeby powrotu.

Przed publikacją: kompilacje, kontrola źródeł/slotu/podpisów, testy protokołu,
ponowień i awarii zapisu. Nie ma jeszcze wyniku szybkości na fizycznym sprzęcie
dla tego wariantu. Wcześniejsze 39,1 s / 1,51 MB dotyczyło sterownika 2.6.4 i komputera
wysyłającego 16 KiB, nie nowego testu telefonu.
