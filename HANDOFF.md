# ucsim-stc handoff

For the next session. Read CLOSE-OUT.md for the full campaign; this is the delta.

## Completed since last handoff (2026-08-15 session)

- **nRF52840 bare-metal execution proven** (`9d8e8f5`): two clean-room ARM Thumb-2 programs run correctly under labwired's nRF52840 model. UART TX (ENABLE/STARTTX/TXD/TXDRDY) and GPIO (DIRSET/OUTSET/OUTCLR at standard Nordic addresses) both work. Test: `tests/rung_nrf52840_bare.sh` (5/5 pass).
- **nRF52833 vs 52840 delta report** (`spec-updates/021`): peripherals are register-compatible at identical addresses for everything course programs need (GPIO, UART, TIMER, TWI, PWM, SAADC). A 52833 chip YAML is a 20-line delta (flash/RAM size, FICR PART override, QSPI omit, P1 pin count). **Verdict: labwired-now, not blocked-on-upstream.**
  - One gap: `--gpio-trace` does not emit events for the nRF GPIO model (declarative register storage); GPIO edges verified via UART-reported state transitions instead.
- **nRF52833 chip config created** (`512d52f`): standalone at `tests/fixtures/nrf52840/nrf52833_chip.yaml`. Both bare-metal programs run identically under it. The micro:bit V2 execution path is unblocked.
- **System ROM boot CI oracle** — three system ROMs, all re-verified 2026-08-15:
  - **Tali Forth 2** (W65C02, public domain): banner + 2 3 + . → 5 + : sq dup * ; 7 sq . → 49 + WORDS. 4/4.
  - **ehBASIC / MS BASIC V1.1** (M6502, NC local only): MEMORY SIZE? → WIDTH? → 15871 BYTES FREE → OK → PRINT 2+3 → 5. 3/3.
  - **CP/M 2.2 + BBC BASIC (Z80)** (Caldera CP/M + zlib BBCBASIC.COM): cold boot → A> → DIR BBCBASIC.COM → launch → PRINT 2+2 → 4. 4/4.
  - Runner: `tests/rung_system_rom_boots.sh` (11/11). All in `run_all.sh`.
- **generateBASIC: full Scratch surface** (sb3-creator `fad322c`→`0c15f47`): 35/35 gallery examples emit ok:true (was 0/35). say/think→PRINT, ask→INPUT, operators→BBC math/string, lists→DIM arrays, pen→VDU MOVE/DRAW, motion→tracked vars, timer→TIME/100. Multi-WHEN serializes, non-w65c02 stubs. Reader inverses for INPUT/CLG/GCOL/MID$/LEN/INSTR/TIME. 379 tests pass, eslint clean.

### micro:bit V2 execution path — READY (task #18 unblocked)

The run path is proven end-to-end:
1. `tests/fixtures/nrf52840/nrf52833_chip.yaml` — chip config (or copy into labwired-core/configs/chips/)
2. `arm-none-eabi-as -mcpu=cortex-m4 -mthumb` + `arm-none-eabi-ld -T gpio_toggle.ld` — assemble bare-metal programs
3. `labwired run --chip nrf52833.yaml --firmware X.elf --max-steps N` — run; UART output on stdout
4. GPIO verified via UART-reported edges (--gpio-trace not yet wired for nRF GPIO model)
5. Peripheral delta documented in `spec-updates/021`: register-compatible at identical addresses for GPIO, UART, TIMER, TWI, PWM, SAADC. Not independently silicon-verified — the 52840 capture is the oracle.

## Completed since prior handoff (2026-08-13 evening session)

