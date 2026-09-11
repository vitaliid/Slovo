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
a main window with a single `File → Exit` menu. No reader, no search, no content
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

`Slovo.res` is generated during the build from settings in `Slovo.dproj` — it is
not kept in the repository. If the application icon ever looks wrong, delete
`Slovo.res` and rebuild.