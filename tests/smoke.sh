#!/bin/bash
# smoke.sh — build the STC12 model and run basic sanity checks.
# Usage: ./tests/smoke.sh [path-to-ucsim_51]
# If no binary is given, builds from source first.
set -e

UCSIM=${1:-ucsim/src/sims/s51.src/ucsim_51}
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -x "$UCSIM" ]; then
    echo "Building ucsim..."
    (cd ucsim && ./configure >/dev/null 2>&1 && make -j$(nproc) >/dev/null 2>&1)
fi

echo "=== STC12 model smoke tests ==="

# 1. Model is listed
echo "[1] Model registration"
$UCSIM -H 2>&1 | grep -q "STC12C5A60S2" && pass "STC12C5A60S2 listed" || fail "STC12C5A60S2 not found in -H"

# 2. Starts without crash
echo "[2] Model starts"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC12 2>&1)
echo "$OUT" | grep -q "STC12C5A60S2" && pass "conf shows STC12C5A60S2" || fail "conf doesn't show STC12C5A60S2"

# 3. Timer 12T mode
echo "[3] Timer 12T mode (AUXR.7=0)"
OUT=$(printf 'set mem sfr 0x89 0x01\nset mem sfr 0x88 0x10\ntick 12\ndump sfr 0x8a 0x8a\nquit\n' | $UCSIM -t STC12 2>&1)
TL0=$(echo "$OUT" | grep "TL0:" | tail -1 | grep -oP '0x\S+' | head -2 | tail -1)
[ "$TL0" = "0x01" ] && pass "12 ticks -> TL0=1" || fail "expected TL0=0x01, got $TL0"

# 4. Timer 1T mode
echo "[4] Timer 1T mode (AUXR.7=1)"
OUT=$(printf 'set mem sfr 0x89 0x01\nset mem sfr 0x88 0x10\nset mem sfr 0x8e 0x80\ntick 12\ndump sfr 0x8a 0x8a\nquit\n' | $UCSIM -t STC12 2>&1)
TL0=$(echo "$OUT" | grep "TL0:" | tail -1 | grep -oP '0x\S+' | head -2 | tail -1)
[ "$TL0" = "0x0c" ] && pass "12 ticks -> TL0=12 (1T)" || fail "expected TL0=0x0c, got $TL0"

# 5. Timer overflow at correct tick count
echo "[5] Timer overflow (FOSC=11059200, 1ms)"
# T0_RELOAD = 65536 - 11059200/12/1000 = 65536 - 921 = 64615 = 0xFC67
# Timer counts 921 times to overflow, at 12T that's 921*12 = 11052 osc clocks
OUT=$(printf 'set mem sfr 0x89 0x01\nset mem sfr 0x88 0x10\nset mem sfr 0x8a 0x67\nset mem sfr 0x8c 0xFC\ntick 11052\ndump sfr 0x88 0x88\nquit\n' | $UCSIM -t STC12 2>&1)
echo "$OUT" | grep "TCON:" | tail -1 | grep -q "0x30" && pass "TF0 set after 11052 ticks" || fail "TF0 not set"

# 6. ADC register sequence
echo "[6] ADC conversion"
OUT=$(printf 'set mem sfr 0x9d 0x08\nset mem sfr 0xbc 0x8b\ntick 500\ndump sfr 0xbc 0xbe\nquit\n' | $UCSIM -t STC12 2>&1)
echo "$OUT" | grep "ADC_CONTR:" | tail -1 | grep -q "0x93" && pass "ADC_FLAG set, channel 3" || fail "ADC_CONTR unexpected"
echo "$OUT" | grep "ADC_RES:" | tail -1 | grep -q "0x80" && pass "ADC_RES=0x80 (mid-scale)" || fail "ADC_RES unexpected"

# 7. PCA prescaler (FOSC/12)
echo "[7] PCA FOSC/12 prescaler"
OUT=$(printf 'set mem sfr 0xd9 0x00\nset mem sfr 0xd8 0x40\ntick 12\ndump sfr 0xe9 0xe9\nquit\n' | $UCSIM -t STC12 2>&1)
CL=$(echo "$OUT" | grep "CL:" | tail -1 | grep -oP '0x\S+' | head -2 | tail -1)
[ "$CL" = "0x01" ] && pass "12 ticks -> CL=1" || fail "expected CL=0x01, got $CL"

# 8. ADC ADRJ=1 (result left-justified per STC12-PERIPHERAL-MODEL.md §4)
echo "[8] ADC ADRJ=1 alignment"
OUT=$(printf 'set mem sfr 0xa2 0x04\nset mem sfr 0x9d 0x08\nset mem sfr 0xbc 0x8b\ntick 500\ndump sfr 0xbd 0xbe\nquit\n' | $UCSIM -t STC12 2>&1)
# Mid-scale 0x200: ADRJ=1 -> ADC_RES=0x02, ADC_RESL=0x00
ADCR=$(echo "$OUT" | grep "ADC_RES:" | tail -1 | grep -oP '0x\S+' | head -2 | tail -1)
[ "$ADCR" = "0x02" ] && pass "ADRJ=1: ADC_RES=0x02 (high 2 bits)" || fail "expected ADC_RES=0x02, got $ADCR"

# 9. SFR names resolve
echo "[9] SFR variable names"
OUT=$(printf 'info var AUXR\ninfo var ADC_CONTR\ninfo var P1M1\ninfo var CCON\nquit\n' | $UCSIM -t STC12 2>&1)
echo "$OUT" | grep -q "sfr\[0x8e\]" && pass "AUXR at 0x8E" || fail "AUXR not found"
echo "$OUT" | grep -q "sfr\[0xbc\]" && pass "ADC_CONTR at 0xBC" || fail "ADC_CONTR not found"

