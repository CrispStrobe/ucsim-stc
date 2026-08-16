#!/bin/bash
# rung_adc_default.sh — ADC reads 0 before any external stimulus.
#
# Silicon truth: STC12C5A60S2 datasheet, SFR table — ADC_RES and ADC_RESL
# reset to 0x00. An undriven analog pin reads 0.
#
# The test fixture enables P1.0 as analog, starts one conversion, and
# signals PASS (P3.0 LOW) if the result is 0, FAIL (P3.0 HIGH) otherwise.
#
# Cross-emulator: runs under both stc12_trace and emu_trace.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/adc_default_test.ihx"
FOSC=11059200

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi
if [ ! -f "$HEX" ]; then
    echo "FAIL: fixture not found at $HEX" >&2; exit 1
fi

PASS=0; FAIL=0

# --- ucsim ---
ucsim_pins=$(timeout 10 "$STC12_TRACE" -t STC12 -fosc $FOSC -until-ns 5000000 "$HEX" 2>/dev/null \
    | awk '$2 == "PIN" && $3 == "3.0"')
ucsim_adc=$(timeout 10 "$STC12_TRACE" -t STC12 -fosc $FOSC -until-ns 5000000 "$HEX" 2>/dev/null \
    | awk '$2 == "ADC" {print $4}' | head -1)

if echo "$ucsim_pins" | grep -q "PP L"; then
    echo "  PASS  ucsim: ADC default = $ucsim_adc, P3.0 = LOW (PASS)"
    PASS=$((PASS+1))
else
    echo "  FAIL  ucsim: ADC default = $ucsim_adc, P3.0 not LOW"
    FAIL=$((FAIL+1))
fi

# --- emu8051 (if available) ---
if [ -x "$EMU_TRACE" ]; then
    emu_pins=$(timeout 10 "$EMU_TRACE" -fosc $FOSC -part stc12 -until-ns 5000000 "$HEX" 2>/dev/null \
        | awk '$2 == "PIN" && $3 == "3.0"')

    # emu8051 emits mode-setup event (PP H) then data write (PP L)
    if echo "$emu_pins" | grep -q "PP L"; then
        echo "  PASS  emu8051: P3.0 = LOW (PASS)"
        PASS=$((PASS+1))
    else
        echo "  FAIL  emu8051: P3.0 not LOW"
        FAIL=$((FAIL+1))
    fi
else
    echo "  SKIP  emu8051: emu_trace not found"
fi

echo ""
echo "=== ADC default value conformance ==="
echo "Pass: $PASS  Fail: $FAIL"
echo "Silicon truth: ADC_RES=0x00, ADC_RESL=0x00 after reset (STC12C5A60S2 datasheet)"

[ $FAIL -eq 0 ] && exit 0 || exit 1
