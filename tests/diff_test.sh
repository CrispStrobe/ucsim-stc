#!/bin/bash
# diff_test.sh — differential execution test against emu8051-stc.
#
# Runs the same firmware image on both emulators and compares the
# non-PC event streams (SFR writes, timer overflows, ADC completions).
# Timestamps are ignored — only event type, addresses, and values
# are compared, because the two emulators have different instruction
# cycle costs.
#
# Requires: emu8051-stc built at /mnt/volume1/code/emu8051-stc/emu_trace
#           (or set EMU_TRACE to the path)
#
# Usage: ./tests/diff_test.sh firmware.hex [cycles]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
EMU_TRACE="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
HEXFILE="${1:?Usage: $0 firmware.hex [cycles]}"
CYCLES="${2:-15000}"
FOSC=11059200

if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2
    exit 0
fi

if [ ! -x "$UCSIM" ]; then
    echo "FAIL: ucsim_51 not found at $UCSIM — build first" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "Running emu8051-stc ($CYCLES cycles)..."
"$EMU_TRACE" -fosc $FOSC -cycles "$CYCLES" "$HEXFILE" 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu.events"

echo "Running ucsim-stc ($CYCLES cycles)..."
"$SCRIPT_DIR/trace.sh" -fosc $FOSC -cycles "$CYCLES" "$HEXFILE" 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/ucsim.events"

EMU_N=$(wc -l < "$TMP/emu.events")
UCSIM_N=$(wc -l < "$TMP/ucsim.events")

# Compare the shorter of the two (they may cover different amounts
# of real time due to different instruction cycle costs)
MIN_N=$((EMU_N < UCSIM_N ? EMU_N : UCSIM_N))

if [ "$MIN_N" -eq 0 ]; then
    echo "FAIL: no events to compare"
    exit 1
fi

head -n "$MIN_N" "$TMP/emu.events" > "$TMP/emu.cmp"
head -n "$MIN_N" "$TMP/ucsim.events" > "$TMP/ucsim.cmp"

if diff -u "$TMP/emu.cmp" "$TMP/ucsim.cmp" > "$TMP/diff.out" 2>&1; then
    echo "PASS: $MIN_N events identical across both emulators"
else
    echo "FAIL: event divergence detected"
    cat "$TMP/diff.out"
    exit 1
fi
