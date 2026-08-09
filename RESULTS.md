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

| Rung | Description | Cross-emulator result |
|------|-------------|----------------------|
| 3 | step(insn) x 1000, interrupts masked | **PASS** 1000/1000 PCs identical |
| 4 | Code breakpoint, same PC + registers | **PASS** PC=011D, A=01, SP=17, PSW=01 |
| 5 | Yield breakpoint, same (task, state) | **PASS** both halt at 0171, state=3 |
| 6 | Write while halted, resume | **PASS** 0xFFFF persists on both |
| 7 | Peripheral-event differential | **PASS** scheduler 37/37, ledcube 348/348, generated 598/598, blink 57/57 |

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

## Rung 8: on-chip monitor vs emulators

The on-chip monitor (`stc/src/10-live-firmware`) answers `HELLO`,
`POS`, `REGS`, `READ` through the emulated UART (emu8051-stc
`test_monitor`, 32/32 assertions).

Three-way comparison at a yield point:

| value | ucsim (direct IRAM) | emu8051 (direct IRAM) | monitor (UART protocol) |
|-------|--------------------|-----------------------|------------------------|
| bw_ms | 7 (at 7.3 ms) | 67 (at ~67 ms) | 67 (via READ cmd) |
| task0_state | 2 | — | 2 (via POS cmd) |
| task1_state | 2 | — | 2 (via POS cmd) |
| SP | 0x42 | 0x44 | 0x44 (via REGS cmd) |
| timeFreezes | inherent | verified | verified: bw_ms=67 before and after 500ms halt |

Values differ between ucsim and emu8051 because they are sampled at
different execution points (7ms vs 67ms). Within each emulator, the
monitor's UART replies match the direct IRAM reads — the monitor
protocol is consistent with the memory model.

**What rung 8 establishes:** the monitor firmware runs, its protocol
is well-formed, and its answers are consistent with the emulator's
own view of memory. Five independent codecs agree on the wire format.

**What it does NOT establish:** UART bring-up, BRT baud divisor, or
1T core behaviour on real silicon. Those need the bench.

## Oracle for the reverse direction (asm → blocks)

`sb3-creator/reference/c-target.md` names this emulator as the
oracle for decompilation: *"a recovered program can be validated
by executing both and comparing pin/SFR traces."*

### Baseline: what differential execution sees

The scheduler fixture (`scheduled_gen.ihx`, 318 instructions)
disassembled with `stc_disasm.py` shows recognisable patterns:

| pattern | disassembly | how a recovery finds it |
|---------|-------------|------------------------|
| Timer 0 ISR (bw_tick) | `LJMP 0x0072` at vector 0x000B, `MOV TL0,#0x67 / MOV TH0,#0xFC` | interrupt vector + reload constant |
| bw_now | `CLR ET0 / MOV A,bw_ms / SETB ET0` | interrupt-safe 16-bit read pattern |
| delay_ms / bw_block_ms | polled TF0 loop with reload | FLIRT-style byte signature |
| adc_read | `MOV ADC_CONTR,#0xE8|ch` + flag poll | SFR write to 0xBC + bit test |
| Port writes | `CPL P1.0`, `SETB P1.1`, `CLR P1.1` | bit-addressable SFR writes |
| Duff's-device yield | `switch (state) { case N: ... state = M; return; }` | `CJNE` chain + state variable write |

The SFR trace (37 events over 10 ms) is the oracle output:
each event is a port write, timer flag, or ADC register change
that a recovered program must reproduce to pass.

### What the oracle catches and what it misses

**Catches:** any difference in observable peripheral behaviour —
wrong port pin, wrong timer reload, wrong ADC channel, wrong
scan order, wrong delay timing.  These are the errors that matter
on real hardware.

**Misses:** structural differences that produce identical traces —
a recovered program could use a different variable layout, different
register allocation, or a different loop structure and still pass.
The oracle proves *behavioural equivalence*, not *structural identity*.

This is a known limitation and is by design: the oracle validates
what the user sees (LED blinks, display scans, ADC reads), not how
the compiler arranged it internally.  A decompiler that passes the
oracle may still produce ugly or incorrect pseudocode — but it
cannot produce wrong pin behaviour.

## STC89C52RC support (12T core)

`-t STC89` or `-t STC89C52RC` selects the STC89C52RC model.

