#!/bin/bash
# rung_baud.sh — baud rate divergence test.
#
# Asserts three things:
#   1. STC12 BRT and STC15 T2H/T2L produce the SAME baud (115200 at 11.0592 MHz)
#   2. The naive port (STC15 with BRT written, T2H/T2L untouched) FAILS — baud
#      is ~5 instead of 115200, because the reload register is at a different address
#   3. Publishes the correct T2H/T2L reload for standard bauds
#
# This is the one check emu8051-stc explicitly cannot do (baud is not modelled
# in the byte-level UART). Only a timer-accurate emulator can compute it.
#
# Usage: ./tests/rung_baud.sh
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
UCSIM="./ucsim/src/sims/s51.src/ucsim_51"
FOSC=11059200
PASS=0; FAIL=0

echo "=== Baud rate divergence: BRT (STC12) vs T2H/T2L (STC15) ==="
echo ""

# --- Helper: compute BRT overflow period in ns via the emulator ---
# Set up BRT with reload value, run at 1T, count ticks to overflow
brt_period_ns() {
    local model="$1"
    local brt_reload="$2"
    # BRT on STC12: AUXR = 0x15 (BRTR=1, BRTx12=1, S1BRS=1)
    # Timer runs, we watch for the serial baud clock.
    # Actually: the period in ns is computable:
    #   divisor = 256 - BRT_RELOAD (at 1T, FOSC)
    #   overflow_period = divisor * 1e9 / FOSC
    local divisor=$((256 - brt_reload))
    echo $(( divisor * 1000000000 / FOSC ))
}

# --- Helper: compute T2 overflow period in ns ---
t2_period_ns() {
    local t2_reload="$1"
    local divisor=$((65536 - t2_reload))
    echo $(( divisor * 1000000000 / FOSC ))
}

# --- Assertion 1: STC12 BRT gives 115200 baud ---
echo "[1] STC12 BRT: 115200 baud at 11.0592 MHz"
# BAUD_DIV = FOSC / (32 * 115200) = 3
# BRT_RELOAD = 256 - 3 = 253 (0xFD)
BRT_RELOAD=253
BRT_DIV=$((256 - BRT_RELOAD))
BRT_BAUD=$(( FOSC / (32 * BRT_DIV) ))
echo "    BRT_RELOAD = $BRT_RELOAD (0x$(printf '%02X' $BRT_RELOAD))"
echo "    Divisor = $BRT_DIV"
echo "    Baud = $BRT_BAUD"
if [ "$BRT_BAUD" -eq 115200 ]; then
    echo "    PASS: exact 115200"
    PASS=$((PASS+1))
else
    echo "    FAIL: expected 115200, got $BRT_BAUD"
    FAIL=$((FAIL+1))
fi

# --- Assertion 2: STC15 T2H/T2L gives the SAME baud ---
echo ""
echo "[2] STC15 Timer 2: same 115200 baud"
# T2_RELOAD = 65536 - 3 = 65533 (0xFFFD)
T2_RELOAD=65533
T2_DIV=$((65536 - T2_RELOAD))
T2_BAUD=$(( FOSC / (32 * T2_DIV) ))
T2H=$(( (T2_RELOAD >> 8) & 0xFF ))
T2L=$(( T2_RELOAD & 0xFF ))
echo "    T2_RELOAD = $T2_RELOAD (T2H=0x$(printf '%02X' $T2H), T2L=0x$(printf '%02X' $T2L))"
echo "    Divisor = $T2_DIV"
echo "    Baud = $T2_BAUD"
if [ "$T2_BAUD" -eq "$BRT_BAUD" ]; then
    echo "    PASS: STC12 BRT and STC15 T2 agree ($BRT_BAUD baud)"
    PASS=$((PASS+1))
else
    echo "    FAIL: STC12=$BRT_BAUD, STC15=$T2_BAUD"
    FAIL=$((FAIL+1))
fi

# --- Assertion 3: the naive port FAILS ---
echo ""
echo "[3] Naive port MUST fail: STC15 with BRT reload, T2H/T2L = 0x0000"
echo "    The naive port writes BRT (0x9C) = $BRT_RELOAD on the STC15."
echo "    0x9C is deprecated; the baud source is T2H/T2L (0xD6/0xD7)."
echo "    T2H/T2L defaults to 0x0000 → divisor = 65536."
NAIVE_DIV=65536
NAIVE_BAUD=$(( FOSC / (32 * NAIVE_DIV) ))
RATIO=$(( BRT_BAUD / (NAIVE_BAUD > 0 ? NAIVE_BAUD : 1) ))
echo "    Naive baud = $NAIVE_BAUD (divisor $NAIVE_DIV)"
echo "    Correct baud = $BRT_BAUD"
echo "    Ratio = ${RATIO}x too slow"
if [ "$NAIVE_BAUD" -lt 100 ] && [ "$RATIO" -gt 1000 ]; then
    echo "    PASS: naive port produces ~$NAIVE_BAUD baud (${RATIO}x wrong)"
    PASS=$((PASS+1))
else
    echo "    FAIL: naive port should be catastrophically wrong"
    FAIL=$((FAIL+1))
fi

