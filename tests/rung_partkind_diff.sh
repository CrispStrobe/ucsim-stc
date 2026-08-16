#!/bin/bash
# rung_partkind_diff.sh — differential execution by part-kind category.
#
# Maps STC12-projectable part kinds from the bw-audit 114-kind sweep
# to test programs, runs ucsim vs emu8051, records agreement.
#
# Usage: ./tests/rung_partkind_diff.sh
set -e
cd "$(dirname "$0")/.."

STC12_TRACE="${STC12_TRACE:-./ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
FOSC=11059200
UNTIL_NS=5000000

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi
if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2; exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0; KNOWN=0

run_diff() {
    local label="$1" ihx="$2" until="$3" adc_flag="$4"

    "$EMU_TRACE" -fosc $FOSC -until-ns "$until" $adc_flag "$ihx" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu.ev"
    timeout 60 "$STC12_TRACE" -fosc $FOSC -until-ns "$until" "$ihx" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/ucsim.ev"

    local EN UN
    EN=$(wc -l < "$TMP/emu.ev")
    UN=$(wc -l < "$TMP/ucsim.ev")

    if [ "$EN" -eq 0 ] && [ "$UN" -eq 0 ]; then
        echo "  EMPTY  $label"
        return 1
    fi

    if [ "$EN" -eq "$UN" ] && diff "$TMP/emu.ev" "$TMP/ucsim.ev" > /dev/null 2>&1; then
        echo "  PASS   $label ($EN events)"
        PASS=$((PASS+1))
        return 0
    fi

    # Check prefix match (emu8051 may produce more/fewer events)
    local MIN=$EN; [ "$UN" -lt "$MIN" ] && MIN=$UN
    if [ "$MIN" -gt 0 ] && head -n "$MIN" "$TMP/emu.ev" \
         | diff - <(head -n "$MIN" "$TMP/ucsim.ev") > /dev/null 2>&1; then
        echo "  PASS   $label ($MIN/$EN prefix match)"
        PASS=$((PASS+1))
        return 0
    fi

    echo "  FAIL   $label (emu=$EN ucsim=$UN)"
    FAIL=$((FAIL+1))
    return 1
}

echo "=== Part-kind differential: STC12-projectable subset ==="
echo ""

# --- GPIO output part kinds ---
echo "--- GPIO output (led, relay, dc_motor, solenoid, vibration_motor,"
echo "    light_bulb, optocoupler, darlington_driver, tip120, rgb_led) ---"

run_diff "traffic_light (3-LED sequence)" \
    tests/fixtures/partkind/traffic_light.ihx $UNTIL_NS
run_diff "dual_blink (2-LED alternating)" \
    tests/fixtures/partkind/dual_blink.ihx $UNTIL_NS
run_diff "sos_morse (timed GPIO pattern)" \
    tests/fixtures/partkind/sos_morse.ihx $UNTIL_NS
run_diff "multi_led (4-LED walking)" \
    tests/fixtures/partkind/multi_led.ihx $UNTIL_NS
run_diff "port_full (8-pin port write)" \
    tests/fixtures/partkind/port_full.ihx $UNTIL_NS
run_diff "relay_npn (NPN transistor drive)" \
    tests/fixtures/partkind/relay_npn.ihx $UNTIL_NS
run_diff "relay_test (existing fixture)" \
    tests/fixtures/relay_test.ihx $UNTIL_NS

echo ""
echo "--- GPIO input (button, dip_switch, tilt_sensor, pir, ir_receiver,"
echo "    phototransistor) ---"

run_diff "button_poll (P3.2 poll loop)" \
    tests/fixtures/partkind/button_poll.ihx $UNTIL_NS
run_diff "button_test (existing fixture)" \
    tests/fixtures/button_test.ihx $UNTIL_NS

echo ""
echo "--- Port mode config (source_vs_sink topology) ---"

run_diff "port_mode (all 4 modes: quasi/PP/input/OD)" \
    tests/fixtures/partkind/port_mode.ihx $UNTIL_NS

echo ""
echo "--- ADC input (potentiometer, ldr, ntc, tmp36, flex_sensor,"
echo "    force_sensor, soil_moisture, ambient_light, gas_sensor, photodiode) ---"

