#!/bin/bash
# rung_simavr_canonical.sh — simavr canonical-trace differential vs avr8js.
#
# Runs both simulators via their canonical-trace adapters on ATmega328P
# hex fixtures, then compares using sb3-creator's compareTraces (the same
# comparator oracle-differential.mjs uses).
#
# Usage: ./tests/rung_simavr_canonical.sh
set -e
cd "$(dirname "$0")/.."

DIFF_CMD="node tests/canonical_diff.mjs"
PASS=0
FAIL=0
KNOWN=0

pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
known() { echo "KNOWN $1"; KNOWN=$((KNOWN+1)); }

if [ ! -x tests/simavr_harness ]; then
    echo "Building simavr_harness..."
    gcc -O2 -o tests/simavr_harness tests/simavr_harness.c -lsimavr -lm
fi

DECL_LED='[{"where":"D13","name":"led1","activeLow":false}]'

echo ""
echo "=== Simavr canonical-trace differential (vs avr8js, via compareTraces) ==="
echo ""

# ── Test 1: Compiled blink ──
echo "--- Test 1: Compiled blink ---"
OUT=$($DIFF_CMD tests/fixtures/avr_blink_compiled.ihx "$DECL_LED" 50 2>&1) && RC=0 || RC=$?
echo "  $OUT"
if [ "$RC" -eq 0 ]; then
    pass "Compiled blink"
else
    fail "Compiled blink"
fi

# ── Test 2: Hand-assembled blink ──
echo "--- Test 2: Hand blink ---"
OUT=$($DIFF_CMD tests/fixtures/avr_blink_hand.ihx "$DECL_LED" 2 2>&1) && RC=0 || RC=$?
echo "  $OUT"
if [ "$RC" -eq 0 ]; then
    pass "Hand blink"
else
    fail "Hand blink"
fi

# ── Test 3: UART test ──
echo "--- Test 3: UART TX ---"
OUT=$($DIFF_CMD tests/fixtures/avr_uart_test.ihx "$DECL_LED" 50 1.05 2>&1) && RC=0 || RC=$?
echo "  $OUT"
if [ "$RC" -eq 0 ]; then
    pass "UART TX"
else
    known "UART TX (simavr phantom parity — spec-updates/018)"
fi

# ── Test 4: Timer0 overflow ──
echo "--- Test 4: Timer0 OVF ---"
OUT=$($DIFF_CMD tests/fixtures/avr_timer0_ovf.ihx "$DECL_LED" 50 2>&1) && RC=0 || RC=$?
echo "  $OUT"
if [ "$RC" -eq 0 ]; then
    pass "Timer0 OVF"
else
    fail "Timer0 OVF"
fi

# ── Test 5: Timer1 CTC ──
echo "--- Test 5: Timer1 CTC ---"
OUT=$($DIFF_CMD tests/fixtures/avr_timer_test.ihx "$DECL_LED" 20 2>&1) && RC=0 || RC=$?
echo "  $OUT"
if [ "$RC" -eq 0 ]; then
    pass "Timer1 CTC"
else
    fail "Timer1 CTC"
fi

# ── Summary ──
echo ""
echo "================================"
echo "Canonical trace differential: $PASS pass, $FAIL fail, $KNOWN known"
echo "================================"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
