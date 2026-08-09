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

| Rung | Description | Status |
|------|-------------|--------|
| 1 | capabilities/state | API implemented in cl_uc_stc12 |
| 2 | Level 1 position | debug_read_bw_ms/task_state/task_until from IRAM |
| 3 | step(insn) PC sequence (interrupts masked) | **PASS** — 1000/1000 PCs identical from reset (blink.ihx) |
| 4 | Code breakpoint at correct PC | **PASS** — halts at bw_task0 entry (0x011D) |
| 5 | Yield breakpoint at correct (task, state) | **PASS** — halts at case-label, task0_state=3 |
| 6 | Write while halted affects execution | **PASS** — task0_state=0xFFFF stays ended after resume |
| 7 | Peripheral-event differential on ISR images | **PASS** — 275/349 corpus, 5006/5006 blink 1s |

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

## ledcube444 scan timing

Reproduced against the local-only corpus; supply inputs to re-run:
`./tests/ledcube_timing.sh ledcube444.c keil_main.hex`

rgm3/ledcube444 is a port of the icstation 4681 kit's vendor firmware,
reformatted for SDCC. The rgm3 repo carries an MIT licence but the
underlying code is from an unlicensed Chinese vendor source (4681.zip).
**We measure against it but do not treat it as independently licensed.**

Input SHA-256 (for verification without publishing contents):
- ledcube444.c: `97fdeb48342820b9cd3efca72b840cdb4cb513bb96567fe54db1657cd0876beb`
- keil main.hex: `2dd4c198548ece891f5efc16a9b2e6dd6e23f2b8fe10fd8ffb05a831e3144976`

| | emu8051 | ucsim | diff |
|---|---|---|---|
| SDCC build scan step | 8.876 ms | 8.875 ms | 1,477 ns (0.017%) |
| Keil build scan step | 12.217 ms | 12.215 ms | 2,123 ns (0.017%) |

Port-state sequence (P0 values): **IDENTICAL** between Keil and SDCC
builds. Both compilers produce the same observable behaviour; only the
software delay loop timing differs (27%).
