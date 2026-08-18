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

## Part 3: 3-channel ADC sweep (STC15, dedicated fixture)

Dedicated test fixture (`adc_3ch_oracle.ihx`) reads all 3 channels in
sequence with P5.5 buzzer markers between reads. Exercises the same
ADC register sequence as the 76-multimeter but without needing a button
press to switch modes.

### Channel 0: Voltage divider (Vin/4 through 30k/10k)

| Vin | Count | emu8051 | ucsim | mv | cand | Display | Match |
|-----|-------|---------|-------|----|------|---------|-------|
| 0 V | 0 | 0 | 0 | 0 | 0 | 0.00 | **PASS** |
| 1 V | 51 | 51 | 51 | 249 | 99 | 0.99 | **PASS** |
| 2 V | 102 | 102 | 102 | 498 | 199 | 1.99 | **PASS** |
| 4 V | 205 | 205 | 205 | 1001 | 400 | 4.00 | **PASS** |
| 6 V | 307 | 307 | 307 | 1500 | 600 | 6.00 | **PASS** |
| 8 V | 409 | 409 | 409 | 1999 | 799 | 7.99 | **PASS** |
| 10 V | 512 | 512 | 512 | 2502 | 1000 | 10.00 | **PASS** |
| 13.2 V | 675 | 675 | 675 | 3299 | 1319 | 13.19 | **PASS** |
| 16 V | 818 | 818 | 818 | 3998 | 1599 | 15.99 | **PASS** |
| 20 V | 1023 | 1023 | 1023 | 5000 | 2000 | 20.00 | **PASS** |

### Channel 1: LM358 shunt amplifier (amps mode)

| Shunt mV | Count | emu8051 | ucsim | mv | mA (×50/47) | Match |
|----------|-------|---------|-------|----|-------------|-------|
| 0 mV | 0 | 0 | 0 | 0 | 0 | **PASS** |
| 5 mV | 1 | 1 | 1 | 4 | 4 | **PASS** |
| 25 mV | 5 | 5 | 5 | 24 | 25 | **PASS** |
| 50 mV | 10 | 10 | 10 | 48 | 51 | **PASS** |
| 100 mV | 20 | 20 | 20 | 97 | 103 | **PASS** |
| 250 mV | 51 | 51 | 51 | 249 | 264 | **PASS** |
| 500 mV | 102 | 102 | 102 | 498 | 529 | **PASS** |
| 1 V | 205 | 205 | 205 | 1001 | 1064 | **PASS** |
| 2.5 V | 512 | 512 | 512 | 2502 | 2661 | **PASS** |

### Channel 2: NTC thermistor divider

| NTC mV | Count | emu8051 | ucsim | mv | deci-°C | Match |
|--------|-------|---------|-------|----|---------|-------|
| 0 mV | 0 | 0 | 0 | 0 | -344 | **PASS** |
| 433 mV | 89 | 89 | 89 | 434 | -200 | **PASS** |
| 733 mV | 150 | 150 | 150 | 733 | -100 | **PASS** |
| 1146 mV | 235 | 235 | 235 | 1148 | 38 | **PASS** |
| 1657 mV | 339 | 339 | 339 | 1656 | 207 | **PASS** |
| 2500 mV | 512 | 512 | 512 | 2502 | 489 | **PASS** |
| 3268 mV | 669 | 669 | 669 | 3269 | 745 | **PASS** |
| 4004 mV | 820 | 820 | 820 | 4007 | 991 | **PASS** |
| 5 V | 1023 | 1023 | 1023 | 5000 | 1322 | **PASS** |

## Summary

| Test area | Points | Pass | Fail |
|-----------|--------|------|------|
| Raw 10-bit ADC (STC12, ch0) | 8 | 8 | 0 |
| Multimeter voltage mode (STC15, ch0) | 9 | 9 | 0 |
| 3-ch fixture ch0 (STC15) | 10 | 10 | 0 |
| 3-ch fixture ch1 (STC15) | 9 | 9 | 0 |
| 3-ch fixture ch2 (STC15) | 9 | 9 | 0 |
| **Total** | **45** | **45** | **0** |

## Divergences

None. The ADC model is byte-exact across all 45 tested voltage points,
all 3 channels, both STC12 and STC15:
- ADC_CONTR register protocol (power, speed, start, flag, channel select)
- ADC_RES / ADC_RESL result registers (10-bit, ADRJ=0 alignment)
- P1ASF analog function enable (multi-channel mask)
- ADC conversion timing (flag set after delay countdown)
- Channel switching (sequential ch0→ch1→ch2→ch0)
- Default value without stimulus (0, per STC12 datasheet — fixed in a41cee0)
- P5.5 buzzer markers between channels (STC15 P5 port model)

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
