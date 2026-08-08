# Tests

## Automated

Run from the repo root:

    ./tests/smoke.sh

11 headless assertions against `ucsim_51 -t STC12`. Exits non-zero on failure.

## Differential execution

    ./tests/diff_test.sh firmware.hex [cycles]

Runs the same firmware on both ucsim-stc and emu8051-stc, compares
SFR/TF event sequences. Requires `emu_trace` from emu8051-stc.

    ./tests/trace.sh -fosc 11059200 -cycles 50000 firmware.hex > trace.tsv

Standalone trace emitter (slow — shell wrapper, practical for < 50000 cycles).
Output format matches emu8051-stc/spec-updates/001-differential-trace-format.md.

## What is NOT tested automatically

- Instruction cycle timing (uses base 8051 counts, not STC12 datasheet timings)
- ADC returns synthetic mid-scale values (register sequence only, no silicon validation)
- PCA PWM pin output (register-level only, not wired to port simulation)
