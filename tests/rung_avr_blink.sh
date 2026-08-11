#!/bin/bash
# rung_avr_blink.sh — AVR oracle: hand-assembled blink cycle count verification.
#
# Runs the same 6-word blink program from bw-board's avr8js-adapter.test.js
# through ucsim_avr and checks cycle counts against the arithmetic oracle.
#
# The program (ATmega328P IO addresses):
#   0: SBI DDRB,5   (0x9A25)  2 cy
#   1: SBI PINB,5   (0x9A1D)  2 cy
#   2: LDI r24,0xFF (0xEF8F)  1 cy
#   3: DEC r24      (0x958A)  1 cy
#   4: BRNE .-2     (0xF7F1)  2 cy taken, 1 cy not
#   5: RJMP .-5     (0xCFFB)  2 cy
#
# Toggle period: SBI(2) + LDI(1) + 254×(DEC+BRNE-taken=3) + (DEC+BRNE-not=2) + RJMP(2) = 769 cy
# First toggle offset: SBI_DDRB(2) + SBI_PINB(2) = 4 cy
# At 16 MHz: 769 cy × 62.5 ns = 48062.5 ns per toggle
# avr8js result: 48063 ns (rounded) — agrees exactly.
#
# Usage: ./tests/rung_avr_blink.sh
set -e
cd "$(dirname "$0")/.."

AVR="./ucsim/src/sims/avr.src/ucsim_avr"
HEX="tests/fixtures/avr_blink_hand.ihx"

if [ ! -x "$AVR" ]; then echo "FAIL: ucsim_avr not found" >&2; exit 1; fi
if [ ! -f "$HEX" ]; then echo "FAIL: $HEX not found" >&2; exit 1; fi

TMP=$(mktemp)
trap "rm -f $TMP" EXIT

# Step through two full toggles (514 + 513 = 1027 steps = 1540 ticks)
# and verify tick count.
cat > "$TMP" << 'CMDS'
set mem rom 0 0x9a25
step 1027
tick
quit
CMDS

OUTPUT=$(timeout 10 "$AVR" "$HEX" -c - < "$TMP" 2>&1)

TICKS=$(echo "$OUTPUT" | grep -Eo 'Simulated [0-9]+ ticks' | tail -1 | grep -Eo '[0-9]+' | head -1)
PC=$(echo "$OUTPUT" | grep -Eo 'Stop at 0x[0-9a-f]+' | tail -1 | sed 's/Stop at 0x//')

PASS=0
FAIL=0

# Check 1: total ticks = 1540 (771 first toggle + 769 second toggle)
if [ "$TICKS" = "1540" ]; then
    echo "PASS  Total ticks: $TICKS (expected 1540: 771+769)"
    PASS=$((PASS+1))
else
    echo "FAIL  Total ticks: $TICKS (expected 1540)"
    FAIL=$((FAIL+1))
fi

# Check 2: PC at 0x000001 (SBI PINB — start of 3rd toggle)
if [ "$PC" = "000001" ]; then
    echo "PASS  PC: 0x$PC (start of third toggle, SBI PINB)"
    PASS=$((PASS+1))
else
    echo "FAIL  PC: 0x$PC (expected 0x000001)"
    FAIL=$((FAIL+1))
fi

# Check 3: per-instruction cycle costs
# Step exactly 6 instructions (one full iteration minus the inner loop)
cat > "$TMP" << 'CMDS'
set mem rom 0 0x9a25
step
tick
step
tick
step
tick
step
tick
step
tick
step
tick
quit
CMDS

OUTPUT=$(timeout 10 "$AVR" "$HEX" -c - < "$TMP" 2>&1)

# Extract stepped-tick lines: "stepped N ticks"
STEPS=($(echo "$OUTPUT" | grep -Eo 'stepped [0-9]+ ticks' | grep -Eo '[0-9]+' | head -6))

# Expected: SBI(2), SBI(2), LDI(1), DEC(1), BRNE-taken(2), DEC(1)
EXPECTED=(2 2 1 1 2 1)
NAMES=("SBI_DDRB" "SBI_PINB" "LDI" "DEC" "BRNE-taken" "DEC")

ALL_OK=true
for i in 0 1 2 3 4 5; do
    if [ "${STEPS[$i]}" = "${EXPECTED[$i]}" ]; then
        echo "PASS  ${NAMES[$i]}: ${STEPS[$i]} cy"
        PASS=$((PASS+1))
    else
        echo "FAIL  ${NAMES[$i]}: ${STEPS[$i]} cy (expected ${EXPECTED[$i]})"
        FAIL=$((FAIL+1))
        ALL_OK=false
    fi
done

echo ""
echo "Results: $PASS pass, $FAIL fail"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
echo ""
echo "ucsim_avr and avr8js agree: 769 cycles per toggle, 48062.5 ns at 16 MHz."
