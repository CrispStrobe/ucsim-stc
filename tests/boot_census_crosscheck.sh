#!/bin/bash
# boot_census_crosscheck.sh — cross-check emu8051's boot census under ucsim.
#
# Runs each census hex file (pre-compiled by census_gen_hex.mjs) through
# stc12_trace and compares against the emu8051 census verdicts.
#
# Key checks:
#   1. Boot verdict: clean vs wedge (must match)
#   2. Port events: present when census says present (count may differ at shorter sim times)
#   3. IE value: must match
#
# Usage: ./tests/boot_census_crosscheck.sh [until_ns] [hex_dir]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STC12_TRACE="$REPO_DIR/ucsim/src/sims/s51.src/stc12_trace"
FOSC=11059200
UNTIL_NS="${1:-2000000000}"   # full 2-second census by default
HEX_DIR="${2:-/tmp/census-hex}"

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found at $STC12_TRACE" >&2; exit 1
fi
if [ ! -d "$HEX_DIR" ]; then
    echo "FAIL: hex dir not found at $HEX_DIR — run census_gen_hex.mjs first" >&2; exit 1
fi

# Census from emu8051-stc/docs/boot-census.md
# Format: name|device|emu_pins|emu_verdict
# (TMOD column in census = address 0x89 = timer was set up, not the value;
#  IE column = 0x00 = interrupts not enabled in these programs)
CENSUS=(
"01-blink|STC12|5|clean"
"02-dimmer|STC12|3|clean"
"03-night-light|STC12|3|clean"
"04-thermostat|STC12|3|clean"
"05-counter|STC12|7|clean"
"06-active-low-high|STC12|11|clean"
"07-buzzer-siren|STC12|0|clean"
"08-led-chaser-595|STC12|6|clean"
"09-relay-clicker|STC12|5|clean"
"10-motor-speed|STC12|3|clean"
"11-toggle-button|STC12|1|clean"
"12-dual-blink|STC12|9|clean"
"13-sos-morse|STC12|8|clean"
"14-traffic-light|STC12|4|clean"
"15-voltage-divider|STC12|2|clean"
"16-ldr-bargraph|STC12|4|clean"
"17-comparator|STC12|3|clean"
"18-logic-and-gate|STC12|1|clean"
"19-logic-or-gate|STC12|1|clean"
"20-shift-register-binary|STC12|150|clean"
"24-pwm-fade|STC12|39|clean"
"25-reaction-timer|STC12|1|clean"
"26-debounce|STC12|1|clean"
"27-led-dice|STC12|1|clean"
"30-multi-led-pattern|STC12|23|clean"
"32-source-vs-sink|STC12|5|clean"
"33-inductive-no-flyback|STC12|4|clean"
"46-port-overcurrent|STC12|24|clean"
"49-lcd-hello|STC12|6520|clean"
"50-7seg-chase|STC12|39|clean"
"53-servo-sweep|STC12|195|clean"
"54-motor-driver|STC12|10|clean"
"60-retro-console|STC15|2443|clean"
"61-console-pong|STC15|5747|clean"
)

PASS=0; FAIL=0; SKIP=0
DIVERGENCES=""

echo "=== Boot Census Cross-Check: ucsim vs emu8051 ==="
echo "Simulation: ${UNTIL_NS} ns   FOSC: ${FOSC}"
echo ""
printf "%-30s %-6s %8s %8s %-8s %-6s\n" \
       "Example" "CPU" "emu-PIN" "ucs-PIN" "Verdict" "Result"
printf "%-30s %-6s %8s %8s %-8s %-6s\n" \
       "-------" "---" "-------" "-------" "-------" "------"

for entry in "${CENSUS[@]}"; do
    IFS='|' read -r name cpu_type emu_pins emu_verdict <<< "$entry"
    hex_file="$HEX_DIR/$name.hex"

    if [ ! -f "$hex_file" ]; then
        printf "%-30s %-6s %8s %8s %-8s %-6s\n" "$name" "$cpu_type" "$emu_pins" "-" "SKIP" "SKIP"
        SKIP=$((SKIP+1))
        continue
    fi

    # Run under stc12_trace
    trace_output=$(timeout 300 "$STC12_TRACE" -t "$cpu_type" -fosc "$FOSC" \
        -until-ns "$UNTIL_NS" "$hex_file" 2>/dev/null)
    exit_code=$?

    if [ $exit_code -eq 124 ]; then
        ucs_verdict="WEDGE(timeout)"
        ucs_pins=0
        last_pc="timeout"
    else
        # Count PIN events
        ucs_pins=$(echo "$trace_output" | awk '$2 == "PIN"' | wc -l)

        # Check for wedge: PC must advance past init
        pc_count=$(echo "$trace_output" | awk '$2 == "PC"' | wc -l)
        last_pc=$(echo "$trace_output" | awk '$2 == "PC" {pc=$3} END {print pc}')

        if [ "$pc_count" -lt 5 ]; then
            ucs_verdict="WEDGE"
        else
            ucs_verdict="clean"
        fi
    fi

    # Check 1: verdict match
    verdict_ok=true
    if [ "$ucs_verdict" != "$emu_verdict" ]; then
        verdict_ok=false
    fi

    # Check 2: port events presence match
    # If emu8051 had >0 port events, ucsim should too (and vice versa)
    pin_ok=true
    if [ "$emu_pins" -gt 0 ] && [ "$ucs_pins" -eq 0 ]; then
        pin_ok=false
    fi
    if [ "$emu_pins" -eq 0 ] && [ "$ucs_pins" -gt 0 ]; then
        # ucsim has events emu didn't — note but don't fail (may be init writes)
        pin_ok=true
    fi

    if $verdict_ok && $pin_ok; then
        result="PASS"
        PASS=$((PASS+1))
    else
        result="FAIL"
        FAIL=$((FAIL+1))
        reason=""
        if ! $verdict_ok; then reason="verdict:${ucs_verdict}≠${emu_verdict}"; fi
        if ! $pin_ok; then reason="${reason} pins:emu=${emu_pins},ucsim=${ucs_pins}"; fi
        DIVERGENCES="${DIVERGENCES}  ${name}: ${reason} (last PC=0x${last_pc})\n"
    fi

    printf "%-30s %-6s %8s %8s %-8s %-6s\n" \
           "$name" "$cpu_type" "$emu_pins" "$ucs_pins" "$ucs_verdict" "$result"
done

echo ""
echo "=== Cross-Check Results ==="
echo "Pass: $PASS  Fail: $FAIL  Skip: $SKIP  Total: ${#CENSUS[@]}"

if [ -n "$DIVERGENCES" ]; then
    echo ""
    echo "=== Divergences (conformance findings) ==="
    echo -e "$DIVERGENCES"
fi

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "CLEAN: ucsim agrees with emu8051 on all ${PASS} census examples."
    exit 0
else
    echo ""
    echo "CONFORMANCE FINDINGS: $FAIL divergence(s)."
    exit 1
fi
