#!/bin/bash
# rung3_step_masked.sh — §8 rung 3: step('insn') x N from reset with
# interrupts masked produces the same PC sequence on both emulators.
#
# Uses a non-ISR image (blink uses polled TF0, EA is never set).
# Steps both emulators N instructions and compares the PC at each step.
#
# Requires emu8051-stc's -step-pcs flag (per COORD-FROM-UCSIM.md).
#
# Usage: ./tests/rung3_step_masked.sh [steps]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
EMU_TRACE="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
STEPS="${1:-500}"
FOSC=11059200

# Use blink (polled TF0, no ISR — EA never set)
HEXFILE=/tmp/blink.ihx
if [ ! -f "$HEXFILE" ]; then
    echo "FAIL: blink.ihx not found at $HEXFILE" >&2; exit 1
fi

if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found" >&2; exit 0
fi
if [ ! -x "$UCSIM" ]; then
    echo "FAIL: ucsim_51 not found" >&2; exit 1
fi

# Check if emu_trace supports -step-pcs
if ! "$EMU_TRACE" --help 2>&1 | grep -q "step-pcs" && \
   ! "$EMU_TRACE" -step-pcs 1 /dev/null 2>&1 | grep -qv "unknown"; then
    echo "SKIP: emu_trace does not support -step-pcs yet" >&2
    exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "Rung 3: step('insn') x $STEPS, interrupts masked"

# emu8051: one hex PC per line, normalize to 4-digit uppercase
# Skip the first line (reset PC before any step executes)
# Filter out any non-PC trace lines (PIN/SFR events may leak through)
"$EMU_TRACE" -fosc $FOSC -step-pcs $((STEPS + 1)) "$HEXFILE" 2>/dev/null \
    | grep -v '	' | tail -n +2 | head -$STEPS \
    | awk '{printf "%04X\n", strtonum("0x" $0)}' > "$TMP/emu_pcs.txt"

# ucsim: step one at a time, extract PC, normalize to 4-digit uppercase
python3 -c "
for i in range($STEPS):
    print('step')
print('quit')
" | $UCSIM -t STC12 "$HEXFILE" 2>/dev/null \
    | grep 'Stop at 0x' \
    | sed 's/.*Stop at 0x\([0-9a-fA-F]*\).*/\1/' \
    | awk '{printf "%04X\n", strtonum("0x" $0)}' \
    | head -$STEPS > "$TMP/ucsim_pcs.txt"

EN=$(wc -l < "$TMP/emu_pcs.txt")
UN=$(wc -l < "$TMP/ucsim_pcs.txt")
echo "  emu: $EN PCs, ucsim: $UN PCs"

MIN=$((EN < UN ? EN : UN))
if [ "$MIN" -eq 0 ]; then
    echo "FAIL: no PCs to compare"; exit 1
fi

if diff "$TMP/emu_pcs.txt" "$TMP/ucsim_pcs.txt" > "$TMP/diff.out" 2>&1; then
    echo "  PASS: $MIN/$MIN PCs identical from reset"
else
    FIRST=$(grep -n "^[<>]" "$TMP/diff.out" | head -1)
    echo "  FAIL: PC divergence at $FIRST"
    head -10 "$TMP/diff.out"
    exit 1
fi
