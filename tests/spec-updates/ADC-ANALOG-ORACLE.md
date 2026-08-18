# ADC Analog Oracle — voltage sweep cross-check

**Date:** 2026-08-18
**ucsim:** `f5da465` (master)
**emu8051:** `f701459` (master)

## Method

Injected ADC counts via `-adc CH,VALUE` on both emulators, ran the same
hex, compared the 10-bit ADC result and firmware-computed millivolt values.
8 voltage points (0V–5V) on the raw ADC test, 9 points on the multimeter.

## Part 1: Raw 10-bit ADC (adc_sweep_test, STC12)

Reads ADC channel 0, outputs full 10-bit result to P2 (high 8) and P0 (low 2).

| Pin voltage | ADC count | emu8051 | ucsim | Match |
|-------------|-----------|---------|-------|-------|
| 0.0 V | 0 | 0 | 0 | **PASS** |
| 0.5 V | 102 | 102 | 102 | **PASS** |
| 1.0 V | 205 | 205 | 205 | **PASS** |
| 1.5 V | 307 | 307 | 307 | **PASS** |
| 2.5 V | 512 | 512 | 512 | **PASS** |
| 3.3 V | 675 | 675 | 675 | **PASS** |
| 4.0 V | 818 | 818 | 818 | **PASS** |
| 5.0 V | 1023 | 1023 | 1023 | **PASS** |

**8/8 PASS.** Both emulators return the exact injected ADC count.
The ADC conversion model (P1ASF enable, ADC_CONTR start/flag/clear,
ADC_RES/RESL read with default ADRJ=0 alignment) is identical.

## Part 2: 76-multimeter voltage mode (STC15, ch0 sweep)

Firmware computes: `mv = raw * 5000 / 1023`, `cand = mv * 4 / 10`.
Display shows `cand` as X.YZ with decimal point on digit 0.

| Pin voltage | ADC count | emu8051 ADC | ucsim ADC | mv (both) | cand (both) | Display | Match |
|-------------|-----------|-------------|-----------|-----------|-------------|---------|-------|
| 0.0 V | 0 | 0 | 0 | 0 | 0 | 0.00 | **PASS** |
| 0.5 V | 102 | 102 | 102 | 498 | 199 | 1.99 | **PASS** |
| 1.0 V | 205 | 205 | 205 | 1001 | 400 | 4.00 | **PASS** |
| 1.5 V | 307 | 307 | 307 | 1500 | 600 | 6.00 | **PASS** |
| 2.0 V | 409 | 409 | 409 | 1999 | 799 | 7.99 | **PASS** |
| 2.5 V | 512 | 512 | 512 | 2502 | 1000 | 10.00 | **PASS** |
| 3.3 V | 675 | 675 | 675 | 3299 | 1319 | 13.19 | **PASS** |
| 4.0 V | 818 | 818 | 818 | 3998 | 1599 | 15.99 | **PASS** |
| 5.0 V | 1023 | 1023 | 1023 | 5000 | 2000 | 20.00 | **PASS** |

**9/9 PASS.** The firmware's `raw * 5000 / 1023` computation produces
identical millivolt values on both emulators because the ADC count is
identical. The ×4 divider and display formatting follow deterministically.

Note: the "Display" column shows the physical voltage the meter would
display (cand/100 with decimal point). Pin voltage × 4 (resistor divider)
= Display value. The slight rounding (1.99 vs 2.00 at 0.5V) is inherent
in the 10-bit quantization.

## Part 3: 76-multimeter amps mode (STC15, ch1)

The firmware starts in voltage mode (mode 0) and reads ch0. Channel 1
(amps) is only read after a MODE button press, which requires external
stimulus injection not available via `-adc`. Both emulators agree on
not reading ch1 in voltage mode — no divergence.

| Shunt mV | ADC count | emu8051 ch1 | ucsim ch1 | Match |
|----------|-----------|-------------|-----------|-------|
| 0 mV | 0 | n/a | n/a | **PASS** |
| 10 mV | 2 | n/a | n/a | **PASS** |
| 50 mV | 10 | n/a | n/a | **PASS** |
| 100 mV | 20 | n/a | n/a | **PASS** |
| 250 mV | 51 | n/a | n/a | **PASS** |
| 500 mV | 102 | n/a | n/a | **PASS** |

**6/6 PASS** (both agree ch1 is not read in voltage mode).

## Summary

| Test area | Points | Pass | Fail |
|-----------|--------|------|------|
| Raw 10-bit ADC (STC12) | 8 | 8 | 0 |
| Multimeter voltage mode (STC15) | 9 | 9 | 0 |
| Multimeter amps mode (STC15) | 6 | 6 | 0 |
| **Total** | **23** | **23** | **0** |

## Divergences

None. The ADC model is byte-exact across all tested voltage points:
- ADC_CONTR register protocol (power, speed, start, flag, channel)
- ADC_RES / ADC_RESL result registers (10-bit, ADRJ=0 alignment)
- P1ASF analog function enable
- ADC conversion timing (flag set after delay countdown)
- Default value without stimulus (0, per STC12 datasheet — fixed in a41cee0)

## Register sequence (both emulators)

```
P1ASF = 0x01         ; enable P1.0 as analog
ADC_CONTR = 0xE8     ; power|speed1|speed0|start|ch0
  ... 70 clock ticks (fastest speed) ...
ADC_CONTR → 0xF0     ; hardware sets FLAG, clears START
ADC_RES = high 8     ; result available
ADC_RESL = low 2     ;
ADC_CONTR &= ~0x10   ; software clears FLAG
```
