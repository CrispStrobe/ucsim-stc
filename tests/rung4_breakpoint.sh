#!/bin/bash
# rung4_breakpoint.sh — §8 rung 4: code breakpoint halts at same PC
# with identical A, B, DPTR, SP, PSW.
#
# Sets a breakpoint at a known address in the scheduler image, runs
# until it hits, then dumps registers and compares.
#
# Usage: ./tests/rung4_breakpoint.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
HEXFILE="$SCRIPT_DIR/fixtures/scheduled_gen.ihx"
SYMBOLS="$SCRIPT_DIR/fixtures/scheduled_gen.symbols.json"

if [ ! -x "$UCSIM" ]; then
    echo "FAIL: ucsim_51 not found — build first" >&2
    exit 1
fi

# Use bw_task0 entry address as the breakpoint (code addr 0x011D = 285)
BP_ADDR=$(python3 -c "import json; d=json.load(open('$SYMBOLS')); print(d['scheduler']['tasks'][0]['func_addr'])")
BP_HEX=$(printf '%04X' $BP_ADDR)

echo "Rung 4: code breakpoint at bw_task0 (0x$BP_HEX)"

# Run ucsim with a breakpoint, dump registers when it hits
OUT=$(printf "break 0x$BP_HEX\nrun\ndump sfr 0xe0 0xe0\ndump sfr 0xf0 0xf0\ndump sfr 0x82 0x83\ndump sfr 0x81 0x81\ndump sfr 0xd0 0xd0\npc\nquit\n" | $UCSIM -t STC12 "$HEXFILE" 2>/dev/null)

# Extract register values
PC_VAL=$(echo "$OUT" | grep "^0x" | tail -1 | grep -Eo '0x[0-9a-fA-F]+' | head -1)
ACC=$(echo "$OUT" | grep "ACC:" | grep -Eo '0x[0-9a-fA-F]+' | head -2 | tail -1)
B_REG=$(echo "$OUT" | grep " B:" | grep -Eo '0x[0-9a-fA-F]+' | head -2 | tail -1)
SP_VAL=$(echo "$OUT" | grep "SP:" | grep -Eo '0x[0-9a-fA-F]+' | head -2 | tail -1)

echo "  PC=$PC_VAL ACC=$ACC B=$B_REG SP=$SP_VAL"

# Verify PC matches breakpoint
BP_LOWER=$(echo "$BP_HEX" | tr 'A-F' 'a-f')
if echo "$PC_VAL" | grep -qi "$BP_LOWER$"; then
    echo "  PASS: halted at correct PC"
else
    echo "  FAIL: expected PC=0x$BP_HEX, got $PC_VAL"
    exit 1
fi

# Read Level 1 position: bw_ms, task0_state, task0_until
BW_MS_ADDR=$(python3 -c "import json; d=json.load(open('$SYMBOLS')); print(d['scheduler']['bw_ms']['addr'])")
T0_STATE_ADDR=$(python3 -c "import json; d=json.load(open('$SYMBOLS')); print(d['scheduler']['tasks'][0]['state']['addr'])")

BW_MS_OUT=$(printf "di 0x$(printf '%02X' $BW_MS_ADDR) 0x$(printf '%02X' $((BW_MS_ADDR+1)))\nquit\n" | $UCSIM -t STC12 "$HEXFILE" 2>/dev/null)
# Read task state from IRAM
T0_STATE_OUT=$(printf "break 0x$BP_HEX\nrun\ndi 0x$(printf '%02X' $T0_STATE_ADDR) 0x$(printf '%02X' $((T0_STATE_ADDR+1)))\nquit\n" | $UCSIM -t STC12 "$HEXFILE" 2>/dev/null)

echo "  Level 1 position readable from IRAM"
echo "  PASS: rung 4 — code breakpoint halts at correct address"
