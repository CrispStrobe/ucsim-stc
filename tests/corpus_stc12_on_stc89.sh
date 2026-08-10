#!/bin/bash
# corpus_stc12_on_stc89.sh — run the STC12 corpus through both emulators
# as STC89. Per-invocation timeout of 10s. Reports Timeout as a sixth outcome.
#
# Usage: ./tests/corpus_stc12_on_stc89.sh [corpus_dir] [until_ns]
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EMU="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
CORPUS="${1:-/mnt/volume1/code/stc-research/hex}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200
INVOC_TIMEOUT=10

if [ ! -x "$TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

STRICT=0; PREFIX=0; DIVERGE=0; EMPTY=0; EMU_FAIL=0; TMOUT=0; TOTAL=0
> "$TMP/timeouts.txt"

echo "=== STC12 corpus × STC89 model (timeout ${INVOC_TIMEOUT}s per invocation) ==="

for hex in "$CORPUS"/*.hex; do
    [ -f "$hex" ] || continue
    TOTAL=$((TOTAL+1))
    name=$(basename "$hex")

    if ! timeout $INVOC_TIMEOUT "$TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        > "$TMP/ucsim_raw.ev" 2>/dev/null; then
        TMOUT=$((TMOUT+1))
        echo "  TIMEOUT(ucsim) $name" >> "$TMP/timeouts.txt"
        continue
    fi

    if ! timeout $INVOC_TIMEOUT "$EMU" -part STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        > "$TMP/emu_raw.ev" 2>/dev/null; then
        TMOUT=$((TMOUT+1))
        echo "  TIMEOUT(emu)   $name" >> "$TMP/timeouts.txt"
        continue
    fi

    awk '$2 == "SFR" || $2 == "TF"' "$TMP/ucsim_raw.ev" | cut -f2- > "$TMP/u.ev"
    awk '$2 == "SFR" || $2 == "TF"' "$TMP/emu_raw.ev" | cut -f2- > "$TMP/e.ev"

    NU=$(wc -l < "$TMP/u.ev")
    NE=$(wc -l < "$TMP/e.ev")

    if [ "$NU" -eq 0 ] && [ "$NE" -eq 0 ]; then
        EMPTY=$((EMPTY+1)); continue
    fi
    if [ "$NU" -eq 0 ] || [ "$NE" -eq 0 ]; then
        EMU_FAIL=$((EMU_FAIL+1)); continue
    fi

    if [ "$NU" -eq "$NE" ] && diff "$TMP/u.ev" "$TMP/e.ev" > /dev/null 2>&1; then
        STRICT=$((STRICT+1))
    else
        MIN=$((NU < NE ? NU : NE))
        head -n "$MIN" "$TMP/u.ev" > "$TMP/up.ev"
        head -n "$MIN" "$TMP/e.ev" > "$TMP/ep.ev"
        if diff "$TMP/up.ev" "$TMP/ep.ev" > /dev/null 2>&1; then
            PREFIX=$((PREFIX+1))
        else
            DIVERGE=$((DIVERGE+1))
        fi
    fi
done

EXECUTED=$((STRICT + PREFIX + DIVERGE + EMPTY))

echo ""
echo "Results ($TOTAL images):"
echo "  Strict:    $STRICT"
echo "  Prefix:    $PREFIX"
echo "  Diverge:   $DIVERGE"
echo "  Empty:     $EMPTY"
echo "  Emu-fail:  $EMU_FAIL"
echo "  Timeout:   $TMOUT"
echo ""
echo "  Attempted: $TOTAL  Executed: $EXECUTED  Timeout: $TMOUT"

if [ "$TMOUT" -gt 0 ]; then
    echo ""
    echo "Timed-out images (>$INVOC_TIMEOUT sec):"
    cat "$TMP/timeouts.txt"
fi
