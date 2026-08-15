# ucsim-stc handoff

Written 2026-08-15 at session end. Read CLOSE-OUT.md for the full STC campaign;
this covers everything a fresh session needs.

## Lane state: what is DONE

### Test harness — 16 suites, all green (verified 2026-08-15)

`tests/run_all.sh` runs everything. Last full pass: 16/16, 0 fail.

| Suite | Runner | Result |
|---|---|---|
| Smoke (STC12/15/89/15W) | `tests/smoke.sh` | 29 pass |
| Timing (1T/12T/FOSC) | `tests/rung_timing.sh` | 6 pass |
| Multi-part differential | `tests/multipart_diff.sh` | 9 pass |
| Cross-part examples | `tests/crosspart_examples.sh` | 9 pass |
| Model difference (12 vs 89) | `tests/rung_model_diff.sh` | 6 pass |
| Baud divergence (BRT vs T2) | `tests/rung_baud.sh` | 7 pass |
| NeoPixel WS2812 | `tests/rung_neopixel.sh` | 4 pass |
| LCD I2C protocol | `tests/rung_lcd_i2c.sh` | 14 pass |
| AVR blink cycles | `tests/rung_avr_blink.sh` | 8 pass |
| Example differentials | `tests/examples_diff.sh` | 9 pass |
| Boundary D ladder | `tests/run_control_diff.sh` | 6 pass |
| AVR oracle (simavr vs avr8js) | `tests/rung_avr_oracle.sh` | 22 pass, 2 known |
| Simavr canonical-trace | `tests/rung_simavr_canonical.sh` | 6 pass |
| NeoPixel cross-emu (cat 1) | `tests/rung_neopixel_cross.sh` | green |
| nRF52840 bare-metal | `tests/rung_nrf52840_bare.sh` | 5 pass |
| System ROM boots | `tests/rung_system_rom_boots.sh` | 11 pass |

Additional audit: `tests/rung_emu8051_bp_write.sh` — 15/15 (all 7 wasm builds export `emu_dbg_set_bp_write`, capabilities() reports `"write"` everywhere).

### Task-18: micro:bit V2 register-level run path — DECIDED

**Verdict: labwired-now, not blocked-on-upstream.**

- Two clean-room ARM Thumb-2 bare-metal programs execute correctly under labwired's silicon-verified nRF52840 model (`9d8e8f5`).
- nRF52833 chip config created at `tests/fixtures/nrf52840/nrf52833_chip.yaml` (`512d52f`). Both programs run identically under it.
- Delta report: `spec-updates/021-nrf52833-vs-52840-microbit-v2.md`. Peripherals register-compatible at identical addresses for GPIO, UART, TIMER, TWI, PWM, SAADC. Not independently silicon-verified — the 52840 capture (11 suites) is the oracle.
- One gap: `--gpio-trace` does not emit events for the nRF GPIO model. GPIO edges verified via UART-reported state transitions.

**Reproduction:**
```bash
arm-none-eabi-as -mcpu=cortex-m4 -mthumb -o X.o X.S
arm-none-eabi-ld -T tests/fixtures/nrf52840/gpio_toggle.ld -o X.elf X.o
labwired-core/target/release/labwired run \
  --chip tests/fixtures/nrf52840/nrf52833_chip.yaml --firmware X.elf --max-steps N
```

### System ROM boot CI oracle — 3 engines, 11/11

Runner: `tests/rung_system_rom_boots.sh`. Re-verified 2026-08-15 against bw-board HEAD (`39a10cb`).

| System | Engine | What it proves |
|---|---|---|
| Tali Forth 2 (public domain) | W65C02 | Banner, 2 3 + . → 5, : sq dup * ; 7 sq . → 49, WORDS |
| ehBASIC / MS BASIC V1.1 (NC) | M6502 | MEMORY SIZE? → OK → PRINT 2+3 → 5 |
| CP/M 2.2 + BBC BASIC (Z80) | Z80 | Cold boot → DIR → BBCBASIC launch → PRINT 2+2 → 4 |

Dependencies (all read-only references, NOT in this repo):
- bw-board: `/mnt/volume1/code/bw-board` — W65C02, M6502Machine, Z80Machine engines
- TaliForth2: `/mnt/volume1/code/TaliForth2/taliforth-py65mon.bin` (public domain)
- ehBASIC ROM: `/mnt/volume1/code/basic-m6502-bw/basic.bin` (NC, 32K, EATER6502 preset)
- BBCZ80: `~/code/BBCZ80/bin/cpm/BBCBASIC.COM` (zlib)
- CP/M: `bw-board/roms/cpm/cpm22-64k.bin` + `bios.bin` (Caldera/MIT)

### PicoBB — BBC BASIC for Pico under RP2040 emulation

`tests/picobb_boot_rp2040js.mjs` boots PicoBB under rp2040js: banner + `PRINT 2+2` → `4`.

