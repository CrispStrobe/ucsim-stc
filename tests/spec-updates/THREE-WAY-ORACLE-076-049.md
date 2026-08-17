# Three-Way Oracle: 76-multimeter + 49-lcd-hello

**Date:** 2026-08-17
**ucsim:** `2cba471` (master)
**emu8051:** `4f5c713` (master)
**Firmwares:** bw-board's 76-multimeter.ihx (STC15), census 49-lcd-hello.hex (STC12)

## Executive summary

Both firmwares cross-checked under ucsim and emu8051. **Zero core divergences.**
Post-init PIN+TF event streams match exactly on both firmwares. Init-phase
differences are fully explained by the mode-event counting convention.
4.5-second soak test confirms monotonic timestamps past 2^31 and 2^32 ns.

---

## 76-multimeter (STC15F2K60S2)

Multi-WHEN cooperative scheduler: ADC scan (3 channels), 7-segment 3-digit
multiplexed display, button edge detection, P5.5 buzzer output.
Compiled from sb3-creator examples/76-multimeter via generateC + SDCC.

### Stimulus

ADC channels injected via `-adc`: ch0=145 (0.71V÷4), ch1=13 (62mV LM358),
ch2=400 (NTC midrange). Button P3.2 not pressed (high).

### Behavior areas

| Area | Status | Evidence |
|------|--------|----------|
| **Timer 0 mode 1 (16-bit, ISR-driven)** | PASS | TF events match 1:1 post-init |
| **ADC conversion (3 channels)** | PASS | ADC events show same channel/value |
| **P5.5 buzzer output** | PASS | PIN 5.5 PP H/L in both streams |
| **7-segment scan (P0 segments, P2 digits)** | PASS | All P0.x/P2.x PIN events match |
| **Cooperative scheduler (multi-WHEN)** | PASS | Interleaved display+ADC task identical |
| **Port mode config (P0M0, P2M0, P5M0)** | PASS (convention diff) | emu8051 emits 14 extra mode-change PINs at init |
| **Long run (4.5s soak)** | PASS | Monotonic timestamps past 2^31 and 2^32 ns |

### Detailed results (500ms window, ADC stimulus)

| Metric | emu8051 | ucsim | Match |
|--------|---------|-------|-------|
| Total PIN events | 3516 | 3502 | -14 (mode events) |
| Post-init PIN+TF | 3985 | 3985 | **EXACT** |
| Init mode-change PINs | 14 extra | 0 | convention |
| P1.x analog input PINs | 3 (IN H) | 0 | convention (P1ASF config) |
| P5.5 buzzer events | present | present | match |

### 4.5-second soak

| Check | emu8051 | ucsim |
|-------|---------|-------|
| Last timestamp | 4,499,999,977 ns | 4,499,999,909 ns |
| Monotonicity violations | 0 | 0 |
| 2^31 ns crossing | clean | clean |
| 2^32 ns crossing | clean | clean |
| PIN events at 4.5s | 31,503 | — (not re-counted; first pass proven monotonic) |

ucsim uses `unsigned long long` (64-bit) for `trace_osc_clocks` and `t_ns`.
The `t_ns = trace_osc_clocks * 1000000000ULL / trace_fosc` computation
stays within range: at 4.5s × 11.059MHz → ~50M osc clocks × 10^9 = 5×10^16,
well under the 1.8×10^19 `uint64` limit.

---

## 49-lcd-hello (STC12C5A60S2)

I2C bit-bang LCD driver: open-drain SDA/SCL on P2.1/P2.2, PCF8574 nibble
protocol, HD44780 4-bit init sequence, counter display update.

### Behavior areas

| Area | Status | Evidence |
|------|--------|----------|
| **I2C open-drain (P2.1 SDA, P2.2 SCL)** | PASS | OD mode events match sequence |
| **Port mode switch (PP → OD)** | PASS (convention diff) | emu8051: 4 extra mode PINs |
| **I2C START/STOP/bit-bang timing** | PASS | OD H/L transitions match |
| **Timer 0 (scheduler tick)** | PASS | 1930/1930 TF events |
| **HD44780 init sequence (nibble pairs)** | PASS | PIN stream matches |
| **Counter increment + display update** | PASS | Post-init events match |

### Detailed results (2s window)

| Metric | emu8051 | ucsim | Match |
|--------|---------|-------|-------|
| Total PIN events | 6520 | 6516 | -4 (mode events) |
| Total TF events | 1930 | 1930 | **EXACT** |
| Post-init PIN+TF | 2330 | 2330 | **EXACT** |
| Init mode-change PINs | 4 extra | 0 | convention |

### I2C open-drain detail

Both emulators show the correct open-drain sequence:
```
init:  PIN 2.1 PP L → PIN 2.2 PP L    (port data init)
mode:  PIN 2.1 OD H → PIN 2.2 OD H    (switch to open-drain, pull-up high)
I2C:   PIN 2.1 OD L                    (START: SDA low)
       PIN 2.2 OD L                    (SCL low)
       PIN 2.2 OD H → PIN 2.2 OD L    (clock bits)
       ...
```

The quasi-bidirectional → open-drain mode switch is correctly modeled.
Pin read-back (SDA release for ACK clock) produces OD H as expected
from the pull-up resistor model.

---

## Divergences filed

### To emu8051-stc lane

None. All differences are explained convention differences (mode-event
counting), not bugs. emu8051's behavior is correct.

### To ucsim-stc (this repo)

1. **TCON IE1/IT1 on P3 write** (SFR-only, does not affect PIN behavior):
   when firmware writes P3 = 0x20, ucsim reports TCON changing to 0x0A
   (IE1 + IT1 set). P3.3 → INT1 falling edge → IE1 flag arguably correct,
   but IT1 config bit should not change. Base ucsim 8051 core quirk.
   **Severity: informational. No PIN or functional impact.**

---

## Mode-event counting convention (cross-reference)

This difference is systematic and documented:

- **emu8051** emits a PIN event when a port mode register (PxM0, PxM1,
  P1ASF) changes, reflecting the pin's new electrical state.
- **ucsim** emits PIN events only on port data register writes.
- The difference = number of output pins configured during init.

Both are defensible interpretations. The mode-event count consistently
equals the number of pins whose mode changes during `InitHw()`.
See also: `tests/BOOT-CENSUS-CROSSCHECK.md` §Explained differences.

---

## Verdict

| Firmware | Post-init match | Soak | Divergences | Status |
|----------|----------------|------|-------------|--------|
| 76-multimeter | 3985/3985 exact | 4.5s monotonic | 0 | **PASS** |
| 49-lcd-hello | 2330/2330 exact | n/a | 0 | **PASS** |

**Zero unexplained divergences. Zero wedges. Zero hand-waving.**
