#!/bin/bash
# diff_test.sh — differential execution test against emu8051-stc.
#
# Runs the same firmware on both emulators for the same amount of
# simulated time (in nanoseconds), then compares the SFR/TF event
# streams. The bound is in nanoseconds so it means the same thing
# regardless of instruction cycle costs.
#
# Usage: ./tests/diff_test.sh firmware.hex [until_ns]
#   Default: 2000000 ns (2 ms simulated time)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEXFILE="${1:?Usage: $0 firmware.hex [until_ns]}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200

if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2
    exit 0
fi

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found — build with: make -C ucsim/src/sims/s51.src stc12_trace" >&2
    exit 1
fi

# Convert ns to approximate cycles for emu_trace (which still uses -cycles)
# emu8051 ticks once per oscillator clock on STC12 (1T)
EMU_CYCLES=$(python3 -c "print(int($UNTIL_NS * $FOSC / 1e9 + 1000))")

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "Running emu8051-stc (until ${UNTIL_NS} ns, ~${EMU_CYCLES} cycles)..."
"$EMU_TRACE" -fosc $FOSC -cycles "$EMU_CYCLES" "$HEXFILE" 2>/dev/null \
    | awk -v limit="$UNTIL_NS" '$1 <= limit' \
    | awk '$2 == "SFR" || $2 == "TF" || $2 == "PIN"' | cut -f2- > "$TMP/emu.events"

echo "Running ucsim-stc (until ${UNTIL_NS} ns)..."
"$STC12_TRACE" -fosc $FOSC -until-ns "$UNTIL_NS" "$HEXFILE" 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF" || $2 == "PIN"' | cut -f2- > "$TMP/ucsim.events"

EMU_N=$(wc -l < "$TMP/emu.events")
UCSIM_N=$(wc -l < "$TMP/ucsim.events")

echo "  emu8051: $EMU_N events, ucsim: $UCSIM_N events"

if [ "$EMU_N" -eq 0 ] && [ "$UCSIM_N" -eq 0 ]; then
    echo "PASS: no SFR/TF events in either trace (run may be too short)"
    exit 0
fi

# Compare event streams
if diff -u "$TMP/emu.events" "$TMP/ucsim.events" > "$TMP/diff.out" 2>&1; then
    echo "PASS: $EMU_N events identical across both emulators over ${UNTIL_NS} ns"
else
    echo "FAIL: event divergence detected"
    head -30 "$TMP/diff.out"
    exit 1
fi
