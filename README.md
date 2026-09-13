# Slovo

A Windows desktop reader for a Christian library — the works of Ellen G. White,
Bible translations, and related historical and devotional books — with fast
full-text search across them.

It is a ground-up successor to **«Исследуя Слово 4.0»**
([original app](https://bible.ucoz.com/load/khristianskie_programmy_skachat_besplatno/ehlektronnaja_biblioteka_dlja_khristianina/programma_issleduja_slovo_4_0/183-1-0-1667)),
which has served the community well for years. The goal is to keep what made it
good and fix what did not.

## Status

**Skeleton only.** The repository currently contains an empty VCL application:
a main window with a `File → Exit` menu, a `Help → SQLite diagnostics` item, and
the SQLite binding those diagnostics exercise. No reader, no search, no content
modules yet. UI design has not started.

Do not expect a working program if you build this today.

## Why a rewrite

Slovo 4.0 is fast and its search is excellent. Two things hold it back:

- **Adding a new book is hard.** The library is effectively closed.
- **User data does not survive.** Highlights and comments are difficult to
  extract and are lost when the application is uninstalled.

Both are consequences of the storage format, so the new version starts there: an
open, versioned, per-book file format, with user annotations kept separately from
read-only content.

## Goals

- Preserve the responsiveness and search quality of the original.
- An open module format — adding a book should not require touching the app.
- User annotations that outlive any install, uninstall or upgrade.
- One self-contained EXE, no external runtime dependencies.

Annotations and online library updates are planned but deliberately outside the
first milestone.

## Requirements

- **Delphi 13** (Community Edition is sufficient — see licensing note below)
- **Windows 10 or newer, x64**

VCL, 64-bit only. There is no 32-bit build and none is planned.

## Building

Open `Slovo.dproj` in the Delphi IDE and build (`Shift+F9`). Output lands in
`Win64\Debug\`.

From the command line, after running the IDE's `rsvars.bat`:

```
msbuild Slovo.dproj /p:Config=Release /p:Platform=Win64
```

`Slovo.res` is regenerated during the build from settings in `Slovo.dproj`
(icon, version info), so a build may leave it modified in the working tree. If
the application icon ever looks wrong, delete `Slovo.res` and rebuild.

## Interface languages

The interface ships in Ukrainian (default), Russian and English, switched from
**View → Language** while the program is running - no restart, no separate
build.

Every translated string lives in `lang\<code>.lang`: a plain UTF-8 file of
`key = value` lines, one file per language, read at run time from next to the
EXE (a post-build event copies them there from `lang\` in the repository).
Correcting wording therefore needs a text editor, not Delphi, and switching
away from a language and back re-reads its file.

A key that is missing from the current file is **not** an error: the key itself
is shown in the interface and the miss is written once to the debug log. A
half-translated interface stays usable and says exactly what is missing.

Adding a language means copying `lang\en.lang`, translating the values, and
adding its code to `UILanguageCodes` in `Presentation.Strings` together with a
menu item for it.

The `.dfm` files hold English placeholders that exist only for the form
designer and are overwritten at run time by `TMainForm.ApplyStrings`. Adding a
caption means adding a key to the three `.lang` files and a line to that
method - never a translated literal in a `.dfm`.

Technical text is not translated: error messages, exceptions and the SQLite
diagnostics report are English and stay as resourcestrings next to the code
that raises them.

The chosen language is not remembered between runs yet - the application starts
in Ukrainian every time. That waits for a settings store.

## SQLite

Storage and full-text search are built on SQLite with the FTS5 extension. The
library lives in `lib/sqlite3/Win64/sqlite3.dll` (see
[`lib/sqlite3/README.md`](lib/sqlite3/README.md) for version and build options)
and is copied next to the freshly built EXE by a post-build event.

It is bound at run time in `Infrastructure.SQLite3.Api` — `LoadLibraryEx` with a
full, explicit path — rather than statically imported or reached through
FireDAC. The reasons:

- The search layer cancels a running query from another thread with
  `sqlite3_interrupt()`, and uses the FTS5 auxiliary functions (`bm25`,
  `snippet`, `highlight`) directly.
- A missing DLL or one of the wrong bitness produces a readable message instead
  of a Windows loader failure before any of our code runs.
- Nothing is ever searched for in the current directory or along `PATH`, which
  closes the DLL pre-loading hole.

`Infrastructure.SQLite3.Database` is the thin wrapper everything else uses:
connection, prepared statement, UTF-8 boundary, errors as exceptions.

**Help → SQLite diagnostics** reports the loaded library path and version, the
threading mode, and probes FTS5 and the `unicode61` tokenizer with a Cyrillic
round-trip. Use it first whenever search behaves oddly on a new machine.

This is the one exception to the "single self-contained EXE" goal above. If that
goal wins later, only the loader in `Infrastructure.SQLite3.Api` changes: the
engine can be linked statically instead (RAD Studio ships SQLite as an object
file, and mORMot 2 ships one with FTS5), and the rest of the codebase does not
notice.