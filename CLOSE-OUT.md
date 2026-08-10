# ucsim-stc close-out

## What was verified (numbers, categories, bench IDs)

All measurements are **category 2b** (two models from the same datasheet) or
**category 1** (independent upstream codebases) as noted. Nothing has run on
silicon. Per `stc/docs/EVIDENCE-CATEGORIES.md`: *"Silicon remains the only
source independent of every document."*

### Category 1 — independent-source agreement

| Measurement | Result | Evidence |
|---|---|---|
| 8051 ISA on 347 real firmware images | 131 strict + 110 prefix + 20 interleave + 33 timing-count, **0 genuine disagreements** | ucsim (Drotos, GPL, C++) vs emu8051 (Komppa, MIT, C) — independent upstream cores |
| STC89 12T core rate | 1085 ns/NOP (12×) on both emulators | Independent instruction dispatch |

### Category 2b — same-source (datasheet 2011-07-15)

| Measurement | Result | Bench ID |
|---|---|---|
| Timer 0 at FOSC/12, 1 ms | 1,000,343 ns (STC12), 1,016,710 ns (STC89) | — |
| AUXR.7=1 Timer 0 → FOSC | 84 µs (STC12) vs 1013 µs (STC89, ignored) | — |
| PWM duty 33/50/75% | 32.83% / 50.05% / 75.07%, period 277,561 ns | `BENCH-PWM` |
| PCA 7.2K edges/sec | 277,561 ns period = 3602.8 Hz = 7206 edges/sec, agrees with bw-board | `BENCH-PWM` |
| Servo 90° pulse | **1499.6 µs**, frame 20,000.0 µs = 50.0 Hz, 0.03% error | `BENCH-PWM` |
| Motor duty 33/50/75% | 32.83% / 50.05% / 75.07% at P1.4 (CCP1) | `BENCH-PWM` |
| UART TX bit period | **86.8 µs** exact (320 BRT overflows × 271.27 ns) | `BENCH-UART` |
| Baud reload table | Divisor 3 → 115200 at 11.0592 MHz, 0.000% error | `BENCH-UART` |
| Naive STC15 port | 5 baud (23,040× wrong) — T2H=0x00, BRT written to wrong addr | `BENCH-UART` |
| Cube refresh | 124.1 Hz, 8.059 ms frame, 1005.4 µs/layer, jitter < 724 ns | `BENCH-CUBE` |
| WS2812 NeoPixel | T0H=362, T1H=814, T0L=814, T1L=452 — all 4 in WS2812 spec windows | `BENCH-PWM` |
| Relay P2.0 active-low | Pin LOW = ON, pin HIGH = OFF, no spurious interrupt | — |
| Button P3.2 GPIO read | Reads 1 (pull-up), INT0 NOT enabled | — |
| ADC register sequence | START→FLAG→clear per §4, result 512 (synthetic) | `BENCH-ADC` |
| HC-SR04 trigger pulse | 10.4 µs (1T), 20.6 µs (12T) — both ≥ 10 µs minimum | — |

### Category 3 — single-implementation

| Measurement | Result | What would raise it |
|---|---|---|
| STC15W no Timer 1 | TF1 never fires, program hangs on while(!TF1) | emu8051 agrees (→ 2b) |
| Naive baud gives 5 baud | T2H=0x00 after init (23,040× wrong) | emu8051 baud model (→ 2b) |

## Defects found

| Defect | Found by | Fixed in | How long it was green |
|---|---|---|---|
| PCA vector 0x0033 (LVD slot, should be 0x003B) | ucsim-stc bfecadc | ucsim-stc 6f8ab39 | ~2 hours |
| IE.6 = ELVD, not EC (no PCA enable in IE) | ucsim-stc c162861, bw-board 4f14c35 | stc e9a3f02 | Entire campaign — in the shared contract |
| PCA CL-wrap: CH read before increment, 256-count miss | ucsim-stc 4c8cc3e | ucsim-stc 4c8cc3e | Since PCA 16-bit compare was added |
| NeoPixel DPL vs ACC: all bytes sent as zero | ucsim-stc 06dc028 | sb3-creator 7d38a0d | Since driver was written |
| NeoPixel R7 collision: only 1 of 9 bytes sent | ucsim-stc c9ee7bb | sb3-creator 261a527 | Since DPL fix |
| HC-SR04 trigger 4.7 µs (busy loop, 1T/12T trap) | ucsim-stc f297076 | sb3-creator 2bfdd98 | Since driver was written |
| Corpus test silent degradation (load fails counted as empty) | fleet note | ucsim-stc corpus_stc89.sh | Since corpus was built |
| 347-image sweep no per-invocation timeout (3-hour hang) | coordinator kill | ucsim-stc corpus_stc12_on_stc89.sh | One run |
| "278 µs ISR overhead" was CL-wrap bug, not hardware | ucsim-stc self-retracted | 4c8cc3e | ~1 hour |
| stc ROADMAP.md "proven on real hardware" — nothing ran on silicon | coordinator | stc b4f4bb1 | Unknown |
| stc PERIPHERAL-MODEL "IE.EC enables PCA" — no EC exists | coordinator 251ac24 | stc e9a3f02 | Since document was written |

## What is open (bench IDs)

| ID | Claim | What settles it |
|---|---|---|
| `BENCH-ADC` | ADC analog path (voltage → correct code) | Pot on P1.3, `src/02-adc` on silicon |
| `BENCH-PWM` | PWM duty / servo pulse / NeoPixel timing | Frequency counter on CEX0/CEX1 |
| `BENCH-UART` | Baud rate on the wire | Logic analyser on UART TX, `HELLO` at 115200 |
| `BENCH-CUBE` | 124.1 Hz refresh, active-HIGH polarity | Photodiode or high-speed camera + lit LED at (FE,01) |

## What I would pick up next

The UART RX path — RI never rises without external stimulus. With the BRT
and TX timing now modelled, RX byte injection is implemented via
`-inject TIME_NS,BYTE` (a81091e). bw-board is unblocked for the
serial DebugTarget e2e test. Idle-timeout resync IS reachable.

**After initial close-out:**
- `-inject` flag (a81091e): timed RX byte delivery, unblocks bw-board
- `rung_neopixel.sh` (f6f35b9): runnable spec-window test, 4/4 pass
- Regression test for stc12_trace hang on 10-live-firmware (8839220)

## Standing caveats

- **Nothing has run on silicon.** Every measurement is emulation-only.
- **The emitter-vs-model matrix** (PARITY-GAPS.md): 11/13 SFR-touching
  paths modelled, 2 cells-only (UART RX, serial print), 31 BW_STUB no-ops.
- **SDCC's stc12.h is the independent check** for any IE/IP bit claim.
  The campaign found one shared-contract error (IE.EC) that three
  implementations agreed on — and all were wrong.