# 10. STC15 model starts
echo "[10] STC15 model starts"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15 2>&1)
echo "$OUT" | grep -q "STC15F2K60S2" && pass "STC15F2K60S2 selectable" || fail "STC15 not found"

# 11. STC15 ADRJ at CLK_DIV.5 (not AUXR1.2)
echo "[11] STC15 ADRJ at CLK_DIV.5"
OUT=$(printf 'set mem sfr 0x97 0x20\nset mem sfr 0x9d 0x08\nset mem sfr 0xbc 0x8b\ntick 500\ndump sfr 0xbd 0xbe\nquit\n' | $UCSIM -t STC15 2>&1)
ADCR=$(echo "$OUT" | grep "ADC_RES:" | tail -1 | grep -oP '0x\S+' | head -2 | tail -1)
[ "$ADCR" = "0x02" ] && pass "STC15 ADRJ via CLK_DIV.5" || fail "expected ADC_RES=0x02, got $ADCR"

# 12. STC15 Timer 2 counts at 12T
echo "[12] STC15 Timer 2 at 12T"
OUT=$(printf 'set mem sfr 0x8e 0x10\nset mem sfr 0xd7 0x00\nset mem sfr 0xd6 0x00\ntick 24\ndump sfr 0xd6 0xd7\nquit\n' | $UCSIM -t STC15 2>&1)
T2L=$(echo "$OUT" | grep "T2L:" | tail -1 | grep -oP '0x\S+' | head -2 | tail -1)
[ "$T2L" = "0x02" ] && pass "24 ticks -> T2L=2 (12T)" || fail "expected T2L=0x02, got $T2L"

# 13. STC15 has Timer 2 hw element
echo "[13] STC15 Timer 2 registered"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15 2>&1)
echo "$OUT" | grep -q "stc15_timer2" && pass "STC15 has timer2 hw" || fail "timer2 not found"

# 14. STC12 does NOT have Timer 2
echo "[14] STC12 no Timer 2"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC12 2>&1)
echo "$OUT" | grep -q "stc15_timer2" && fail "STC12 should not have timer2" || pass "STC12 correctly lacks timer2"

# 15. STC89 model starts
echo "[15] STC89 model starts"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC89 2>&1)
echo "$OUT" | grep -q "STC89C52RC" && pass "STC89C52RC selectable" || fail "STC89 not found"

# 16. STC89 has Timer 2 (standard 8052 T2CON at 0xC8)
echo "[16] STC89 has Timer 2"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC89 2>&1)
echo "$OUT" | grep -q "timer2" && pass "STC89 has timer2 (standard 8052)" || fail "STC89 missing timer2"

# 17. STC89 timer runs at 12T (no 1T option — no AUXR)
echo "[17] STC89 timer 12T only"
# Standard 8052 timer: counts once per machine cycle.
# On a 12T core, 1 tick = 1 machine cycle = 1 timer increment.
# (The 12T factor is in time-per-cycle, not in the count rate.)
OUT=$(printf 'set mem sfr 0x89 0x01\nset mem sfr 0x88 0x10\ntick 1\ndump sfr 0x8a 0x8a\nquit\n' | $UCSIM -t STC89 2>&1)
TL0=$(echo "$OUT" | grep "TL0:" | tail -1 | grep -oP '0x\S+' | head -2 | tail -1)
[ "$TL0" = "0x01" ] && pass "STC89 12T: 1 tick -> TL0=1" || fail "expected TL0=0x01, got $TL0"

# 18. STC89 no port modes (no PxM0/PxM1 hw)
echo "[18] STC89 no port modes"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC89 2>&1)
echo "$OUT" | grep -q "stc12_port" && fail "STC89 should not have port mode hw" || pass "STC89 correctly lacks port mode hw"

# 19. STC89 no ADC
echo "[19] STC89 no ADC"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC89 2>&1)
echo "$OUT" | grep -q "stc12_adc" && fail "STC89 should not have ADC" || pass "STC89 correctly lacks ADC"

# 20. STC89 no PCA
echo "[20] STC89 no PCA"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC89 2>&1)
echo "$OUT" | grep -q "stc12_pca" && fail "STC89 should not have PCA" || pass "STC89 correctly lacks PCA"

# 21. STC15W model starts
echo "[21] STC15W model starts"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15W 2>&1)
echo "$OUT" | grep -q "STC15W408AS" && pass "STC15W408AS selectable" || fail "STC15W not found"

# 22. STC15W has Timer 2
echo "[22] STC15W has Timer 2"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15W 2>&1)
echo "$OUT" | grep -q "stc15_timer2" && pass "STC15W has timer2" || fail "STC15W missing timer2"

# 23. STC15W has port modes (for P0-P3)
echo "[23] STC15W has port modes"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15W 2>&1)
echo "$OUT" | grep -q "stc12_port" && pass "STC15W has port mode hw" || fail "STC15W missing port mode hw"

# 24. STC15W has ADC
echo "[24] STC15W has ADC"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15W 2>&1)
echo "$OUT" | grep -q "stc12_adc" && pass "STC15W has ADC" || fail "STC15W missing ADC"

# 25. STC15W has PCA (3 modules)
echo "[25] STC15W has PCA"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15W 2>&1)
echo "$OUT" | grep -q "pca\[" && pass "STC15W has PCA" || fail "STC15W missing PCA"

# 26. STC15W no Timer 1 hw
echo "[26] STC15W no Timer 1"
OUT=$(printf 'conf\nquit\n' | $UCSIM -t STC15W 2>&1)
echo "$OUT" | grep -q "timer1" && fail "STC15W should not have timer1" || pass "STC15W correctly lacks timer1"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
