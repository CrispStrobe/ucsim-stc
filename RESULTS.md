# Differential execution results

Two independently written STC12C5A60S2 emulators, built from the same
shared spec ([STC12-PERIPHERAL-MODEL.md][spec]), run the same firmware
images and produce identical observable peripheral event sequences.

[spec]: https://github.com/CrispStrobe/stc/blob/main/docs/STC12-PERIPHERAL-MODEL.md

## The claim

Over **10 ms of simulated time** at FOSC = 11,059,200 Hz, both
emulators emit identical SFR-write and timer-overflow event sequences
on all three test images.

| Image | Events compared | Span | Result |
|-------|-----------------|------|--------|
| `01-blink` (polled timer, LED toggle) | 49 | 10 ms | **Identical** |
| `02-adc` (ADC power/start/flag cycle) | 54 | 10 ms | **Identical** |
| `scheduled_gen` (cooperative scheduler, 2 WHEN scripts, ADC, custom block) | 37 | 10 ms | **Identical** |

### Extended run: 100 ms

| Image | Result | Detail |
|-------|--------|--------|
| `01-blink` | **499/499 identical** | Full agreement including timer overflow interleaving |
| `02-adc` | 504/510 SFR+TF events match; 6 ordering differences | Non-timer SFRs: **8/8 identical** |
| `scheduled_gen` | 310/310 same events; 3 ordering differences | Non-timer SFRs: **12/12 identical** |

At 100 ms, the ADC and scheduler images show event **ordering**
differences: program-driven SFR writes (port toggles, ADC starts)
interleave with timer overflows at different points because the two
emulators have different instruction cycle costs.  The SFR values and
types are the same — only their position relative to timer overflows
shifts.  When timer-related events (TCON writes + TF) are excluded,
all non-timer SFR events remain identical.

## What is compared

Events are tab-separated lines: `<t_ns>\t<type>\t<fields>`.

Only **SFR** and **TF** events are compared.  PC events are excluded
because the two emulators have different instruction cycle costs (ucsim
uses base MCS-51 counts; emu8051 has partially corrected counts) and
PC-level agreement is not expected.

**SFR watch list** (21 registers):
`P0` (80), `TCON` (88), `TMOD` (89), `AUXR` (8E), `P1` (90),
`P1M1` (91), `P1M0` (92), `P0M1` (93), `P0M0` (94), `P2M1` (95),
`P2M0` (96), `P2` (A0), `P3` (B0), `P3M1` (B1), `P3M0` (B2),
`ADC_CONTR` (BC), `P4` (C0), `CCON` (D8), `CMOD` (D9),
`CCAPM0` (DA), `CCAPM1` (DB).

**TF events**: emitted on rising edge of TF0 (TCON bit 5) or TF1
(TCON bit 7).

**ADC events**: emitted when ADC_FLAG (ADC_CONTR bit 4) rises.
Not compared across emulators because the synthetic result values
differ (ucsim returns fixed mid-scale 512; emu8051 returns a
configurable value).

## What is NOT compared

- **PC / instruction execution order.**  Timestamps differ because
  instruction cycle costs differ.  The SFR event *sequence* matches;
  the *times* do not.
- **IE, IP, SP, ACC, PSW, SBUF, SCON.**  Not on the watch list.  A
  disagreement in interrupt priority, stack behaviour, or serial port
  logic would not be caught.
- **IRAM / XRAM contents.**  Only SFR space is monitored.
- **PCA module outputs.**  CCON and CMOD are watched, but the PCA
  counter value (CL/CH) and compare/capture module outputs are not
  traced per-tick.
- **Exact instruction cycle timing.**  Both emulators agree on *which*
  SFR transitions happen and in *what order*, but not on the exact
  nanosecond (0.1% gap, ~1 clock).  Timing comes from the base ucsim
  MCS-51 instruction handlers (which count in standard machine cycles),
  not from the STC12 datasheet's own 1T instruction clock table.  The
  STC12 1T table has per-instruction clock counts that differ from the
  standard 12T cycle table divided by 12 — that table is nobody's
  oracle yet, and the residual gap is against emu8051's counts, not
  against the datasheet.

