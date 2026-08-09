#!/bin/bash
# corpus_stc89.sh — cross-emulator differential on STC89 firmware corpus.
#
# Runs all hex/ihx files in corpus/stc89/ through both emulators as STC89
# and compares SFR+TF events (timestamps stripped).
#
# Usage: ./tests/corpus_stc89.sh [corpus_dir] [until_ns]
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EMU="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
CORPUS="${1:-corpus/stc89}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200

if [ ! -x "$TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

STRICT=0; PREFIX=0; DIVERGE=0; EMPTY=0; ERROR=0; TOTAL=0

echo "=== STC89 cross-emulator corpus ($CORPUS, ${UNTIL_NS}ns) ==="

for hex in "$CORPUS"/*.ihx "$CORPUS"/*.hex; do
    [ -f "$hex" ] || continue
    TOTAL=$((TOTAL+1))
    name=$(basename "$hex")

    "$TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/ucsim.ev"
    "$EMU" -part STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu.ev"

    NU=$(wc -l < "$TMP/ucsim.ev")
    NE=$(wc -l < "$TMP/emu.ev")

    if [ "$NU" -eq 0 ] && [ "$NE" -eq 0 ]; then
        EMPTY=$((EMPTY+1)); continue
    fi
    if [ "$NU" -eq 0 ] || [ "$NE" -eq 0 ]; then
        ERROR=$((ERROR+1)); echo "  ERROR  $name (ucsim=$NU, emu=$NE)"; continue
    fi

    if [ "$NU" -eq "$NE" ] && diff "$TMP/ucsim.ev" "$TMP/emu.ev" > /dev/null 2>&1; then
        STRICT=$((STRICT+1))
    else
        MIN=$((NU < NE ? NU : NE))
        head -n "$MIN" "$TMP/ucsim.ev" > "$TMP/u_pre.ev"
        head -n "$MIN" "$TMP/emu.ev" > "$TMP/e_pre.ev"
        if diff "$TMP/u_pre.ev" "$TMP/e_pre.ev" > /dev/null 2>&1; then
            PREFIX=$((PREFIX+1))
        else
            DIVERGE=$((DIVERGE+1))
            echo "  DIVERGE  $name (ucsim=$NU, emu=$NE)"
        fi
    fi
done

echo ""
echo "Results ($TOTAL images):"
echo "  Strict:  $STRICT"
echo "  Prefix:  $PREFIX"
echo "  Diverge: $DIVERGE"
echo "  Empty:   $EMPTY"
echo "  Error:   $ERROR"

[ $DIVERGE -le 1 ] && exit 0 || exit 1
