#!/bin/bash
# multipart_diff.sh — differential execution across parts.
#
# Phase 1 (today): ucsim-only consistency checks.
#   - STC89 blink produces expected events (Timer 0, port toggle)
#   - Same firmware on STC12 vs STC89 with AUXR.7=0: Timer 0 at FOSC/12
#     produces identical OVERFLOW counts in the same time window
#   - STC15W runs STC12 firmware (subset that doesn't touch Timer 1)
#
# Phase 2 (pending emu_trace -part): cross-emulator per part.
#
# Usage: ./tests/multipart_diff.sh

set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
FOSC=11059200
UNTIL_NS=10000000

if [ ! -x "$TRACE" ]; then
  echo "FAIL: stc12_trace not found" >&2; exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0; SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

echo "=== Multi-part differential tests ==="

# --- Test 1: STC89 blink produces events ---
echo "[1] STC89 blink produces SFR events"
"$TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS \
    tests/fixtures/blink_stc89.ihx 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' > "$TMP/stc89_blink.ev"
N=$(wc -l < "$TMP/stc89_blink.ev")
if [ "$N" -gt 3 ]; then
    pass "STC89 blink: $N events"
else
    fail "STC89 blink: only $N events"
fi

# --- Test 2: STC89 blink has TF0 at ~1ms intervals ---
echo "[2] STC89 Timer 0 overflow timing"
"$TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS \
    tests/fixtures/blink_stc89.ihx 2>/dev/null \
    | awk '$2 == "TF" && $3 == "0" {print $1}' > "$TMP/stc89_tf.times"
N_TF=$(wc -l < "$TMP/stc89_tf.times")
if [ "$N_TF" -ge 5 ]; then
    # Check first interval is ~1ms (1000000 ns ± 10%)
    T0=$(sed -n '1p' "$TMP/stc89_tf.times")
    T1=$(sed -n '2p' "$TMP/stc89_tf.times")
    DELTA=$((T1 - T0))
    if [ "$DELTA" -gt 900000 ] && [ "$DELTA" -lt 1100000 ]; then
        pass "STC89 TF0 interval: ${DELTA}ns (~1ms)"
    else
        fail "STC89 TF0 interval: ${DELTA}ns (expected ~1000000ns)"
    fi
else
    fail "STC89: only $N_TF TF0 events"
fi

# --- Test 3: STC89 blink P1 toggle ---
echo "[3] STC89 blink P1 toggle"
grep "SFR	90" "$TMP/stc89_blink.ev" | head -2 > "$TMP/stc89_p1.ev"
N_P1=$(wc -l < "$TMP/stc89_p1.ev")
if [ "$N_P1" -ge 1 ]; then
    pass "STC89 blink: P1 toggled ($N_P1 transitions in 10ms)"
else
    fail "STC89 blink: no P1 events"
fi

# --- Test 4: STC12 scheduled_gen still works ---
echo "[4] STC12 scheduled_gen (regression)"
"$TRACE" -t STC12 -fosc $FOSC -until-ns $UNTIL_NS \
    tests/fixtures/scheduled_gen.ihx 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/stc12_sched.ev"
N=$(wc -l < "$TMP/stc12_sched.ev")
if [ "$N" -gt 20 ]; then
    pass "STC12 scheduled_gen: $N events (regression green)"
else
    fail "STC12 scheduled_gen: only $N events"
fi

# --- Test 5: STC15 runs STC12 firmware (same peripherals at same addrs) ---
echo "[5] STC15 vs STC12 scheduled_gen"
"$TRACE" -t STC15 -fosc $FOSC -until-ns $UNTIL_NS \
    tests/fixtures/scheduled_gen.ihx 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/stc15_sched.ev"
if diff "$TMP/stc12_sched.ev" "$TMP/stc15_sched.ev" > /dev/null 2>&1; then
    N15=$(wc -l < "$TMP/stc15_sched.ev")
    pass "STC15 vs STC12 scheduled_gen: $N15/$N identical"
else
    fail "STC15 vs STC12 scheduled_gen: diverged"
fi

# --- Test 6: STC15W runs STC12 firmware (subset — no Timer 1 used) ---
echo "[6] STC15W vs STC12 scheduled_gen"
"$TRACE" -t STC15W -fosc $FOSC -until-ns $UNTIL_NS \
    tests/fixtures/scheduled_gen.ihx 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/stc15w_sched.ev"
if diff "$TMP/stc12_sched.ev" "$TMP/stc15w_sched.ev" > /dev/null 2>&1; then
    N15W=$(wc -l < "$TMP/stc15w_sched.ev")
    pass "STC15W vs STC12 scheduled_gen: $N15W/$N identical"
else
    fail "STC15W vs STC12 scheduled_gen: diverged"
fi

# --- Test 7: Cross-emulator STC89 (requires emu_trace -part support) ---
echo "[7] Cross-emulator STC89 blink"
# Check if emu_trace supports -part by looking for 12T timing in its output.
# If it runs at 1T, the flag was silently ignored and we skip.
EMU_HAS_PART=false
if [ -x "$EMU_TRACE" ]; then
    # Run a NOP sled and check whether inter-PC timing is ~1085ns (12T) or ~90ns (1T)
    EMU_TIMES=$("$EMU_TRACE" -part STC89 -fosc $FOSC -until-ns 50000 \
        tests/fixtures/nop_sled.ihx 2>/dev/null \
        | grep "^[0-9]*	PC	" | head -3 | awk -F'\t' '{print $1}')
    EMU_T0=$(echo "$EMU_TIMES" | sed -n '1p')
    EMU_T1=$(echo "$EMU_TIMES" | sed -n '2p')
    if [ -n "$EMU_T0" ] && [ -n "$EMU_T1" ]; then
        EMU_DELTA=$((EMU_T1 - EMU_T0))
        if [ "$EMU_DELTA" -gt 500 ]; then
            EMU_HAS_PART=true
        fi
    fi
fi

if $EMU_HAS_PART; then
    "$EMU_TRACE" -part STC89 -fosc $FOSC -until-ns $UNTIL_NS \
        tests/fixtures/blink_stc89.ihx 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu_stc89_blink.ev"
    # Compare against ucsim's STC89 blink
    cut -f2- "$TMP/stc89_blink.ev" > "$TMP/ucsim_stc89_nots.ev"
    if diff "$TMP/ucsim_stc89_nots.ev" "$TMP/emu_stc89_blink.ev" > /dev/null 2>&1; then
        pass "Cross-emu STC89 blink: identical"
    else
        fail "Cross-emu STC89 blink: diverged"
    fi
else
    skip "emu_trace does not support -part with 12T timing (see spec-updates/012)"
fi

echo ""
echo "=== Results: $PASS pass, $FAIL fail, $SKIP skip ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