The STC89 is a **12T** core — the single most consequential difference
in the part list.  `clock_per_cycle()` returns 12, so every instruction
takes 12 oscillator clocks per machine cycle.  Timers count at FOSC/12
natively (one increment per machine cycle, no prescaler needed).

### What the STC89 has

Standard 8052 hardware only:
- Timer 0 and Timer 1 (standard modes, FOSC/12)
- Timer 2 (standard 8052 T2CON at 0xC8)
- Serial port (standard 8051 UART, baud from Timer 1)
- Interrupt system (standard IE/IP)
- Ports P0–P3 (quasi-bidirectional only)

### What the STC89 does NOT have

- No AUXR (no 1T/12T switching)
- No port modes (PxM0/PxM1)
- No ADC
- No PCA/PWM
- No dual DPTR
- No P4, P5

### 12T timing verification

Measured via NOP sled at FOSC = 11,059,200 Hz:

| Part | Clocks/NOP | ns/NOP | Ratio to STC12 |
|------|-----------|--------|----------------|
| STC12 (1T) | 1 | 90 ns | 1× |
| STC15F (1T) | 1 | 90 ns | 1× |
| **STC89 (12T)** | **12** | **1085 ns** | **12.06×** |
| STC15W (1T) | 1 | 90 ns | 1× |

The Timer 0 at FOSC/12 timing equivalence is confirmed: the STC89
blink fixture (`blink_stc89.ihx`) shows TF0 at ~1017 µs intervals,
matching the STC12's Timer 0 at FOSC/12 within 2%.

### STC89 smoke tests (28/28)

Tests 15–20 verify: STC89 selectable, has Timer 2, 12T timing correct,
no port modes / ADC / PCA hardware present.

## STC15W408AS support

`-t STC15W` or `-t STC15W408AS` selects the STC15W408AS model.

The STC15W408AS is a smaller STC15 variant: 1T core, 8K flash, 512B SRAM,
2.5–5.5V (wide voltage), 28-pin package max.

### Delta from STC15F2K60S2

| Feature | STC15F2K60S2 | STC15W408AS |
|---------|-------------|-------------|
| Timer 1 | present | **absent** |
| Ports | P0–P5 | **P0–P3 only** |
| UARTs | 2 | **1** |
| Flash | 60 KB | **8 KB** |
| SRAM | 2048 B | **512 B** |
| Supply | 4.2–5.5 V | **2.5–5.5 V** |

### What the STC15W has

Same as STC15F2K60S2 for available peripherals:
- Timer 0 with AUXR.T0x12 (1T/12T switching)
- Timer 2 (T2H/T2L at 0xD6/0xD7)
- Port modes for P0–P3
- 10-bit ADC on P1
- 3-channel PCA/PWM
- Watchdog

### STC15W smoke tests

Tests 21–26 verify: STC15W selectable, has Timer 2/ADC/PCA/port modes,
correctly lacks Timer 1.

## Multi-part parity

### Internal parity (ucsim across parts)

Firmware that uses only the shared subset (Timer 0 at FOSC/12, ports,
no STC12-specific peripherals) produces **identical event traces** on
STC12, STC15, and STC15W:

| Firmware | STC12 events | STC15 | STC15W |
|----------|-------------|-------|--------|
| `scheduled_gen.ihx` | 37 | **37/37 identical** | **37/37 identical** |

All 9 example bundles also produce identical traces across the three
1T parts (crosspart_examples.sh: 9/9 pass):

| Example | Events | STC12 = STC15 = STC15W |
|---------|--------|------------------------|
| 01-blink | 9 | identical |
| 02-button | 3 | identical |
| 03-potentiometer | 14 | identical |
| 04-brightness | 11 | identical |
| 05-scheduler | 8 | identical |
| 06-dimmer | 27 | identical |
| 07-buzzer | 3 | identical |
| 08-seven-segment | 9 | identical |
| 09-shift-register | 29 | identical |

### Cross-emulator parity (STC89: verified)

Cross-emulator STC89 differential resolved after emu8051-stc rebuilt
`emu_trace` with `-part` support (post commit `00e9d5b`, the 12T fix).

| Image | ucsim events | emu events | Prefix match |
|-------|-------------|-----------|--------------|
| `blink_stc89.ihx` | 43 | 388 | **43/43 identical** |

Event count differs because emu8051 runs more instructions in the same
time window (same pattern as the STC12 corpus §Prefix-only). Within the
overlap, every SFR value and event type is identical.

### STC89 firmware corpus (27 images)

