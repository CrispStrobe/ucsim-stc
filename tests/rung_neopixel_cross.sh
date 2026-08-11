#!/bin/bash
# rung_neopixel_cross.sh — WS2812 NeoPixel cross-emulator verification.
#
# Runs neo_v3.ihx through BOTH stc12_trace (ucsim) and emu_trace (emu8051)
# and compares every P1.5 edge interval. Agreement promotes NeoPixel timing
# from category 2b (single-source) to category 1 (independent-source).
#
# Prerequisites:
#   - stc12_trace built (ucsim/src/sims/s51.src/stc12_trace)
#   - emu_trace built  (/mnt/volume1/code/emu8051-stc/emu_trace)
#   - neo_v3.ihx fixture
#
# Usage: ./tests/rung_neopixel_cross.sh
set -e
cd "$(dirname "$0")/.."

UCSIM_TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="/mnt/volume1/code/emu8051-stc/emu_trace"
FIXTURE="tests/fixtures/neo_v3.ihx"
FOSC=11059200
DURATION=2000000

for bin in "$UCSIM_TRACE" "$EMU_TRACE"; do
    if [ ! -x "$bin" ]; then echo "FAIL: $bin not found" >&2; exit 1; fi
done
if [ ! -f "$FIXTURE" ]; then echo "FAIL: $FIXTURE not found" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Run both emulators
timeout 30 "$UCSIM_TRACE" -t STC12 -fosc $FOSC -until-ns $DURATION "$FIXTURE" 2>/dev/null \
    | awk '$2 == "PIN" && $3 ~ /1\.5/' > "$TMP/ucsim.txt"

timeout 30 "$EMU_TRACE" -fosc $FOSC -until-ns $DURATION "$FIXTURE" 2>/dev/null \
    | awk '$2 == "PIN" && $3 ~ /1\.5/' > "$TMP/emu.txt"

UCSIM_N=$(wc -l < "$TMP/ucsim.txt")
EMU_N=$(wc -l < "$TMP/emu.txt")

if [ "$UCSIM_N" -lt 50 ]; then echo "FAIL: ucsim only $UCSIM_N edges"; exit 1; fi
if [ "$EMU_N" -lt 50 ]; then echo "FAIL: emu8051 only $EMU_N edges"; exit 1; fi

python3 -c "
import sys

def load(path):
    with open(path) as f:
        return [(int(l.split('\t')[0]), l.split()[-1]) for l in f]

def measure(edges):
    t0h, t1h, t0l, t1l = [], [], [], []
    for i in range(len(edges) - 1):
        dt = edges[i+1][0] - edges[i][0]
        if dt > 2000:
            continue
        if edges[i][1] == 'H':
            (t0h if dt < 550 else t1h).append(dt)
        elif i > 0:
            prev_dt = edges[i][0] - edges[i-1][0]
            (t0l if prev_dt < 550 else t1l).append(dt)
    return t0h, t1h, t0l, t1l

ue = load('$TMP/ucsim.txt')
ee = load('$TMP/emu.txt')

# emu8051 P1 defaults to 0x00, so the first edge is a startup H that
# ucsim (P1 defaults 0xFF) doesn't emit.  Skip it for alignment.
if ee[0][1] == 'H' and ue[0][1] != 'H':
    ee = ee[1:]

# --- Per-emulator spec-window check ---
specs = [('T0H', 250, 550), ('T1H', 650, 950), ('T0L', 700, 1000), ('T1L', 300, 600)]

for label, edges in [('ucsim', ue), ('emu8051', ee)]:
    vals = measure(edges)
    print(f'=== {label} ===')
    all_ok = True
    for (name, lo, hi), v in zip(specs, vals):
        if not v:
            print(f'  FAIL  {name}: no samples')
            all_ok = False
            continue
        avg = sum(v)/len(v)
        vmin, vmax = min(v), max(v)
        ok = lo <= vmin and vmax <= hi
        status = 'PASS' if ok else 'FAIL'
        if not ok: all_ok = False
        print(f'  {status}  {name}: avg={avg:.0f}ns [{vmin},{vmax}] window=[{lo},{hi}] n={len(v)}')
    print()

# --- Edge-by-edge comparison ---
min_len = min(len(ue), len(ee))
diffs = []
for i in range(min_len - 1):
    u_dt = ue[i+1][0] - ue[i][0]
    e_dt = ee[i+1][0] - ee[i][0]
    diffs.append(abs(e_dt - u_dt))

max_diff = max(diffs)
mean_diff = sum(diffs) / len(diffs)
over_1 = sum(1 for d in diffs if d > 1)

print(f'=== Cross-emulator edge comparison ===')
print(f'Edges compared: {len(diffs)}')
print(f'Max |diff|: {max_diff} ns')
print(f'Mean |diff|: {mean_diff:.1f} ns')
print(f'Edges with |diff| > 1 ns: {over_1}')
print()

if max_diff <= 1 and over_1 == 0:
    print('PASS  Both emulators agree on every edge within 1 ns (clock rounding).')
    print('      NeoPixel WS2812 timing: category 1 (independent-source agreement).')
else:
    print(f'FAIL  Max divergence {max_diff} ns, {over_1} edges differ by > 1 ns.')
    sys.exit(1)
" 2>&1