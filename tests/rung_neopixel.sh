#!/bin/bash
# rung_neopixel.sh — WS2812 NeoPixel pulse width verification.
#
# Measures T0H, T1H, T0L, T1L at P1.5 against the WS2812 spec windows,
# NOT against predicted cycle counts. The spec is the requirement; the
# predictions are what is being tested.
#
# WS2812B spec windows (datasheet):
#   T0H: 250–550 ns    T0L: 700–1000 ns
#   T1H: 650–950 ns    T1L: 300–600  ns
#
# Requires: neo_v3.ihx fixture (GRB = [0x00,0xFF,0x00, 0xFF,0x00,0x00, ...])
# which contains both 0-bits (byte 0: G=0x00) and 1-bits (byte 1: R=0xFF).
#
# T1H and T0L are both 814 ns because the delay loops happen to be the
# same length (9 cycles): T0L = 6 nop + djnz(2) + setb(1); T1H includes
# 5 nop before clr, and the path from setb through rlc+jc-taken+5nop+clr
# totals 9 cycles at the measured instruction costs. They come from
# DISTINCT code paths (0-bit low half vs 1-bit high half) and DISTINCT
# trace edges (verified below by pairing each low with its preceding high).
#
# Usage: ./tests/rung_neopixel.sh
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
FIXTURE="tests/fixtures/neo_v3.ihx"
FOSC=11059200

if [ ! -x "$TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -f "$FIXTURE" ]; then echo "FAIL: $FIXTURE not found" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

timeout 30 "$TRACE" -t STC12 -fosc $FOSC -until-ns 2000000 "$FIXTURE" 2>/dev/null \
    | awk '$2 == "PIN" && $3 ~ /1\.5/' > "$TMP/edges.txt"

TOTAL=$(wc -l < "$TMP/edges.txt")
if [ "$TOTAL" -lt 50 ]; then
    echo "FAIL: only $TOTAL edges (expected ~145 for 9 bytes)"
    exit 1
fi

python3 -c "
import sys

with open('$TMP/edges.txt') as f:
    edges = [(int(l.split('\t')[0]), l.split()[-1]) for l in f]

# Pair each HIGH with its following LOW (= high time),
# and each LOW with its following HIGH (= low time).
# Skip inter-byte gaps (> 2000 ns).
t0h, t1h, t0l, t1l = [], [], [], []

for i in range(len(edges) - 1):
    dt = edges[i+1][0] - edges[i][0]
    if dt > 2000:
        continue  # inter-byte gap, not a bit-level pulse

    if edges[i][1] == 'H':
        # HIGH→LOW transition: dt is the HIGH time
        if dt < 550:
            t0h.append(dt)
        else:
            t1h.append(dt)
    else:
        # LOW→HIGH transition: dt is the LOW time
        # Classify by the PRECEDING high time to know which bit type
        if i > 0:
            prev_dt = edges[i][0] - edges[i-1][0]
            if prev_dt < 550:
                t0l.append(dt)  # low after a 0-bit high
            else:
                t1l.append(dt)  # low after a 1-bit high

# WS2812B spec windows
specs = {
    'T0H': (t0h, 250, 550),
    'T1H': (t1h, 650, 950),
    'T0L': (t0l, 700, 1000),
    'T1L': (t1l, 300, 600),
}

passed = 0
failed = 0
for name, (vals, lo, hi) in specs.items():
    if not vals:
        print(f'FAIL  {name}: no samples')
        failed += 1
        continue
    avg = sum(vals) / len(vals)
    vmin, vmax = min(vals), max(vals)
    ok = lo <= vmin and vmax <= hi
    status = 'PASS' if ok else 'FAIL'
    print(f'{status}  {name}: avg={avg:.0f}ns range=[{vmin},{vmax}] window=[{lo},{hi}] n={len(vals)}')
    if ok:
        passed += 1
    else:
        failed += 1

# Byte count
total_bits = len(t0h) + len(t1h)
print(f'')
print(f'Total: {total_bits} bits ({len(t0h)} zero + {len(t1h)} one) = {total_bits/8:.0f} bytes')

# Confirm T1H and T0L come from distinct edges
print(f'')
print(f'T1H and T0L are both ~{sum(t1h)//len(t1h) if t1h else 0}ns and ~{sum(t0l)//len(t0l) if t0l else 0}ns.')
if t1h and t0l and abs(sum(t1h)/len(t1h) - sum(t0l)/len(t0l)) < 5:
    print(f'Same duration from DISTINCT code paths:')
    print(f'  T0L = clr→setb across 0-bit low half (6 nop + djnz + setb = 9 cy)')
    print(f'  T1H = setb→clr across 1-bit high half (rlc + jc-taken + 5 nop + clr = 9 cy)')
    print(f'  Coincidence: both paths happen to total 9 cycles.')

print(f'')
print(f'Results: {passed} pass, {failed} fail')
sys.exit(1 if failed > 0 else 0)
" 2>&1