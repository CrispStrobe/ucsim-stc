#!/bin/bash
# ledcube_timing.sh — measure scan step timing on ledcube444 firmware.
#
# Requires two inputs from the local-only corpus (never committed):
#   $1 = ledcube444.c (SDCC-compatible source)
#   $2 = Keil-compiled main.hex (original vendor build)
#
# Not runnable from a clean clone. Supply the inputs to re-run.
#
# Usage: ./tests/ledcube_timing.sh ledcube444.c keil_main.hex
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-$(command -v emu_trace 2>/dev/null || echo "")}"
FOSC=11059200

if [ $# -lt 1 ]; then
    echo "Usage: $0 <ledcube444.c> [keil_main.hex]"
    echo "Needs local-only corpus inputs; not runnable from a clean clone."
    exit 77  # conventional skip
fi

SRC="$1"
KEIL_HEX="${2:-}"

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi
if [ -z "$EMU_TRACE" ] || [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found" >&2; exit 77
fi
if [ ! -f "$SRC" ]; then
    echo "SKIP: source not found at $SRC" >&2; exit 77
fi

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

# Compare timestamps
python3 -c "
import sys
emu = [int(l.split('\t')[0]) for l in open('$TMP/emu_p0.tsv')]
ucsim = [int(l.split('\t')[0]) for l in open('$TMP/ucsim_p0.tsv')]
n = min(len(emu), len(ucsim), 10)
if n < 4:
    print('  too few events'); sys.exit(1)
print(f'  First {n} P0 write timestamps:')
max_diff = 0
for i in range(n):
    d = abs(emu[i] - ucsim[i])
    max_diff = max(max_diff, d)
    print(f'    [{i}] emu={emu[i]:>12} ucsim={ucsim[i]:>12} diff={d:>6} ns')
step_e = emu[2] - emu[0]
step_u = ucsim[2] - ucsim[0]
step_diff = abs(step_e - step_u)
print(f'  Scan step: emu={step_e/1e6:.3f}ms ucsim={step_u/1e6:.3f}ms diff={step_diff}ns ({step_diff/step_e*100:.4f}%)')
print(f'  Max per-event diff: {max_diff} ns')
if step_diff < 5000:
    print('  PASS: scan step agrees to microsecond precision')
else:
    print(f'  FAIL: scan step differs by {step_diff/1e3:.1f} us')
    sys.exit(1)
"

# Keil vs SDCC port-state comparison (if Keil hex provided)
if [ -n "$KEIL_HEX" ] && [ -f "$KEIL_HEX" ]; then
    echo ""
    echo "Keil vs SDCC port-state comparison:"
    "$EMU_TRACE" -fosc $FOSC -until-ns 200000000 "$KEIL_HEX" 2>/dev/null \
        | awk '$2 == "SFR" && ($3 ~ /^80/ || $3 ~ /^A0/)' | cut -f2- | head -20 > "$TMP/keil_ports.ev"
    "$EMU_TRACE" -fosc $FOSC -until-ns 200000000 "$TMP/ledcube.ihx" 2>/dev/null \
        | awk '$2 == "SFR" && ($3 ~ /^80/ || $3 ~ /^A0/)' | cut -f2- | head -20 > "$TMP/sdcc_ports.ev"
    KN=$(wc -l < "$TMP/keil_ports.ev"); SN=$(wc -l < "$TMP/sdcc_ports.ev")
    MIN=$((KN < SN ? KN : SN))
    if [ "$MIN" -gt 0 ] && diff <(head -$MIN "$TMP/keil_ports.ev") <(head -$MIN "$TMP/sdcc_ports.ev") > /dev/null 2>&1; then
        echo "  PASS: first $MIN port states identical between Keil and SDCC"
    else
        echo "  FAIL: port states differ"
    fi
fi
