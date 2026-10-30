# SRP-1 — sterownik2.6.5: szybkie Wi-Fi i sygnalizacja serwisu

**Aktualizuj wyłącznie sterownik do2.6.5.** Konsolka2.6.2 obsługuje już
potrzebne kolory; nie trzeba jej wgrywać ponownie. Obecny pomiarowy i KOMA
pozostają bez zmian.

Poprzednia poprawka przyspieszyła pobieranie, ale wyciszyła także informację
o serwisie. Sterownik wysyła teraz stan przy wejściu/wyjściu z trybu serwisowego
i przy zmianie połączeniaWi-Fi/BLE. Dioda sterownika świeci ciemnoniebiesko
w serwisie, dioda telefonu ciemnoniebiesko przy połączeniuWi-Fi.
Niezmieniony stan nie generuje dodatkowych pakietów. Nie wznowiono cyklicznych
pomiarów ani odświeżania konsolki podczas transferu. Stosowany jest zgodny
format rozumiany przez obecną konsolkę, bez zmiany protokołu.

Wydanie zawiera też poprawkę blokady drugiego pomiaru automatycznego oraz
przyspieszenieWi-Fi. Na poprzedniej2.6.4 rzeczywisty transfer tych samych
577676B skrócił się48,2s→7,5s(6,4x), pliki były identyczne. Ten wynik nie jest
jeszcze pomiarem2.6.5 na telefonie. Kalibracja, konfiguracjaLCD i daneSD
pozostają zachowane.

## Aktualizacja i sprawdzenie

1. KOMA → Firmware → Sterownik → Aktualizuj → Sprawdź/wybierz:
   wybierz2.6.5 i pobierz paczkę zGitHuba.
2. Zwykłą procedurąWi-FiOTA prześlij paczkę naSD, zweryfikuj i zastosuj.
   Poczekaj na zakończenie i restart, sprawdź odczytaną wersję2.6.5.
3. WłączWi-Fi rejestru: dioda sterownika powinna pokazać serwis.
   Po połączeniu telefonu druga dioda powinna pokazaćWi-Fi.
4. Pobierz rejestry i zakończWi-Fi; kolory mają wrócić do normalnego stanu.
5. Sprawdź także przejście doWi-FiOTA. Podczas jawnej aktualizacji konsolki
   jej protokółOTA zachowuje pierwszeństwo nad komunikatamiLED.

Weryfikacja: końcowa kompilacja, rozmiar slotu, podpis/szyfrowanie/MAC;
test rzeczywistego nadajnika z istniejącym dekodowaniem i mapowaniemRGB
konsolki obejmuje wejście, połączenie, rozłączenie, wyjście, brak ruchu
przy niezmienionym stanie i ochronę własnościUART podczasOTA.
Test fizycznych diod i aktualizacji tej wersji wykonuje użytkownik;
nie wgrano2.6.5 przezUSB w tym zadaniu. Paczka przypisana do sterownikaSRP1-2.