Three patches required (all in the script):
1. Real RP2040 B1 bootrom (from `wokwi/rp2040js` demo, commit `00a4a19`)
2. SIO FIFO stub: FIFO_ST=0x02 (VLD=0, RDY=1) — rp2040js returns 0xFFFFFFFF for unknown SIO addresses
3. ANSI terminal: respond to ESC[6n with ESC[24;80R

Build from source: `TYPE=pico STDIO=UART SOUND=NONE BOARD=pico` (SOUND=NONE avoids multicore deadlock).
Prebuilt V23_03 `bbcbasic_pkc.uf2` fails (CYW43 driver blocks). Binaries gitignored.

**Forward note:** the FIFO_ST gap affects any rp2040js firmware that touches the multicore FIFO. bw-board's adapter should eventually stub SIO 0x50/0x54/0x58 the same way.

### emu8051 write-watchpoint audit — CONFIRMED

`tests/rung_emu8051_bp_write.sh`: all 7 shipped wasm builds (emu8051-stc/build, lego src/build/overlay, bw-bundle src/build/overlay) export `emu_dbg_set_bp_write`. `capabilities()` reports `"write"` in breakpoints everywhere. Deployed copies are byte-identical (md5 `d44df13d`). No rebuild was needed.

### sb3-creator: generateBASIC full Scratch surface

Pushed to sb3-creator (`fad322c`→`0c15f47`). 35/35 gallery examples emit `ok:true` (was 0/35).

Coverage: say/think→PRINT, ask→INPUT answer$, operators→BBC math/string, lists→DIM arrays, pen→VDU MOVE/DRAW/GCOL, motion→tracked bw_x%/bw_y%, timer→TIME/100, key_pressed→INKEY. Costumes/sounds/broadcasts/clones→REM stubs. Multi-WHEN serializes. Non-w65c02 pin ops→REM stubs.

Reader inverses (`basicToPseudocode.js`): INPUT→ask, CLG→clear, GCOL→pen color, MOVE/DRAW→go to, MID$→letter, LEN→length, INSTR→contains, TIME/100→timer, TIME=0→reset timer, bw_pen%→pen down/up.

Test: `test/basic-sweep.test.mjs` (188 assertions). 379 total tests pass, eslint clean.

## Blocked — waiting on external

| Item | Blocked on | Unblocked by |
|---|---|---|
| Resync e2e | bw-board owns the test | spec-updates/017 (they have the corrected invocation) |
| Bench procedures | Physical instruments | spec-updates/019 (procedures written, predictions registered) |
| labwired gpio-trace for nRF | labwired upstream | Not a blocker for task-18 (UART-reported edges suffice) |

## Known upstream bugs (workarounds in place)

- **ucsim_avr word-0 clobber**: ROM[0] reads 0 after hex load. Workaround: `set mem rom 0 <value>`.
- **ucsim_avr IO map**: AT90S-era addresses (PORTB at IO 0x18), not ATmega328P. Cosmetic only.
- **ucsim_avr disassembler**: LDI/OUT show wrong register names (d decoded as r0..r15, should be r16..r31). Execution correct.
- **simavr 1.6 UART**: overcounts frame by 1 bit in 8N1 (phantom parity). spec-updates/018.

## Learned but not in a spec-update

- **stc12_trace build rule**: `Makefile.in` has the target but `./configure`'s `Makefile` doesn't propagate. Use `make -f Makefile.in stc12_trace`.
- **`-inject` and `-e` are incompatible**: `-inject` requires `-until-ns`, not `-e 'run ...'`. spec-updates/017.
- **Portability**: use `grep -Eo` (POSIX ERE), not `grep -oP` (GNU Perl). Fixed in `6356b3b`.

## Key files

| File | What |
|---|---|
| `tests/run_all.sh` | Master test runner (16 suites) |
| `tests/rung_system_rom_boots.sh` | Tali Forth 2 + ehBASIC + CP/M (11/11) |
| `tests/rung_nrf52840_bare.sh` | nRF52840 bare-metal execution (5/5) |
| `tests/rung_emu8051_bp_write.sh` | emu8051 write-watchpoint audit (15/15) |
| `tests/picobb_boot_rp2040js.mjs` | PicoBB boot (rp2040js + FIFO stub) |
| `tests/rung_neopixel.sh` | WS2812 spec-window (single emu) |
| `tests/rung_neopixel_cross.sh` | WS2812 cross-emu (cat 1) |
| `tests/rung_avr_blink.sh` | AVR cycle-count (8/8) |
| `tests/rung_avr_oracle.sh` | simavr vs avr8js (22 pass, 2 known) |
| `tests/rung_lcd_i2c.sh` | LCD I2C protocol (14/14) |
| `tests/fixtures/nrf52840/` | ARM Thumb-2 programs + nRF52833 chip YAML |
| `tests/fixtures/picobb/` | PicoBB binaries (gitignored) |
| `spec-updates/021` | Task-18 decision: nRF52833 vs 52840 delta |
| `spec-updates/020` | LCD I2C + labwired nRF52840/ESP32-C3 validation |
| `spec-updates/019` | Bench procedures (NEO, I2C, AVR) |
| `spec-updates/018` | simavr UART phantom parity bug |
| `spec-updates/017` | `-inject` / `-e` incompatibility |
| `CLOSE-OUT.md` | Full STC campaign results |
| `PARITY-GAPS.md` | Emitter vs model matrix |
| `RESULTS.md` | Detailed methodology and numbers |
