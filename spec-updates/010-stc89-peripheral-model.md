# Proposed: STC89C52RC peripheral model — a delta against the STC12

For `stc/docs/STC89-PERIPHERAL-MODEL.md`. From ucsim-stc, for review.

## Why this part

The compile chain already knows STC89C52RC (`stc_pseudocode.py` line 1841,
`SB3Creator.STC_PARTS`): `8052.h`, no port modes, no AUXR 1T bit, no ADC.
Users can target it; neither emulator can run what comes out. That is the gap.

## The delta: mostly subtractive

The STC89C52RC is a **12T** core. This is the single most consequential
difference in the whole part list. Everything else follows from "it is a
standard 8052 with STC's power-on and ISP bootstrap."

### What is identical to a standard 8052

- **Core instruction set** — same opcodes, same cycle counts
- **Timer 0 and Timer 1** — standard modes 0/1/2/3, counter at FOSC/12
- **UART** — standard 8051 UART, baud from Timer 1 (NOT from BRT)
- **Interrupt system** — IE, IP, standard vectors
- **P0–P3** — standard quasi-bidirectional ports, reset to 0xFF
- **SP, DPL, DPH, ACC, B, PSW, PCON** — standard locations and reset values
- **256 bytes IRAM**, standard 8052 upper-128 mapping
- **Timer 0 at FOSC/12 timing is exact** — `T0_RELOAD = 65536 - FOSC/12/1000`
  gives 1 ms at 11.0592 MHz, same as on STC12 with AUXR.7=0

### What is absent (relative to STC12)

| feature | STC12 | STC89 |
|---------|-------|-------|
| **AUXR** (0x8E) | T0x12, T1x12, BRTR, etc. | **absent** — no 1T/12T switching |
| **Port modes** (PxM0/PxM1) | 4 modes per pin | **absent** — quasi-bidir only |
| **ADC** (P1ASF, ADC_CONTR/RES/RESL) | 8ch 10-bit | **absent** |
| **PCA/PWM** (CCON, CMOD, CCAPMn) | 2 modules | **absent** |
| **P4** (0xC0), **P5** (0xC8) | present | **absent** (0xC8 = T2CON) |
| **Dual DPTR** (DPS 0x86) | present | **absent** |
| **CLK_DIV** (0x97), **P1ASF** (0x9D) | present | **absent** |
| **P4SW** (0xBB), **P4M0/1**, **P5M0/1** | present | **absent** |
| **WDT_CONTR** | 0xC1 | **0xE1** (different address) |
| **BRT** (0x9C) | dedicated baud rate timer | **absent** — baud from Timer 1 |
| **AUXR1** (0xA2) | present | **absent** |

### What the STC89 has that a plain 8052 does not

- **WDT_CONTR at 0xE1** — watchdog timer with prescaler
- **ISP_DATA/CONTR/CMD/TRIG** at 0xE2–0xE5 — in-system programming
- **P4 at 0xE8** (NOT 0xC0 like STC12) — only on PLCC-44 packages

These are not modelled because no generated code touches them.

### 12T timing rule

**This is the headline.** On the STC89:
- Every instruction takes 12 osc clocks per machine cycle (standard 8052 timing)
- Timer 0 counts at FOSC/12 (one increment per machine cycle)
- There is no AUXR, no 1T option

The timing equivalence: Timer 0 in mode 1 at FOSC/12 counts identically
on the STC89 (12T, native FOSC/12) and the STC12/STC15 (1T, AUXR.7=0
selects FOSC/12). This is by design — the emitter uses this as the one
mode that makes one program timing-correct on all three families.

### SFR address map (defined addresses)

Standard 8052 set only:

| addr | name | addr | name | addr | name |
|------|------|------|------|------|------|
| 0x80 | P0 | 0xA0 | P2 | 0xD0 | PSW |
| 0x81 | SP | 0xA8 | IE | 0xE0 | ACC |
| 0x82 | DPL | 0xB0 | P3 | 0xF0 | B |
| 0x83 | DPH | 0xB8 | IP | | |
| 0x87 | PCON | 0xC8 | T2CON | | |
| 0x88 | TCON | 0xCA | RCAP2L | | |
| 0x89 | TMOD | 0xCB | RCAP2H | | |
| 0x8A | TL0 | 0xCC | TL2 | | |
| 0x8B | TL1 | 0xCD | TH2 | | |
| 0x8C | TH0 | | | | |
| 0x8D | TH1 | | | | |
| 0x90 | P1 | | | | |
| 0x98 | SCON | | | | |
| 0x99 | SBUF | | | | |

### Capabilities and refusal

An STC89 model must refuse:
- `ANALOG` pins — no ADC (same reason, same message as stc-compiler)
- `PWM` pins — no PCA
- Port mode configuration — all pins are quasi-bidirectional
- 1T timer switching — no AUXR

The refusal must match emu8051-stc's refusal for the same part.

### What this proves and what it does not

A model written from the standard 8052 spec is on solid ground — the 8052 is
the most thoroughly documented 8-bit MCU ever made. The STC89 adds nothing
that generated code touches. The interesting test is the *absence* test: that
firmware targeting STC89 runs correctly on both emulators despite having no
STC12-specific peripherals, and that both emulators refuse the same operations
identically.
