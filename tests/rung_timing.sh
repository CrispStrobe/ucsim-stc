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

# --- Difference assertion: STC89 MUST differ from STC12 ---
# Per the correction in stc89-correction.md: a probe that only checks
# agreements can pass with all values wrong. Assert the known difference.
echo ""
echo "=== Difference assertion: STC89 vs STC12 ==="

STC12_TIMES=$("$TRACE" -t STC12 -fosc "$FOSC" -until-ns 50000 "$FIXTURE" 2>/dev/null \
  | grep "^[0-9]*	PC	" | head -3 | awk -F'\t' '{print $1}')
STC89_TIMES=$("$TRACE" -t STC89 -fosc "$FOSC" -until-ns 50000 "$FIXTURE" 2>/dev/null \
  | grep "^[0-9]*	PC	" | head -3 | awk -F'\t' '{print $1}')

STC12_T0=$(echo "$STC12_TIMES" | sed -n '1p')
STC12_T1=$(echo "$STC12_TIMES" | sed -n '2p')
STC89_T0=$(echo "$STC89_TIMES" | sed -n '1p')
STC89_T1=$(echo "$STC89_TIMES" | sed -n '2p')

STC12_D=$((STC12_T1 - STC12_T0))
STC89_D=$((STC89_T1 - STC89_T0))

# The ratio must be ~12 (11.5 to 12.5 to allow rounding)
if [ "$STC12_D" -gt 0 ]; then
  # Use integer arithmetic: ratio*10 to get one decimal place
  RATIO10=$(( STC89_D * 10 / STC12_D ))
  if [ "$RATIO10" -ge 115 ] && [ "$RATIO10" -le 125 ]; then
    echo "PASS  STC89/STC12 ratio = ${RATIO10}/10 (expected ~12.0)"
    echo "      STC12: ${STC12_D}ns, STC89: ${STC89_D}ns"
    PASS=$((PASS + 1))
  else
    echo "FAIL  STC89/STC12 ratio = ${RATIO10}/10 (expected ~12.0)"
    echo "      STC12: ${STC12_D}ns, STC89: ${STC89_D}ns"
    FAIL=$((FAIL + 1))
  fi
else
  echo "FAIL  could not compute ratio (STC12 delta = 0)"
  FAIL=$((FAIL + 1))
fi

# --- Timer equivalence: STC89 Timer 0 at FOSC/12 = STC12 Timer 0 at FOSC/12 ---
# This is the whole point of the FOSC/12 design: one program is
# timing-correct on both. The CORE rate differs 12×; the TIMER rate
# is identical. Assert both: the difference (core) and the equality (timer).
echo ""
echo "=== Timer rate equivalence: STC89 vs STC12 (must agree) ==="

STC12_TF=$("$TRACE" -t STC12 -fosc "$FOSC" -until-ns 10000000 \
    tests/fixtures/blink_stc89.ihx 2>/dev/null \
    | awk '$2 == "TF" && $3 == "0" {print $1}' | head -3)
STC89_TF=$("$TRACE" -t STC89 -fosc "$FOSC" -until-ns 10000000 \
    tests/fixtures/blink_stc89.ihx 2>/dev/null \
    | awk '$2 == "TF" && $3 == "0" {print $1}' | head -3)

STC12_TF0=$(echo "$STC12_TF" | sed -n '1p')
STC12_TF1=$(echo "$STC12_TF" | sed -n '2p')
STC89_TF0=$(echo "$STC89_TF" | sed -n '1p')
STC89_TF1=$(echo "$STC89_TF" | sed -n '2p')

if [ -n "$STC12_TF0" ] && [ -n "$STC12_TF1" ] && [ -n "$STC89_TF0" ] && [ -n "$STC89_TF1" ]; then
  STC12_TF_D=$((STC12_TF1 - STC12_TF0))
  STC89_TF_D=$((STC89_TF1 - STC89_TF0))
  # Both should be ~1,000,000 ns (1 ms). Allow 5% tolerance for
  # instruction-timing interleaving differences.
  TF_DIFF=$((STC89_TF_D - STC12_TF_D))
  TF_DIFF=${TF_DIFF#-} # abs
  TF_PCT=$(( TF_DIFF * 100 / STC12_TF_D ))
  if [ "$TF_PCT" -le 5 ]; then
    echo "PASS  Timer 0 TF interval: STC12=${STC12_TF_D}ns STC89=${STC89_TF_D}ns (${TF_PCT}% diff)"
    PASS=$((PASS + 1))
  else
    echo "FAIL  Timer 0 TF interval: STC12=${STC12_TF_D}ns STC89=${STC89_TF_D}ns (${TF_PCT}% diff)"
    FAIL=$((FAIL + 1))
  fi
else
  echo "FAIL  no TF0 events to compare"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS pass, $FAIL fail"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
