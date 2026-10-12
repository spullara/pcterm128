#!/bin/sh
# verify.sh - rebuild every disasm/*.s with ca65/ld65 and compare the result
# byte for byte with the original file in the repository root.
#
#   disasm/pc.ml2.s  ->  pc.ml2   (the .s name minus ".s")
#
# Link: if disasm/<name>.cfg exists, ld65 uses it (-C); else "ld65 -t none".
# With -t none each .s must emit its own 2-byte load address (.word) and
# use .org, so the output is a flat PRG image.
#
# Usage: sh disasm/verify.sh [name.s ...]    (default: all disasm/*.s)
# Exit status: 0 if all files match, 1 otherwise.
# Needs: ca65, ld65 (cc65 suite), cmp.

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$DIR")
TMP=$(mktemp -d "${TMPDIR:-/tmp}/pcterm-verify.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

if [ $# -eq 0 ]; then
    set -- "$DIR"/*.s
fi

fail=0
for src in "$@"; do
    [ -f "$src" ] || src="$DIR/$src"
    base=$(basename "$src" .s)
    orig="$ROOT/$base"
    obj="$TMP/$base.o"
    out="$TMP/$base.bin"
    if [ ! -f "$orig" ]; then
        echo "SKIP  $base.s (no original file $base)"
        continue
    fi
    if [ -f "$DIR/$base.cfg" ]; then
        link="-C $DIR/$base.cfg"
    else
        link="-t none"
    fi
    if ! ca65 "$src" -o "$obj"; then
        echo "FAIL  $base.s (ca65 error)"; fail=1; continue
    fi
    # shellcheck disable=SC2086
    if ! ld65 $link -o "$out" "$obj"; then
        echo "FAIL  $base.s (ld65 error)"; fail=1; continue
    fi
    if cmp "$out" "$orig"; then
        echo "OK    $base.s == $base ($(wc -c < "$orig" | tr -d ' ') bytes)"
    else
        echo "FAIL  $base.s differs from $base"; fail=1
    fi
done
exit $fail
