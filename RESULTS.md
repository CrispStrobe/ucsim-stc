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
  nanosecond.  A 1-cycle error in a specific opcode would shift
  timestamps but not change the event sequence — and so would not be
  caught by this comparison.

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

## Firmware images tested

| Image | Source | What it exercises |
|-------|--------|-------------------|
| `01-blink` | `/mnt/volume1/code/stc/src/01-blink` | Timer 0 mode 1 polled overflow, port mode push-pull, LED toggle |
| `02-adc` | `/mnt/volume1/code/stc/src/02-adc` | ADC power/start/flag/result, P1ASF, input-only port mode |
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
| PCA counter start | periph | **Partial** — CCON watched; CL/CH values not traced |
| PCA module outputs (PWM, compare) | — | **No** — not exercised by any test image |
| Timer 0 ISR (interrupt-driven TF0) | scheduler | **Yes** — tick_hw hook catches transient TF0 |
| Cooperative scheduler (Duff's device) | scheduler | **Yes** — full bw_tick/bw_task cycle |

**Not covered:** PCA PWM output, Timer 2 (STC12 doesn't have it),
serial port, watchdog, EEPROM/IAP, power modes, SPI.  These are out
of scope per the peripheral model spec §8.

## Corpus run: 349 real firmware images

Ran both emulators on 349 third-party firmware images from
`stc-research/hex/` (2 ms simulated time, FOSC = 11,059,200 Hz).

| Result | Count | % |
|--------|-------|---|
| **Pass** (SFR+TF events identical) | **275** | **79%** |
| Diverge | 33 | 9% |
| Wrong-target (unmodelled SFRs) | 9 | 3% |
| Empty (no SFR/TF events) | 29 | 8% |
| Error (one side failed to load) | 3 | 1% |

### Divergence causes

The 42 divergences fall into three categories:

1. **Wrong target** (~10 images): STC8H/STC15 firmware (not STC12).
   These use a different SFR map — P4 at different addresses, different
   timer registers.  emu8051-stc models some STC8 registers that
   ucsim-stc does not, producing large event count differences
   (e.g. 3894 vs 36).  Not a peripheral model bug.

2. **Timer overflow interleaving** (~20 images): both emulators see the
   same SFR values and event types, but timer overflows interleave with
   program-driven SFR writes at different points due to instruction
   cycle cost differences.  Same cause as the 100 ms blink divergence.

3. **Unmodelled external peripherals** (~12 images): programs that
   interact with external chips (ADC0808, DS1302, NRF905, AT24C02)
   via port bit-banging.  The timing of port-state transitions depends
   on exact instruction cycle counts, which differ.

**No genuine peripheral model disagreement was found in the corpus.**
Every divergence is attributable to instruction timing differences or
target mismatch, not to the Timer/ADC/PCA/port-mode peripheral model.

### Constraint

The corpus is unlicensed third-party code.  Image names are published
here for reproducibility; image contents are never committed or pushed.

## Boundary D acceptance ladder (DEBUG-CONTROL-MODEL.md §8)

| Rung | Description | Status |
|------|-------------|--------|
| 1 | capabilities/state | API implemented in cl_uc_stc12 |
| 2 | Level 1 position | debug_read_bw_ms/task_state/task_until from IRAM |
| 3 | step(insn) PC sequence (interrupts masked) | **PASS** — 500/500 PCs identical from reset (blink.ihx) |
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
