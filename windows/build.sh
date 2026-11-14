#!/bin/bash
# Cross-build Ember.exe (works with llvm-mingw or the Ubuntu gcc-mingw-w64 package).
set -e
cd "$(dirname "$0")"
MINGW_BIN="$HOME/tools/mingw/bin"
CC="$MINGW_BIN/x86_64-w64-mingw32-clang"; WINDRES="$MINGW_BIN/x86_64-w64-mingw32-windres"
if [ ! -x "$CC" ]; then CC="$(command -v x86_64-w64-mingw32-gcc || true)"; WINDRES="$(command -v x86_64-w64-mingw32-windres || true)"; fi
[ -n "$CC" ] && [ -x "$CC" ] || { echo "no mingw compiler found"; exit 1; }
"$WINDRES" -I. ember.rc -O coff -o resources.o
"$CC" -Os -s -mwindows -municode -DUNICODE -D_UNICODE -ffunction-sections -fdata-sections -Wl,--gc-sections \
  -o Ember.exe main.c resources.o -lgdi32 -luser32 -lshell32 -lshlwapi -lole32 -lmsimg32 -ladvapi32
ls -la Ember.exe
