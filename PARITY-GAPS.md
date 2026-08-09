# Feature parity gaps — what each chip has vs what the model implements

Derived by comparing the STC datasheets against the emulator models.
Three levels: **MODELLED** (behavioral model), **REGISTERED** (SFR cell
accepts writes, no behavioral effect), **ABSENT** (not in the model).

## STC12C5A60S2

| Peripheral | Chip | Model | Notes |
|---|---|---|---|
| 1T core, AUXR.T0x12/T1x12 | yes | **MODELLED** | Timer prescaler, verified |
| Timer 0 (mode 0/1/2/3) | yes | **MODELLED** | All modes via base 8051 |
| Timer 1 (mode 0/1/2/3) | yes | **MODELLED** | All modes via base 8051 |
| Port modes PxM0/PxM1 (P0-P5) | yes | **MODELLED** | Mode tracking, no electrical |
| ADC 10-bit (8 ch on P1) | yes | **MODELLED** | Power/start/flag/clear cycle |
| PCA/PWM (2 modules) | yes | **MODELLED** | 8 clock sources, PWM, capture |
| Dual DPTR | yes | **MODELLED** | DPS at 0x86 |
| Watchdog timer | yes | **MODELLED** | Prescaler, flag (no reset) |
| UART1 (SCON/SBUF) | yes | **MODELLED** | Basic byte-level via base 8051 |
| BRT (baud rate timer) | yes | **REGISTERED** | SFR cell at 0x9C, no baud generation |
| UART2 (S2CON/S2BUF) | yes | **REGISTERED** | SFR cells, no second serial |
| EEPROM/IAP | yes | **REGISTERED** | SFR cells at 0xC2-0xC7, no flash ops |
| Enhanced interrupts (IP2H/IPH) | yes | **REGISTERED** | 4-priority not enforced |
| SADDR/SADEN (multiprocessor) | yes | **REGISTERED** | Cells exist, no address match |
| WAKE_CLKO | yes | **REGISTERED** | Cell at 0x8F, no clock output |
| SPI | **yes** | **ABSENT** | Not registered, not modelled |
| Power modes (idle/power-down) | yes | **ABSENT** | PCON bits not acted on |
| Comparator | no | n/a | STC12 has none |

## STC15F2K60S2

Everything from STC12 above, plus:

| Peripheral | Chip | Model | Notes |
|---|---|---|---|
| Timer 2 (T2H/T2L) | yes | **MODELLED** | 16-bit auto-reload, baud source |
| 3rd PCA module (CCAPM2) | yes | **MODELLED** | |
| ADRJ at CLK_DIV.5 | yes | **MODELLED** | Moved from AUXR1.2 |
| INT_CLKO/AUXR2 | yes | **REGISTERED** | Cell at 0x8F |
| SPI (SPSTAT/SPCTL/SPDAT) | yes | **REGISTERED** | Cells at 0xCD-0xCF, no SPI |
| Peripheral switch (P_SW1/P_SW2) | yes | **REGISTERED** | AUXR1 cell; P_SW2 at 0xBA |
| Wake-up timer (WKTCL/WKTCH) | yes | **REGISTERED** | Cells at 0xAA-0xAB |
| BUS_SPEED | yes | **REGISTERED** | Cell at 0xA1 |
| Comparator | **yes** | **ABSENT** | STC15 has one, not modelled |
| External interrupts 2-4 | **yes** | **ABSENT** | INT_CLKO bits registered |
| Power modes | yes | **ABSENT** | |

## STC89C52RC

| Peripheral | Chip | Model | Notes |
|---|---|---|---|
| 12T core | yes | **MODELLED** | clock_per_cycle=12, verified 12x |
| Timer 0/1 (standard 8052) | yes | **MODELLED** | Via cl_uc52 base |
| Timer 2 (T2CON at 0xC8) | yes | **MODELLED** | Standard 8052 Timer 2 |
| UART1 (Timer 1 baud) | yes | **MODELLED** | Basic byte-level |
| Ports P0-P3 (quasi-bidir) | yes | **MODELLED** | No mode registers |
| Watchdog (WDT_CONTR at 0xE1) | yes | **REGISTERED** | Cell exists, no reset |
| ISP/IAP (0xE2-0xE7) | yes | **REGISTERED** | Cells exist, no flash ops |
| SADDR/SADEN | yes | **REGISTERED** | |
| SPI | **yes** | **ABSENT** | STC89 has SPI, not modelled |
| Power modes | yes | **ABSENT** | |

## STC15W408AS

Everything from STC15F above, minus Timer 1 and P4/P5:

| Peripheral | Chip | Model | Notes |
|---|---|---|---|
| No Timer 1 | correct | **MODELLED** | Timer 1 hardware absent |
| No P4/P5 | correct | **MODELLED** | Port mode regs absent |
| 1 UART only | correct | **MODELLED** | UART2 absent |
| All other STC15 peripherals | yes | same as STC15F | |

## Summary

| Category | Count | Impact |
|---|---|---|
| **MODELLED** (behavioral) | 12 peripheral blocks | Core, timers, AUXR, ports, ADC, PCA, WDT, dual DPTR |
| **REGISTERED** (SFR cell only) | 10 peripheral blocks | Firmware can write without UNMODELLED warning |
| **ABSENT** (not in model) | 3 peripheral blocks | SPI, comparator, power modes |

The REGISTERED peripherals are ones real firmware writes but whose behavioral
effects don't matter for the differential ladder: SPI transfers don't produce
SFR events on the watched list, IAP reads/writes don't affect timer or port
behavior, and multiprocessor addressing doesn't affect UART byte delivery.

The ABSENT peripherals (SPI, comparator, power modes) would need new hardware
element classes. SPI is the most impactful — several firmware images in the
corpus use it.

## Cross-model agreement: PWM edge rate

Two independent models arrive at the same physical quantity:

| Source | Derivation | Result |
|--------|-----------|--------|
| **ucsim-stc** (7e3cee2) | `pwm_set(0, 50)` → PCA at SYSclk/12, period measured at PIN events | **277.6 µs** = 3.60 kHz = **7.2 K edges/sec** |
| **bw-board** (PARTS-TO-BLOCKS.md) | Performance budget measurement, PWM at `CMOD=0x00` | **7.2 K edges/sec** |

Both use the same clock source (SYSclk/12 = 11059200/12 = 921600 Hz),
the same PCA period (256 counts), and arrive at 921600/256 = 3600 Hz
= 7200 edges/sec. The agreement is arithmetic, not coincidental — but
it confirms bw-board's 1.1×-real-time headroom figure was computed
against a realistic edge rate.

**Caveat:** two models agreeing is not silicon agreeing. Both derive
from the same datasheet section (§10, PCA clock = SYSclk/12 when
`CMOD.CPS2:1:0 = 000`). A shared misreading would produce exactly
this agreement.

### Duty vs brightness: which emulator has both halves?

ucsim-stc verifies **duty** (50.0% at the pin) but has no board
adapter. emu8051-stc has `emu8051-adapter.js` — a working boundary A
adapter that calls `board.setPin()` on every pin change — AND it
models PCA PWM (full 9-bit comparator, double buffering, pin output
in `stc12.c` line 640–680).

So the **brightness question is answerable today** via emu8051-stc +
bw-board, with no new code needed from ucsim-stc. What is missing is
not the interface — boundary A is implemented — but a ucsim-specific
adapter. That is one file to write, not one architecture to design,
and it should satisfy `bw-board/conformance.js` on day one.

Correction: the earlier version of this section stated "the interface
needed to ask this question is missing." That was wrong — I should
have grepped for `emu8051-adapter.js` before recording it.
