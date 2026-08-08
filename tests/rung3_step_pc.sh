#!/bin/bash
# rung3_step_pc.sh — §8 rung 3: step('insn') x N produces the same PC sequence
#
# Steps both emulators N instructions from reset, captures the PC at each step,
# and diffs the sequences. This tests run control, not free-running behaviour.
#
# Usage: ./tests/rung3_step_pc.sh firmware.hex [steps]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
HEXFILE="${1:?Usage: $0 firmware.hex [steps]}"
STEPS="${2:-1000}"
FOSC=11059200

if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2
    exit 0
fi

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found — build with: make -C ucsim/src/sims/s51.src stc12_trace" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# emu8051: step N instructions, capture PC per instruction
# Use -until-ns with enough time to cover N instructions
# At 1T, ~1 instruction per osc clock, so N clocks ≈ N * 90ns at 11MHz
UNTIL_NS=$((STEPS * 200))  # generous margin
"$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEXFILE" 2>/dev/null \
    | awk '$2 == "PC" {print $3}' | head -$STEPS > "$TMP/emu_pcs.txt"

# ucsim: step N instructions, capture PC per instruction
"$STC12_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEXFILE" 2>/dev/null \
    | awk '$2 == "PC" {print $3}' | head -$STEPS > "$TMP/ucsim_pcs.txt"

EN=$(wc -l < "$TMP/emu_pcs.txt")
UN=$(wc -l < "$TMP/ucsim_pcs.txt")
MIN=$((EN < UN ? EN : UN))

echo "Rung 3: step('insn') x $STEPS"
echo "  emu8051: $EN PCs, ucsim: $UN PCs"

if [ "$MIN" -eq 0 ]; then
    echo "FAIL: no PCs to compare"
    exit 1
fi

if diff "$TMP/emu_pcs.txt" "$TMP/ucsim_pcs.txt" > "$TMP/diff.out" 2>&1; then
    echo "PASS: $MIN/$MIN PCs identical from reset"
else
    # Find first divergence
    FIRST_DIFF=$(diff "$TMP/emu_pcs.txt" "$TMP/ucsim_pcs.txt" | head -1)
    echo "FAIL: PC divergence at $FIRST_DIFF"
    echo "First 5 differing lines:"
    diff "$TMP/emu_pcs.txt" "$TMP/ucsim_pcs.txt" | head -10
    exit 1
fi
