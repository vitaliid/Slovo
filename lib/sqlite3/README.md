# Vendored SQLite

`Win64/sqlite3.dll` is the library `Infrastructure.SQLite3.Api` loads at run
time. It is committed on purpose: the build must not depend on whatever SQLite
happens to be installed on a machine, and the search layer needs FTS5, which is
not present in every build of SQLite.

| | |
|---|---|
| Version | 3.53.4 |
| Source ID | `2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc` |
| Target | Windows x64 |
| SHA-256 | `e04ff6e217f7dceeca8696a44242d46565a550194c5279fe636138c46ea0ef77` |
| Imports | `KERNEL32.dll`, `msvcrt.dll` only - no C++ runtime, no MinGW runtime |

## Compile options

```
-DSQLITE_THREADSAFE=1
-DSQLITE_ENABLE_FTS3
-DSQLITE_ENABLE_FTS3_PARENTHESIS
-DSQLITE_ENABLE_FTS4
-DSQLITE_ENABLE_FTS5
-DSQLITE_ENABLE_RTREE
-DSQLITE_ENABLE_GEOPOLY
-DSQLITE_ENABLE_DBSTAT_VTAB
-DSQLITE_ENABLE_MATH_FUNCTIONS
-DSQLITE_ENABLE_COLUMN_METADATA
-DSQLITE_ENABLE_STMT_SCANSTATUS
-DSQLITE_MAX_EXPR_DEPTH=0
-DSQLITE_USE_URI=1
```

This matches the option set of the official `sqlite-dll-win-x64` build closely
enough that the two are interchangeable.

## Replacing it

Any x64 `sqlite3.dll` with FTS5 works, including the official one from
<https://sqlite.org/download.html> (`sqlite-dll-win-x64-*.zip`) - the official
Windows builds ship with FTS5 enabled. Drop the new file in as
`Win64\sqlite3.dll`, update the table above, and run
**Довідка → SQLite diagnostics** in the application: it prints the version the
process actually loaded and probes FTS5 and the `unicode61` tokenizer with a
Cyrillic round-trip.

Two things to keep in mind when swapping:

- The bitness must match the build target. A 32-bit DLL fails to load with
  Windows error 193 and the loader reports it explicitly.
- `Infrastructure.SQLite3.Api` refuses anything older than 3.27.0, the release
  that introduced the `remove_diacritics 2` tokenizer setting the index uses.

## Where it has to end up

The application calls `LoadLibraryEx` with an explicit full path -
`<directory of the EXE>\sqlite3.dll` - and never searches the current directory
or `PATH`. The project's post-build event copies this file into
`$(Platform)\$(Config)\` after every build, so a freshly built EXE always finds
it. An installer has to place the DLL beside `Slovo.exe` for the same reason.
