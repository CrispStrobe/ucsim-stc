# spec-update 019: bench procedures for three unassigned instruments

**Date:** 2026-08-12
**Covers:** NeoPixel WS2812B strip, logic analyser on I2C SCL,
ammeter on Arduino Nano LED.

These three instruments are named in the verification ledger but no
existing bench ID (BENCH-ADC / BENCH-CUBE / BENCH-PWM / BENCH-UART)
covers them.  Written as a spec-update rather than editing
`BENCH-RUNBOOK.md`, which is the owner's operational document.

---

## BENCH-NEO: WS2812B NeoPixel strip timing

### Pre-registered prediction

| Pulse | Predicted | WS2812B spec window |
|-------|-----------|---------------------|
| T0H   | **362 ns**  | 250–550 ns |
| T1H   | **814 ns**  | 650–950 ns |
| T0L   | **814 ns**  | 700–1000 ns |
| T1L   | **452 ns**  | 300–600 ns |

T1H and T0L are both 814 ns — a coincidence from distinct code paths
(both happen to be 9 machine cycles at 11.0592 MHz), verified by
edge-pairing in `tests/rung_neopixel_cross.sh`.

Source: ucsim-stc `564825d`, cross-checked between `stc12_trace` (ucsim)
and `emu_trace` (emu8051 post-`6cb9bc7`).  144 edges compared,
max |diff| = 1 ns (clock-period rounding).  **Category 1.**

### What the bench measures

Whether a real WS2812B strip shows the **correct colour** when driven
by the STC12C5A60S2.  The generated NeoPixel driver sends GRB bytes on
P1.5, bit-banged in assembly with timing calibrated to the 1T clock.

### Wiring

| Signal | Port bit | PDIP-40 chip pin | Connect to |
|--------|----------|------------------|------------|
| DATA   | P1.5     | **6**            | WS2812B DIN |
| VCC    | —        | 40 (VCC)         | WS2812B VCC (5 V) |
| GND    | —        | 20 (VSS)         | WS2812B GND |

P1.5 configured push-pull (`P1M1 &= ~0x20; P1M0 |= 0x20`).
No series resistor is strictly required for short runs (< 30 cm), but
a 330 Ω between chip pin 6 and DIN is good practice.  Power the strip
from the 5 V supply, not from the STC12's VCC pin.

### Firmware

`tests/fixtures/neo_v3.ihx` — nine GRB bytes, chosen to contain both
0-bits (`G=0x00`) and 1-bits (`R=0xFF`).

Flash: standard STC-ISP or `stcgal`.
Clock: **11.0592 MHz** internal RC.

### Procedure

1. Flash `neo_v3.ihx` to the STC12C5A60S2.
2. Connect wiring per the table above.  Strip should be ≤ 3 LEDs for
   signal integrity on a breadboard.
3. Power cycle the board.
4. **Observe colour.**

### Pass / fail / inconclusive

| Outcome | Reading | Interpretation |
|---------|---------|----------------|
| **Pass** | LEDs show the **expected colour** (green-red-... per the GRB sequence) | Timing within all four spec windows |
| **Fail — wrong colour** | LEDs light but show the **wrong colour** | At least one timing window violated — the strip decoded bits differently from what the driver intended |
| **Fail — dim/flickering** | LEDs flicker or are dim | Latch timing violated (inter-byte gap too short or too long) |
| **Inconclusive — no light** | LEDs do not light at all | Wiring problem (check DIN, VCC, GND), power supply issue, or chip not running.  This does not tell you about timing |

### What this measurement cannot settle

The two-emulator agreement is already category 1; a green result on
silicon **confirms** the prediction but does not raise the category
further.  A strip showing the correct colour means the driver's
bit-level timing is within the WS2812B's acceptance window — it does
not measure the *exact* nanosecond values (that would require a logic
analyser or oscilloscope on the DATA line).

If exact pulse widths are wanted: connect a logic analyser or scope to
chip pin 6.  The predictions are T0H=362, T1H=814, T0L=814, T1L=452 ns
±30 ns (clock rounding + probe loading).

---

## BENCH-I2C: Logic analyser on I2C SCL

### Pre-registered prediction

| Parameter | Predicted | Spec minimum (NXP UM10204 table 10, Sm 100 kHz) | Margin |
|-----------|-----------|--------------------------------------------------|--------|
| t_HIGH (SCL high period) | **5.61 µs** | ≥ 4.0 µs | +1.61 µs |
| t_LOW (SCL low period)   | **7.26 µs** | ≥ 4.7 µs | +2.56 µs |

1T mode (STC12C5A60S2, 11.0592 MHz).  12T reference: t_HIGH = 15.19 µs,
t_LOW = 36.89 µs.

