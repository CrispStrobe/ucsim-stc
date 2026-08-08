#!/bin/bash
# trace.sh — differential execution trace emitter for ucsim-stc.
#
# Emits tab-separated events to stdout in the format defined by
# emu8051-stc/spec-updates/001-differential-trace-format.md.
#
# Usage: ./tests/trace.sh [-fosc Hz] [-until-ns N] firmware.hex
#
# The bound is in nanoseconds of simulated time (not cycles or
# instructions), so it means the same thing regardless of whether
# the CPU is 1T or 12T.
#
# LIMITATIONS:
# Shell/Python wrapper around ucsim's command interface — steps one
# instruction at a time. Practical for < 2000000 ns (~2 ms simulated).
# A C++ trace hook in the ucsim core would be needed for longer runs.

set -e

UCSIM="${UCSIM:-$(dirname "$0")/../ucsim/src/sims/s51.src/ucsim_51}"
FOSC=11059200
UNTIL_NS=2000000  # 2 ms default
HEXFILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -fosc)     FOSC="$2"; shift 2 ;;
        -until-ns) UNTIL_NS="$2"; shift 2 ;;
        -cycles)   # backwards compat: convert to approx ns
                   UNTIL_NS=$(python3 -c "print(int($2 * 1e9 / $FOSC))"); shift 2 ;;
        *)         HEXFILE="$1"; shift ;;
    esac
done

if [ -z "$HEXFILE" ]; then
    echo "Usage: $0 [-fosc Hz] [-until-ns N] firmware.hex" >&2
    exit 1
fi

if [ ! -x "$UCSIM" ]; then
    echo "ucsim_51 not found at $UCSIM — build first" >&2
    exit 1
fi

# We step instructions one at a time and sample SFRs after each.
# Estimate max instructions needed: UNTIL_NS / (ns per osc clock) * 2 (margin)
MAX_STEPS=$(python3 -c "print(int($UNTIL_NS * $FOSC / 1e9 * 2 + 1000))")

# Generate ucsim commands
python3 -c "
n = $MAX_STEPS
for i in range(n):
    print('step')
    print('dump sfr 0x80 0x80')
    print('dump sfr 0x88 0x89')
    print('dump sfr 0x8e 0x8e')
    print('dump sfr 0x90 0x96')
    print('dump sfr 0xa0 0xa0')
    print('dump sfr 0xb0 0xb2')
    print('dump sfr 0xbc 0xbc')
    print('dump sfr 0xc0 0xc0')
    print('dump sfr 0xd8 0xdb')
print('quit')
" | "$UCSIM" -t STC12 "$HEXFILE" 2>/dev/null | python3 -c "
import sys, re

fosc = $FOSC
until_ns = $UNTIL_NS
osc_clocks = 0
last_pc = None
sfr_shadow = {}

for a in [0x80, 0x90, 0xA0, 0xB0, 0xC0]:
    sfr_shadow[a] = 0xFF
for a in [0x88, 0x89, 0x8E, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0xB1, 0xB2, 0xBC, 0xD8, 0xD9, 0xDA, 0xDB]:
    sfr_shadow[a] = 0x00

for line in sys.stdin:
    line = line.rstrip()

    m = re.match(r'Stop at 0x([0-9a-fA-F]+):.* stepped (\d+) tick', line)
    if m:
        pc = int(m.group(1), 16)
        ticks = int(m.group(2))
        osc_clocks += ticks
        t_ns = osc_clocks * 1_000_000_000 // fosc
        if t_ns > until_ns:
            break
        if pc != last_pc:
            print(f'{t_ns}\tPC\t{pc:04X}')
            last_pc = pc
        continue

    m2 = re.match(r'0x([0-9a-fA-F]{2})\s+\S+:\s+\S+\s+0x([0-9a-fA-F]{2})\b', line)
    if m2:
        addr = int(m2.group(1), 16)
        val = int(m2.group(2), 16)
        if addr in sfr_shadow and sfr_shadow[addr] != val:
            t_ns = osc_clocks * 1_000_000_000 // fosc
            if t_ns > until_ns:
                break
            print(f'{t_ns}\tSFR\t{addr:02X} {val:02X}')
            if addr == 0x88:
                old = sfr_shadow[addr]
                if (val & 0x20) and not (old & 0x20):
                    print(f'{t_ns}\tTF\t0')
                if (val & 0x80) and not (old & 0x80):
                    print(f'{t_ns}\tTF\t1')
            if addr == 0xBC:
                old = sfr_shadow[addr]
                if (val & 0x10) and not (old & 0x10):
                    ch = val & 0x07
                    print(f'{t_ns}\tADC\t{ch} 512')
            sfr_shadow[addr] = val
"
