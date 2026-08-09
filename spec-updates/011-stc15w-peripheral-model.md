# Proposed: STC15W408AS peripheral model — a delta against the STC15F2K60S2

For `stc/docs/STC15W-PERIPHERAL-MODEL.md`. From ucsim-stc, for review.

## Why this part

The STC15W408AS is a smaller, wide-voltage STC15 variant. It is NOT the
STC15F2K60S2 with less memory — it has genuine peripheral differences.

## Part identity (from stcmicro.com product page)

| | STC15W408AS | STC15F2K60S2 |
|---|---|---|
| Flash | **8 KB** | 60 KB |
| SRAM | **512 B** (256 scratch + 256 aux) | 2048 B (256 + 1792) |
| Supply | **2.5–5.5 V** (W = wide voltage) | 5.5–4.2 V |
| Core | 1T | 1T |
| Max clock | **35 MHz** | 28 MHz |
| Timers | **T0, T2 only (no T1)** | T0, T1, T2 |
| UARTs | **1** | 2 |
| ADC | 8 channels, 10-bit | 8 channels, 10-bit |
| CCP/PCA/PWM | 3 channels | 3 channels |
| SPI | 1 | 1 |
| Package | **SOP28/DIP28 max** (no 40-pin) | PDIP-40 |
| Ports | **P0–P3 only (no P4, P5)** | P0–P5 |

## The delta: what differs from STC15F2K60S2

### 1. No Timer 1

This is the headline difference. Timer 1 is completely absent:
- **TMOD upper nibble** (Timer 1 mode bits) — not functional
- **TH1** (0x8D), **TL1** (0x8B) — not functional
- **TCON bits 6–7** (TF1, TR1) — not functional
- **AUXR bit 6** (T1x12) — not applicable

⚠ Consequence for baud rate: without Timer 1, UART1 baud rate must come
from Timer 2 (via AUXR.S1ST2 / AUXR bit 0). The STC15F2K60S2 can use
either; the W408AS has no choice.

⚠ Consequence for generated code: the `TONE` pin feature uses Timer 1
for frequency generation. On the W408AS, `TONE` is not available, and
the model must refuse it with a reason.

### 2. No P4, no P5

Only P0–P3 are available (28-pin package maximum). The STC12/STC15F's:
- P4 (0xC0), P4M1 (0xB3), P4M0 (0xB4) — **absent**
- P5 (0xC8), P5M1 (0xC9), P5M0 (0xCA) — **absent**
- P4SW (0xBB) — **absent** (already absent on STC15F)

Port mode registers for P0–P3 are present and work identically to the
STC15F2K60S2.

### 3. One UART only

UART1 is present (SCON/SBUF at 0x98/0x99). UART2 is absent:
- S2CON, S2BUF — **not present**

### What is identical to the STC15F2K60S2

Everything not listed above:
- **AUXR** (0x8E) — T0x12 at bit 7 works identically; T1x12 bit is don't-care
- **Timer 0** — identical, FOSC/12 with T0x12=0
- **Timer 2** — T2H/T2L at 0xD6/0xD7, identical
- **Port modes** for P0–P3 — PxM1/PxM0, same addresses, same four modes
- **ADC** — P1ASF, ADC_CONTR/RES/RESL, same addresses and behaviour
- **ADRJ** location — CLK_DIV (0x97) bit 5, same as STC15F2K60S2
- **PCA** — 3 channels, CCON/CMOD/CCAPMn, identical
- **INT_CLKO** (0x8F) — present
- **SPI** — SPSTAT/SPCTL/SPDAT at 0xCD/0xCE/0xCF
- **WDT_CONTR** (0xC1)
- **Internal RC clock** — ±0.3%, same canonical frequencies
- **1T core** — `clock_per_cycle()` = 1

### SFR defined addresses

STC15F2K60S2 set minus Timer 1 SFRs, minus P4/P5/P4M/P5M, minus UART2.

TH1 (0x8D) and TL1 (0x8B) remain as SFR addresses (the physical register
cells exist in the SFR space) but writes have no timer effect.

### Capabilities and refusal

An STC15W408AS model must refuse:
- `TONE` pins — no Timer 1 for frequency generation
- Pins on P4 or P5 — those ports don't exist
- UART2 operations

It must NOT refuse:
- `ANALOG` pins on P1 — ADC works
- `PWM` pins — PCA works
- Port mode configuration on P0–P3 — works
- 1T timer switching — AUXR.T0x12 works

### What is unverified

Everything. This is derived from the stcmicro.com product page and the
STC15 series datasheet. No STC15W408AS silicon has been tested. The
SFR map is assumed identical to STC15F2K60S2 for the peripherals that
exist; confirm from the actual datasheet section for this sub-family.
