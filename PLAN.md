# ucsim-stc — handover

## What this is

A GPL-2 fork of ucsim (from SDCC) adding STC12C5A60S2 and STC15F2K60S2
processor models.  It exists as a simulation oracle for the BrickWright
toolchain — never bundled, never shipped to users.

## What is proven and what is not

**Proven (two independent emulators agree):**
- Free-running peripheral traces: 220/349 strict on a third-party corpus
- Run-control ladder (DEBUG-CONTROL-MODEL §8): all 8 rungs pass
- Blocks → C → measured behaviour: 101/101 on unedited generateC output
- 9/9 example bundles identical across emulators
- Scan timing on real firmware (ledcube444): 0.097% cross-emulator

**Consistent but not independently confirmed:**
- The model matches the STC12C5A60S2 datasheet, but a shared misreading
  would produce the same agreement.  No claim has been confirmed on
  silicon.  The bench session is the one thing that settles it.

## The four commands

    ./tests/smoke.sh                                          # 16 assertions
    EMU_TRACE=… ./tests/run_control_diff.sh                   # §8 ladder, rungs 3-7
    EMU_TRACE=… ./tests/examples_diff.sh                      # 9 example bundles
    EMU_TRACE=… ./tests/generated_cube_diff.sh                # blocks→C→behaviour

`smoke.sh` runs standalone.  The others need `emu_trace` from
`emu8051-stc` (set `EMU_TRACE` to its path).

## What the bench session is for

When a real STC12C5A60S2 is on the bench:
- Does P0 active-HIGH match the hardware? (measured from firmware,
  not confirmed on silicon — `BW_CUBE_ACTIVE_HIGH`)
- Does the ADC analog path produce the right number? (register
  sequence verified, voltage→number untested)
- Does the timer overflow land at exactly 921 counts? (both emulators
  agree, but both read the same datasheet)

A disagreement between the chip and the model is the most valuable
finding this project can produce, and it would be worth a fresh
session with the measurement in hand.
