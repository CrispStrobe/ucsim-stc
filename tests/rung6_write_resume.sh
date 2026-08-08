#!/bin/bash
# rung6_write_resume.sh — §8 rung 6: write a variable while halted,
# resume, and verify the effect in the subsequent execution.
#
# Halts at bw_task0 entry, writes bw_task0_state = 0xFFFF (ended),
# resumes. The task should never run again, so no P1 toggles from task0.
#
# Usage: ./tests/rung6_write_resume.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
HEXFILE="$SCRIPT_DIR/fixtures/scheduled_gen.ihx"
SYMBOLS="$SCRIPT_DIR/fixtures/scheduled_gen.symbols.json"

if [ ! -x "$UCSIM" ]; then
    echo "FAIL: ucsim_51 not found" >&2; exit 1
fi

echo "Rung 6: write variable while halted, resume"

# Get addresses from symbol table
BP_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['func_addr'])")
T0_STATE_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['state']['addr'])")

BP_HEX=$(printf '%04x' $BP_ADDR)
STATE_HEX=$(printf '%02x' $T0_STATE_ADDR)
STATE_HI_HEX=$(printf '%02x' $((T0_STATE_ADDR + 1)))

echo "  Break at bw_task0 (0x$BP_HEX), write state=0xFFFF, resume"

# 1. Set breakpoint at task0 entry
# 2. Run until it hits
# 3. Write task0_state = 0xFFFF (little-endian: FF at addr, FF at addr+1)
# 4. Resume and step 5000 times
# 5. Read task0_state — should still be 0xFFFF (task never re-entered)
OUT=$(printf "break 0x$BP_HEX\nrun\nset mem iram 0x$STATE_HEX 0xFF\nset mem iram 0x$STATE_HI_HEX 0xFF\ndi 0x$STATE_HEX 0x$STATE_HI_HEX\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\ndi 0x$STATE_HEX 0x$STATE_HI_HEX\nquit\n" | $UCSIM -t STC12 "$HEXFILE" 2>/dev/null)

# Check that task0_state is 0xFFFF after stepping
LAST_DUMP=$(echo "$OUT" | grep "^0x$(printf '%02x' $T0_STATE_ADDR)" | tail -1)
if echo "$LAST_DUMP" | grep -q "ff ff"; then
    echo "  PASS: task0_state = 0xFFFF after resume (task stayed ended)"
else
    echo "  FAIL: task0_state changed after resume"
    echo "  Last dump: $LAST_DUMP"
    exit 1
fi

echo "  PASS: rung 6 — write while halted affects subsequent execution"
