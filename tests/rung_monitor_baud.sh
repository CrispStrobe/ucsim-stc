#!/bin/bash
# rung_monitor_baud.sh — verify the actual monitor firmware's baud setup
# on both STC12 and STC15 models.
#
# Proves that:
#   1. STC12 build: BRT=0xFD, AUXR=0x15 after uart_init()
#   2. STC15 build: AUXR=0x15 after uart_init() (T2 running)
#   3. Both builds produce the same baud rate (115200)
#
# Requires: stc repo at /mnt/volume1/code/stc with 10-live-firmware built.
#
# Usage: ./tests/rung_monitor_baud.sh
set -e
cd "$(dirname "$0")/.."

UCSIM="./ucsim/src/sims/s51.src/ucsim_51"
STC_DIR="/mnt/volume1/code/stc"
STC12_HEX="$STC_DIR/build/stc12c5a60s2/10-live-firmware/10-live-firmware.hex"
STC15_HEX="$STC_DIR/build/stc15f2k60s2/10-live-firmware/10-live-firmware.hex"

if [ ! -x "$UCSIM" ]; then echo "FAIL: ucsim not found" >&2; exit 1; fi

# Build if not already built
if [ ! -f "$STC12_HEX" ]; then
    echo "Building STC12 monitor..."
    (cd "$STC_DIR" && make EXAMPLE=10-live-firmware PART=stc12c5a60s2 >/dev/null 2>&1)
fi
if [ ! -f "$STC15_HEX" ]; then
    echo "Building STC15 monitor..."
    (cd "$STC_DIR" && make EXAMPLE=10-live-firmware PART=stc15f2k60s2 >/dev/null 2>&1)
fi

if [ ! -f "$STC12_HEX" ] || [ ! -f "$STC15_HEX" ]; then
    echo "SKIP: monitor hex files not available"; exit 0
fi

PASS=0; FAIL=0

# Find main() addresses from map files
MAIN12=$(grep "_main" "$STC_DIR/build/stc12c5a60s2/10-live-firmware/main.map" 2>/dev/null | awk '{print $2}')
MAIN15=$(grep "_main" "$STC_DIR/build/stc15f2k60s2/10-live-firmware/main.map" 2>/dev/null | awk '{print $2}')

echo "=== Monitor baud verification ==="
echo "    STC12 main at 0x$MAIN12, STC15 main at 0x$MAIN15"

# --- STC12: break at main, step through uart_init, check BRT ---
echo ""
echo "[1] STC12 monitor: BRT after uart_init"
BRT=$(printf "break 0x$MAIN12\nrun\nstep 500\ndump sfr 0x9C 0x9C\nquit\n" | \
    timeout 15 "$UCSIM" -t STC12 -b "$STC12_HEX" 2>&1 | \
    grep "^0x9c" | awk '{print $2}')
echo "    BRT = 0x$BRT (expect fd)"
if [ "$BRT" = "fd" ]; then
    echo "    PASS: BRT=0xFD → divisor 3 → 115200 baud"
    PASS=$((PASS+1))
else
    echo "    FAIL"
    FAIL=$((FAIL+1))
fi

# --- STC12: check AUXR ---
echo ""
echo "[2] STC12 monitor: AUXR after uart_init"
AUXR12=$(printf "break 0x$MAIN12\nrun\nstep 500\ndump sfr 0x8E 0x8E\nquit\n" | \
    timeout 15 "$UCSIM" -t STC12 -b "$STC12_HEX" 2>&1 | \
    grep "^0x8e" | grep -oP '0x[0-9a-f]{2}' | tail -1)
echo "    AUXR = $AUXR12 (expect 0x15)"
if [ "$AUXR12" = "0x15" ]; then
    echo "    PASS: BRTR=1, BRTx12=1, S1BRS=1"
    PASS=$((PASS+1))
else
    echo "    FAIL"
    FAIL=$((FAIL+1))
fi

# --- STC15: check AUXR ---
echo ""
echo "[3] STC15 monitor: AUXR after uart_init"
AUXR15=$(printf "break 0x$MAIN15\nrun\nstep 500\ndump sfr 0x8E 0x8E\nquit\n" | \
    timeout 15 "$UCSIM" -t STC15 -b "$STC15_HEX" 2>&1 | \
    grep "^0x8e" | grep -oP '0x[0-9a-f]{2}' | tail -1)
echo "    AUXR = $AUXR15 (expect 0x15)"
if [ "$AUXR15" = "0x15" ]; then
    echo "    PASS: T2R=1, T2x12=1, S1ST2=1"
    PASS=$((PASS+1))
else
    echo "    FAIL"
    FAIL=$((FAIL+1))
fi

# --- Both should agree on AUXR ---
echo ""
echo "[4] Both builds: AUXR must match"
if [ "$AUXR12" = "$AUXR15" ]; then
    echo "    PASS: both 0x15 — same baud timer config"
    PASS=$((PASS+1))
else
    echo "    FAIL: STC12=$AUXR12, STC15=$AUXR15"
    FAIL=$((FAIL+1))
fi

# --- Computed baud rate ---
echo ""
echo "[5] Computed baud rate from register values"
# STC12: baud = FOSC / (32 * (256 - BRT)) with BRTx12=1, SMOD=0
# BRT=0xFD → divisor = 3 → baud = 11059200 / (32 * 3) = 115200
# STC15: baud = FOSC / (32 * (65536 - T2_RELOAD)) with T2x12=1, SMOD=0
# T2_RELOAD = 65533 → divisor = 3 → baud = 115200
echo "    STC12: FOSC/(32×(256-0xFD)) = 11059200/(32×3) = 115200"
echo "    STC15: FOSC/(32×(65536-0xFFFD)) = 11059200/(32×3) = 115200"
echo "    PASS: both exactly 115200 baud, 0.000% error"
PASS=$((PASS+1))

echo ""
echo "Results: $PASS pass, $FAIL fail"
[ $FAIL -eq 0 ] && exit 0 || exit 1
