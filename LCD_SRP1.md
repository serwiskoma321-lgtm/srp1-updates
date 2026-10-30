# Typ LCD konsolki SRP-1

Konsolka 2.6.2 ma jedną paczkę dla dwóch rodzajów wyświetlacza 20×4.
**Domyślne jest sterowanie bezpośrednio z pinów procesora**, zgodnie ze
zleceniem użytkownika. W konsolce 2.6.1 opublikowany był wyłącznie wariant I²C;
nie obsługiwał LCD podłączonego bezpośrednio.

## Aktualizacja

Do wgrania procesorów wystarczy dotychczasowa **KOMA 1.6.2**.
Nowa aplikacja **1.6.3+112** dodaje wybór typu LCD z telefonu;
nie jest wymagana do przywrócenia domyślnego obrazu na pinach.

1. Przez znaną procedurę Firmware → Wi-Fi OTA zaktualizuj **konsolkę do 2.6.2**.
   Po zakończeniu zapisu i restarcie LCD podłączony do pinów powinien wyświetlać
   obraz bez zmiany ustawień w aplikacji.
2. Zaktualizuj **sterownik do 2.6.2**, aby obsługiwał zmianę typu LCD.
3. Sprawdź odczytane wersje po każdym restarcie.
4. Pomiarowy pozostaje **3.4.1**; nie wymaga ponownej aktualizacji do tej poprawki.
5. Zaktualizuj aplikację do **1.6.3+112**, gdy chcesz zmieniać typ LCD z telefonu.

Aktualizacja konsolki jest możliwa z telefonu mimo pustego LCD. Nie używaj
pierwszego uruchomienia USB ani kasowania całej pamięci do tej poprawki.

## Wybór trybu

W aplikacji: **Parametry → Ustawienia → Typ LCD konsolki**.
Na konsolce: **Ustawienia → Typ LCD**. Wybierz strzałkami i zatwierdź ENTER.

- **Bezpośrednio / PINY** — domyślny tryb 4-bitowy HD44780, bez konwertera I²C.
- **I²C** — konwerter pod adresem **0x27**, SDA **GPIO10**, SCL **GPIO9**;
  magistrala LCD pracuje przy 100 kHz.
- **Auto** — sprawdza odpowiedź adresu 0x27. Jeśli odpowiada, wybiera I²C;
  w przeciwnym razie wybiera piny. W razie nietypowego modułu wybierz tryb ręcznie.

Tryb bezpośredni: RS=GPIO2, EN=GPIO37, D4=GPIO36, D5=GPIO35,
D6=GPIO0, D7=GPIO45; RW wyświetlacza jest połączone z GND.
Klawiatura zachowuje osobną magistralę I²C (SDA4/SCL5).

Wybór zapisuje się w sterowniku razem z pozostałymi ustawieniami i jest
przekazywany do konsolki. Zapis nie zmienia historycznego formatu NVS ani
rozmiaru pakietu konfiguracji UART. Wyjściowa konfiguracja wybiera piny.
Konsolka rozpoczyna pracę od tego domyślnego trybu, a po odebraniu konfiguracji
stosuje zapisany wybór; przy I²C ekran może więc pojawić się po połączeniu ze sterownikiem.

Aplikacja sprawdza potwierdzenie przyjęcia parametru, trwałego zapisu i
zastosowania przez konsolkę. Gdy nie ma jeszcze potwierdzenia zastosowania,
pokazuje to osobno. Ręczne przełączenie działa także przy niewidocznym obrazie;
możesz przywrócić właściwy tryb z aplikacji.

Wybór niewłaściwego typu nie zmienia okablowania. Zwykłe przywrócenie
ustawień sterownika przywraca domyślny typ PINY; osobny zapis kalibracji prądu
pozostaje zachowany.