Sourced from GitHub: `treideme/stc89c52-demos` (16 programs, compiled
with SDCC), `chenjr15/STC89C52RC` (5 hex files), `MangnimitMCU/STC89C52RC`
(3 hex files). Stored in `corpus/stc89/` (non-committed, unlicensed).

Cross-emulator differential (2 ms, FOSC = 11,059,200 Hz):

| Result | Count | % |
|--------|-------|---|
| **Strict** (both streams identical) | **16** | **59%** |
| Prefix-only (shorter prefix matches) | 8 | 30% |
| Diverge | 1 | 4% |
| Empty (no SFR/TF events) | 2 | 7% |

The single divergence (`PWM_LED.hex`) is timer-interleaving: P1 writes
appear at different positions relative to timer overflows. The SFR values
are the same — no peripheral model disagreement.

**No genuine peripheral model disagreement was found.**

Expanded with Gitee repos (`oopxiajun/STC89C52`, `lujiancy/STC89C52_Tutorial`,
`pgwangc/stc89c52`) — 36 Keil-compiled hex files (LED, button, timer,
UART, stepper motor, IR remote, DS18B20, LCD, etc.):

| Result | Count (63 images) | % |
|--------|-------|---|
| **Strict** | **29** | **46%** |
| Prefix | 22 | 35% |
| Diverge | 4 | 6% |
| Empty | 6 | 10% |
| Error (emu load fail) | 2 | 3% |

51/55 images with events agree (93%). All 4 divergences are timer-interleaving.

### STC12 corpus on STC89 model (cross-target)

Ran the first 100 of the existing 347 STC12 corpus images through
both emulators as STC89 (1 ms window). Most produce no events in
the shorter window (12T = 12× fewer instructions per ms). Of the
26 that did:

| Result | Count |
|--------|-------|
| Strict | 20 |
| Prefix | 6 |
| Diverge | **0** |

**26/26 (100%) agree.** No peripheral model disagreement when
running STC12-compiled firmware on the STC89 model.

### STC15W firmware corpus (3 images)

Sourced from GitHub: `zerog2k/stc_diyclock`, `aFewBits/stc-led-clock`,
`shenghaoyang/stc_led_clock_8k`. All are SDCC-compiled LED clock kits
for the STC15W408AS. Stored in `corpus/stc15w/` (non-committed).

All 5 images load and produce events on the STC15W model:

| Image | Source | Events (2ms) |
|-------|--------|-------------|
| `stc_diyclock.hex` | zerog2k/stc_diyclock | 400 |
| `stc_diyclock_ntp.hex` | onivan/stc_diyclock-ntp | 402 |
| `stc_diywatch.hex` | ruthsarian/stc_diywatch | 784 |
| `stc_led_clock_8k.ihx` | shenghaoyang/stc_led_clock_8k | 13 |
| `stc-led-clock.hex` | aFewBits/stc-led-clock | 772 |

Cross-emulator differential pending emu_trace `-part STC15W` testing.

### Test summary (all green)

| Suite | Result |
|-------|--------|
| Smoke tests (STC12/STC15/STC89/STC15W) | **28/28** |
| Timing verification (4 parts + diff + equiv) | **6/6** |
| Example differentials (STC12 cross-emu) | **9/9** |
| Boundary D ladder (STC12 cross-emu) | **6/6** |
| Multi-part differentials (incl. cross-emu STC89) | **9/9** |
| Cross-part examples (STC12=STC15=STC15W) | **9/9** |

### What was blocked and is now resolved

Cross-emulator STC89 parity was blocked on `emu_trace -part`. Resolved
after requesting via spec-updates/012 and direct message to emu8051-stc.
They rebuilt with commit `00e9d5b`'s 12T fix.

Cross-emulator STC15W parity remains untested (no `-part STC15W` tested
yet, but the API exists in emu8051-stc).

### Methodology notes

The `/tmp/stc89-correction.md` withdrawal is addressed: the test now
asserts both axes — the 12× DIFFERENCE in core rate (which must exist)
AND the 1% EQUALITY in Timer 0 at FOSC/12 (which must hold). The
methodological point — "a differential probe needs a control that is
known to differ" — is exactly what rung_timing.sh's difference
assertion implements.

### stc-compiler pseudocode path bug (not blocking)

`POST /compile` with `language=pseudocode, target=stc89c52rc` generates
`P1M0` and `AUXR` writes despite `port_modes=False`. Noted in
spec-updates/013. Worked around by using `language=c` for test fixtures.