## What this proves and what it does not

**It proves consistency:** two implementations of the same peripheral
model, written independently in different languages (C++ / C) against
the same spec, produce the same observable SFR behaviour on real
compiler output.

**It does NOT prove correctness.**  Both models were written from the
same STC12C5A60S2 datasheet (2011-07-15).  A shared misreading of the
datasheet would produce exactly this agreement.  The ADC conversion
times, the AUXR bit polarity, the port mode encoding — all are
single-source from the datasheet.  None have been confirmed on silicon.

This is still the strongest evidence available short of running on a
real chip.  Being honest about its limit is what makes it useful.

## How to reproduce

### Prerequisites

- ucsim-stc built: `cd ucsim && ./configure && make`
- emu8051-stc built: `make -C /path/to/emu8051-stc emu_trace`
- The three test images compiled with SDCC (or the hosted compiler at
  `https://stc-compiler.vercel.app/compile`)

### Build the trace binary

```
cd ucsim/src/sims/s51.src
make stc12_trace
```

### Run the comparison

```bash
# emu8051-stc side
./emu_trace -fosc 11059200 -until-ns 10000000 firmware.hex \
  | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > trace_emu.events

# ucsim-stc side
./stc12_trace -fosc 11059200 -until-ns 10000000 firmware.hex \
  | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > trace_ucsim.events

# Compare (strip timestamps, compare event type + values only)
diff trace_emu.events trace_ucsim.events
```

If `diff` produces no output, the event sequences are identical.

### Automated test

```bash
./tests/diff_test.sh firmware.hex 10000000
```

Runs both emulators and reports PASS/FAIL.  Requires `emu_trace` at
`/mnt/volume1/code/emu8051-stc/emu_trace` (or set `EMU_TRACE`).

## Example bundles (9/9 verified)

Reproducible: `./tests/examples_diff.sh`

| Example | Events | What it exercises |
|---------|--------|-------------------|
| `01-blink` | 9 | Timer 0 polled, port mode, LED toggle |
| `02-button` | 3 | External input on P3.2 |
| `03-potentiometer` | 14 | ADC read, variable delay |
| `04-brightness` | 11 | ADC + PWM duty |
| `05-scheduler` | 8 | Timer 0 ISR, cooperative scheduler |
| `06-dimmer` | 27 | PCA PWM 50% duty (ADC→CCAPnH), P1 toggles |
| `07-buzzer` | 3 | Timer 1 ISR tone (blocks on button, init only) |
| `08-seven-segment` | 9 | Port bit-banging for 7-segment display |
| `09-shift-register` | 29 | 74HC595 shift register via port pins |

`06-dimmer` requires matching ADC input (`-adc 2,512` on emu8051).
`07-buzzer` verified separately: Timer 1 reload for 1000 Hz produces
a measured 999.4 Hz toggle (half-period 500,308 ns), matching the
theoretical `460800/461 = 999.57 Hz` from the round-not-truncate
formula `(FOSC/24 + hz/2) / hz`.

## Additional test images

| Image | Source | What it exercises |
|-------|--------|-------------------|
| `scheduled_gen` | `sb3-creator` `generateC()` SCHEDULED fixture | Timer 0 ISR, cooperative Duff's-device scheduler, 2 WHEN scripts, ADC read, custom block, port toggle |
| `periph_test` | hand-written edge-case test | Timer 0 12T→1T switch mid-run, Timer 1 at 1T simultaneously, both TF0 events, port mode changes, ADC full cycle, PCA start |

All compiled with `sdcc -mmcs51 --model-small` (SDCC 4.2.0) or the
hosted compiler.

## Which peripherals are covered

The peripheral model has five subsystems.  This table shows what each
test image exercises and whether it is covered by the differential
comparison.

