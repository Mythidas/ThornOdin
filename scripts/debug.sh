#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Debug-only shim: keep dlopen'd libs (e.g. Mesa/RADV) mapped until exit so
# LSan doesn't report false-positive leaks from unload order.
SHIM="$ROOT/build/nodlclose.so"
if [[ ! -f "$SHIM" || "$ROOT/scripts/nodlclose.c" -nt "$SHIM" ]]; then
    mkdir -p "$ROOT/build"
    gcc -shared -fPIC -o "$SHIM" "$ROOT/scripts/nodlclose.c"
fi

odin build src -out:src.bin -sanitize:address -collection:extern=./extern

LD_PRELOAD="$SHIM" ./src.bin "$@"
