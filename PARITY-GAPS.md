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
element classes. None are exercised by emitted code or the 347-image corpus.

## Emitted code vs model: what is verified, what is merely executed

Crossed the emitter's lowerings against model status. A program whose
SFR writes land on cells-only registers has been *executed*, not
*verified* — and "verified under emulation" in a commit message does
not distinguish the two. Per `stc/docs/EVIDENCE-CATEGORIES.md`, a
program verified against a modelled peripheral is at best category 2b;
a program merely executed against SFR cells is not evidence at all.

| Emitted code path | SFRs | Model | Verifiable? |
|---|---|---|---|
| Pin set/clear/toggle | Px, PxM0/M1 | **Modelled** | Yes — port data + mode tracked |
| Port write | Px | **Modelled** | Yes |
| Timer 0 (bw_tick, delay_ms) | TMOD, TH0/TL0, TCON, AUXR | **Modelled** | Yes — 1T/12T prescaler |
| Timer 1 (TONE pin) | TMOD, TH1/TL1, TCON | **Modelled** | Yes |
| ADC read | P1ASF, ADC_CONTR/RES/RESL | **Modelled** | Yes — power/start/flag cycle |
| PWM set (PCA) | CMOD, CCON, CCAPnH, PCA_PWMn | **Modelled** | Yes — 25/50/75% verified at pin |
| LED cube scan | P0, P2 | **Modelled** | Yes — 124.1 Hz measured |
| 74HC595 shift register | Px_n bit writes | **Modelled** | Yes — bit-bang, order-only |
| Interrupt enable/disable | IE, IP | **Modelled** | Yes — standard 8051 dispatch |
| **UART TX (uart_putc)** | SCON, SBUF, TI | **Modelled** | Yes — TI fires after frame time from BRT/T2 baud clock |
| **UART RX (uart_getc)** | SCON, SBUF, RI | **Cells only** ⚠ | **No** — RI never rises, RX hangs |
| **BRT baud (STC12)** | BRT, AUXR | **Modelled** | Yes — 8-bit auto-reload, overflows feed serial port |
| **Serial print (bw_print)** | SCON, SBUF | **Cells only** ⚠ | **No** — same as UART TX |

**11 of 13 SFR-touching paths are modelled** and verifiable.
**2 of 13 remain cells-only** — UART RX (RI never rises) and
serial print (uses TX, which now has timing, but the print
function itself is a no-op wrapper).

### BW_STUB: device helpers that compile but do nothing on hardware

In addition to the 13 SFR-touching paths above, `generateC()` emits
**31 device-helper stubs** (grep `BW_STUB:` in generated C). These
compile and the program runs, but on hardware they do nothing — the
real work would be an I2C/SPI/PWM protocol to an external device
that the emitter has not lowered to SFR writes.

| Category | Count | What happens |
|----------|-------|-------------|
| Actuator no-ops | 15 | `void` → empty body. Servo, motor, relay, LCD, RGB, matrix, neopixel calls vanish. |
| Reporter fabrications | 16 | `return 0`. Temperature, distance, light, force, IR, pressed, motion sensors always read 0. |

A program that calls `bw_servo_set(0, 90)` compiles, runs under the
emulator, and produces no visible effect anywhere. A program that
reads `bw_temperature(0)` compiles, runs, and always gets 0 — a
plausible temperature. Neither the emulator nor the hardware can
distinguish "sensor returned 0" from "sensor not connected."

**This is not an emulator gap — these stubs are by design.** The
emitter documents them: *"The stubs make the code compile and record
the call for the simulator."* The simulator (bw-board + bw-circuit-ui)
is the intended consumer, not the emulator. But the stubs mean that
"compiles and runs under emulation" is strictly weaker than "works"
for any program that uses a device helper.

**The full inventory of what `generateC()` emits:**

| Tier | Count | What it is | Emulator status |
|------|-------|-----------|----------------|
| **Real SFR work** | 11 | Pins, timers, ADC, PCA, cube, 74HC595, interrupts, UART TX, BRT | **Modelled** — verifiable |
| **UART/serial** | 2 | RX, print | **Cells only** — executed, not verified |
| **BW_STUB** | 31 | Device helpers (servo, motor, LCD, sensors…) | **No-op / return 0** — compiles, does nothing |
| **Total** | 44 | | 11 verifiable, 2 executed-only, 31 stubs |

The UART gap matters because `10-live-firmware` (the on-chip debug
monitor) is entirely UART-driven. It runs, its timer setup is verified
(baud reload table), but its protocol — HELLO, POS, REGS, READ — has
only been verified on emu8051-stc, which delivers bytes regardless of
baud. Neither emulator can detect a baud mismatch on the wire.

## Cross-model agreement: PWM edge rate

Two independent models arrive at the same physical quantity:

| Source | Derivation | Result |
|--------|-----------|--------|
| **ucsim-stc** (d4701f2) | `pwm_set(0, 50)` → PCA at SYSclk/12, period measured at PIN events | **277.6 µs** = 3.60 kHz = **7.2 K edges/sec** |
| **bw-board** (PARTS-TO-BLOCKS.md) | Performance budget measurement, PWM at `CMOD=0x00` | **7.2 K edges/sec** |

Both use the same clock source (SYSclk/12 = 11059200/12 = 921600 Hz),
the same PCA period (256 counts), and arrive at 921600/256 = 3600 Hz
= 7200 edges/sec. The agreement is arithmetic, not coincidental — but
it confirms bw-board's 1.1×-real-time headroom figure was computed
against a realistic edge rate.

**Re-verified after PCA CL-wrap fix** (`f531860`): PWM period
unchanged at 277,561 ns to the nanosecond. The 8-bit PWM path
compares `CL` vs `CCAPnL` only, never reads `CH` — the
wrap-ordering fix is in a disjoint code path (16-bit compare
with `bmMAT && !bmPWM`). 7.2K edges/sec is re-earned.

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
