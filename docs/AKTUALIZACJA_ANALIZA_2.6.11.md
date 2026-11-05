# KOMA — statystyki fragmentu, wyniki historyczne i osobne okna

Pakiet: KOMA **1.6.6+117** (Android i Windows) oraz sterownik SRP-1
**2.6.11**. Pomiarowy **3.4.4** i konsolka **2.6.2** pozostają bez zmian.
Użytkownik instaluje samodzielnie. Nie wykonujemy automatycznego flashowania.

## Aplikacja

- Nad tabelą statystyk rejestru są dwa uchwyty wyboru początku i końca.
  Minimum, średnia i maksimum wszystkich wielkości przeliczają się podczas
  przesuwania. Widoczne są granice czasu, długość i liczba próbek.
- „Cały rejestr” przywraca pełny zakres. „Pomiar aktywny” używa granicy
  zapisanej w nowym rejestrze. Wybrany zakres nie usuwa danych i nie zmienia
  zapisu. Wyniki reakcji i narostu opisują całą próbę, niezależnie od suwaków.
- Nowa sekcja wyników pokazuje czas reakcji, narostu i narostu + reakcji.
  Brak wyznaczonego wyniku jest odróżniony od poprawnej wartości zero.
  Starsze pliki bez tych metadanych mają informację o braku zapisanego wyniku.
- Starsze rejestry nadal się otwierają i obsługują ręczny wybór zakresu.
  Nie odtwarzamy ich aktywnej granicy przez odjęcie aktualnego podtrzymania
  ani przez zgadywanie progu. Ustawienia urządzenia zmienione po pomiarze
  nie wpływają na interpretację zapisanego rejestru.
- W Windows na pasku KOMA jest zapamiętywany przełącznik osobnych okien.
  Wyłączony zachowuje dotychczasową nawigację. Włączony otwiera główne
  moduły w osobnych oknach. Ponowne wybranie modułu przywołuje jego okno.
  Android zachowuje zwykłą nawigację.
- Każde połączenie z danym modułem sprzętowym ma jednego właściciela.
  Przekazanie SRP/TSR z głównego okna do osobnego rozłącza poprzedniego
  klienta; połącz urządzenie w nowym oknie. Wewnętrzny przycisk połączenia
  w Rejestrze urządzeń otwiera pulpit w tym samym oknie, aby po powrocie
  zachować jego połączenie. Wspólne ustawienia i zapisy archiwów są chronione
  blokadami plików, a aktualizator wymaga zamknięcia osobnych okien modułów.

## Sterownik i dane rejestru

- Każdy nowy KREG zapisuje konfigurację używaną podczas tej próby:
  podtrzymanie, cztery progi prądu, kalibrację i identyfikator pomiarowego.
  Dotychczasowe metadane próbkowania narostu, w tym dzielnik, pozostają.
- Granica zaniku prądu pochodzi ze zbocza sygnału procesora pomiarowego,
  a nie z czasu późniejszej obsługi zadania. Powrót prądu w podtrzymaniu
  unieważnia poprzednią granicę; końcowy aktywny zakres obejmuje całą próbę
  do ostatniego zaniku, łącznie z ewentualnymi wewnętrznymi przerwami.
- Sterownik zatrzaskuje wyniki z pierwszej poprawnej ramki końca tej sesji.
  Nie pożycza wyników następnego pomiaru. CSV również używa zatrzaśniętych
  progów i wyników. Nowe rozszerzone metadane zakresu są w KREG.
- Ustawienia wpływające na akwizycję są blokowane podczas aktywnej lub
  domykanej sesji. Podtrzymanie i kalibracja są zamrożone na czas próby.
- Zachowane są pełny strumieniowy CSV, kontrola całego KREG, ponowienia,
  limity oczekiwania i czerwona dioda do potwierdzonego zakończenia zapisu.
  Przy czerwonej diodzie nie rozpoczynaj kolejnej rejestracji.

Nowy nagłówek KREG ma 160 bajtów. Nowy sterownik odczytuje również stare
nagłówki 32/64/96 bajtów. Starszy sterownik nie zna nowego rozszerzenia przy
odzyskiwaniu rejestrów, dlatego przed cofnięciem firmware pobierz nowe
archiwa na telefon lub komputer. Poprzednie paczki pozostają dostępne.

## Kolejność i krótki test

1. Zainstaluj KOMA 1.6.6 przez „Sprawdź aktualizacje” na telefonie i komputerze.
2. W KOMA → Firmware → Sterownik → Sprawdź/wybierz pobierz i zastosuj 2.6.11.
   Potwierdź wersję po restarcie. Nie aktualizuj pomiarowego ani konsolki.
3. Zrób nową automatyczną rejestrację z podtrzymaniem. Poczekaj na zieloną
   diodę, pobierz rejestr i sprawdź zapisane progi, podtrzymanie oraz wyniki.
4. Porównaj „Pomiar aktywny” z „Cały rejestr”. Przesuń oba uchwyty,
   wybierz środkowy fragment i sprawdź zmianę minimum/średniej/maksimum.
   Pełne dane powinny być nadal dostępne po przywróceniu całego zakresu.
5. Otwórz także stary rejestr: ręczny zakres działa, brak nowych metadanych
   jest opisany, nie są dopisywane nieistniejące wyniki.
6. W Windows włącz przełącznik, otwórz Rejestry i SRP-1 w osobnych oknach.
   Powtórne kliknięcie przywołuje istniejące okno. Wyłącz przełącznik i po
   zamknięciu osobnego okna sprawdź zwykłą nawigację. Ustawienie przełącznika
   powinno pozostać po ponownym uruchomieniu aplikacji.

Testy kodu obejmują rzeczywisty nagłówek z firmware odczytywany przez Dart,
granice czasowe i wznowienie prądu, suwaki podczas przeciągania, stare pliki,
blokady między procesami i odzyskanie blokady po zakończeniu procesu.
Testy sprzętowe nowej rejestracji użytkownik wykonuje po instalacji.
