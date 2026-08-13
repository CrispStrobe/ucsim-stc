#!/bin/bash
# run_all.sh — run every test suite and report a combined result.
# Usage: ./tests/run_all.sh
set -e
cd "$(dirname "$0")/.."

TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0
SUITES_PASS=0; SUITES_FAIL=0

run_suite() {
    local name="$1"
    local script="$2"
    echo ""
    echo "=============== $name ==============="
    if "$script" 2>&1; then
        SUITES_PASS=$((SUITES_PASS+1))
    else
        SUITES_FAIL=$((SUITES_FAIL+1))
    fi
}

run_suite "Smoke tests" ./tests/smoke.sh
run_suite "Timing verification" ./tests/rung_timing.sh
run_suite "Multi-part differential" ./tests/multipart_diff.sh
run_suite "Cross-part examples" ./tests/crosspart_examples.sh
run_suite "Model difference (STC12 vs STC89)" ./tests/rung_model_diff.sh
run_suite "Baud divergence (BRT vs T2)" ./tests/rung_baud.sh
run_suite "NeoPixel WS2812 spec windows" ./tests/rung_neopixel.sh
run_suite "LCD I2C protocol edges" ./tests/rung_lcd_i2c.sh
run_suite "AVR blink cycle counts" ./tests/rung_avr_blink.sh

# Cross-emulator tests (require emu_trace)
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
if [ -x "$EMU_TRACE" ]; then
    run_suite "Example differentials" ./tests/examples_diff.sh
    EMU_TRACE="$EMU_TRACE" run_suite "Boundary D ladder" ./tests/run_control_diff.sh
else
    echo ""
    echo "=============== Cross-emulator tests ==============="
    echo "SKIP: emu_trace not found at $EMU_TRACE"
fi

# simavr tests (require libsimavr harness)
if [ -x tests/simavr_harness ]; then
    run_suite "AVR oracle (simavr vs avr8js)" ./tests/rung_avr_oracle.sh
    run_suite "Simavr canonical-trace differential" ./tests/rung_simavr_canonical.sh
else
    echo ""
    echo "=============== AVR oracle ==============="
    echo "SKIP: simavr_harness not found (build with 'make -C tests simavr_harness')"
fi

# NeoPixel cross-emu (require both emu_trace and stc12_trace)
if [ -x "$EMU_TRACE" ]; then
    run_suite "NeoPixel cross-emu (cat 1)" ./tests/rung_neopixel_cross.sh
fi

echo ""
echo "========================================="
echo "Suites: $SUITES_PASS passed, $SUITES_FAIL failed"
[ $SUITES_FAIL -eq 0 ] && exit 0 || exit 1
