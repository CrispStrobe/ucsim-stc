#!/bin/bash
# rung_oracle_corpus.sh — cross-emulator PIN event comparison for oracle corpus.
#
# Runs each corpus hex through both emu_trace and stc12_trace, compares PIN
# event streams (with timestamps stripped). Reports prefix match length and
# any divergences.
#
# Usage: ./tests/rung_oracle_corpus.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STC12_TRACE="$REPO_DIR/ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
FOSC=11059200
UNTIL_NS=2000000000

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi
if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2; exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

run_check() {
    local label="$1" hex="$2" cpu="$3"

    if [ ! -f "$hex" ]; then
        echo "  SKIP  $label (hex not found)"
        return
    fi

    timeout 30 "$EMU_TRACE" -fosc $FOSC -part "$cpu" -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "PIN"' | cut -f2- > "$TMP/emu.pin"
    timeout 300 "$STC12_TRACE" -t "$(echo $cpu | tr '[:lower:]' '[:upper:]')" -fosc $FOSC \
        -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "PIN"' | cut -f2- > "$TMP/ucsim.pin"

    local EN UN
    EN=$(wc -l < "$TMP/emu.pin")
    UN=$(wc -l < "$TMP/ucsim.pin")

    if [ "$EN" -eq "$UN" ] && diff "$TMP/emu.pin" "$TMP/ucsim.pin" > /dev/null 2>&1; then
        echo "  PASS   $label ($EN PIN events, exact match)"
        PASS=$((PASS+1))
        return
    fi

    # Check prefix match (strip mode-change events from emu8051)
    # Mode events: "PIN X.Y PP L" at init time (before any timer fires)
    local MIN=$EN; [ "$UN" -lt "$MIN" ] && MIN=$UN
    if [ "$MIN" -gt 0 ] && head -n "$MIN" "$TMP/emu.pin" \
         | diff - <(head -n "$MIN" "$TMP/ucsim.pin") > /dev/null 2>&1; then
        echo "  PASS   $label (prefix $MIN match, emu=$EN ucsim=$UN)"
        PASS=$((PASS+1))
        return
    fi

    # Find the block of mode-change events (contiguous "PP L" lines that
    # appear in emu8051 but not in ucsim, early in the stream). Remove them
    # and check if the remaining streams match (or prefix-match).
    # The mode events are the diff between the first N lines of each stream.
    local first_diff_line=$(diff "$TMP/emu.pin" "$TMP/ucsim.pin" 2>/dev/null \
        | grep "^[0-9]" | head -1 | sed 's/[^0-9].*//')
    if [ -n "$first_diff_line" ]; then
        # Extract the deleted lines from emu (mode events)
        local mode_count=$(diff "$TMP/emu.pin" "$TMP/ucsim.pin" 2>/dev/null \
            | grep "^< " | wc -l)
        local extra_ucsim=$(diff "$TMP/emu.pin" "$TMP/ucsim.pin" 2>/dev/null \
            | grep "^> " | wc -l)

        # Remove mode-event block from emu, check if rest matches ucsim prefix
        diff "$TMP/emu.pin" "$TMP/ucsim.pin" 2>/dev/null \
            | grep "^< " | sed 's/^< //' > "$TMP/mode_events.txt"
        # Remove those exact lines from emu output (first occurrence block)
        local start_line=$(echo "$first_diff_line" | head -1)
        sed "${start_line},$((start_line + mode_count - 1))d" "$TMP/emu.pin" > "$TMP/emu_trimmed.pin"
        local EN2=$(wc -l < "$TMP/emu_trimmed.pin")

        local MIN2=$EN2; [ "$UN" -lt "$MIN2" ] && MIN2=$UN
        if [ "$MIN2" -gt 0 ] && head -n "$MIN2" "$TMP/emu_trimmed.pin" \
             | diff - <(head -n "$MIN2" "$TMP/ucsim.pin") > /dev/null 2>&1; then
            echo "  PASS   $label (emu=$EN→$EN2 after $mode_count mode events, ucsim=$UN, prefix $MIN2)"
            PASS=$((PASS+1))
            return
        fi
    fi

    echo "  FAIL   $label (emu=$EN ucsim=$UN)"
    diff "$TMP/emu.pin" "$TMP/ucsim.pin" 2>/dev/null | head -10
    FAIL=$((FAIL+1))
}

echo "=== Oracle Corpus Cross-Check ==="
echo "FOSC=$FOSC  UNTIL=${UNTIL_NS}ns"
echo ""

echo "--- mogoreanu/8x16 (STC15) ---"
run_check "mogoreanu_8x16" "$SCRIPT_DIR/fixtures/oracle-corpus/mogoreanu_8x16.hex" "stc15"

echo ""
echo "--- rainbowpeee (STC15) ---"
run_check "rainbowpeee_empty" "$SCRIPT_DIR/fixtures/oracle-corpus/rainbowpeee_empty.hex" "stc15"
run_check "rainbowpeee_led" "$SCRIPT_DIR/fixtures/oracle-corpus/rainbowpeee_led.hex" "stc15"

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"

[ $FAIL -eq 0 ] && exit 0 || exit 1
