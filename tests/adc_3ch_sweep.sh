#!/bin/bash
# adc_3ch_sweep.sh — sweep all 3 multimeter ADC channels across both emulators.
#
# For each voltage combination, runs the 3-channel ADC test fixture on both
# emulators and compares the 10-bit results per channel. Also computes the
# firmware's expected millivolt/cand values.
#
# Usage: ./tests/adc_3ch_sweep.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/adc_3ch_oracle.ihx"
FOSC=11059200

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

PASS=0; FAIL=0

# Voltage points for each channel:
# ch0 (volts): pin sees Vin/4 through 30k/10k divider
# ch1 (amps): LM358 shunt amp output, ~0-500mV range
# ch2 (NTC): thermistor divider, ~0.4-4.5V range

echo "=== 3-Channel ADC Analog Oracle (STC15) ==="
echo ""

# --- Sweep ch0 (voltage divider) ---
echo "--- Channel 0: Voltage divider (Vin/4) ---"
printf "%-8s %6s %8s %8s %8s %8s %-6s\n" "Vin" "count" "emu-ch0" "ucs-ch0" "mv" "cand" "Match"
printf "%-8s %6s %8s %8s %8s %8s %-6s\n" "----" "-----" "-------" "-------" "----" "----" "-----"

for entry in "0V:0" "1V:51" "2V:102" "4V:205" "6V:307" "8V:409" "10V:512" "13.2V:675" "16V:818" "20V:1023"; do
    label="${entry%%:*}"
    ch0="${entry##*:}"
    emu_adc=$(timeout 10 "$EMU_TRACE" -fosc $FOSC -part stc15 -adc 0,$ch0 -adc 1,0 -adc 2,0 \
        -until-ns 5000000 "$HEX" 2>/dev/null | awk '$2=="ADC" && $3=="0" {print $4; exit}')
    ucs_adc=$(timeout 10 "$STC12_TRACE" -t STC15 -fosc $FOSC -adc 0,$ch0 -adc 1,0 -adc 2,0 \
        -until-ns 5000000 "$HEX" 2>/dev/null | awk '$2=="ADC" && $3=="0" {print $4; exit}')
    mv=$((ch0 * 5000 / 1023))
    cand=$((mv * 4 / 10))
    if [ "$emu_adc" = "$ucs_adc" ]; then m="PASS"; PASS=$((PASS+1)); else m="FAIL"; FAIL=$((FAIL+1)); fi
    printf "%-8s %6d %8s %8s %8d %8d %-6s\n" "$label" "$ch0" "$emu_adc" "$ucs_adc" "$mv" "$cand" "$m"
done

# --- Sweep ch1 (amps shunt) ---
echo ""
echo "--- Channel 1: LM358 shunt amplifier (amps mode) ---"
printf "%-10s %6s %8s %8s %8s %8s %-6s\n" "Shunt-mV" "count" "emu-ch1" "ucs-ch1" "mv" "mA" "Match"
printf "%-10s %6s %8s %8s %8s %8s %-6s\n" "---------" "-----" "-------" "-------" "----" "----" "-----"

for entry in "0mV:0" "5mV:1" "25mV:5" "50mV:10" "100mV:20" "250mV:51" "500mV:102" "1V:205" "2.5V:512"; do
    label="${entry%%:*}"
    ch1="${entry##*:}"
    emu_adc=$(timeout 10 "$EMU_TRACE" -fosc $FOSC -part stc15 -adc 0,0 -adc 1,$ch1 -adc 2,0 \
        -until-ns 5000000 "$HEX" 2>/dev/null | awk '$2=="ADC" && $3=="1" {print $4; exit}')
    ucs_adc=$(timeout 10 "$STC12_TRACE" -t STC15 -fosc $FOSC -adc 0,0 -adc 1,$ch1 -adc 2,0 \
        -until-ns 5000000 "$HEX" 2>/dev/null | awk '$2=="ADC" && $3=="1" {print $4; exit}')
    mv=$((ch1 * 5000 / 1023))
    # Firmware: cand = mv * 50 / 47 (LM358 gain inversion to get shunt current)
    ma=$((mv * 50 / 47))
    if [ "$emu_adc" = "$ucs_adc" ]; then m="PASS"; PASS=$((PASS+1)); else m="FAIL"; FAIL=$((FAIL+1)); fi
    printf "%-10s %6d %8s %8s %8d %8d %-6s\n" "$label" "$ch1" "$emu_adc" "$ucs_adc" "$mv" "$ma" "$m"
done

# --- Sweep ch2 (NTC thermistor) ---
echo ""
echo "--- Channel 2: NTC thermistor divider ---"
printf "%-10s %6s %8s %8s %8s %8s %-6s\n" "NTC-mV" "count" "emu-ch2" "ucs-ch2" "mv" "deci-C" "Match"
printf "%-10s %6s %8s %8s %8s %8s %-6s\n" "---------" "-----" "-------" "-------" "----" "------" "-----"

for entry in "0mV:0" "433mV:89" "733mV:150" "1146mV:235" "1657mV:339" "2500mV:512" "3268mV:669" "4004mV:820" "5V:1023"; do
    label="${entry%%:*}"
    ch2="${entry##*:}"
    emu_adc=$(timeout 10 "$EMU_TRACE" -fosc $FOSC -part stc15 -adc 0,0 -adc 1,0 -adc 2,$ch2 \
        -until-ns 5000000 "$HEX" 2>/dev/null | awk '$2=="ADC" && $3=="2" {print $4; exit}')
    ucs_adc=$(timeout 10 "$STC12_TRACE" -t STC15 -fosc $FOSC -adc 0,0 -adc 1,0 -adc 2,$ch2 \
        -until-ns 5000000 "$HEX" 2>/dev/null | awk '$2=="ADC" && $3=="2" {print $4; exit}')
    mv=$((ch2 * 5000 / 1023))
    # Firmware NTC piecewise: t10 depends on mv breakpoints
    # Simplified: use the first segment formula
    t10=$(( (mv - 433) * 100 / 300 - 200 ))
    if [ "$emu_adc" = "$ucs_adc" ]; then m="PASS"; PASS=$((PASS+1)); else m="FAIL"; FAIL=$((FAIL+1)); fi
    printf "%-10s %6d %8s %8s %8d %8d %-6s\n" "$label" "$ch2" "$emu_adc" "$ucs_adc" "$mv" "$t10" "$m"
done

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
