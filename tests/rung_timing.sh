#!/bin/bash
# Rung 0: clocks-per-instruction verification across all four parts.
#
# A NOP sled produces one PC event per instruction. On a 1T core,
# each NOP takes 1 osc clock (~90 ns at 11.0592 MHz). On a 12T core,
# each NOP takes 12 osc clocks (~1085 ns). This test asserts the ratio.
#
# Usage: ./tests/rung_timing.sh

set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
FOSC=11059200
FIXTURE="tests/fixtures/nop_sled.ihx"

if [ ! -x "$TRACE" ]; then
  echo "FAIL: $TRACE not found. Build with: cd ucsim/src/sims/s51.src && make stc12_trace"
  exit 1
fi

# Expected ns per NOP:
#   1T:  1e9 / 11059200 * 1  =  90.42 ns  (truncated: ~90)
#   12T: 1e9 / 11059200 * 12 = 1085.07 ns (truncated: ~1085)

PASS=0
FAIL=0

check_timing() {
  local part="$1"
  local expected_clocks="$2"
  local label="$3"

  # Get the first two PC events and compute the delta in ns
  local times
  times=$("$TRACE" -t "$part" -fosc "$FOSC" -until-ns 50000 "$FIXTURE" 2>/dev/null \
    | grep "^[0-9]*	PC	" | head -3 | awk -F'\t' '{print $1}')

  local t0 t1 t2
  t0=$(echo "$times" | sed -n '1p')
  t1=$(echo "$times" | sed -n '2p')
  t2=$(echo "$times" | sed -n '3p')

  if [ -z "$t0" ] || [ -z "$t1" ] || [ -z "$t2" ]; then
    echo "FAIL  $label: no trace output"
    FAIL=$((FAIL + 1))
    return
  fi

  local delta1=$((t1 - t0))
  local delta2=$((t2 - t1))

  # Expected ns per NOP = 1e9 * expected_clocks / FOSC
  # At 11059200: 1T = 90 ns, 12T = 1085 ns (integer truncation)
  local expected_ns=$(( 1000000000 * expected_clocks / FOSC ))

  # Allow ±2 ns for integer rounding
  local lo=$((expected_ns - 2))
  local hi=$((expected_ns + 2))

  if [ "$delta1" -ge "$lo" ] && [ "$delta1" -le "$hi" ] && \
     [ "$delta2" -ge "$lo" ] && [ "$delta2" -le "$hi" ]; then
    echo "PASS  $label: ${delta1}ns/NOP (expected ${expected_ns}ns, ${expected_clocks} clocks)"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $label: got ${delta1}ns, ${delta2}ns, expected ${expected_ns}ns (${expected_clocks} clocks)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Rung 0: clocks-per-instruction timing ==="
check_timing "STC12"       1  "STC12 (1T)"
check_timing "STC15"       1  "STC15F2K60S2 (1T)"
check_timing "STC89"       12 "STC89C52RC (12T)"
check_timing "STC15W"      1  "STC15W408AS (1T)"

echo ""
echo "Results: $PASS pass, $FAIL fail"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
