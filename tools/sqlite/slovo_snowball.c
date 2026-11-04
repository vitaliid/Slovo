/*
** slovo_snowball.c — glue that links the fts5-snowball tokenizer into the
** SQLite core of Slovo's own sqlite3.dll (decision B-31, Slovo_02).
**
** Compiled with -DSQLITE_CORE, so the SQLITE_EXTENSION_INIT* macros in
** fts5stemmer.c become no-ops and all sqlite3_* calls go straight to the core.
**
** sqlite3.c is compiled with -DSQLITE_EXTRA_INIT=slovo_extra_init: SQLite calls
** that function at the end of sqlite3_initialize(), and it registers the
** tokenizer as an auto-extension. From then on every new connection already
** knows tokenize='snowball ...' — no sqlite3_load_extension, no second file.
**
** The upstream file is included unchanged:
**   - its entry point is renamed so it is not confused with a loadable
**     extension's sqlite3_extension_init;
**   - its __declspec(dllexport) is neutralised, so the DLL exports only the
**     public SQLite API.
*/

#define sqlite3_extension_init slovo_fts5stemmer_init

#pragma push_macro("__declspec")
#undef __declspec
#define __declspec(x)
#include "fts5stemmer.c"
#pragma pop_macro("__declspec")

#undef sqlite3_extension_init

int slovo_extra_init(const char *unused)
{
  (void)unused;
  return sqlite3_auto_extension((void (*)(void))slovo_fts5stemmer_init);
}
