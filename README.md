# ucsim-stc

A GPL-2 fork of [ucsim](http://mazsola.iit.uni-miskolc.hu/~drdani/embedded/ucsim/)
(from SDCC) adding an **STC12C5A60S2** processor model.

## Build

    cd ucsim
    ./configure
    make -j$(nproc)

The binary is `ucsim/src/sims/s51.src/ucsim_51`.  Select the STC12 model with:

    ucsim/src/sims/s51.src/ucsim_51 -t STC12

## Test

    ./tests/smoke.sh                                          # 16 assertions
    EMU_TRACE=… ./tests/run_control_diff.sh                   # §8 ladder, rungs 3-7
    EMU_TRACE=… ./tests/examples_diff.sh                      # 9 example bundles
    EMU_TRACE=… ./tests/generated_cube_diff.sh                # blocks→C→behaviour

`smoke.sh` runs standalone.  The others need `emu_trace` from
`emu8051-stc` (set `EMU_TRACE` to its path).

## Baseline version

**ucsim 0.8.15** from the SDCC 4.5.0 Debian orig tarball
(`sdcc_4.5.0+dfsg.orig.tar.xz`).

This version was chosen deliberately: SDCC 4.5.0 is the compiler version
the BrickWright toolchain targets, so differential execution compares
like with like.  The gap (no STC model) was verified independently at
upstream git head 0.9.9 — the finding holds for both versions.

SourceForge is unreachable from the build host (403), so the Debian
tarball at `https://deb.debian.org/debian/pool/main/s/sdcc/` is the
canonical source.

## What was changed

See `NOTICE` for the full list.  In summary: a new processor class
`cl_uc_stc12` (inheriting from `cl_uc52`) with:

- AUXR.7/AUXR.6 timer 1T/12T prescaler
- PxM1/PxM0 port mode registers
- 10-bit ADC with ADRJ alignment support
- PCA with 1T-correct clock prescaling
- All STC12-specific SFRs from the datasheet

## Shared contract

Peripheral behaviour follows
[STC12-PERIPHERAL-MODEL.md](https://github.com/CrispStrobe/stc/blob/main/docs/STC12-PERIPHERAL-MODEL.md)
in the `stc` repo.  The emu8051-stc fork implements the same spec.
Any resolution (e.g. ADRJ alignment) must be recorded in the spec
first, then adopted by both implementations.

## Licence

GPL-2.0-or-later, inherited from ucsim/SDCC.  See `LICENSE`.

This fork must **never** be bundled into brickwright-lite (MIT, app-store).
It exists as a GPL-licensed simulation oracle, kept separate specifically
to maintain the licence boundary.
