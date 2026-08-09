#!/bin/bash
# ledcube_timing.sh — measure scan step timing on rgm3/ledcube444.
#
# Compiles the firmware, runs both emulators, and compares P0 write
# timestamps to microsecond precision.
#
# Usage: ./tests/ledcube_timing.sh [source_dir]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
SRC="${1:-/mnt/volume1/code/stc-research/corpus/rgm3_ledcube444/ledcube444.c}"
FOSC=11059200

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$SRC" ]; then echo "SKIP: ledcube444.c not found at $SRC" >&2; exit 0; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Compile
sdcc -mmcs51 --model-small -o "$TMP/ledcube.ihx" "$SRC" 2>/dev/null || {
    echo "FAIL: compilation failed" >&2; exit 1
}

# Run both for 200ms
"$EMU_TRACE" -fosc $FOSC -until-ns 200000000 "$TMP/ledcube.ihx" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80"' > "$TMP/emu_p0.tsv"

timeout 120 "$STC12_TRACE" -fosc $FOSC -until-ns 200000000 "$TMP/ledcube.ihx" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80"' > "$TMP/ucsim_p0.tsv"

EN=$(wc -l < "$TMP/emu_p0.tsv")
UN=$(wc -l < "$TMP/ucsim_p0.tsv")

echo "ledcube444 scan timing (FOSC=$FOSC, 200ms span)"
echo "  emu8051: $EN P0 events"
echo "  ucsim:   $UN P0 events"

# Compare timestamps of first 10 P0 events
python3 -c "
import sys
emu = [int(l.split('\t')[0]) for l in open('$TMP/emu_p0.tsv')]
ucsim = [int(l.split('\t')[0]) for l in open('$TMP/ucsim_p0.tsv')]
n = min(len(emu), len(ucsim), 10)
if n < 4:
    print('  too few events'); sys.exit(1)
# Scan step = gap between consecutive P0 writes
print(f'  First {n} P0 write timestamps:')
max_diff = 0
for i in range(n):
    d = abs(emu[i] - ucsim[i])
    max_diff = max(max_diff, d)
    print(f'    [{i}] emu={emu[i]:>12} ucsim={ucsim[i]:>12} diff={d:>6} ns')
# First scan step
step_e = emu[2] - emu[0]
step_u = ucsim[2] - ucsim[0]
step_diff = abs(step_e - step_u)
print(f'  Scan step: emu={step_e/1e6:.3f}ms ucsim={step_u/1e6:.3f}ms diff={step_diff}ns ({step_diff/step_e*100:.4f}%)')
print(f'  Max per-event diff: {max_diff} ns')
if step_diff < 5000:
    print('  PASS: scan step agrees to microsecond precision')
else:
    print(f'  FAIL: scan step differs by {step_diff/1e3:.1f} µs')
    sys.exit(1)
"
