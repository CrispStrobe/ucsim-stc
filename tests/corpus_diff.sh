#!/bin/bash
# corpus_diff.sh — differential execution across a corpus of firmware images.
#
# Results are NEVER committed (corpus may be unlicensed third-party code).
# Only aggregate statistics are reported.
#
# Usage: ./tests/corpus_diff.sh /path/to/hex-dir [until_ns]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEXDIR="${1:?Usage: $0 /path/to/hex-dir [until_ns]}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200
TIMEOUT=30

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "FAIL: emu_trace not found" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

TOTAL=0; PASS=0; PREFIX_PASS=0; FAIL=0; ERROR=0; EMPTY=0; WRONG_TARGET=0
DIVERGE_LOG="$TMP/divergences.txt"
> "$DIVERGE_LOG"

for img in "$HEXDIR"/*.hex "$HEXDIR"/*.ihx; do
    [ -f "$img" ] || continue
    TOTAL=$((TOTAL + 1))
    NAME=$(basename "$img")

    timeout $TIMEOUT "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$img" \
        2>/dev/null | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu.events" 2>/dev/null || true
    # Run ucsim once, capture all events including UNMODELLED
    timeout $TIMEOUT "$STC12_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$img" \
        2>/dev/null > "$TMP/ucsim_raw.events" 2>/dev/null || true
    awk '$2 == "SFR" || $2 == "TF"' "$TMP/ucsim_raw.events" | cut -f2- > "$TMP/ucsim.events"
    grep "UNMODELLED" "$TMP/ucsim_raw.events" > "$TMP/unmod.events" 2>/dev/null || true

    EN=$(wc -l < "$TMP/emu.events")
    UN=$(wc -l < "$TMP/ucsim.events")
    HAS_UNMOD=$(wc -l < "$TMP/unmod.events")

    if [ "$EN" -eq 0 ] && [ "$UN" -eq 0 ]; then
        EMPTY=$((EMPTY + 1)); continue
    fi
    if [ "$EN" -eq 0 ] || [ "$UN" -eq 0 ]; then
        ERROR=$((ERROR + 1))
        echo "ERROR $NAME emu=$EN ucsim=$UN" >> "$DIVERGE_LOG"
        continue
    fi

    MIN=$((EN < UN ? EN : UN))

    # Strict comparison: both streams must be fully identical
    if [ "$EN" -eq "$UN" ] && diff "$TMP/emu.events" "$TMP/ucsim.events" > /dev/null 2>&1; then
        PASS=$((PASS + 1))
    elif diff <(head -$MIN "$TMP/emu.events") <(head -$MIN "$TMP/ucsim.events") > /dev/null 2>&1; then
        PREFIX_PASS=$((PREFIX_PASS + 1))
        echo "PREFIX $NAME (emu=$EN ucsim=$UN diff=$((EN > UN ? EN - UN : UN - EN)))" >> "$DIVERGE_LOG"
    elif [ "$HAS_UNMOD" -gt 0 ]; then
        WRONG_TARGET=$((WRONG_TARGET + 1))
        FIRST_UNMOD=$(head -1 "$TMP/unmod.events" | awk '{print $3}')
        echo "WRONG-TARGET $NAME: unmodelled SFR $FIRST_UNMOD (emu=$EN ucsim=$UN)" >> "$DIVERGE_LOG"
    elif [ "$EN" -gt 0 ] && [ "$UN" -gt 0 ] && \
         [ $((EN > UN ? EN / UN : UN / EN)) -ge 3 ]; then
        # Count ratio > 3x suggests wrong target (one side models registers the other doesn't)
        WRONG_TARGET=$((WRONG_TARGET + 1))
        echo "WRONG-TARGET $NAME: count ratio (emu=$EN ucsim=$UN)" >> "$DIVERGE_LOG"
    else
        FAIL=$((FAIL + 1))
        FIRST_DIFF=$(diff <(head -$MIN "$TMP/emu.events") <(head -$MIN "$TMP/ucsim.events") | head -3 | tail -1)
        echo "DIVERGE $NAME (emu=$EN ucsim=$UN): $FIRST_DIFF" >> "$DIVERGE_LOG"
    fi

    # Progress
    if [ $((TOTAL % 50)) -eq 0 ]; then
        echo "... $TOTAL images processed ($PASS pass, $FAIL diverge, $EMPTY empty)" >&2
    fi
done

echo ""
echo "=== Corpus differential results (${UNTIL_NS} ns) ==="
echo "Total:    $TOTAL images"
echo "Strict:   $PASS (both streams fully identical)"
echo "Prefix:   $PREFIX_PASS (shorter stream prefix-matches longer)"
echo "Diverge:  $FAIL"
echo "Wrong-target: $WRONG_TARGET (touches unmodelled SFRs)"
echo "Empty:    $EMPTY (no events in either trace)"
echo "Error:    $ERROR (one side produced no output)"
echo ""
if [ -s "$DIVERGE_LOG" ]; then
    echo "=== Divergences ==="
    cat "$DIVERGE_LOG"
fi