Source: ucsim-stc `stc12_trace`, measured at P2.2.  **Category 3** —
single implementation, no cross-check exists for I2C.

History: v1 driver (`loop=13`) gave t_HIGH = 3.25 µs — **0.75 µs below
spec**.  Fixed in v2 (`loop=26`, bw-blocks `222b2ab`).  The prediction
before the re-measure was ~6.5 µs; actual was 5.61 µs, a 14% miss whose
residual is ~0.89 µs of fixed per-call overhead in `i2c_delay()`.

### What the bench measures

Whether real SCL timing on an STC12 running the I2C LCD driver meets
NXP I2C standard-mode minimums.  This is category 3 — the bench would
be the **first independent check** of the timing model, not a
confirmation of prior agreement.

### Wiring

| Signal | Port bit | PDIP-40 chip pin | Connect to |
|--------|----------|------------------|------------|
| SDA    | P2.1     | **22**           | PCF8574 SDA (+ 4.7 kΩ pull-up to VCC) |
| SCL    | P2.2     | **23**           | PCF8574 SCL (+ 4.7 kΩ pull-up to VCC) |
| VCC    | —        | 40               | PCF8574 VCC (5 V) |
| GND    | —        | 20               | PCF8574 GND |
| PROBE  | —        | —                | Logic analyser CH1 → chip pin 23 (SCL) |

Port mode: open-drain (`P2M1 |= 0x06; P2M0 |= 0x06`).
Pull-ups: 4.7 kΩ to VCC on both SDA and SCL.  Without them, the bus
stays low — open-drain has no active high drive.

### Firmware

`tests/fixtures/i2c_1t_v2.ihx` — the v2 I2C driver with `loop=26`.

Clock: **11.0592 MHz** internal RC.

### Procedure

1. Flash `i2c_1t_v2.ihx` to the STC12C5A60S2.
2. Connect wiring per the table above.  The LCD module
   (PCF8574 + HD44780) is the load; without it, pin 23 still toggles
   but there is no ACK, so the protocol stalls after the address byte.
   For timing measurement alone, a bare PCF8574 on the bus is sufficient.
3. Connect logic analyser probe to chip pin 23 (SCL).  Ground clip to
   pin 20 (VSS).  Sample rate ≥ 2 MHz (0.5 µs resolution).
4. Power cycle the board.  Capture ≥ 100 ms of SCL (SDCC init takes
   ~100 ms; the I2C activity starts after that).
5. Measure t_HIGH and t_LOW on the captured waveform.

### Pass / fail / inconclusive

| Outcome | Reading | Interpretation |
|---------|---------|----------------|
| **Pass** | t_HIGH ≥ 4.0 µs **and** within ±0.5 µs of 5.61 µs; t_LOW ≥ 4.7 µs and within ±0.5 µs of 7.26 µs | Model matches silicon |
| **Fail — below spec** | t_HIGH < 4.0 µs or t_LOW < 4.7 µs | Loop count still too short; bus will malfunction with strict slaves |
| **Fail — far from prediction** | Within spec but > 1.0 µs from prediction | Model is wrong (clock trim, pin capacitance, or overhead not modelled) |
| **Inconclusive — no edges** | SCL stays low or high | Wiring problem (check pull-ups, port mode, chip running).  No timing data |
| **Inconclusive — between spec and prediction** | t_HIGH is 4.0–5.1 µs (in spec but > 0.5 µs below prediction) | The model's fixed overhead (0.89 µs) may be wrong; does not necessarily mean the bus will malfunction |

### What this measurement cannot settle

This measures only the **clock phase timing**, not the full I2C
protocol.  Whether the PCF8574 address byte is correct, whether ACK is
received, whether the LCD initialisation sequence works — those are
protocol-level questions that require either an I2C protocol decoder
(most logic analysers have one) or observing the LCD display.

A second emulator implementing I2C (neither emu8051 nor simavr has one)
would raise the category to 2 or 1 without needing silicon.

---

## BENCH-AVR: Ammeter on Arduino Nano LED

### Pre-registered prediction

| Parameter | Predicted | Derivation |
|-----------|-----------|------------|
| Duty cycle | **0.5882** (58.82%) | 500 ms ON / (500 + 350) ms total |
| I_on | **11.76 mA** | (VCC − Vf) / (R + Rd + Rth) = (5 − 2) / (220 + 10 + 25) = 3/255 |
| I_avg (ammeter reading) | **6.92 mA** | I_on × duty = 11.76 × 0.5882 |

Circuit model: VCC = 5 V, R = 220 Ω, LED Vf = 2 V, LED Rd = 10 Ω
(dynamic resistance), ATmega328P pin source resistance Rth = 25 Ω.

An earlier estimate of "close to 0.68" was wrong — it omitted Rd.

