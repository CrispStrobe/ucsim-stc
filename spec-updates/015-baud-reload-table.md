# Baud reload table: BRT (STC12) vs T2H/T2L (STC15)

From ucsim-stc. For 10-live-firmware, bw-board, and the coordinator.

## The claim, now computed rather than hoped

The STC12 on-chip monitor at 115200 baud programs BRT = 0xFD (divisor 3).
The STC15 version programs T2H:T2L = 0xFF:0xFD (divisor 3).

**Both produce exactly 115200 baud at FOSC = 11,059,200 Hz.** The divisor
is the same; only the register address differs.

## The naive port fails, and by how much

Writing `BRT = 0xFD` on an STC15 writes to 0x9C (deprecated). Timer 2's
reload at 0xD6/0xD7 stays at the reset default (0x0000), giving:

- Effective divisor: 65536
- Baud: **5.27** (not 115200)
- Ratio: **23,040× too slow**

The wire would be silent. And emu8051-stc would not notice, because it
delivers UART bytes regardless of baud configuration.

## The firmware already handles this

`stc/src/10-live-firmware/main.c` lines 197–210 use `#ifdef PART_STC15F2K60S2`
to switch between BRT and T2H/T2L. The code is correct. This test confirms
it computationally: both paths produce 271 ns overflow period (= 115200 baud
at SMOD=0, mode 1 /32 divider).

## Baud reload table

All values at FOSC = 11,059,200 Hz, BRTx12=1 / T2x12=1 (1T mode), SMOD=0.

| Baud | Divisor | BRT (STC12) | T2H:T2L (STC15) | Error |
|------|---------|-------------|-----------------|-------|
| 300 | 1152 | N/A (>255) | 0xFB:0x80 (64384) | 0.000% |
| 600 | 576 | N/A (>255) | 0xFD:0xC0 (64960) | 0.000% |
| 1200 | 288 | N/A (>255) | 0xFE:0xE0 (65248) | 0.000% |
| 2400 | 144 | 0x70 | 0xFF:0x70 (65392) | 0.000% |
| 4800 | 72 | 0xB8 | 0xFF:0xB8 (65464) | 0.000% |
| 9600 | 36 | 0xDC | 0xFF:0xDC (65500) | 0.000% |
| 19200 | 18 | 0xEE | 0xFF:0xEE (65518) | 0.000% |
| 38400 | 9 | 0xF7 | 0xFF:0xF7 (65527) | 0.000% |
| 57600 | 6 | 0xFA | 0xFF:0xFA (65530) | 0.000% |
| 115200 | 3 | 0xFD | 0xFF:0xFD (65533) | 0.000% |

11.0592 MHz gives 0.000% error for all standard bauds from 300 to 115200.
This is the entire reason this crystal frequency exists.

Baud rates below 2400 do NOT fit the 8-bit BRT — they need the STC15's
16-bit Timer 2. This is the STC15's genuine advantage for serial
applications: it covers the full range without a dedicated baud timer.

## What the STC89 uses

The STC89 has no BRT and no Timer 2 baud — it uses **Timer 1 in mode 2
(8-bit auto-reload)** for UART baud, same as a standard 8052. The formula
is identical (divisor = FOSC / (32 * BAUD)), but the reload goes into TH1.
This is why `TONE` and `UART` are mutually exclusive on the STC89 — both
want Timer 1.

## Formula reference

```
divisor      = FOSC / (32 × baud)        # SMOD=0, mode 1
BRT_RELOAD   = 256 - divisor             # STC12 (8-bit, fits if divisor ≤ 255)
T2_RELOAD    = 65536 - divisor           # STC15 (16-bit, always fits)
T2H          = (T2_RELOAD >> 8) & 0xFF
T2L          = T2_RELOAD & 0xFF
actual_baud  = FOSC / (32 × divisor)
tolerance    = ±2-3% for UART to work reliably
```

With SMOD=1 (double rate), divide by 16 instead of 32.
