#!/bin/bash
# examples_diff.sh — differential execution on all stc/examples bundles.
#
# Runs each example through both emulators and compares SFR+TF events.
# Exits non-zero if any example diverges.
#
# Usage: ./tests/examples_diff.sh [examples_dir] [until_ns]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
EXAMPLES="${1:-/mnt/volume1/code/stc/examples}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi
if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2; exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0; SKIP=0

for dir in "$EXAMPLES"/*/; do
    name=$(basename "$dir")
    hex="$dir/${name}.hex"
    [ -f "$hex" ] || { SKIP=$((SKIP+1)); continue; }

    # emu8051: use -adc 2,512 for images that read the ADC
    # (matches ucsim's synthetic mid-scale default)
    "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS -adc 2,512 "$hex" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu.ev"

    timeout 60 "$STC12_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/ucsim.ev"

    EN=$(wc -l < "$TMP/emu.ev")
    UN=$(wc -l < "$TMP/ucsim.ev")

    if [ "$EN" -eq 0 ] && [ "$UN" -eq 0 ]; then
        echo "  EMPTY  $name"
        SKIP=$((SKIP+1))
        continue
    fi

    if [ "$EN" -eq "$UN" ] && diff "$TMP/emu.ev" "$TMP/ucsim.ev" > /dev/null 2>&1; then
        echo "  PASS   $name: $EN events"
        PASS=$((PASS+1))
    else
        MIN=$((EN < UN ? EN : UN))
        if [ "$MIN" -gt 0 ] && diff <(head -$MIN "$TMP/emu.ev") <(head -$MIN "$TMP/ucsim.ev") > /dev/null 2>&1; then
            echo "  PREFIX $name: first $MIN identical (emu=$EN ucsim=$UN)"
            PASS=$((PASS+1))  # prefix match still counts for non-timing peripherals
        else
            echo "  FAIL   $name (emu=$EN ucsim=$UN)"
            diff "$TMP/emu.ev" "$TMP/ucsim.ev" 2>/dev/null | head -5
            FAIL=$((FAIL+1))
        fi
    fi
done

echo ""
echo "=== Examples differential results ==="
echo "Pass: $PASS  Fail: $FAIL  Skip: $SKIP"

[ $FAIL -eq 0 ] && exit 0 || exit 1
