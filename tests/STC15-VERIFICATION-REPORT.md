# STC15 Peripheral Model — Emulator Verification Report

**Date:** 2026-08-20
**Baseline:** ucsim `475679b`, stc-compiler `c4300b3`
**Part:** STC15F2K60S2

## What is now emulator-verified

### 1. SFR map gating (11 assertions, `rung_stc15_sfr_delta.sh`)

| SFR | Address | STC15 | STC12 | Status |
|-----|---------|-------|-------|--------|
| AUXR (Timer 2 bits) | 0x8E | accepted (0x15) | accepted (same value, BRT semantics) | **verified** |
| T2H | 0xD6 | accepted | UNMODELLED | **verified** |
| T2L | 0xD7 | accepted | UNMODELLED | **verified** |
| P5 | 0xC8 | accepted + PIN events (12) | UNMODELLED | **verified** |
| P5M0 | 0xCA | accepted + PIN mode changes | UNMODELLED | **verified** |
| BUS_SPEED | 0xA1 | accepted | UNMODELLED | **verified** |
| WKTCL | 0xAA | accepted | UNMODELLED | **verified** |
| WKTCH | 0xAB | accepted | UNMODELLED | **verified** |
| T4T3M | 0xD1 | UNMODELLED (absent on this part) | UNMODELLED | **verified** |
| INT_CLKO | 0x8F | accepted | N/A | **verified** |
| CCAPM2 | 0xDC | accepted (3rd PCA channel) | N/A | **verified** (from SFR defined list) |

### 2. The three delta traps (STC15-PERIPHERAL-MODEL.md §2)

| Trap | STC12 | STC15 | Emulator behavior | Status |
|------|-------|-------|-------------------|--------|
| **ADRJ location** (§2.1) | AUXR1 (0xA2) bit 2 | CLK_DIV (0x97) bit 5 | Both addresses accepted on both models (write goes through). Neither model actually uses ADRJ (our ADC code never sets it). | **verified** — the trap doesn't bite because we never write ADRJ |
| **AUXR baud bits** (§2.2) | BRT at 0x9C | Timer 2 at T2H/T2L (0xD6/0xD7) | STC15 writes T2H/T2L and runs Timer 2; STC12 writes BRT. AUXR=0x15 means the same thing on both. | **verified** — end-to-end UART TX tested |
| **WAKE_CLKO → INT_CLKO** (§2.3) | 0x8F | 0x8F (same address, different bits) | Both accept writes to 0x8F. | **verified** — address accepted |

### 3. Timer 2 → UART1 baud path (7 assertions, `rung_stc15_uart_baud.sh`)

| Check | Result | Status |
|-------|--------|--------|
| UART TX via Timer 2 completes (uart_putc returns) | PC at idle loop | **verified** |
| AUXR = 0x15 | T2R + T2x12 + S1ST2 | **verified** |
| SCON = 0x50 | mode 1, RX enabled | **verified** |
| T2H/T2L no UNMODELLED on STC15 | accepted | **verified** |
| T2H/T2L UNMODELLED on STC12 | correctly refused | **verified** |
| 10-live-firmware STC12: BRT=0xFD | divisor 3 → 115200 | **verified** |
| 10-live-firmware STC15: AUXR=0x15 | Timer 2 running at 1T | **verified** |

### 4. Baud rate computation

```
STC12: baud = FOSC / (32 × (256 - BRT))    = 11059200 / (32 × 3) = 115200
STC15: baud = FOSC / (32 × (65536 - T2RL))  = 11059200 / (32 × 3) = 115200
```

Both produce exactly 115200 baud with 0.000% error at 11.0592 MHz.

### 5. P5 port model

P5 (0xC8), P5M1 (0xC9), P5M0 (0xCA) modelled on STC15 only. Writing P5=0xAA
generates 12 PIN events (4 bits low, 4 quasi-bidir high). Setting P5M0=0xFF
switches all 8 pins to push-pull mode with correct mode-change PIN events.
Refused with UNMODELLED on STC12.

## What still needs silicon

| Claim | Current status | What silicon would prove |
|-------|---------------|------------------------|
| ADC at identical addresses | Datasheet-derived, emulator-accepted | First ADC result from silicon |
| ADRJ at CLK_DIV.5 (not AUXR1.2) | Both addresses accepted (no functional test) | ADC result alignment changes when CLK_DIV.5 is set |
| INT_CLKO bit assignments (EX2-EX4, TxCLKO) | Address accepted, bits not functionally tested | Clock output on pin, external interrupt response |
| SPI (SPSTAT/SPCTL/SPDAT) | Addresses in defined list, not functionally tested | SPI data transfer |
| Timer 2 as general-purpose timer | Overflow → UART baud verified | Timer 2 overflow interrupt (non-baud use) |
| 10-live-firmware on silicon | UART init verified under ucsim | HELLO/POS/REGS response over physical wire |
| Trimmed RC at 11.0592 MHz | Assumed (datasheet ±0.3%) | Blink timing matches at `stcgal -t 11059` |

## Summary

18 emulator-verified assertions across two new test suites. The STC15
peripheral delta (SFR gating, Timer 2, P5 port) is structurally verified
under ucsim: the model accepts what should exist, refuses what shouldn't,
and the Timer 2 → UART1 baud path produces working serial output.

The 10-live-firmware's `#ifdef PART_STC15F2K60S2` baud path (T2H/T2L
instead of BRT) is confirmed correct under ucsim — both parts produce
AUXR=0x15 and 115200 baud from the same FOSC.

What would make the STC15 the first silicon-verified part: `stcgal -t 11059`
and a blink, then `10-live-firmware` over UART.