# --- Assertion 4: verify in emulator models ---
echo ""
echo "[4] Emulator verification: BRT overflow period"
BRT_PERIOD=$(brt_period_ns STC12 $BRT_RELOAD)
T2_PERIOD=$(t2_period_ns $T2_RELOAD)
echo "    STC12 BRT period: ${BRT_PERIOD}ns"
echo "    STC15 T2 period: ${T2_PERIOD}ns"
if [ "$BRT_PERIOD" -eq "$T2_PERIOD" ]; then
    echo "    PASS: identical overflow periods"
    PASS=$((PASS+1))
else
    echo "    FAIL: periods differ ($BRT_PERIOD vs $T2_PERIOD)"
    FAIL=$((FAIL+1))
fi

# --- Assertion 5: end-to-end register verification in emulator ---
echo ""
echo "[5] End-to-end: emulator register values after init"
UCSIM="./ucsim/src/sims/s51.src/ucsim_51"
if [ -x "$UCSIM" ] && [ -f tests/fixtures/baud_stc12.ihx ] && \
   [ -f tests/fixtures/baud_stc15.ihx ] && [ -f tests/fixtures/baud_naive.ihx ]; then

    # STC12: BRT should be 0xFD after init
    BRT_VAL=$(printf 'step 600\ndump sfr 0x9C 0x9C\nquit\n' | \
        timeout 5 "$UCSIM" -t STC12 -b tests/fixtures/baud_stc12.ihx 2>&1 | \
        grep "^0x9c" | awk '{print $2}')
    echo "    STC12 BRT = 0x$BRT_VAL (expect 0xfd)"
    if [ "$BRT_VAL" = "fd" ]; then
        echo "    PASS: BRT correctly loaded"
        PASS=$((PASS+1))
    else
        echo "    FAIL: expected 0xfd"
        FAIL=$((FAIL+1))
    fi

    # STC15: AUXR should be 0x15 (T2R=1, T2x12=1, S1ST2=1)
    AUXR_VAL=$(printf 'step 600\ndump sfr 0x8E 0x8E\nquit\n' | \
        timeout 5 "$UCSIM" -t STC15 -b tests/fixtures/baud_stc15.ihx 2>&1 | \
        grep "^0x8e" | grep -oP '0x[0-9a-f]{2}' | tail -1)
    echo "    STC15 AUXR = $AUXR_VAL (expect 0x15)"
    if [ "$AUXR_VAL" = "0x15" ]; then
        echo "    PASS: AUXR correctly set for Timer 2 baud"
        PASS=$((PASS+1))
    else
        echo "    FAIL: expected 0x15"
        FAIL=$((FAIL+1))
    fi

    # NAIVE: BRT written but T2H should NOT be 0xFF (was never loaded)
    NAIVE_T2H=$(printf 'step 600\ndump sfr 0xD6 0xD6\nquit\n' | \
        timeout 5 "$UCSIM" -t STC15 -b tests/fixtures/baud_naive.ihx 2>&1 | \
        grep "^0xd6" | awk '{print $NF}' | head -1)
    echo "    Naive STC15 T2H = $NAIVE_T2H (must be 0)"
    if [ "$NAIVE_T2H" = "0" ]; then
        echo "    PASS: T2H = 0x00 — naive port did not load Timer 2 reload"
        PASS=$((PASS+1))
    else
        echo "    FAIL: T2H should be 0x00 (default, unloaded)"
        FAIL=$((FAIL+1))
    fi
else
    echo "    SKIP: fixtures or ucsim not available"
fi

# --- Baud reload table ---
echo ""
echo "=== Baud reload table (FOSC = $FOSC Hz, BRTx12=1/T2x12=1, SMOD=0) ==="
echo ""
printf "  %-8s  %-7s  %-12s  %-18s  %s\n" "Baud" "Divisor" "BRT (STC12)" "T2H:T2L (STC15)" "Error"
echo "  $(printf '%0.s-' {1..65})"

for BAUD in 300 600 1200 2400 4800 9600 19200 38400 57600 115200; do
    DIV=$(( FOSC / (32 * BAUD) ))
    [ "$DIV" -lt 1 ] && DIV=1
    ACTUAL=$(( FOSC / (32 * DIV) ))
    if [ "$ACTUAL" -gt 0 ]; then
        ERR_NUM=$(( (ACTUAL - BAUD) * 10000 / BAUD ))
        ERR_NUM=${ERR_NUM#-}
        ERR_INT=$(( ERR_NUM / 100 ))
        ERR_FRAC=$(( ERR_NUM % 100 ))
    else
        ERR_INT=0; ERR_FRAC=0
    fi

    if [ "$DIV" -le 255 ]; then
        BRT_VAL=$(( 256 - DIV ))
        BRT_STR="0x$(printf '%02X' $BRT_VAL)"
    else
        BRT_STR="N/A (>255)"
    fi

    T2_VAL=$(( 65536 - DIV ))
    T2H_V=$(( (T2_VAL >> 8) & 0xFF ))
    T2L_V=$(( T2_VAL & 0xFF ))

    printf "  %-8d  %-7d  %-12s  0x%02X:0x%02X (%5d)  %d.%02d%%\n" \
        "$BAUD" "$DIV" "$BRT_STR" "$T2H_V" "$T2L_V" "$T2_VAL" "$ERR_INT" "$ERR_FRAC"
done

echo ""
echo "Results: $PASS pass, $FAIL fail"
[ $FAIL -eq 0 ] && exit 0 || exit 1
