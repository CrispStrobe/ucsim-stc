# Part-kind differential ledger

Maps the STC12-projectable subset of bw-audit's 114-kind electrical sweep
to ucsim-vs-emu8051 differential test programs. Runner: `tests/rung_partkind_diff.sh`.

## Category

All entries are **category 1** (independent-source agreement): ucsim (Drotos, GPL, C++)
vs emu8051 (Komppa, MIT, C). Both run the same SDCC-compiled IHX. The SFR+TF event
trace must match exactly (or prefix-match if one emulator runs further).

## Ledger

| Part kind | MCU peripheral | Test program | Events | Status |
|---|---|---|---|---|
| **GPIO output** | | | | |
| led | GPIO P1 output | traffic_light, dual_blink, sos_morse, multi_led, port_full | 42–159 | AGREE |
| rgb_led | GPIO P1 multi-pin | multi_led (4-pin walk), port_full (8-pin) | 44, 38 | AGREE |
| relay | GPIO → NPN → coil | relay_npn, relay_test | 27, 6 | AGREE |
| dc_motor (simple) | GPIO → NPN drive | relay_npn (same MCU path) | 27 | AGREE |
| solenoid | GPIO → NPN drive | relay_npn (same MCU path) | 27 | AGREE |
| vibration_motor | GPIO → NPN drive | relay_npn (same MCU path) | 27 | AGREE |
| light_bulb | GPIO output | relay_npn (same MCU path) | 27 | AGREE |
| optocoupler | GPIO output | relay_npn (same MCU path) | 27 | AGREE |
| darlington_driver | GPIO → NPN drive | relay_npn (same MCU path) | 27 | AGREE |
| tip120 | GPIO → NPN drive | relay_npn (same MCU path) | 27 | AGREE |
| piezo | GPIO output (on/off) | sos_morse (same MCU path as buzzer GPIO) | 159 | AGREE |
| **GPIO input** | | | | |
| button | GPIO P3.2 read | button_poll, button_test | 16, 2 | AGREE |
| dip_switch | GPIO input read | button_poll (same MCU path) | 16 | AGREE |
| tilt_sensor | GPIO input read | button_poll (same MCU path) | 16 | AGREE |
| pir | GPIO input read | button_poll (same MCU path) | 16 | AGREE |
| ir_receiver | GPIO input read | button_poll (same MCU path) | 16 | AGREE |
| phototransistor | GPIO input read | button_poll (same MCU path) | 16 | AGREE |
| **Port mode** | | | | |
| (source_vs_sink) | P1M1/P1M0 all 4 modes | port_mode | 45 | AGREE |
| **ADC input** | | | | |
| potentiometer | ADC ch2 (P1ASF, ADC_CONTR) | adc_multi | 24 | AGREE |
| ldr | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| ntc | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| tmp36 | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| flex_sensor | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| force_sensor | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| soil_moisture | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| ambient_light | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| gas_sensor | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| photodiode | ADC input | adc_multi (same MCU path) | 24 | AGREE |
| **Multi-pin GPIO sequence** | | | | |
| shift_register (74hc595) | bit-bang SPI (data/clock/latch) | shift_out | 103 | AGREE |
| 74hc95 | shift register | shift_out (same MCU path) | 103 | AGREE |
| stepper | 4-pin half-step sequence | stepper_seq | 98 | AGREE |
| h_bridge | 2-pin direction + enable | hbridge | 49 | AGREE |
| seven_segment | port mask write | port_full (same MCU path) | 38 | AGREE |
| led_matrix | multiplexed port write | port_full, multi_led (same MCU path) | 38, 44 | AGREE |
| led_cube | multiplexed port write | port_full (same MCU path) | 38 | AGREE |
| bargraph | multi-pin output | multi_led (same MCU path) | 44 | AGREE |
| dc_motor_encoder | GPIO + direction | hbridge (same MCU path) | 49 | AGREE |
| gearmotor | GPIO + H-bridge | hbridge (same MCU path) | 49 | AGREE |
| **PCA/PWM** | | | | |
| servo | PCA compare/match (CEX0) | servo_90 | 3 | AGREE |
| dc_motor (PWM) | PCA PWM (CCP1) | motor_50 | 39 | AGREE |
| buzzer (tone) | PCA PWM | pwm_50pct | 38 | AGREE |
| **Bit-bang protocol** | | | | |
| neopixel | WS2812 bit-bang | rung_neopixel_cross (144 edges, max 1ns diff) | 144 | AGREE (cat 1) |
| char_lcd_i2c | I2C bit-bang | rung_lcd_i2c (v1/v2/12T) | 309/195/50 txns | single-emu |
| **Ultrasonic** | | | | |
| ultrasonic | trigger pulse (GPIO timed) | ultrasonic_fixed | 12 | AGREE |
| **P5 port (STC15 only)** | | | | |
| buzzer (P5.5) | P5M1/P5M0 all 4 modes | p5_mode (STC15, PIN+TF) | 17 | AGREE |
| **Timer/UART** | | | | |
| (timer1) | Timer 1 overflow | timer1_test | 11 | AGREE |
| (uart) | UART TX bit period | uart_tx_test | 3 | AGREE |

## Part kinds NOT STC12-projectable

These appear in the 114-kind sweep but are passive/analog circuit elements with no MCU
pin interaction, or are MCU/board kinds themselves:

| Category | Kinds |
|---|---|
| Passive components | resistor, capacitor, polarized_cap, inductor, diode, zener, fuse |
| Analog ICs | lm339, lm393, lm7805, ld1117v33, vreg, timer_555, timer_556, opamp |
| Logic gates (standalone) | 74hc00, 74hc02, 74hc04, 74hc08, 74hc10, 74hc11, 74hc14, 74hc20, 74hc21, 74hc27, 74hc32, 74hc73, 74hc74, 74hc75, 74hc86, 74hc93, 74hc132, 74hc283 |
| Power sources | battery, battery_9v, battery_aa, battery_coin, solar_cell, vcc, vsource, isource |
| MCU/board kinds | mcu, arduino_uno, arduino_nano, pi_pico |
| Wiring/structural | header, breadboard, usb_a |
| I2C bus devices | pcf8574, eeprom, char_lcd (need I2C master) |
| IR compound | ir_remote, ir_transmitter (TX-side, no MCU read) |
| Display compound | clock_display, cd4511, decade_counter (driven by logic, not direct MCU) |

## Notes

- "Same MCU path" means the part kind is electrically identical from the MCU's perspective.
  A relay and an LED both appear as a GPIO output pin toggle. The differential proves the
  MCU-side SFR/timer behaviour; the part-kind difference is in the circuit, not the firmware.
- `char_lcd_i2c` is single-emulator only: emu8051 does not model I2C bit-bang timing.
  The I2C protocol edges are verified in `rung_lcd_i2c.sh` against the HD44780 spec.
- `adc_temp_test` (existing fixture) has a known ADC stimulus mapping difference between
  emu8051 and ucsim (512 → different ADC_RES values). Register sequence and timing agree.
  The `adc_multi` fixture avoids this by using a simpler program.
