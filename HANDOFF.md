# ucsim-stc handoff

For the next session. Read CLOSE-OUT.md for the full campaign; this is the delta.

## Completed since the close-out

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

## In flight

### AVR oracle track — next concrete steps

The hand-assembled blink proves cycle-count agreement. Three things remain before the AVR oracle is useful for differential execution:

1. **Compiled blink cycle-count comparison.** `tests/fixtures/avr_blink_compiled.ihx` (from `stc-compiler.vercel.app/compile`, target `atmega328p`) loads and toggles PORTB correctly (confirmed: IRAM[0x25] flips 0x85↔0xA5 via IN/EOR/OUT at IO 0x05). Next step: step ~10,000 instructions per toggle (the `for (volatile uint16_t i=0; i<1000; i++)` delay loop), measure the toggle period, compare with avr8js running the same hex.

2. **Word-0 clobber workaround.** ROM[0] reads 0x0000 after hex load despite `read_input_files()` calling `read_file()` which calls `reset()` — the reset may be clearing word 0. Workaround: `set mem rom 0 <first-word>`. Root cause is in `cl_uc::read_file` at `uc.cc:138` calling `reset()` after load. Needs either a fix in the AVR reset or a wrapper script. The `rung_avr_blink.sh` test already works around it.

3. **AT90S vs ATmega328P IO register map.** ucsim_avr hardcodes AT90S-era addresses (PORTB at IRAM 0x38 = IO 0x18) but ATmega328P code targets IO 0x05. The opcodes execute correctly at the right IO address — the map is cosmetic (names and disassembly), not behavioral. For the oracle role: cycle counting works now; full PORTB trace would require either remapping the SFR name table in `avr.cc:52-114` or writing an ATmega328P model. The disassembler also shows wrong register names (r24 as r0) — display bug in the `disass()` function, not an execution bug.

### Bench procedures (spec-update draft)

Coordinator requested (`/tmp/three-instruments-no-procedure.md`) procedures for three instruments the ledger names but no bench question covers:
- **WS2812B strip** — NeoPixel timing (cat 1 prediction: T0H=362, T1H=814, T0L=814, T1L=452 ns)
- **Logic analyser on SCL** — I2C timing (cat 2b prediction: t_HIGH=5.61 µs, t_LOW=7.26 µs)
- **Ammeter on Nano** — AVR LED brightness (avr8js prediction: 0.5882 duty)

To be written as a spec-update in this repo (not editing `BENCH-RUNBOOK.md`). Each needs: pre-registered prediction, inconclusive band, what it cannot settle, wiring by chip pin number. Not started.

### LCD I2C full protocol

SCL timing is done (v2 in spec). The full I2C START/address/data/STOP edge measurement was blocked by SDCC init taking >100ms. Next step: use `-until-ns 500000000` or longer, or set a breakpoint past init.

## Learned but not in a spec-update

- **stc12_trace build rule**: `Makefile.in` has the `stc12_trace` target but `./configure`'s generated `Makefile` does not propagate it. Must append the rule manually or use `make -f Makefile.in stc12_trace`. This has bitten three people.
- **Bit-write trace visibility**: bit-addressable SFR writes (SETB/CLR on port pins) DO change the byte-level SFR value and ARE visible in the trace shadow comparison — but only if `trace_check_sfr()` runs after the write. The trace sees them fine; the earlier "zero output" on the LCD was SDCC init time, not a trace bug.
- **`-inject` and `-e` are incompatible**: `-e 'run ...'` runs ucsim's internal command loop; `-inject` fires in stc12_trace's own `for(;;) { do_inst(); }` loop controlled by `-until-ns`. spec-updates/017 documents this.
- **ucsim_avr word-0 clobber**: `cl_uc::read_file()` calls `reset()` after loading the hex file (`uc.cc:138`), which appears to zero ROM[0]. All other words load correctly. Workaround: `set mem rom 0 <value>` before execution.
- **ucsim_avr disassembler register bug**: LDI/OUT/IN/EOR show wrong register names. Encoding `1110 KKKK dddd KKKK` has d=0..15 mapping to r16..r31, but `disass()` appears to decode d as r0..r15. Execution is correct — only the display is wrong.
- **ucsim_avr IO map is AT90S, not ATmega**: SFR table in `avr.cc` places PORTB at IRAM 0x38 (IO 0x18). ATmega328P has PORTB at IRAM 0x25 (IO 0x05). The SBI/IN/OUT opcodes address IO space directly, so ATmega code runs at the correct IO addresses — the name table is just wrong for ATmega targets.
- **Portability**: `grep -oP` (GNU Perl regex) fails on macOS. Owner fixed existing tests in `6356b3b` using `grep -Eo` (POSIX ERE). New scripts follow this pattern.

## Blocked

- **Resync e2e**: bw-board owns the test. Unblocked by spec-updates/017 (use `-until-ns` not `-e`). They have the corrected invocation.
- **LCD I2C protocol edges**: needs longer `-until-ns` to get past SDCC init (~100ms). Not architecturally blocked.
- **JBC cycle count**: 1 MC in ucsim, should be 2 per MCS-51 spec. No driver uses JBC. Fix is one `tick(1)` call in `jmp.cc instruction_10`.

## Key files

- `CLOSE-OUT.md` — full campaign results, defects, bench IDs
- `PARITY-GAPS.md` — emitter vs model matrix (11/13 modelled, 31 BW_STUB)
- `RESULTS.md` — detailed methodology and numbers
- `tests/rung_neopixel.sh` — runnable WS2812 spec-window test (single emulator)
- `tests/rung_neopixel_cross.sh` — cross-emulator WS2812 test (cat 1)
- `tests/rung_avr_blink.sh` — AVR oracle cycle-count test (8/8 pass)
- `tests/fixtures/avr_blink_hand.ihx` — 6-word hand-assembled AVR blink
- `tests/fixtures/avr_blink_compiled.ihx` — compiled AVR blink from stc-compiler
- `tests/classify_divergences.sh` — 347-image corpus classifier
- `spec-updates/017-inject-requires-until-ns.md` — the `-inject` / `-e` incompatibility
- `ucsim/src/sims/avr.src/ucsim_avr` — built AVR simulator binary
- `ucsim/src/sims/avr.src/avr.cc:52-114` — AT90S SFR name table (needs ATmega update for full oracle)
