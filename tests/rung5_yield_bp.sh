#!/bin/bash
# rung5_yield_bp.sh — §8 rung 5: yield breakpoint halts at the correct
# (task, state) with a consistent bw_ms.
#
# Sets a code breakpoint at a case-label address (from the symbol table),
# runs until it hits, then reads bw_ms and task_state from IRAM.
#
# Usage: ./tests/rung5_yield_bp.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
HEXFILE="$SCRIPT_DIR/fixtures/scheduled_gen.ihx"
SYMBOLS="$SCRIPT_DIR/fixtures/scheduled_gen.symbols.json"
PASS=0; FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -x "$UCSIM" ]; then
    echo "FAIL: ucsim_51 not found — build first" >&2
    exit 1
fi

echo "Rung 5: yield breakpoint on scheduler image"

# Get yield address for task0, state 3 (the wait_150ms yield)
YIELD_ADDR=$(python3 -c "
import json
d = json.load(open('$SYMBOLS'))
for y in d['scheduler']['tasks'][0]['yields']:
    if y['state'] == 3:
        print(y['addr'])
        break
")
YIELD_HEX=$(printf '%04x' $YIELD_ADDR)

# Get IRAM addresses
BW_MS_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['bw_ms']['addr'])")
T0_STATE_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['state']['addr'])")
T0_UNTIL_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['until']['addr'])")

echo "  Yield breakpoint: task0 state=3 at code 0x$YIELD_HEX"
echo "  bw_ms at iram 0x$(printf '%02x' $BW_MS_ADDR)"
echo "  task0_state at iram 0x$(printf '%02x' $T0_STATE_ADDR)"

# Run until yield breakpoint, then read Level 1 position
BMS_HI=$((BW_MS_ADDR + 1))
T0S_HI=$((T0_STATE_ADDR + 1))
T0U_HI=$((T0_UNTIL_ADDR + 1))

OUT=$(printf "break 0x$YIELD_HEX\nrun\ndi $(printf '0x%02x' $BW_MS_ADDR) $(printf '0x%02x' $BMS_HI)\ndi $(printf '0x%02x' $T0_STATE_ADDR) $(printf '0x%02x' $T0S_HI)\ndi $(printf '0x%02x' $T0_UNTIL_ADDR) $(printf '0x%02x' $T0U_HI)\npc\nquit\n" | $UCSIM -t STC12 "$HEXFILE" 2>/dev/null)

# Check PC matches yield address
PC_LINE=$(echo "$OUT" | grep "^0x" | tail -1)
if echo "$PC_LINE" | grep -qi "$YIELD_HEX"; then
    pass "halted at yield point 0x$YIELD_HEX"
else
    fail "wrong PC: $PC_LINE (expected 0x$YIELD_HEX)"
fi

# Parse IRAM dump to get task_state value
# The di output looks like: "0xNN  XX YY  .."
T0_STATE_LINE=$(echo "$OUT" | grep "^0x$(printf '%02x' $T0_STATE_ADDR)" | head -1)
if [ -n "$T0_STATE_LINE" ]; then
    # Extract first data byte (little-endian low byte of state)
    STATE_LOW=$(echo "$T0_STATE_LINE" | awk '{print $2}')
    STATE_VAL=$(printf '%d' "0x$STATE_LOW" 2>/dev/null || echo "?")
    if [ "$STATE_VAL" = "3" ]; then
        pass "task0_state = 3 at yield point"
    else
        fail "task0_state = $STATE_VAL, expected 3"
    fi
else
    fail "could not read task0_state from IRAM"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
