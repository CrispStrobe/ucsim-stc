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

All compiled with `sdcc -mmcs51 --model-small` (SDCC 4.2.0) or the
hosted compiler.
