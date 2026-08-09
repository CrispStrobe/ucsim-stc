# Request: `-part` flag on emu_trace for cross-emulator parity

From ucsim-stc. For emu8051-stc.

## What is needed

`emu_trace` currently always runs as STC12. The four-part parity campaign
needs it to accept:

```
emu_trace -part STC89 [-fosc Hz] [-until-ns N] firmware.hex
emu_trace -part STC15W [-fosc Hz] [-until-ns N] firmware.hex
```

Mapping:
- `STC12` → PART_STC12 (default, current behaviour)
- `STC15` → PART_STC15
- `STC89` → PART_STC89 (12T core: **clock_per_cycle must be 12**)
- `STC15W` → PART_STC15W (no Timer 1)

The API exists and works — `stc12_set_part()` in `stc12.h` line 390,
`PART_STC12/STC15/STC89/STC15W` at lines 340–343, and the core's
`mMachineCycleScale` field (`emu8051.h` line 77) already does the 12T
scaling. Commit `00e9d5b` verified 12.0 clocks/NOP for STC89.

`trace.c` just needs to parse `-part NAME`, call `stc12_set_part()`,
and set `cpu.mMachineCycleScale` (currently implicit in wasm_api.c's
`emu_set_part` but not available to the trace binary). The trace binary
also predates the 12T fix and needs a rebuild.

## Why

The timing rung (rung 0) verifies clocks-per-instruction across parts.
ucsim-stc passes it: STC89 NOPs take 1085 ns (12× the STC12's 90 ns).
Cross-emulator parity requires the same measurement on emu8051-stc.

The `/tmp/stc89-12t.md` finding already notes that the WASM build runs
STC89 at 1T speed. The trace binary needs the same fix as the WASM build
needs, and needs it first — without it, the differential harness cannot
verify that the fix is correct.

## What ucsim-stc has ready

- `stc12_trace -t STC89` works and produces correct 12T timing
- `tests/rung_timing.sh` verifies all four parts
- `tests/fixtures/blink_stc89.ihx` — blink compiled for STC89 (8052.h)
- STC12/STC15 differential tests remain green (9/9 examples, 6/6 ladder)

Once emu_trace supports `-part`, the cross-emulator diff script extends
trivially: same hex, same flags, compare output.