- **PicoBB boots under rp2040js** (`6a33d2c`): BBC BASIC for Raspberry Pi Pico (Memotech-Bill/PicoBB, zlib) boots under rp2040js emulation with UART console. Built from source with `TYPE=pico STDIO=UART SOUND=NONE BOARD=pico`. Three patches required:
  1. Real RP2040 B1 bootrom (from rp2040js/pico-bootrom, 16KB Uint32Array)
  2. SIO FIFO stub — rp2040js returns 0xFFFFFFFF for unknown SIO offsets, making FIFO_ST.VLD=1 (data available) permanently; firmware spins. Fix: FIFO_ST=0x02 (RDY=1, VLD=0), FIFO_RD=0
  3. ANSI terminal emulation — PicoBB sends ESC[6n cursor position queries for terminal detection; respond with ESC[24;80R
  - **SOUND=NONE required**: default SDL sound module calls `multicore_launch_core1()`, rp2040js is single-core, FIFO handshake deadlocks
  - **Prebuilt V23_03 `bbcbasic_pkc.uf2` fails**: includes CYW43 driver that blocks without wireless hardware
  - **labwired path investigated**: ELF loads, no crash with B1 bootrom, but no UART output after 120s/500M steps (root cause: labwired's SIO model likely has same FIFO gap)
  - Banner: `BBC BASIC for Pico Console v0.50`, prompt `>`, `PRINT 2+2` → `4`
  - 250M cycles, 3.1s simulated, 20s wall on this VPS
  - Test: `tests/picobb_boot_rp2040js.mjs`, binaries gitignored
  - **Reproduction recipe:**
    ```bash
    # 1. Bootrom — B1 revision, extracted from wokwi/rp2040js demo/bootrom.ts
    #    Source: https://github.com/raspberrypi/pico-bootrom commit 00a4a19114195e20fb817bdfbca1165e157eef37
    #    rp2040js bundles it as Uint32Array (4096 words = 16384 bytes)
    curl -sL https://raw.githubusercontent.com/wokwi/rp2040js/main/demo/bootrom.ts -o /tmp/bootrom.ts
    python3 -c "import re,struct; t=open('/tmp/bootrom.ts').read(); \
      vs=re.findall(r'0x([0-9a-fA-F]+)',t); \
      open('tests/fixtures/picobb/rp2040_bootrom_b1.bin','wb').write( \
        b''.join(struct.pack('<I',int(v,16)) for v in vs))"
    # Verify: sha256 should start with the B1 revision fingerprint
    # Vectors: SP=0x20041f00 PC=0x000000ef, magic at 0x10 = 4d750102

    # 2. Build PicoBB from source (requires pico-sdk + arm-none-eabi-gcc)
    git clone --depth 1 --recurse-submodules https://github.com/Memotech-Bill/PicoBB.git /tmp/PicoBB
    git clone --depth 1 https://github.com/raspberrypi/pico-sdk.git /tmp/pico-sdk
    cd /tmp/pico-sdk && git submodule update --init --depth 1 lib/tinyusb
    cd /tmp/PicoBB/console/pico
    PICO_SDK_PATH=/tmp/pico-sdk make TYPE=pico STDIO=UART SOUND=NONE BOARD=pico bbcbasic
    cp bbcbasic_console_pico.uf2 <project>/tests/fixtures/picobb/

    # 3. Run
    node tests/picobb_boot_rp2040js.mjs 60 --send "PRINT 2+2"
    # Expect: banner, ">", "PRINT 2+2", "         4", ">"
    ```
  - **Forward note (no action now):** the FIFO_ST gap (SIO offset 0x50 returning 0xFFFFFFFF) affects any rp2040js firmware that touches the multicore FIFO. bw-board's adapter should eventually stub SIO 0x50/0x54/0x58 the same way. The monkey-patch in `picobb_boot_rp2040js.mjs` is the reference implementation

- **nRF52840 + ESP32-C3 validation report** (`e625ad2`): spec-updates/020 complete. nRF52840 = deep behavioural (11 suites, temporal fidelity, boots Zephyr). ESP32-C3 = reset-state only (84/84 register values, cross-board, no runtime behavioural).

## Completed in prior sub-session

- **LCD I2C full protocol** (`fcdba07`): full I2C START/address/data/STOP decode on P2.1 (SDA) and P2.2 (SCL). Address 0x4E on all transactions, HD44780 init byte-identical across v1/v2/12T. SCL timing: v2 5606/7415 ns in spec, v1 3255 ns below spec (known). 14/14 pass. Cat 3. spec-updates/020, `tests/rung_lcd_i2c.sh`, `tests/decode_i2c_trace.py`.
- **AVR word-0 clobber investigated** (`8c092de`): NOT in `reset()`. `set_rom(0)` succeeds during hex parsing (immediate readback correct), but `rom->read(0)` returns 0 afterward. Cell data pointer remapping suspected. Upstream ucsim bug, affects only 16-bit ROM. Workaround unchanged.
- **JBC cycle count verified** (`8c092de`): already 2 MC (correct). `tickt()` default 1 + `instruction_10` `tick(1)` = 2. No fix needed.
- **run_all.sh expanded** (`4753346`): 13 suites (was 8). Added NeoPixel, LCD I2C, AVR blink, AVR oracle (simavr), NeoPixel cross-emu.
- **NeoPixel promoted** to cat 1 in README (was listed as 2b; cross-emu agreement was already in CLOSE-OUT).

## Completed in prior sessions

- **Servo 0°/90°/180°** measured: 499.1 / 1499.6 / 2500.0 µs, frame 20.0 ms exact. Category 3. STC89 produces 0 edges (no PCA) — bw-blocks added compile-time refusal (sb3-creator `6b0e6f6`).
- **I2C SCL timing** measured: v1 (loop=13) HIGH=3.25 µs — **below 4.0 µs spec**. v2 (loop=26) HIGH=5.61 µs, LOW=7.26 µs — both in spec. bw-blocks fixed in `222b2ab`.
- **NeoPixel cross-emu** (`564825d`): ran `neo_v3.ihx` through both `stc12_trace` and `emu_trace` (post-CLR/SETB fix `6cb9bc7`). 144 edges compared, max diff 1 ns (clock rounding), all 4 timing windows pass on both. **Category 2b → category 1.** Test: `tests/rung_neopixel_cross.sh`. Predictions: T0H=362, T1H=814, T0L=814, T1L=452 ns.
- **Motor duty** 33/50/75% at P1.4: 32.83% / 50.05% / 75.07%.
- **HC-SR04 trigger** measured: 4.7 µs (below 10 µs min), fixed to 10.4 µs (1T) / 20.6 µs (12T).
- **-inject TIME_NS,BYTE** flag in stc12_trace: schedules timed byte delivery to UART RX. RI rises after ~83 µs at 115200. Root cause of bw-board's INCONCLUSIVE: `-inject` requires `-until-ns`, not `-e 'run ...'` (spec-updates/017).
- **PCA interrupt dispatch** at 0x003B with per-module enable (CCAPMn.ECCF0, not IE.EC). IE.6 = ELVD (LVD), not EC — named trap in the peripheral model.
- **PCA CL-wrap fix**: CH must increment before the 16-bit compare, not after. Was causing 256-count (278 µs) systematic error.
- **UART TX bit-timing**: BRT model feeds serial baud clock. Bit period 86.8 µs exact. Naive STC15 port = 5 baud (23040× wrong).
- **CLR/SETB/CPL cycle audit**: ucsim = 1 MC (correct per MCS-51 spec). emu8051 had 3 MC (fixed in `6cb9bc7`). JBC is 1 MC in ucsim (should be 2, no driver uses it).
- **347-image sweep re-run** against fixed emu8051: 2 images reclassified, 0 genuine disagreements. Category 1.
- **steveschnepp/emu8051 fork audit**: bit-addressing fixes are logically equivalent to our code. No ledger impact.
- **Path sweep**: 0 `/mnt/volume1` in tracked files. 22 configure-generated Makefiles untracked.
- **README rewritten**: 4 parts, 8 suites, measurements with categories, what is NOT done.
- **Spec-update convention adopted** (session start scan, not every task).
- **AVR oracle — hand-assembled blink** (`1b4c257`): ucsim_avr executes the 6-word blink from `bw-board/test/avr8js-adapter.test.js`. All instruction cycle costs match avr8js exactly: SBI=2, DEC=1, BRNE-taken=2, LDI=1, RJMP=2. Toggle period = 769 cycles = 48062.5 ns at 16 MHz, confirmed 1540 ticks for 2 complete toggles. Test: `tests/rung_avr_blink.sh` (8/8 pass, portable grep per `6356b3b`).
- **AVR oracle — simavr vs avr8js differential** (`297961b`): libsimavr harness + avr8js harness, same hex files, compared pin edges / UART / ADC / timer timing. 13/13 pass, 2 known divergences:
  - **Pin edges agree exactly** on hand-assembled blink (769 cy), compiled blink (19015 cy), Timer1 CTC (±1 cy over 40k), Timer0 OVF (32768 cy avg, ±1 jitter).
  - **ADC completion timing matches** (cy 3262 for first ADC read).
  - **UART byte values match**; first byte cycle matches. **KNOWN BUG in simavr 1.6**: UART frame duration overcounts by 1 bit per byte (phantom parity bit — `avr_uart.c` adds `+1 parity` unconditionally, even for 8N1). Drifts 1664 cy/byte cumulative. Adjudicated: datasheet says 10 bits for 8N1, avr8js correct. spec-updates/018.
  - **OC1A pin visibility**: simavr fires PORTB IRQ on hardware COMnx toggles; avr8js (correctly) doesn't modify PORT register. Harness difference, not a bug.
  - **Scheduler integration**: cooperative scheduler (Timer0 OVF ISR as 1ms tick, PB5/PB4 toggles at 5/10ms, UART tick report) — same event count, same edge order, same UART values, max pin-edge offset 14 cy (ISR dispatch jitter).
  - Test: `tests/rung_avr_oracle.sh` (22 pass, 0 fail, 2 known). 9 test programs across all major peripherals.

## In flight

### AVR oracle track — status

**Completed:** simavr vs avr8js differential oracle is operational. Compiled blink, UART TX, ADC read, Timer0 OVF, Timer1 CTC — all tested. Pin edges agree exactly; UART has a known simavr bug (spec-updates/018). The oracle is usable for all non-UART-timing comparisons.

**Remaining ucsim_avr issues** (lower priority now that simavr oracle exists):

1. **Word-0 clobber workaround.** ROM[0] reads 0x0000 after hex load despite `read_input_files()` calling `read_file()` which calls `reset()` — the reset may be clearing word 0. Workaround: `set mem rom 0 <first-word>`. Root cause is in `cl_uc::read_file` at `uc.cc:138` calling `reset()` after load.

2. **AT90S vs ATmega328P IO register map.** ucsim_avr hardcodes AT90S-era addresses (PORTB at IRAM 0x38 = IO 0x18) but ATmega328P code targets IO 0x05. Cosmetic only — cycle counting works.

### Bench procedures — DONE

Written as `spec-updates/019-bench-procedures.md`. Three procedures:
- **BENCH-NEO** (WS2812B strip): cat 1, predictions T0H=362/T1H=814/T0L=814/T1L=452 ns, wiring to PDIP-40 pin 6 (P1.5). Confirms existing cross-emu agreement.
- **BENCH-I2C** (logic analyser on SCL): cat 3, predictions t_HIGH=5.61/t_LOW=7.26 µs, wiring to PDIP-40 pin 23 (P2.2). **Highest marginal value** — first independent check, only path to promotion.
- **BENCH-AVR** (ammeter on Nano D13): cat 1, prediction I_avg=6.92 mA (duty 0.5882). Weakest return but first AVR-on-silicon. Scope on D13 recommended over ammeter if available.

Each includes: pre-registered prediction, inconclusive band, what it cannot settle, wiring by chip pin number.

### LCD I2C full protocol — DONE

Full I2C protocol decode completed. The "SDCC init >100ms" blocker was
overstated — `lcd_i2c.ihx` starts I2C at ~78 µs; the other fixtures
are similar. Used `-until-ns 500000000` as planned.

Results: 14/14 pass (`tests/rung_lcd_i2c.sh`). Address 0x4E (PCF8574
at 0x27) on all transactions, HD44780 init byte-identical across all
fixtures, SCL timing matches prior measurement. spec-updates/020.
Decoder: `tests/decode_i2c_trace.py`.

## Learned but not in a spec-update

- **stc12_trace build rule**: `Makefile.in` has the `stc12_trace` target but `./configure`'s generated `Makefile` does not propagate it. Must append the rule manually or use `make -f Makefile.in stc12_trace`. This has bitten three people.
- **Bit-write trace visibility**: bit-addressable SFR writes (SETB/CLR on port pins) DO change the byte-level SFR value and ARE visible in the trace shadow comparison — but only if `trace_check_sfr()` runs after the write. The trace sees them fine; the earlier "zero output" on the LCD was SDCC init time, not a trace bug.
- **`-inject` and `-e` are incompatible**: `-e 'run ...'` runs ucsim's internal command loop; `-inject` fires in stc12_trace's own `for(;;) { do_inst(); }` loop controlled by `-until-ns`. spec-updates/017 documents this.
- **ucsim_avr word-0 clobber** (investigated 2026-08-13): NOT in `reset()` — `reset()` preserves ROM. `set_rom(0, 0x9A25)` during hex parsing succeeds (immediate readback = 0x9A25 via `d()`), but `rom->read(0)` returns 0 afterward. The cell's `download()` writes via `dl()` to `*data`, and `d()` confirms it, but a later `read()` or `get()` returns 0. Suspect: the cell's `data` pointer (set by `decode()` to point into `rom_chip` storage) is remapped or the chip-level storage is zeroed by something between `read_hex_file()` and the next access. Not in `reset()`, not in `analyze_init()` (only clears CELL_INST flags). Upstream ucsim bug, affects only AVR (16-bit ROM); 8-bit MCS-51 ROM is unaffected. Workaround: `set mem rom 0 <value>` before execution.
- **ucsim_avr disassembler register bug**: LDI/OUT/IN/EOR show wrong register names. Encoding `1110 KKKK dddd KKKK` has d=0..15 mapping to r16..r31, but `disass()` appears to decode d as r0..r15. Execution is correct — only the display is wrong.
- **ucsim_avr IO map is AT90S, not ATmega**: SFR table in `avr.cc` places PORTB at IRAM 0x38 (IO 0x18). ATmega328P has PORTB at IRAM 0x25 (IO 0x05). The SBI/IN/OUT opcodes address IO space directly, so ATmega code runs at the correct IO addresses — the name table is just wrong for ATmega targets.
- **Portability**: `grep -oP` (GNU Perl regex) fails on macOS. Owner fixed existing tests in `6356b3b` using `grep -Eo` (POSIX ERE). New scripts follow this pattern.

## Blocked

- **Resync e2e**: bw-board owns the test. Unblocked by spec-updates/017 (use `-until-ns` not `-e`). They have the corrected invocation.
- **Bench procedures**: waiting on physical instruments (BENCH-NEO, BENCH-I2C, BENCH-AVR written in spec-updates/019).

## Key files

- `tests/run_all.sh` — master test runner (16 suites)
- `tests/rung_system_rom_boots.sh` — Tali Forth 2 + ehBASIC + CP/M smoke (11/11)
- `tests/rung_nrf52840_bare.sh` — nRF52840 bare-metal execution (5/5)
- `tests/rung_emu8051_bp_write.sh` — emu8051 write-watchpoint audit (15/15)
- `tests/picobb_boot_rp2040js.mjs` — PicoBB boot harness (rp2040js + FIFO stub)
- `tests/rung_neopixel.sh` — WS2812 spec-window test (single emulator)
- `tests/rung_neopixel_cross.sh` — cross-emulator WS2812 test (cat 1)
- `tests/rung_avr_blink.sh` — AVR oracle cycle-count test (8/8)
- `tests/rung_avr_oracle.sh` — simavr vs avr8js differential (22 pass, 2 known)
- `tests/rung_lcd_i2c.sh` — LCD I2C protocol edge test (14/14)
- `spec-updates/021-nrf52833-vs-52840-microbit-v2.md` — task-18 decision report
- `spec-updates/020-labwired-nrf52840-esp32c3-adjudication.md` — nRF52840/ESP32-C3 validation
- `spec-updates/019-bench-procedures.md` — BENCH-NEO, BENCH-I2C, BENCH-AVR
- `spec-updates/018-simavr-uart-phantom-parity.md` — simavr UART 8N1 bug
- `spec-updates/017-inject-requires-until-ns.md` — `-inject` / `-e` incompatibility
- `tests/fixtures/nrf52840/` — bare-metal ARM Thumb-2 programs + nRF52833 chip config
- `tests/fixtures/picobb/` — PicoBB binaries (gitignored)
- `CLOSE-OUT.md` — full campaign results, defects, bench IDs
- `PARITY-GAPS.md` — emitter vs model matrix
- `RESULTS.md` — detailed methodology and numbers
