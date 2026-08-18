#!/bin/bash
# rung_ledbank8_golden.sh — per-tick LEDBANK8 golden trace.
#
# For the fixture ledbank8_pattern (shadow=0xA5, active-low on P1), asserts:
#   - P1 = ~0xA5 = 0x5A on the first tick (active-low inversion)
#   - P1 remains stable across all subsequent ticks (no spurious changes)
#   - P2 is NOT written by LEDBANK8 (stays at reset default 0xFF)
#
# Reuses the same harness structure as MATRIX8X8 / SEVENSEG8.
#
# Usage: ./tests/rung_ledbank8_golden.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/ledbank8_pattern.ihx"
FOSC=11059200
UNTIL_NS=18000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Shadow = 0xA5, active-low → P1 = ~0xA5 = 0x5A
GOLDEN_P1="5A"

PASS=0; FAIL=0

echo "=== LEDBANK8 Per-Tick Golden Trace (shadow=0xA5, active-low, STC89) ==="
echo ""

# Run both emulators — capture P1 (SFR 0x90) writes and TF events
timeout 10 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    > "$TMP/emu_full.txt"
timeout 10 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    > "$TMP/ucsim_full.txt"

# --- Section 1: P1 value on first tick ---
echo "--- Section 1: P1 on first tick (shadow → port) ---"

emu_p1=$(awk '$2 == "SFR" && $3 == "90" { print $4; exit }' "$TMP/emu_full.txt" \
    | tr '[:lower:]' '[:upper:]')
ucs_p1=$(awk '$2 == "SFR" && $3 == "90" { print $4; exit }' "$TMP/ucsim_full.txt" \
    | tr '[:lower:]' '[:upper:]')
GOLDEN_P1_UP=$(echo "$GOLDEN_P1" | tr '[:lower:]' '[:upper:]')

printf "%-12s %-10s %-10s %-10s %-6s\n" "Shadow" "golden" "emu-P1" "ucs-P1" "Match"
if [ "$emu_p1" = "$GOLDEN_P1_UP" ] && [ "$ucs_p1" = "$GOLDEN_P1_UP" ]; then
    printf "%-12s %-10s %-10s %-10s %-6s\n" "0xA5→~5A" "0x$GOLDEN_P1_UP" "0x$emu_p1" "0x$ucs_p1" "PASS"
    PASS=$((PASS+1))
else
    printf "%-12s %-10s %-10s %-10s %-6s\n" "0xA5→~5A" "0x$GOLDEN_P1_UP" "0x$emu_p1" "0x$ucs_p1" "FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 2: P1 stability (no spurious changes after first write) ---
echo ""
echo "--- Section 2: P1 stability (all writes must be 0x$GOLDEN_P1_UP) ---"

emu_p1_writes=$(awk '$2 == "SFR" && $3 == "90" { print $4 }' "$TMP/emu_full.txt" \
    | tr '[:lower:]' '[:upper:]' | sort -u)
ucs_p1_writes=$(awk '$2 == "SFR" && $3 == "90" { print $4 }' "$TMP/ucsim_full.txt" \
    | tr '[:lower:]' '[:upper:]' | sort -u)

emu_p1_count=$(awk '$2 == "SFR" && $3 == "90" { n++ } END { print n+0 }' "$TMP/emu_full.txt")
ucs_p1_count=$(awk '$2 == "SFR" && $3 == "90" { n++ } END { print n+0 }' "$TMP/ucsim_full.txt")

# The trace is differential — P1 is written every tick by the ISR, but since
# the value never changes (shadow is constant), only the FIRST write appears.
# Verify: exactly 1 unique value, and it's 0x5A.
if [ "$emu_p1_writes" = "$GOLDEN_P1_UP" ]; then
    echo "emu: P1 stable ($emu_p1_count write(s), all 0x$GOLDEN_P1_UP) — PASS"
    PASS=$((PASS+1))
else
    echo "emu: P1 unstable (values: $emu_p1_writes) — FAIL"
    FAIL=$((FAIL+1))
fi

if [ "$ucs_p1_writes" = "$GOLDEN_P1_UP" ]; then
    echo "ucsim: P1 stable ($ucs_p1_count write(s), all 0x$GOLDEN_P1_UP) — PASS"
    PASS=$((PASS+1))
else
    echo "ucsim: P1 unstable (values: $ucs_p1_writes) — FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 3: P2 untouched (shared-P2 interaction) ---
echo ""
echo "--- Section 3: Shared-P2 interaction (P2 must NOT be written by LEDBANK8) ---"

emu_p2_writes=$(awk '$2 == "SFR" && $3 == "A0"' "$TMP/emu_full.txt" | wc -l)
ucs_p2_writes=$(awk '$2 == "SFR" && $3 == "A0"' "$TMP/ucsim_full.txt" | wc -l)

if [ "$emu_p2_writes" -eq 0 ]; then
    echo "emu: P2 untouched (0 writes) — PASS"
    PASS=$((PASS+1))
else
    echo "emu: P2 written $emu_p2_writes time(s) — FAIL"
    awk '$2 == "SFR" && $3 == "A0"' "$TMP/emu_full.txt" | head -5
    FAIL=$((FAIL+1))
fi

if [ "$ucs_p2_writes" -eq 0 ]; then
    echo "ucsim: P2 untouched (0 writes) — PASS"
    PASS=$((PASS+1))
else
    echo "ucsim: P2 written $ucs_p2_writes time(s) — FAIL"
    awk '$2 == "SFR" && $3 == "A0"' "$TMP/ucsim_full.txt" | head -5
    FAIL=$((FAIL+1))
fi

# --- Section 4: Cross-emulator P1 PIN events ---
echo ""
echo "--- Section 4: Cross-emulator P1 PIN events ---"
awk '$2 == "PIN" && $3 ~ /^1\./' "$TMP/emu_full.txt" | cut -f2- > "$TMP/emu_p1.pin"
awk '$2 == "PIN" && $3 ~ /^1\./' "$TMP/ucsim_full.txt" | cut -f2- > "$TMP/ucsim_p1.pin"

emu_pin_count=$(wc -l < "$TMP/emu_p1.pin")
ucs_pin_count=$(wc -l < "$TMP/ucsim_p1.pin")

if diff "$TMP/emu_p1.pin" "$TMP/ucsim_p1.pin" > /dev/null 2>&1; then
    echo "P1 PINs: EXACT match ($emu_pin_count events)"
    PASS=$((PASS+1))
else
    echo "P1 PINs: DIVERGENCE (emu=$emu_pin_count ucsim=$ucs_pin_count)"
    diff "$TMP/emu_p1.pin" "$TMP/ucsim_p1.pin" | head -10
    FAIL=$((FAIL+1))
fi

# --- Section 5: TF tick count cross-emu ---
echo ""
echo "--- Section 5: Timer tick count cross-emu ---"
emu_tf=$(awk '$2 == "TF" { n++ } END { print n+0 }' "$TMP/emu_full.txt")
ucs_tf=$(awk '$2 == "TF" { n++ } END { print n+0 }' "$TMP/ucsim_full.txt")

if [ "$emu_tf" -ge 16 ] && [ "$ucs_tf" -ge 16 ]; then
    echo "Tick counts: emu=$emu_tf ucsim=$ucs_tf (both >= 16) — PASS"
    PASS=$((PASS+1))
else
    echo "Tick counts: emu=$emu_tf ucsim=$ucs_tf — FAIL (expected >= 16)"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
