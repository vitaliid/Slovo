# tools/sqlite — власна `sqlite3.dll` зі Snowball (B-31)

Одна DLL для застосунку й виробника `library.db`: SQLite 3.54.1 + FTS5 + токенізатор
`fts5-snowball` + Snowball 3.2.0 (`ukrainian`, `russian`, `english` та решта).
Токенізатор реєструється сам (`SQLITE_EXTRA_INIT` → `sqlite3_auto_extension`) —
`sqlite3_load_extension` не потрібен.

| Що | Де |
|---|---|
| Готова DLL, консоль на тій самій DLL, ліцензії | `out\` |
| Версії й SHA-256 | `out\build-info.txt` |
| Вихідні коди (без змін) | `vendor\` — амальгамація SQLite, `fts5stemmer.c`, `libstemmer_c-3.2.0.tar.gz` |
| Клей ядро ↔ токенізатор | `slovo_snowball.c` |
| Збірка | `build.sh` |
| Перевірка SQL | `test.sql` |
| Перевірка з Delphi | `delphi\SnowballCheck.dpr` |

## Перевірка

```
cd out
sqlite3.exe :memory: ".read ../test.sql"
```
Усі рядки мають починатися з `PASS`.

Delphi: відкрити `delphi\SnowballCheck.dpr`, додати платформу **Windows 64-bit**,
зібрати, покласти `out\sqlite3.dll` поруч з EXE, запустити в консолі.
Кінець виводу — `ALL PASS`, код виходу 0.

## Перезбірка

Linux (Ubuntu): `sudo apt install gcc-mingw-w64-x86-64`, далі `./build.sh`.
Windows: MSYS2, шелл **UCRT64**, `pacman -S mingw-w64-ucrt-x86_64-gcc`, далі `./build.sh`.

Оновити SQLite = замінити файли в `vendor\sqlite\` новою амальгамацією
(sqlite.org → `sqlite-amalgamation-*.zip`) і перезапустити скрипт.