Source: avr8js (bw-board adapter), cross-checked against simavr
(`bw-board spec-updates/avr-cross-check.md`) — 5 ns agreement on ON
period (500,000,125 vs 500,000,130 ns).  Third anchor: ucsim_avr
(`ucsim-stc 1b4c257`) confirmed 769-cycle toggle period via
hand-verified instruction costs.  **Category 1.**

### What the bench measures

Whether the average LED current on a real Arduino Nano matches the
predicted duty cycle.  This is the first AVR measurement on silicon —
no AVR hardware has run anything in this campaign.

### Wiring

| Signal | Arduino pin | ATmega328P port | Connect to |
|--------|-------------|-----------------|------------|
| LED    | **D13**     | **PB5**         | Onboard LED (already wired on the Nano) |
| AMMETER | —          | —               | In series with D13 external LED circuit, or inline with onboard LED |

If using the **onboard LED** (simplest): insert the ammeter between the
Nano's 5 V pin and VCC rail.  The reading will include the board's own
quiescent draw (~15 mA).  Subtract that baseline (measured with the
blink sketch not running, or with D13 held low).

If using an **external LED**: wire D13 → 220 Ω → LED anode, LED
cathode → ammeter → GND.  The reading is purely the LED current.

### Firmware

The standard Arduino blink sketch (`_delay_ms(500)` toggle), compiled
by the hosted avr-gcc endpoint (`POST /compile`, target `atmega328p`).
`tests/fixtures/avr_blink_compiled.ihx` is a pre-built version with a
loop delay (not `_delay_ms`, but functionally equivalent).

Clock: **16 MHz** external crystal (standard Nano).

### Procedure

1. Flash the blink hex to the Nano via `avrdude` or the Arduino IDE.
2. Connect the ammeter as described above.
3. Set the ammeter to DC mA range (20 mA scale).
4. Power the Nano.  The LED should visibly blink.
5. Read the ammeter.  It shows the **time-averaged** current.

### Pass / fail / inconclusive

| Outcome | Reading | Interpretation |
|---------|---------|----------------|
| **Pass** | **5.5–8.3 mA** (±20% of 6.92) with external LED; or the onboard delta (blink − baseline) is in this range | Duty cycle and circuit model match |
| **Fail — too high** | > 10 mA | Firmware stuck on, or duty much higher than predicted |
| **Fail — too low** | < 2 mA | Firmware not blinking, or LED not conducting |
| **Inconclusive — onboard baseline uncertain** | Reading is in range but baseline subtraction is ambiguous (board draws variable current) | Use the external LED circuit instead; the onboard path has too much common-mode noise for a precise duty measurement |

### What this measurement cannot settle

An ammeter cannot tell you **whether the timing is right** — only the
time-averaged duty.  A 50/50 duty at 2× speed would read the same
current as a 50/50 duty at the correct speed.  To verify the actual ON
and OFF periods (500 ms and 350 ms), use an oscilloscope or logic
analyser on D13.

The ammeter also cannot distinguish the pin's source resistance
(Rth = 25 Ω assumed) from the LED's dynamic resistance (Rd = 10 Ω
assumed).  Both are small compared to R = 220 Ω, so their combined
effect on total current is < 15%.  A more informative test would
measure the voltage across R with a scope and compute I = V/R directly.

### Is this bench slot worth the setup?

Marginally.  The cross-emulator agreement is already category 1 with
5 ns precision, and the ammeter's ±20% band is wide enough to pass
even with wrong assumptions about Rd and Rth.  The ammeter confirms
"the Nano blinks at roughly the right duty" — it does not add
precision.

**Recommendation:** if an oscilloscope is available, measure the ON/OFF
periods directly on D13.  That is strictly more informative than the
ammeter and uses the same probe.  If only an ammeter is available, it
is still worth running: it is the first AVR-on-silicon measurement in
this campaign, and even a coarse pass is evidence that the firmware
runs at all.

---

## Summary

| Bench ID | Instrument | Category before bench | What the bench does |
|----------|------------|----------------------|---------------------|
| BENCH-NEO | WS2812B strip | **1** (cross-emu, 144 edges, 1 ns) | Confirms silicon matches the 362/814/814/452 ns timing |
| BENCH-I2C | Logic analyser | **3** (ucsim only) | **First independent check** — could promote to cat 2 |
| BENCH-AVR | Ammeter (or scope) | **1** (avr8js + simavr + ucsim_avr) | First AVR-on-silicon measurement; coarse duty confirmation |

BENCH-I2C has the highest marginal value — it is category 3 and the
bench is its only path to promotion.  BENCH-NEO confirms an already
strong result.  BENCH-AVR is the weakest return on setup time, but is
the campaign's only AVR contact with real hardware.