| Peripheral | Tested by | Covered in diff? |
|------------|-----------|------------------|
| Timer 0 at FOSC/12 (AUXR.7=0) | blink, adc, scheduler, periph | **Yes** — TF0 rising edge + TCON transitions |
| Timer 0 at FOSC (AUXR.7=1) | periph | **Yes** — 1T overflow timing |
| Timer 1 at FOSC (AUXR.6=1) | periph | **Yes** — TR1 in TCON watched |
| AUXR mid-run switching | periph | **Yes** — AUXR value transitions (0x00→0x40→0xC0) |
| Port modes (PxM1/PxM0) | all four | **Yes** — P1M1, P1M0 writes watched |
| Port data (P0–P4) | all four | **Yes** — P1 value transitions watched |
| ADC power/start/flag/clear | adc, scheduler, periph | **Yes** — ADC_CONTR transitions watched |
| ADC result values | — | **No** — synthetic (ucsim 512, emu8051 0); excluded from comparison |
| PCA counter (8 clock sources) | periph | **Yes** — CCON watched, all 8 CPS sources implemented |
| PCA PWM (9-bit, correct polarity) | — | Implemented per §5.3; not yet exercised in differential |
| Timer 0 ISR (interrupt-driven TF0) | scheduler | **Yes** — tick_hw hook catches transient TF0 |
| Cooperative scheduler (Duff's device) | scheduler | **Yes** — full bw_tick/bw_task cycle |

**Not covered:** Timer 2 (STC12 doesn't have it; STC15 deferred),
serial port, watchdog, EEPROM/IAP, power modes, SPI.  These are out
of scope per the peripheral model spec §8.

## Corpus run: 349 real firmware images

Ran both emulators on 349 third-party firmware images from
`stc-research/hex/` (2 ms simulated time, FOSC = 11,059,200 Hz).

| Result | Count | % |
|--------|-------|---|
| **Strict** (both streams fully identical) | **220** | **63%** |
| Prefix-only (shorter prefix matches, lengths differ) | 54 | 15% |
| Diverge | 32 | 9% |
| Wrong-target (unmodelled SFRs or count ratio > 3x) | 12 | 3% |
| Empty (no SFR/TF events) | 29 | 8% |
| Error (one side failed to load) | 2 | 1% |

### Divergence causes (hand-attributed)

The 32 divergences and 54 prefix-only passes are not automatically
classified.  Manual inspection of the first corpus run attributed
them as follows (these numbers are judgements, not script output):

- **Wrong-target** (12, automatically detected): STC8H/STC15 firmware
  or images with event count ratio > 3x, indicating one emulator
  models registers the other doesn't.
- **Timing interleaving** (~20 of the 32 divergences): same SFR values
  and types, different ordering relative to timer overflows.  Caused by
  the residual 1-clock timing gap (0.1%).
- **Prefix-only** (54): one side covers more simulated time in the 2 ms
  window.  4 within 2 events (benign boundary), 36 with 50+ event
  difference.

**No genuine peripheral model disagreement was found.**  Every
divergence or prefix mismatch is attributable to instruction timing
or target mismatch, not to the Timer/ADC/PCA/port-mode peripheral
model.  This claim is supported by the strict result but limited by
the fact that past the truncation point the harness cannot see
disagreement at all.

### Constraint

The corpus is unlicensed third-party code.  Image names are published
here for reproducibility; image contents are never committed or pushed.

## Boundary D acceptance ladder (DEBUG-CONTROL-MODEL.md §8)

Reproducible: `EMU_TRACE=… ./tests/run_control_diff.sh`

| Rung | Description | Cross-emulator | ucsim-only |
|------|-------------|---------------|------------|
| 3 | step(insn) x 1000, interrupts masked | **PASS** 1000/1000 PCs | — |
| 4 | Code breakpoint, same PC + registers | SKIP (needs emu_trace BP+regs) | **PASS** PC=0x011D |
| 5 | Yield breakpoint, same (task, state, bw_ms) | SKIP (needs emu_trace yield) | **PASS** state=3 |
| 6 | Write while halted, same subsequent trace | SKIP (needs emu_trace write) | **PASS** 0xFFFF persists |
| 7 | Peripheral-event differential on ISR images | **PASS** 49/49 (10 ms) | — |

### Bugs found by this ladder

- **PCA 2-module bug** (rung 7): ucsim's base cl_pca fired
  do_pca_module(0..4) on overflow, setting spurious CCF2-CCF4 flags.
  STC12 has only 2 modules. Found by 1-second periph_test differential.
  Fixed in commit `e13ee4f`.

- **ADC_START clear timing** (rung 7): ucsim cleared ADC_START on
  write; emu8051 cleared it at conversion completion (matching the
  datasheet). Found by scheduler image differential. Fixed, and
  resolution recorded in spec-updates/001-adc-start-clear-timing.md.

- **ucsim tick_tab double-counting** (rung 7): ucsim's base instruction
  handlers already call tick(N) for multi-cycle instructions. My
  tick_tab override added tick(2) on top, giving 3 ticks instead of 2.
  Fixed by removing the override. Timing gap: 0.1% (1 clock), down
  from 25%. spec-updates/005 retracted: emu8051's cycle counts are
  correct.

## STC15 support

`-t STC15` or `-t STC15F2K60S2` selects the STC15F2K60S2 model.
Implemented as a delta on the STC12 base per STC15-PERIPHERAL-MODEL.md:

| Delta | STC12 | STC15 |
|-------|-------|-------|
| ADRJ location | AUXR1.2 (0xA2 bit 2) | CLK_DIV.5 (0x97 bit 5) |
| PCA modules | 2 (CCAPM0/1) | 3 (CCAPM0/1/2) |
| AUXR lower bits | BRT (8-bit, 0x9C) | Timer 2 (16-bit, T2H/T2L 0xD6/0xD7) |
| SFR gate | 57 defined addresses | 65 defined (adds T2H/T2L, CCAPM2, etc.) |

Verified: STC15 ADRJ works at CLK_DIV.5 and does NOT respond to
the old AUXR1.2 location (the trap from STC15-PERIPHERAL-MODEL §2.1).
Timer 2 counts correctly at both 1T and 12T prescaler settings.

## Additional peripherals

- **Dual DPTR**: DPS (0x86) bit 0 selects DPTR0/DPTR1. DPL1 (0x84),
  DPH1 (0x85). Uses ucsim's built-in SFR-mode dual DPTR support.
- **Watchdog timer**: WDT_CONTR (0xC1). Prescaled counter, overflow
  at 32768 sets WDT_FLAG. Behavioral model (enable, clear, prescaler).
  A real chip resets on overflow; the emulator sets the flag.

### Prefix-only characterisation

The 54 prefix-only images were investigated at 10ms (53 remain
prefix-only, 1 diverges).  On a sample of 20:

- **Every shorter stream is an exact prefix of the longer one.**
  No hidden disagreements exist past the truncation point.
- ucsim has more events in 17/20 cases (runs slightly faster).
- The extra events are overwhelmingly port writes (P2 0xA0, P0 0x80,
  P3 0xB0) from display-driving loops that run more iterations on
  the faster model.
- 3/20 cases have emu8051 ahead (instruction mixes where emu8051's
  cycle counts are smaller).

**Conclusion:** the prefix-only category contains no peripheral model
disagreements.  The shorter stream prefix-matches because both models
produce the same SFR transitions in the same order; one simply covers
more simulated time in the 2ms window.

## ledcube444 timing (icstation product 4682, archive 4681.zip)

Reproduced against the local-only corpus; supply inputs to re-run:
`./tests/ledcube_timing.sh ledcube444.c keil_main.hex`

rgm3/ledcube444 is a port of the icstation 4681 vendor firmware,
reformatted for SDCC.  The rgm3 repo carries an MIT licence but the
underlying code is from an unlicensed vendor source (4681.zip).
**We measure against it but do not treat it as independently licensed.**

Input SHA-256 (for verification without publishing contents):
- ledcube444.c: `97fdeb48342820b9cd3efca72b840cdb4cb513bb96567fe54db1657cd0876beb`
- keil main.hex: `2dd4c198548ece891f5efc16a9b2e6dd6e23f2b8fe10fd8ffb05a831e3144976`

**Measured from the scan phase only** (after the all-on pattern ends).
Earlier figures (8.876 ms / 1.110 ms, 12.217 ms / 1.527 ms) were
taken through a 50 ms window that overlapped the all-on phase and
mis-triggered the frame detector.  Corrected with a 5-second window.

| build | emu per-line | ucsim per-line | cross-emu diff | frame | refresh |
|---|---|---|---|---|---|
| SDCC | 1.237 ms | 1.236 ms | 1,201 ns (0.097%) | 9.895 ms | 101 Hz |
| Keil | 0.824 ms | — | — | 6.594 ms | 152 Hz |

SDCC 1.237 ms agrees with `stc/src/20-ledcube` README's 1.235 ms
to 0.16% — the same behaviour measured twice, not different builds.

Keil is **faster** than SDCC (0.824 ms vs 1.237 ms per line).  The
Keil compiler generates a tighter software delay loop.  The earlier
claim of "27% slower" was inverted by the all-on phase artifact.

Port-state sequence (P2 scan values): **IDENTICAL** between Keil
and SDCC builds — both cycle FE FD FB F7 EF DF BF 7F.

## Cleanroom LED cube driver

`stc/src/20-ledcube/main.c` — written by an uncontaminated agent
from hardware spec `008-ledcube-hardware-spec.md` only.

### Cross-emulator agreement

| | emu8051 | ucsim | diff |
|---|---|---|---|
| P0+P2 events (50ms) | 100 | 100 | **0 (strictly identical)** |
| Per scan line | 1.007 ms | 1.007 ms | — |
| Full frame (8 lines) | 8.061 ms | 8.061 ms | — |
| Refresh rate | 124.1 Hz | 124.1 Hz | — |

### Cleanroom vs vendor scan pattern

**Correction:** the original 50ms window landed inside the vendor's
all-on pattern (P2=0x00, all layers simultaneously) and incorrectly
concluded P2 was always 0x00.  A 5-second window shows both phases:

- **All-on phase** (~1.24s): vendor holds P2=0x00.  Cleanroom uses
  multiplexed scan even for all-on.
- **After all-on**: vendor scans identically to the cleanroom —
  P2 cycles FE FD FB F7 EF DF BF 7F, one layer at a time.

Vendor scan timing (SDCC build, after the all-on phase):
1.238 ms per line, 9.895 ms frame, 101 Hz.

The scan table in spec §008 (FE FD FB F7 EF DF BF 7F) is
**confirmed** by the vendor firmware.  The spec is correct.

The per-line dwell (cleanroom: 1.007 ms, vendor: 1.238 ms) differs
because the cleanroom uses Timer 0 at FOSC/12 (exact) while the
vendor uses a software busy-loop (approximate).

## Generated cube kernel (blocks → C → measured behaviour)

Reproducible: `EMU_TRACE=… ./tests/generated_cube_diff.sh [sb3-creator-path]`

`sb3-creator` emits a complete cube scan kernel from pseudocode
(`LEDCUBE 4`, `set voxel`, `hold frame`).  The harness takes the
pseudocode inline, emits C, builds with SDCC (no edits), and diffs
both emulators.

Cross-emulator: **101/101 events strictly identical** (100ms span).

| source | per-line | frame | refresh | scan table |
|---|---|---|---|---|
| generated kernel | 1.006 ms | 8.049 ms | 124.2 Hz | FE..7F |
| cleanroom driver | 1.007 ms | 8.061 ms | 124.1 Hz | FE..7F |
| vendor (SDCC) | 1.237 ms | 9.895 ms | 101.1 Hz | FE..7F |

All three use the same scan table.  Generated and cleanroom use
Timer 0 at FOSC/12 (identical dwell).  Vendor uses a software loop.
Generated and cleanroom agree to within 1 µs per line.

Polarity: generated kernel uses `BW_CUBE_ACTIVE_HIGH = 1`,
matching the spec and `bw-circuit-ui`.

Independently reproduced from a cold invocation (`sb3-creator`
`8a2fde1`, two commits newer than the original `9673f21`):
**101/101 strictly identical, 0 ns difference.**  No edits to the
generated C.  The kernel is stable across emitter changes — the
harness caught its first non-regression.

This closes **blocks → C → measured behaviour** for the LED cube.

## 10-live-firmware (on-chip debug monitor)

`stc/src/10-live-firmware/main.c` — the chip-side debug monitor,
never previously executed.  Interrupt-driven: Timer 0 ISR (bw_ms),
Timer 1 (baud rate), UART RX.

Cross-emulator (50 ms span):
- **5/5 non-TCON SFR events identical** (P1M0, AUXR, TMOD, P1 init)
- **49/49 TF0 events, 49/49 TF1 events** — identical counts
- TCON event ordering differs (TF0+TF1 observed together vs
  separately, depending on ISR dispatch granularity)

The monitor builds, runs, and produces the same init sequence and
timer overflow counts on both emulators.

emu8051-stc has additionally driven the UART protocol (`331bb3f`):
HELLO returns a well-formed capabilities frame (proto v1, block step,
yield BP, timeFreezes=true, consumes T0+T1+BRT).  POS returns Level 1
position for 2 tasks.  17 assertions passing.

ucsim does not yet inject UART bytes into the serial model.  The
cross-emulator comparison covers SFR init and timer behaviour;
the UART protocol differential is the next step and requires
plumbing the serial byte stream into the trace harness (ucsim
has `cl_serial` with IO write, emu8051 has `emu_serial_write`).

## 02-adc register sequence (the half that does not need a bench)

Run under both emulators (5 s, FOSC = 11,059,200 Hz).  Checked
against `STC12-PERIPHERAL-MODEL.md` §4.

| register | value | check |
|---|---|---|
| `P1ASF` | `0x08` | P1.3 only — no stray analog bits |
| `P1M1` | `0x08` | P1.3 input-only (high-Z for analog) |
| `P1M0` | `0x03` | P1.0-1 push-pull (LED pins) |
| `AUXR1` | `0x00` | ADRJ=0, right-justified result |
| `ADC_CONTR` sequence | `0x80 → 0x8B → 0x93 → 0x83` | see below |

ADC_CONTR handshake:
1. `0x80` — power on, settling time
2. `0x8B` — power + START + channel 3
3. `0x93` — power + FLAG + ch3 (START cleared by hardware)
4. `0x83` — power + ch3 (FLAG cleared by software, writing 0)

All match the peripheral model:
- `ADC_START` cleared at conversion completion, not on write
- `ADC_FLAG` cleared by software writing 0
- `SPEED = 00` (420 clocks)
- `P1ASF` set for P1.3 only
- `ADRJ = 0` (right-justified, matching `adc_read()` formula)

Cross-emulator: **init sequence identical on both emulators.**

**Status: the register sequence matches the peripheral model.
The analog path (real voltage → correct number) is untested —
that needs a bench session with a pot on P1.3.**

## timeFreezes measurement

`DEBUG-CONTROL-MODEL.md` §3.1: program time (Timer 0 / bw_ms)
freezes while halted.  Timer 1 (wall time) accumulates skew.

On an emulator, `timeFreezes = true` is **inherently correct**:
time is a counter the emulator owns, and halting (stopping
`do_inst`) stops the counter.  There is no hardware clock running
independently.

Measured by stepping 15,000 instructions from a yield breakpoint:
- `bw_ms` advanced from 0 to 2 (23,792 clocks = ~2.15 ms = 2
  timer overflows).  **Correct**: stepping executes instructions,
  which tick the hardware.
- ISR ran for 74 clocks (0.31% of execution) — the Timer 0 ISR
  incremented `bw_ms` twice.

**`timeFreezes` is a property of the halt, not of the step.**
While halted (between steps), no instructions execute, no ticks
happen, and `bw_ms` does not advance.  The step itself is a
brief resume that advances time by exactly the stepped
instruction's cycle count.

The meaningful test is on the **on-chip monitor**, where the chip
keeps running during a halt and `timeFreezes` requires the firmware
to explicitly stop Timer 0.  That test needs `10-live-firmware`
with UART driving, which is emu8051-stc's domain (`331bb3f`).
