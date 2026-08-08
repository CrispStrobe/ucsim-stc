#!/bin/bash
# trace.sh — differential execution trace emitter for ucsim-stc.
#
# Emits tab-separated events to stdout in the format defined by
# emu8051-stc/spec-updates/001-differential-trace-format.md.
#
# Usage: ./tests/trace.sh [-fosc Hz] [-cycles N] firmware.hex
#
# LIMITATIONS:
# This is a shell/Python wrapper around ucsim's command interface.
# It steps the simulator one instruction at a time and samples SFRs,
# so it is SLOW — practical only for small cycle counts (< 50000).
# For production differential execution, a C++ trace hook inside
# the ucsim core would be needed.
#
# The output is diffable against emu8051-stc's emu_trace output:
#   ./emu_trace -fosc 11059200 -cycles 50000 firmware.hex > trace_emu.tsv
#   ./tests/trace.sh -fosc 11059200 -cycles 50000 firmware.hex > trace_ucsim.tsv
#   diff trace_emu.tsv trace_ucsim.tsv

set -e

UCSIM="${UCSIM:-$(dirname "$0")/../ucsim/src/sims/s51.src/ucsim_51}"
FOSC=11059200
CYCLES=50000
HEXFILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -fosc)   FOSC="$2"; shift 2 ;;
        -cycles) CYCLES="$2"; shift 2 ;;
        *)       HEXFILE="$1"; shift ;;
    esac
done

if [ -z "$HEXFILE" ]; then
    echo "Usage: $0 [-fosc Hz] [-cycles N] firmware.hex" >&2
    exit 1
fi

if [ ! -x "$UCSIM" ]; then
    echo "ucsim_51 not found at $UCSIM — build first" >&2
    exit 1
fi

# Generate ucsim commands: step + dump watched SFRs after each step
python3 -c "
n = $CYCLES
for i in range(n):
    print('step')
    # Dump only the watched SFRs (compact output)
    print('dump sfr 0x80 0x80')   # P0
    print('dump sfr 0x88 0x89')   # TCON, TMOD
    print('dump sfr 0x8e 0x8e')   # AUXR
    print('dump sfr 0x90 0x96')   # P1, P1M1, P1M0, P0M1, P0M0, P2M1, P2M0
    print('dump sfr 0xa0 0xa0')   # P2
    print('dump sfr 0xb0 0xb2')   # P3, P3M1, P3M0
    print('dump sfr 0xbc 0xbc')   # ADC_CONTR
    print('dump sfr 0xc0 0xc0')   # P4
    print('dump sfr 0xd8 0xdb')   # CCON, CMOD, CCAPM0, CCAPM1
print('quit')
" | "$UCSIM" -t STC12 "$HEXFILE" 2>/dev/null | python3 -c "
import sys, re

fosc = $FOSC
osc_clocks = 0
last_pc = None
sfr_shadow = {}

# Ports reset to 0xFF, everything else to 0
for a in [0x80, 0x90, 0xA0, 0xB0, 0xC0]:
    sfr_shadow[a] = 0xFF
for a in [0x88, 0x89, 0x8E, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0xB1, 0xB2, 0xBC, 0xD8, 0xD9, 0xDA, 0xDB]:
    sfr_shadow[a] = 0x00

for line in sys.stdin:
    line = line.rstrip()

    # Match step output
    m = re.match(r'Stop at 0x([0-9a-fA-F]+):.* stepped (\d+) tick', line)
    if m:
        pc = int(m.group(1), 16)
        ticks = int(m.group(2))
        osc_clocks += ticks
        t_ns = osc_clocks * 1_000_000_000 // fosc
        if pc != last_pc:
            print(f'{t_ns}\tPC\t{pc:04X}')
            last_pc = pc
        continue

    # Match SFR dump: '0xAA NAME:  0bxxxxxxxx 0xVV ...'
    m2 = re.match(r'0x([0-9a-fA-F]{2})\s+\S+:\s+\S+\s+0x([0-9a-fA-F]{2})\b', line)
    if m2:
        addr = int(m2.group(1), 16)
        val = int(m2.group(2), 16)
        if addr in sfr_shadow and sfr_shadow[addr] != val:
            t_ns = osc_clocks * 1_000_000_000 // fosc
            print(f'{t_ns}\tSFR\t{addr:02X} {val:02X}')
            # TF events
            if addr == 0x88:
                old = sfr_shadow[addr]
                if (val & 0x20) and not (old & 0x20):
                    print(f'{t_ns}\tTF\t0')
                if (val & 0x80) and not (old & 0x80):
                    print(f'{t_ns}\tTF\t1')
            # ADC completion
            if addr == 0xBC:
                old = sfr_shadow[addr]
                if (val & 0x10) and not (old & 0x10):
                    ch = val & 0x07
                    print(f'{t_ns}\tADC\t{ch} 512')
            sfr_shadow[addr] = val
"