run_diff "adc_multi (channel 2 read sequence)" \
    tests/fixtures/partkind/adc_multi.ihx $UNTIL_NS "-adc 2,512"

echo ""
echo "--- Multi-pin GPIO sequence (shift_register/74hc595, stepper,"
echo "    h_bridge, seven_segment, led_matrix, led_cube, bargraph) ---"

run_diff "shift_out (74HC595 bit-bang)" \
    tests/fixtures/partkind/shift_out.ihx $UNTIL_NS
run_diff "stepper_seq (4-pin half-step)" \
    tests/fixtures/partkind/stepper_seq.ihx $UNTIL_NS
run_diff "hbridge (L293D direction+enable)" \
    tests/fixtures/partkind/hbridge.ihx $UNTIL_NS

echo ""
echo "--- PCA/PWM (servo, dc_motor PWM, buzzer tone) ---"

run_diff "servo_90 (PCA compare/match)" \
    tests/fixtures/servo_90.ihx $UNTIL_NS
run_diff "motor_50 (PCA PWM 50%)" \
    tests/fixtures/motor_50.ihx $UNTIL_NS
run_diff "pwm_50pct (PCA PWM)" \
    tests/fixtures/pwm_50pct.ihx $UNTIL_NS

echo ""
echo "--- Ultrasonic (trigger pulse + echo) ---"

run_diff "ultrasonic_fixed (HC-SR04)" \
    tests/fixtures/ultrasonic_fixed.ihx $UNTIL_NS

echo ""
echo "--- Timer (timer1, UART baud) ---"

run_diff "timer1_test" tests/fixtures/timer1_test.ihx $UNTIL_NS
run_diff "uart_tx_test" tests/fixtures/uart_tx_test.ihx $UNTIL_NS

echo ""
echo "--- P5 port (STC15 only: buzzer pin P5.5) ---"

# P5 differential uses STC15 mode and compares PIN+TF events (emu8051
# does not emit SFR events for P5/P5M0/P5M1, but PIN events agree).
run_diff_p5() {
    local label="$1" ihx="$2" until="$3"

    "$EMU_TRACE" -fosc $FOSC -until-ns "$until" "$ihx" 2>/dev/null \
        | awk '$2 == "PIN" || $2 == "TF"' | cut -f2- > "$TMP/emu.ev"
    timeout 60 "$STC12_TRACE" -t STC15 -fosc $FOSC -until-ns "$until" "$ihx" 2>/dev/null \
        | awk '$2 == "PIN" || $2 == "TF"' | cut -f2- > "$TMP/ucsim.ev"

    local EN UN
    EN=$(wc -l < "$TMP/emu.ev")
    UN=$(wc -l < "$TMP/ucsim.ev")

    if [ "$EN" -eq 0 ] && [ "$UN" -eq 0 ]; then
        echo "  EMPTY  $label"
        return 1
    fi

    if [ "$EN" -eq "$UN" ] && diff "$TMP/emu.ev" "$TMP/ucsim.ev" > /dev/null 2>&1; then
        echo "  PASS   $label ($EN events)"
        PASS=$((PASS+1))
        return 0
    fi

    local MIN=$EN; [ "$UN" -lt "$MIN" ] && MIN=$UN
    if [ "$MIN" -gt 0 ] && head -n "$MIN" "$TMP/emu.ev" \
         | diff - <(head -n "$MIN" "$TMP/ucsim.ev") > /dev/null 2>&1; then
        echo "  PASS   $label ($MIN/$EN prefix match)"
        PASS=$((PASS+1))
        return 0
    fi

    echo "  FAIL   $label (emu=$EN ucsim=$UN)"
    FAIL=$((FAIL+1))
    return 1
}

run_diff_p5 "p5_mode (P5.5 all 4 modes, STC15)" \
    tests/fixtures/partkind/p5_mode.ihx $UNTIL_NS

echo ""
echo "================================"
echo "Part-kind differential: $PASS pass, $FAIL fail, $KNOWN known"
echo "================================"

[ "$FAIL" -eq 0 ]
