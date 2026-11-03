# SRP-1 — domykanie sesji i diagnostyka

Sterownik **2.6.8**, pomiarowy **3.4.3**. Paczki do samodzielnego testu.
KOMA **1.6.5+116** i konsolka **2.6.2** pozostają bez aktualizacji.
Nie wykonano automatycznego wgrywania ani resetu podłączonych urządzeń.

## Co naprawiono

- Pomiarowy zgłasza zakończenie również wtedy, gdy nie wyznaczył czasu reakcji.
  Zgłoszenie czeka na potwierdzenie; nie znika przed wymianą poprawnej ramki.
- Gotowość bufora jest publikowana atomowo dopiero po zakończeniu kopiowania.
  Nowy pomiar nie nadpisuje bufora oczekującego na transfer.
- Nieudana próba nie kasuje narostu: dwa żądania ponowienia, trzecia próba
  kończy się wynikiem. Numery bloków wykrywają powtórzone/stare fragmenty.
  Nowe ramki są uzgadniane, starsze wersje zachowują dotychczasowy format.
- Limit transmisji uwzględnia sumy kontrolne (30 próbek na ramkę64B).
  Pełne15360 próbek przechodzi w512 ramkach plus ramka końcowego potwierdzenia.
  Pełny bufor bez dodatkowego terminatora jest prawidłowym wynikiem.
- Po 30 s od żądania zakończenia brak końca/narostu nie blokuje bezterminowo
  zwykłego rejestru. Sterownik zapisuje go z wynikiem WAIT_TIMEOUT lub innym
  kodem braku narostu. Nie uzupełnia danych narostu sztucznymi wartościami.
- KREG jest zapisywany do pliku tymczasowego, odczytywany i weryfikowany CRC,
  przemianowany i dodany do indeksu. Teraz wynik tej operacji musi być poprawny.
- CSV jest sprawdzany przez odczyt. Częściowy wiersz jest nadpisywany od tej
  samej pozycji, a udany etap KREG nie powtarza się przy ponowieniu CSV.
- Trzy nieudane próby SD pozostawiają czerwoną diodę, błąd diagnostyczny i RAM.
  Nie sygnalizują gotowości i nie odblokowują nowych pomiarów kosztem danych.
  Ponowienie po usunięciu przyczyny jest dostępne diagnostycznie (REG_RETRY).
- Próba, która nie osiągnęła progu potwierdzenia, oraz celowo wyłączony zapis SD
  są domykane jako NOT_RECORDED. Nie blokują kolejnego startu i nie udają zapisu.
- Zachowane szybkie Wi-Fi, sygnalizacja konsolki, kalibracja i czas narostu.

## Aktualizacja

1. Zakończ pomiary. Aktualizacja/restart usuwa niezapisane dane RAM bieżącej
   zablokowanej próby; użytkownik potwierdził, że tych wartości nie odzyskujemy.
   Jeżeli próba nadal blokuje tryb OTA, uruchom ponownie cały zestaw przed
   aktualizacją. USB może nadal zasilać procesory po wyłączeniu zasilania głównego.
2. W KOMA → Firmware → Sterownik → Sprawdź/wybierz pobierz **2.6.8**, prześlij
   przez Wi-Fi i zastosuj. Po restarcie odczytaj wersję.
3. W Firmware → Pomiarowy wybierz **3.4.3** i zaktualizuj przez sterownik.
   Po zakończeniu sprawdź obie wersje. Nie wykonuj prób między tymi etapami.
4. Wykonaj kilka kolejnych rejestracji z narostem, szczególnie krótką próbę,
   która nie osiąga progu końcowego narostu. Po każdej sprawdź obecność nowego
   rejestru, możliwość kolejnego startu i powrót koloru po domknięciu.
5. Przy czerwonej diodzie nie resetuj od razu: podłącz oba USB i odczytaj
   diagnostykę. REG_STATUS w sterowniku działa bez rozłączania aplikacji BLE.

Poprzedni sterownik **2.6.7** pozostaje w wykazie. Dołączono dotychczasowy
pomiarowy **3.4.2** jako wybieralny powrót. Zachowano ten sam układ OTA/NVS;
paczki są podpisane, szyfrowane i przypisane do konkretnych MAC kompletu SRP1-2.

## Diagnostyka

Odczyt: USB sterownika `REG_STATUS` albo BLE `APP:REG_INFO`.
Numer sesji diagnostycznej jest licznikiem od uruchomienia, nie numerem pliku.

| Pole | Znaczenie |
|---|---|
| regSessionSeq | Kolejność rozpoczętych sesji od uruchomienia |
| regCompletionStage | 0 bezczynność, 1 pomiar, 2 oczekiwanie końca, 3 transfer, 4 ponowienie transferu, 5 SD, 6 ponowienie SD, 7 zapisane, 8 błąd SD, 9 bez zapisu zgodnie z progami/ustawieniem |
| regRiseOutcome | 0 oczekiwanie, 1 narost odebrany, 2 wyłączony, 3 brak bufora, 4 wyczerpane próby, 5 przekroczony czas |
| regStopSeen | Czy faktycznie odebrano koniec od pomiarowego (timeout nie ustawia tego na 1) |
| regTransferAttempts / regSdAttempts | Próby bieżącej/ostatniej sesji |
| regSdResult | Ostatni etap/wynik zapisu, np. NO_SD, OPEN_WRITE, VERIFY, CSV_WRITE_VERIFY, OK |
| regKregSaved / regCsvSaved | Potwierdzone fazy trwałego zapisu |
| regWaitMs | Czas oczekiwania, 0 po prawidłowym domknięciu |

Po trzech błędach SD polecenie USB `REG_RETRY` lub BLE `APP:REG_RETRY` pozwala
ponowić zapis zachowanego RAM. Polecenie nie wyłącza narostu ani nie zmienia
ustawień pomiaru. Po resecie RAM jest tracony — nie jest to trwała kolejka.

Pomiarowy: logi END_QUEUED, END_ACK, XFER_ABORT i okresowe END_SUMMARY.
END_SUMMARY: a=numer zakończenia od startu, b=czas reakcji przy zakończeniu,
c=liczba prób, d=1 oczekiwanie / 2 transfer / 3 przerwanie / 4 odebrane.
Podsumowanie zachowuje ostatnią przyczynę także po przepełnieniu kolejki USB.
`lost` dotyczy komunikatów diagnostycznych, nie próbek rejestru.

W nowych KREG zachowano nagłówek96B. Rezerwowe słowa TLV0x1002:
offset88=wynik narostu, offset92=liczba prób transferu. CRC obejmuje te pola.
Indeks oznacza brak narostu jako COMPLETE_NO_RISE; dotychczasowa KOMA pokaże
taki rejestr w filtrze „Z problemami”. Poprawny pomiar zwykły pozostaje czytelny.

## Zakres weryfikacji

Wykonano test dwóch rzeczywistych pętli SPI w symulowanej wymianie full duplex:
brak czasu reakcji, utracony ACK/START, błędna suma, krótki odczyt DMA,
powtórzony blok, ograniczone ponowienia, starszy protokół, brak END i wrap zegara.
Testy rzeczywistego finalizatora i zapisu obejmują brak SD, częściowy CSV,
błędny odczyt, ponowienie bez duplikatu oraz dwa kolejne zapisy.
Sprawdzono kompilacje, zgodność źródeł, podpisy i pobieranie opublikowanych
paczek. Fizyczne pomiary po instalacji wykona użytkownik. Historycznej przyczyny
konkretnej próby nie dało się odtworzyć z logu rozpoczętego już po zdarzeniu.
