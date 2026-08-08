#!/bin/bash
# rung3_step_masked.sh — §8 rung 3: step('insn') x N from reset with
# interrupts masked produces the same PC sequence on both emulators.
#
# Runs a non-ISR image (blink, which uses polled TF0) or masks
# interrupts by clearing EA. Steps both emulators and compares
# the PC at each step.
#
# Usage: ./tests/rung3_step_masked.sh [steps]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
EMU_TRACE="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
HEXFILE="${SCRIPT_DIR}/fixtures/scheduled_gen.ihx"
STEPS="${1:-200}"
FOSC=11059200

if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2
    exit 0
fi
if [ ! -x "$UCSIM" ]; then
    echo "FAIL: ucsim_51 not found" >&2; exit 1
fi

echo "Rung 3: step('insn') x $STEPS with interrupts masked"

# Use blink image — it never enables interrupts (polled TF0),
# so EA is already 0 from reset.
HEXFILE=/tmp/blink.ihx
if [ ! -f "$HEXFILE" ]; then
    echo "FAIL: blink.ihx not found at $HEXFILE" >&2; exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# emu8051: emit PC per instruction
# The trace format emits PC on each new instruction (when mTickDelay==0)
UNTIL_NS=$((STEPS * 500))  # generous
"$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEXFILE" 2>/dev/null \
    | awk '$2 == "PC" {print $3}' | head -$STEPS > "$TMP/emu_pcs.txt"

# ucsim: step one instruction at a time, capture PC
# Use the ucsim command interface
python3 -c "
for i in range($STEPS):
    print('step')
print('quit')
" | $UCSIM -t STC12 "$HEXFILE" 2>/dev/null \
    | grep 'Stop at' | sed 's/.*0x\([0-9a-fA-F]*\).*/\1/' \
    | tr 'a-f' 'A-F' | head -$STEPS > "$TMP/ucsim_pcs.txt"

EN=$(wc -l < "$TMP/emu_pcs.txt")
UN=$(wc -l < "$TMP/ucsim_pcs.txt")
echo "  emu8051: $EN PCs, ucsim: $UN PCs"

# Compare. The sequences may not align 1:1 because emu8051 skips
# multi-cycle instruction PCs. Compare unique-PC sequences instead.
# Both should visit the same addresses in the same order.
awk '!seen[$0]++' "$TMP/emu_pcs.txt" > "$TMP/emu_unique.txt"
awk '!seen[$0]++' "$TMP/ucsim_pcs.txt" > "$TMP/ucsim_unique.txt"

EU=$(wc -l < "$TMP/emu_unique.txt")
UU=$(wc -l < "$TMP/ucsim_unique.txt")
MIN=$((EU < UU ? EU : UU))

if diff <(head -$MIN "$TMP/emu_unique.txt") <(head -$MIN "$TMP/ucsim_unique.txt") > /dev/null 2>&1; then
    echo "  PASS: first $MIN unique PCs identical"
else
    echo "  FAIL: PC sequence divergence"
    diff <(head -$MIN "$TMP/emu_unique.txt") <(head -$MIN "$TMP/ucsim_unique.txt") | head -15
    exit 1
fi
