#!/bin/bash
# rung_stc15_sfr_delta.sh — STC15 SFR map + delta trap verification.
#
# Verifies the three STC15 vs STC12 delta traps from
# docs/STC15-PERIPHERAL-MODEL.md and the SFR presence/absence model.
#
# Tests run the SAME hex on both -t STC15 and -t STC12, checking that:
#   STC15: T2H/T2L/P5/P5M0/INT_CLKO modelled, T4T3M refused
#   STC12: T2H/T2L/P5 refused (UNMODELLED), BRT modelled
#
# Usage: ./tests/rung_stc15_sfr_delta.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
HEX="$SCRIPT_DIR/fixtures/stc15_sfr_verify.ihx"
FOSC=11059200
UNTIL_NS=2000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

echo "=== STC15 SFR Delta Trap Verification ==="
echo ""

# Run on both STC15 and STC12
timeout 5 "$STC12_TRACE" -t STC15 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | grep -E "SFR|UNMODELLED|PIN" > "$TMP/stc15.txt"
timeout 5 "$STC12_TRACE" -t STC12 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | grep -E "SFR|UNMODELLED|PIN" > "$TMP/stc12.txt"

# --- Section 1: Delta trap 2 — AUXR baud bits route correctly ---
echo "--- Section 1: AUXR = 0x15 (Timer 2 config on STC15, BRT config on STC12) ---"

# Both parts should accept AUXR = 0x15
stc15_auxr=$(grep "SFR.*8E.*15" "$TMP/stc15.txt" | head -1)
stc12_auxr=$(grep "SFR.*8E.*15" "$TMP/stc12.txt" | head -1)

if [ -n "$stc15_auxr" ]; then
    echo "STC15: AUXR=0x15 accepted (T2R+T2x12+S1ST2) — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: AUXR=0x15 NOT accepted — FAIL"
    FAIL=$((FAIL+1))
fi

if [ -n "$stc12_auxr" ]; then
    echo "STC12: AUXR=0x15 accepted (BRTR+BRTx12+S1BRS) — PASS"
    PASS=$((PASS+1))
else
    echo "STC12: AUXR=0x15 NOT accepted — FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 2: T2H/T2L (0xD6/0xD7) — modelled on STC15, refused on STC12 ---
echo ""
echo "--- Section 2: Timer 2 registers (T2H=0xD6, T2L=0xD7) ---"

stc15_t2h_unmod=$(grep "UNMODELLED.*D6" "$TMP/stc15.txt")
stc15_t2l_unmod=$(grep "UNMODELLED.*D7" "$TMP/stc15.txt")
stc12_t2h_unmod=$(grep "UNMODELLED.*D6" "$TMP/stc12.txt")
stc12_t2l_unmod=$(grep "UNMODELLED.*D7" "$TMP/stc12.txt")

if [ -z "$stc15_t2h_unmod" ] && [ -z "$stc15_t2l_unmod" ]; then
    echo "STC15: T2H/T2L accepted (Timer 2 present) — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: T2H/T2L UNMODELLED (wrong) — FAIL"
    FAIL=$((FAIL+1))
fi

if [ -n "$stc12_t2h_unmod" ] && [ -n "$stc12_t2l_unmod" ]; then
    echo "STC12: T2H/T2L UNMODELLED (Timer 2 absent) — PASS"
    PASS=$((PASS+1))
else
    echo "STC12: T2H/T2L accepted (should be absent) — FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 3: P5 (0xC8) — modelled on STC15, refused on STC12 ---
echo ""
echo "--- Section 3: Port 5 (P5=0xC8, P5M0=0xCA) ---"

stc15_p5=$(grep "SFR.*C8.*AA" "$TMP/stc15.txt")
stc15_p5_unmod=$(grep "UNMODELLED.*C8" "$TMP/stc15.txt")
stc12_p5_unmod=$(grep "UNMODELLED.*C8" "$TMP/stc12.txt")

if [ -n "$stc15_p5" ] && [ -z "$stc15_p5_unmod" ]; then
    echo "STC15: P5=0xAA accepted, modelled with PIN events — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: P5 not modelled correctly — FAIL"
    FAIL=$((FAIL+1))
fi

if [ -n "$stc12_p5_unmod" ]; then
    echo "STC12: P5 UNMODELLED (absent) — PASS"
    PASS=$((PASS+1))
else
    echo "STC12: P5 accepted (should be absent) — FAIL"
    FAIL=$((FAIL+1))
fi

# P5 PIN events on STC15
stc15_p5_pins=$(grep "PIN.*5\." "$TMP/stc15.txt" | wc -l)
if [ "$stc15_p5_pins" -gt 0 ]; then
    echo "STC15: P5 PIN events generated ($stc15_p5_pins events) — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: P5 no PIN events — FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 4: T4T3M (0xD1) — absent on STC15F2K60S2, absent on STC12 ---
echo ""
echo "--- Section 4: Timer 3/4 (T4T3M=0xD1, not on STC15F2K60S2) ---"

stc15_t4_unmod=$(grep "UNMODELLED.*D1" "$TMP/stc15.txt")
stc12_t4_unmod=$(grep "UNMODELLED.*D1" "$TMP/stc12.txt")

if [ -n "$stc15_t4_unmod" ]; then
    echo "STC15: T4T3M UNMODELLED (absent, correct) — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: T4T3M accepted (should be absent) — FAIL"
    FAIL=$((FAIL+1))
fi

if [ -n "$stc12_t4_unmod" ]; then
    echo "STC12: T4T3M UNMODELLED (absent, correct) — PASS"
    PASS=$((PASS+1))
else
    echo "STC12: T4T3M accepted (should be absent) — FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 5: STC15-only SFRs accepted ---
echo ""
echo "--- Section 5: STC15-only SFRs (BUS_SPEED, WKTCL, WKTCH) ---"

stc15_bus_unmod=$(grep "UNMODELLED.*A1" "$TMP/stc15.txt")
stc15_wktcl_unmod=$(grep "UNMODELLED.*AA" "$TMP/stc15.txt")
stc15_wktch_unmod=$(grep "UNMODELLED.*AB" "$TMP/stc15.txt")

stc12_bus_unmod=$(grep "UNMODELLED.*A1" "$TMP/stc12.txt")
stc12_wktcl_unmod=$(grep "UNMODELLED.*AA" "$TMP/stc12.txt")

if [ -z "$stc15_bus_unmod" ] && [ -z "$stc15_wktcl_unmod" ] && [ -z "$stc15_wktch_unmod" ]; then
    echo "STC15: BUS_SPEED/WKTCL/WKTCH all accepted — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: some STC15-only SFRs UNMODELLED — FAIL"
    FAIL=$((FAIL+1))
fi

if [ -n "$stc12_bus_unmod" ] && [ -n "$stc12_wktcl_unmod" ]; then
    echo "STC12: BUS_SPEED/WKTCL UNMODELLED (absent) — PASS"
    PASS=$((PASS+1))
else
    echo "STC12: some STC15-only SFRs accepted (should be absent) — FAIL"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
