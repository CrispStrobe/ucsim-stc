# ucsim-stc

A GPL-2 fork of [ucsim](http://mazsola.iit.uni-miskolc.hu/~drdani/embedded/ucsim/)
(part of [SDCC](https://sdcc.sourceforge.net/)) adding four STC 8051
processor models. ucsim is by Drotos Daniel; the STC peripheral layers,
test harness, and trace binary are ours.

**Baseline:** ucsim 0.8.15 from SDCC 4.5.0 (`sdcc_4.5.0+dfsg.orig.tar.xz`).
The gap (no STC model) was verified independently at upstream git head 0.9.9.

**Licence:** GPL-2.0-or-later, inherited from ucsim/SDCC. See `LICENSE`.
This fork is a simulation oracle — it must **never** be bundled into
MIT-licensed applications.

## Four processor models

| Part | Core | `clock_per_cycle()` | Key peripherals |
|------|------|---------------------|-----------------|
| STC12C5A60S2 | 1T | 1 | AUXR 1T/12T, port modes, ADC, 2-ch PCA, BRT, WDT, dual DPTR |
| STC15F2K60S2 | 1T | 1 | + Timer 2 (T2H/T2L), 3-ch PCA, ADRJ at CLK_DIV.5 |
| STC89C52RC | **12T** | **12** | Standard 8052 only — no AUXR, no port modes, no ADC, no PCA |
| STC15W408AS | 1T | 1 | No Timer 1, no P4/P5, 1 UART. Same ADC/PCA/port modes as STC15F |

Select with `-t STC12`, `-t STC15`, `-t STC89`, `-t STC15W`.

## What is verified (category 2b unless noted)

Evidence categories per [`stc/docs/EVIDENCE-CATEGORIES.md`](https://github.com/CrispStrobe/stc12c5a60s2-lab/blob/main/docs/EVIDENCE-CATEGORIES.md).
**Nothing has run on real silicon.** Every measurement is emulation-only.

| Measurement | Result | Category |
|---|---|---|
| 347-image corpus sweep, 0 genuine disagreements | 131 strict + 110 prefix + 20 interleave + 33 timing-count | **1** (independent upstream cores) |
| STC89 12T core rate | 1085 ns/NOP, ratio 12.0× vs STC12 | **1** |
| PCA 8-bit PWM duty 33/50/75% | 32.83% / 50.05% / 75.07%, period 277,561 ns | 2b |
| PCA 16-bit compare/match (servo 90°) | 1499.6 µs pulse, 20,000.0 µs frame = 50.0 Hz | 2b |
| WS2812 NeoPixel 4 pulse widths | T0H=362, T1H=814, T0L=814, T1L=452 — all in spec | **1** |
| UART TX bit period | 86.8 µs exact (BRT at 115200) | 2b |
| LCD I2C protocol (14 tests) | START/addr/data/STOP, HD44780 init, SCL timing v2 in spec | 3 |
| Cube refresh | 124.1 Hz, 8.059 ms frame | 2b |
| Motor duty 33/50/75% | 32.83% / 50.05% / 75.07% at P1.4 | 2b |

See `CLOSE-OUT.md` for the full table with bench IDs, and `RESULTS.md`
for detailed methodology.

## What is NOT done

- **ADC analog path** — register sequence verified, voltage-to-code is not (`BENCH-ADC`)
- **UART RX** — TX has bit timing (BRT model); RX has `-inject` for scheduled delivery but no baud-mismatch detection
- **SPI, comparator, power modes** — absent (see `PARITY-GAPS.md`)
- **31 BW_STUB device helpers** — compile but do nothing on hardware (by design — the simulator is the consumer, not the emulator)
- **No silicon verification** for any measurement

## Build

```
cd ucsim
./configure
make -j$(nproc)
```

The binary is `ucsim/src/sims/s51.src/ucsim_51`.

### Trace binary (headless differential execution)

```
cd ucsim/src/sims/s51.src
make stc12_trace
```

Or manually:
```
gcc ... -o stc12_trace stc12_trace.o [objects] [libs]
```
(see `Makefile.in` for the full link line)

Usage:
```
./stc12_trace [-t STC12|STC15|STC89|STC15W] [-fosc Hz] [-until-ns N] [-inject TIME_NS,BYTE] firmware.hex
```

`-inject` schedules a byte delivery to the UART RX path at a point in
simulated time. The serial model counts bit periods before raising RI.
Injected bytes always arrive intact regardless of baud configuration —
baud mismatch is not modelled.

## Test

```
./tests/run_all.sh          # 8 suites, all must pass
```

Individual suites:

| Suite | Command | What it checks |
|---|---|---|
| Smoke (29 tests) | `./tests/smoke.sh` | All 4 parts, peripheral presence/absence, 12T timing |
| Timing (6 tests) | `./tests/rung_timing.sh` | NOP rate × 4 parts, 12× difference, timer equivalence |
| Model difference (6 tests) | `./tests/rung_model_diff.sh` | AUXR effect, Timer 1 absence — controls that MUST differ |
| Baud (7 tests) | `./tests/rung_baud.sh` | BRT reload, T2 reload, naive-port failure, register values |
| NeoPixel (4 tests) | `./tests/rung_neopixel.sh` | T0H/T1H/T0L/T1L against WS2812 spec windows |
| Multi-part diff (9 tests) | `./tests/multipart_diff.sh` | Cross-emu STC89, cross-part STC12=STC15=STC15W |
| Cross-part examples (9 tests) | `./tests/crosspart_examples.sh` | 9 example bundles identical on 3 parts |
| Example diff (9 tests) | `./tests/examples_diff.sh` | Cross-emu STC12, requires `EMU_TRACE` |
| LCD I2C (14 tests) | `./tests/rung_lcd_i2c.sh` | I2C protocol edges, HD44780 init, SCL timing |
| AVR blink (8 tests) | `./tests/rung_avr_blink.sh` | Hand-assembled AVR cycle counts vs avr8js |
| AVR oracle (22 tests) | `./tests/rung_avr_oracle.sh` | simavr vs avr8js: blink, UART, ADC, timers, scheduler |
| NeoPixel cross-emu (cat 1) | `./tests/rung_neopixel_cross.sh` | ucsim vs emu8051, 144 edges, max diff 1 ns |

Cross-emulator tests need `emu_trace` from emu8051-stc (set `EMU_TRACE`).

## Shared contract

Peripheral behaviour follows
[STC12-PERIPHERAL-MODEL.md](https://github.com/CrispStrobe/stc12c5a60s2-lab/blob/main/docs/STC12-PERIPHERAL-MODEL.md).
The emu8051-stc fork implements the same spec. Resolutions must be
recorded in the spec first, then adopted by both implementations.

**Named trap:** there is no `IE.EC` on the STC12. IE bit 6 is `ELVD`
(Low Voltage Detection). The PCA interrupt is enabled per-module via
`CCAPMn.ECCF0` and `CMOD.ECF`, not via a global IE bit. Verified
against SDCC's `mcs51/stc12.h` (independent source, category 1).
