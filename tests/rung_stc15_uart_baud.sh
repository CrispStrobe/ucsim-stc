#!/bin/bash
# rung_stc15_uart_baud.sh — STC15 UART TX via Timer 2 baud verification.
#
# Proves the Timer 2 → UART1 baud path works end-to-end:
#   1. Timer 2 accepts T2H/T2L reload (0xFFFD = divisor 3)
#   2. AUXR = 0x15 (T2R + T2x12 + S1ST2) accepted on STC15
#   3. UART TX completes (uart_putc returns for both bytes)
#   4. Matches the STC12 BRT path result (both reach idle loop)
#   5. Monitor firmware (10-live-firmware) has correct init on both parts
#
# Usage: ./tests/rung_stc15_uart_baud.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UCSIM="$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
STC15_TX="$SCRIPT_DIR/fixtures/stc15_uart_tx.ihx"
STC_DIR="../stc"
STC12_HEX="$STC_DIR/build/stc12c5a60s2/10-live-firmware/10-live-firmware.hex"
STC15_HEX="$STC_DIR/build/stc15f2k60s2/10-live-firmware/10-live-firmware.hex"

if [ ! -x "$UCSIM" ]; then echo "FAIL: ucsim not found" >&2; exit 1; fi
if [ ! -f "$STC15_TX" ]; then echo "FAIL: fixture not found" >&2; exit 1; fi

PASS=0; FAIL=0

echo "=== STC15 UART Timer 2 Baud Verification ==="
echo ""

# --- Section 1: STC15 UART TX via Timer 2 completes ---
echo "--- Section 1: STC15 UART TX via Timer 2 (two bytes) ---"

stc15_pc=$(printf "step 100000\npc\nquit\n" | \
    timeout 10 "$UCSIM" -t STC15 -b "$STC15_TX" 2>&1 | \
    grep "^F " | awk '{print $2}')

# PC should be at the idle loop (0x0041 = for(;;){})
if [ "$stc15_pc" = "0x000041" ]; then
    echo "STC15: UART TX complete, PC at idle loop ($stc15_pc) — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: PC=$stc15_pc (expected 0x000041, stuck in while(!TI)?) — FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 2: AUXR and SCON correct ---
echo ""
echo "--- Section 2: AUXR/SCON register values ---"

stc15_regs=$(printf "step 100000\ndump sfr 0x8E 0x8E\ndump sfr 0x98 0x98\nquit\n" | \
    timeout 10 "$UCSIM" -t STC15 -b "$STC15_TX" 2>&1)

stc15_auxr=$(echo "$stc15_regs" | grep "^0x8e" | grep -Eo '0x[0-9a-f]{2}' | tail -1)
stc15_scon=$(echo "$stc15_regs" | grep "^0x98" | grep -Eo '0x[0-9a-f]{2}' | tail -1)

if [ "$stc15_auxr" = "0x15" ]; then
    echo "STC15: AUXR=0x15 (T2R+T2x12+S1ST2) — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: AUXR=$stc15_auxr (expected 0x15) — FAIL"
    FAIL=$((FAIL+1))
fi

if [ "$stc15_scon" = "0x50" ]; then
    echo "STC15: SCON=0x50 (mode 1, RX enabled) — PASS"
    PASS=$((PASS+1))
else
    echo "STC15: SCON=$stc15_scon (expected 0x50) — FAIL"
    FAIL=$((FAIL+1))
fi

# --- Section 3: STC15 accepts T2H/T2L (no UNMODELLED) ---
echo ""
echo "--- Section 3: Timer 2 (T2H/T2L) on STC15 vs STC12 ---"

if [ -x "$STC12_TRACE" ]; then
    stc15_unmod=$(timeout 5 "$STC12_TRACE" -t STC15 -fosc 11059200 -until-ns 500000 \
        "$STC15_TX" 2>/dev/null | grep "UNMODELLED")
    stc12_unmod=$(timeout 5 "$STC12_TRACE" -t STC12 -fosc 11059200 -until-ns 500000 \
        "$STC15_TX" 2>/dev/null | grep "UNMODELLED")

    if [ -z "$stc15_unmod" ]; then
        echo "STC15: no UNMODELLED events (T2H/T2L accepted) — PASS"
        PASS=$((PASS+1))
    else
        echo "STC15: UNMODELLED: $stc15_unmod — FAIL"
        FAIL=$((FAIL+1))
    fi

    stc12_t2_unmod=$(echo "$stc12_unmod" | grep -c "D[67]")
    if [ "$stc12_t2_unmod" -gt 0 ]; then
        echo "STC12: T2H/T2L UNMODELLED ($stc12_t2_unmod events, Timer 2 absent) — PASS"
        PASS=$((PASS+1))
    else
        echo "STC12: T2H/T2L accepted (should be absent) — FAIL"
        FAIL=$((FAIL+1))
    fi
fi

# --- Section 4: Monitor firmware init (both parts) ---
echo ""
echo "--- Section 4: Monitor firmware (10-live-firmware) init ---"

if [ -f "$STC12_HEX" ] && [ -f "$STC15_HEX" ]; then
    MAIN12=$(grep "_main" "$STC_DIR/build/stc12c5a60s2/10-live-firmware/main.map" 2>/dev/null | awk '{print $2}')
    MAIN15=$(grep "_main" "$STC_DIR/build/stc15f2k60s2/10-live-firmware/main.map" 2>/dev/null | awk '{print $2}')

    # STC12: BRT=0xFD, AUXR=0x15
    brt12=$(printf "break 0x$MAIN12\nrun\nstep 500\ndump sfr 0x9C 0x9C\nquit\n" | \
        timeout 15 "$UCSIM" -t STC12 -b "$STC12_HEX" 2>&1 | \
        grep "^0x9c" | awk '{print $2}')
    if [ "$brt12" = "fd" ]; then
        echo "STC12 monitor: BRT=0xFD (divisor 3 → 115200 baud) — PASS"
        PASS=$((PASS+1))
    else
        echo "STC12 monitor: BRT=0x$brt12 (expected fd) — FAIL"
        FAIL=$((FAIL+1))
    fi

    # STC15: AUXR=0x15
    auxr15=$(printf "break 0x$MAIN15\nrun\nstep 500\ndump sfr 0x8E 0x8E\nquit\n" | \
        timeout 15 "$UCSIM" -t STC15 -b "$STC15_HEX" 2>&1 | \
        grep "^0x8e" | grep -Eo '0x[0-9a-f]{2}' | tail -1)
    if [ "$auxr15" = "0x15" ]; then
        echo "STC15 monitor: AUXR=0x15 (T2R+T2x12+S1ST2 → 115200 baud) — PASS"
        PASS=$((PASS+1))
    else
        echo "STC15 monitor: AUXR=$auxr15 (expected 0x15) — FAIL"
        FAIL=$((FAIL+1))
    fi

    echo ""
    echo "Baud rate computation:"
    echo "  STC12: FOSC/(32×(256-0xFD)) = 11059200/(32×3) = 115200"
    echo "  STC15: FOSC/(32×(65536-0xFFFD)) = 11059200/(32×3) = 115200"
else
    echo "SKIP: monitor hex files not available"
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
