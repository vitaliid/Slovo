#!/usr/bin/env bash
# Builds Slovo's own sqlite3.dll (Win64): SQLite amalgamation + FTS5
# + fts5-snowball tokenizer + Snowball libstemmer (uk/ru/en and the rest).
# Decision B-31, Slovo_02 «Власна sqlite3.dll зі Snowball».
#
# Runs on:
#   - Linux (Ubuntu/Debian):  apt install gcc-mingw-w64-x86-64
#   - Windows, MSYS2 UCRT64:  pacman -S mingw-w64-ucrt-x86_64-gcc
#
# Output: out/sqlite3.dll, out/sqlite3.exe (console on the same DLL),
#         out/build-info.txt
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$HERE/vendor"
OUT="$HERE/out"
OBJ="$OUT/obj"
STEMMER_VER="3.2.0"

# --- toolchain ---------------------------------------------------------------
if [[ -z "${CC:-}" ]]; then
  if command -v x86_64-w64-mingw32-gcc >/dev/null; then CC=x86_64-w64-mingw32-gcc
  elif [[ "${MSYSTEM:-}" == UCRT64 || "${MSYSTEM:-}" == MINGW64 ]]; then CC=gcc
  else echo "No Win64 compiler: install gcc-mingw-w64-x86-64 (Linux) or use the MSYS2 UCRT64 shell" >&2; exit 1
  fi
fi
OBJDUMP="${OBJDUMP:-${CC%gcc}objdump}"
command -v "$OBJDUMP" >/dev/null || OBJDUMP=objdump
echo "CC = $CC ($("$CC" -dumpversion))"
"$CC" -dumpmachine | grep -q x86_64 || { echo "Compiler does not target x86_64" >&2; exit 1; }

# --- sources -----------------------------------------------------------------
rm -rf "$OUT"; mkdir -p "$OBJ"
tar xzf "$VENDOR/libstemmer_c-$STEMMER_VER.tar.gz" -C "$OUT"
LS="$OUT/libstemmer_c-$STEMMER_VER"
[[ -f "$LS/src_c/stem_UTF_8_ukrainian.c" ]] || { echo "Snowball $STEMMER_VER has no Ukrainian stemmer — wrong archive" >&2; exit 1; }

# UTF-8 libstemmer sources, exactly as listed by the distribution itself
mapfile -t STEM_SRC < <(sed -n '/^snowball_sources=/,/^$/p' "$LS/mkinc_utf8.mak" | grep -oE '[A-Za-z0-9_/]+\.c')
echo "libstemmer: ${#STEM_SRC[@]} files"

CFLAGS_COMMON=(-O2 -DNDEBUG -Wno-unused-parameter)

# --- compile -----------------------------------------------------------------
echo "compile sqlite3.c"
"$CC" "${CFLAGS_COMMON[@]}" -c "$VENDOR/sqlite/sqlite3.c" -o "$OBJ/sqlite3.o" \
  -DSQLITE_ENABLE_FTS5 \
  -DSQLITE_EXTRA_INIT=slovo_extra_init \
  "-DSQLITE_API=__declspec(dllexport)"

echo "compile slovo_snowball.c (+ fts5stemmer.c)"
"$CC" "${CFLAGS_COMMON[@]}" -c "$HERE/slovo_snowball.c" -o "$OBJ/slovo_snowball.o" \
  -DSQLITE_CORE \
  -I"$VENDOR/sqlite" -I"$VENDOR/fts5-snowball" -I"$LS/include"

echo "compile libstemmer"
for f in "${STEM_SRC[@]}"; do
  "$CC" "${CFLAGS_COMMON[@]}" -c "$LS/$f" -o "$OBJ/stem_$(basename "${f%.c}").o" -I"$LS/include"
done

# --- link --------------------------------------------------------------------
echo "link sqlite3.dll"
"$CC" -shared -static-libgcc -s -o "$OUT/sqlite3.dll" "$OBJ"/*.o \
  -Wl,--out-implib,"$OBJ/libsqlite3.dll.a" \
  -Wl,--nxcompat -Wl,--dynamicbase -Wl,--high-entropy-va

echo "link sqlite3.exe (shell on the same DLL)"
"$CC" -O2 -static-libgcc -s -o "$OUT/sqlite3.exe" "$VENDOR/sqlite/shell.c" \
  -I"$VENDOR/sqlite" "$OBJ/libsqlite3.dll.a"

# --- self-check --------------------------------------------------------------
PE="$("$OBJDUMP" -p "$OUT/sqlite3.dll")"
DEPS=$(awk '/DLL Name:/{print $3}' <<<"$PE" | sort -u)
EXPORTS=$(awk '/\[Ordinal\/Name Pointer\] Table/{f=1;next} f&&/\[/{print $NF} f&&/^$/{f=0}' <<<"$PE")
echo "DLL imports: $(echo $DEPS)"
if grep -qiE 'libgcc|libwinpthread|libstdc' <<<"$DEPS"; then echo "Unexpected MinGW runtime dependency" >&2; exit 1; fi
for s in sqlite3_open_v2 sqlite3_prepare_v2 sqlite3_compileoption_used sqlite3_libversion; do
  grep -qx "$s" <<<"$EXPORTS" || { echo "Missing export $s" >&2; exit 1; }
done
if grep -qE '^(sb_|slovo_|sqlite3_extension_init)$|^sb_|^slovo_' <<<"$EXPORTS"; then echo "Internal symbols leaked into exports" >&2; exit 1; fi
echo "exports: $(grep -c . <<<"$EXPORTS") functions"

SQLITE_VER=$(grep -m1 '#define SQLITE_VERSION ' "$VENDOR/sqlite/sqlite3.h" | awk -F'"' '{print $2}')
{
  echo "Slovo sqlite3.dll build info"
  echo "built:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "compiler:     $CC $("$CC" -dumpversion) ($("$CC" -dumpmachine))"
  echo "SQLite:       $SQLITE_VER"
  echo "Snowball:     libstemmer_c $STEMMER_VER"
  echo "fts5-snowball: vendor/fts5-snowball/fts5stemmer.c (upstream, unchanged)"
  echo "options:      SQLITE_ENABLE_FTS5, SQLITE_EXTRA_INIT=slovo_extra_init"
  echo "imports:      $(echo $DEPS)"
  echo
  echo "SHA-256:"
  (cd "$OUT" && sha256sum sqlite3.dll sqlite3.exe)
  (cd "$VENDOR" && sha256sum sqlite/sqlite3.c sqlite/shell.c fts5-snowball/fts5stemmer.c "libstemmer_c-$STEMMER_VER.tar.gz")
} > "$OUT/build-info.txt"
# Licenses that must ship next to the DLL in the ZIP (Slovo_00: LICENSES\)
mkdir -p "$OUT/LICENSES"
cp "$LS/COPYING" "$OUT/LICENSES/Snowball-BSD-3-Clause.txt"
cp "$VENDOR/fts5-snowball/LICENSE" "$OUT/LICENSES/fts5-snowball-BSD-3-Clause.txt"
echo "SQLite is in the public domain: https://sqlite.org/copyright.html" > "$OUT/LICENSES/SQLite-public-domain.txt"

rm -rf "$OBJ" "$LS"
cat "$OUT/build-info.txt"
