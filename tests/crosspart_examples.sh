#!/bin/bash
# crosspart_examples.sh — verify all 9 examples produce identical traces
# across STC12, STC15, and STC15W (the three 1T parts).
#
# These examples were compiled for STC12 and use STC12-compatible SFRs.
# Since the STC15 and STC15W share those SFR addresses and behaviour,
# all three parts must produce identical event traces.
#
# Usage: ./tests/crosspart_examples.sh [examples_dir]
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EXAMPLES="${1:-../stc/examples}"
FOSC=11059200
UNTIL_NS=2000000

if [ ! -x "$TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0; SKIP=0

echo "=== Cross-part parity: STC12 vs STC15 vs STC15W ==="

for dir in "$EXAMPLES"/*/; do
    name=$(basename "$dir")
    hex="$dir/${name}.hex"
    [ -f "$hex" ] || { SKIP=$((SKIP+1)); continue; }

    "$TRACE" -t STC12 -fosc $FOSC -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/stc12.ev"
    "$TRACE" -t STC15 -fosc $FOSC -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/stc15.ev"
    "$TRACE" -t STC15W -fosc $FOSC -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/stc15w.ev"

    N=$(wc -l < "$TMP/stc12.ev")
    ok=true
    diff "$TMP/stc12.ev" "$TMP/stc15.ev" > /dev/null 2>&1 || ok=false
    diff "$TMP/stc12.ev" "$TMP/stc15w.ev" > /dev/null 2>&1 || ok=false

    if $ok; then
        echo "  PASS  $name ($N events, all 3 parts identical)"
        PASS=$((PASS+1))
    else
        echo "  FAIL  $name"
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "Results: $PASS pass, $FAIL fail, $SKIP skip"
[ $FAIL -eq 0 ] && exit 0 || exit 1
