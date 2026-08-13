# 019 — labwired-core RP2040 evaluation for oracle layer 5

Status: **CONFIRMED — both UART and GPIO paths work.** `labwired test`
with `--watch-gpio sio:PIN` captures GPIO edges in `result.json
.logic_edges`; UART lands in `uart.log`. No upstream patch needed.

## 1. What labwired-core is

[github.com/w1ne/labwired-core](https://github.com/w1ne/labwired-core) (MIT,
Rust) — a multi-architecture firmware simulator. 21 chips across ARM
Cortex-M, RISC-V, and Xtensa. Built from `cargo build --release --bin
labwired`; the binary is 100% local (no network deps at runtime). 7m19s
build on this box (Rust 1.96.0, release profile).

## 2. RP2040 peripheral fidelity (what our traces need)

| Peripheral | labwired status | Our need | Verdict |
|---|---|---|---|
| **GPIO (SIO)** | Modeled: 30-bit output latch + OE, set/clr/xor, readback = OUT & OE. LogicTap push-capture on SIO writes. | Pin edges (blink, two-tasks) | **Modeled, observation gap** (see §3) |
| **TIMER** (64-bit µs counter) | Modeled: free-running 64-bit counter, alarm registers. | Busy-wait timing (`wait N seconds`) | **Adequate** |
| **UART0** (PL011) | Modeled: 8N1 TX via DR write, baud divisor, bus-trace events with cycle stamps. | `print` / serial lines | **Works today** (tier-1 PASS) |
| **ADC** | Tier-1 says PASS. Model exists at `peripherals/rp2040/adc.rs`. | `read pot` | **Modeled** (not HW-validated) |
| **PWM** | Tier-1 says PASS. Model at `peripherals/rp2040/pwm.rs`. | PWM percent | **Modeled** (not HW-validated) |
| **PIO** | Declared, no test coverage. | NeoPixel (future) | **Not usable** |
| **SPI0** (PL022) | Modeled: loopback transfer. | Not needed for BW traces | N/A |
| **I2C0** (DW_apb_i2c) | Modeled: no-slave NACK abort. | Not needed for BW traces | N/A |
| **XIP_SSI** | Modeled: boot2 QSPI bring-up. | Boot path | **Works** |
| **Clocks/Resets** | Modeled: RESET_DONE, PLL-LOCK, XOSC-STABLE. | Boot path | **Works** |
| **Spinlocks** | Modeled: try-lock/release. | pico-sdk mutex | **Works** |

Validation tier: **⚪ structural** — no silicon capture. All values are
reference-manual-derived. The tier-1 fixture
(`tests/fixtures/tier1/rp2040.elf`) passes:
```
TIER1 clock PASS
TIER1 timer PASS
TIER1 gpio PASS
TIER1 spi PASS
TIER1 i2c PASS
TIER1 pwm PASS
TIER1 adc PASS
TIER1 rtc PASS
TIER1 wdt PASS
TIER1 irq PASS
TIER1 done
```

## 3. GPIO observation — SOLVED via `labwired test --watch-gpio`

**`labwired test` mode** captures GPIO edges through the in-engine
LogicTap — the same path the browser logic analyzer uses. No upstream
patch required.

**Recipe:**
```bash
labwired test --script blink.yaml --watch-gpio sio:25 --output-dir out/
```
Result: `out/result.json` `.logic_edges.channels[].transitions` =
`[{cycle, value}...]` where `cycle ~= microseconds` (labwired TIMER
model). UART output lands in `out/uart.log`.

**Script shape:**
```yaml
schema_version: "1.0"
inputs:
  firmware: "/path/to/firmware.elf"
  chip: "rp2040"           # built-in name, not a file path
limits:
  max_steps: 50000000
assertions:
  - expected_stop_reason: max_steps
```

`--watch-gpio` is repeatable — one channel per declared output pin.

**Verified:** Our blink probe (GP25 toggle every 500 ms) produces 6
transitions at cycles 503643, 1013093, 1519120, 2022748, 2529136,
3032589 — ~500 ms half-periods, matching rp2040js within the 1.2%
ROSC timer model gap (the coordinator confirmed exact agreement on
pico-sdk-compiled programs which configure PLL to 125 MHz).

**`labwired run --gpio-trace`** remains Xtensa-only. Contributing the
ARM wiring upstream is optional polish, not a blocker.

## 4. Feasibility run

### UART output — works end to end
```
$ labwired run --chip configs/chips/rp2040.yaml \
    --firmware tests/fixtures/rp2040-demo.elf \
    --max-steps 2000000 --bus-trace-out /tmp/bus.json
```
Output: `RP2040_SMOKE_OK` lines printed via UART0 at 115200 baud.
Bus trace: 4096 UART TX events with cycle timestamps:
```json
{"seq":2193,"cycle":697392,"bus":"uart0","payload":{"protocol":"uart","direction":"tx","byte":82}}
```

Cycle → tMs conversion: `tMs = cycle / (freq / 1000)`.  Default ring
oscillator is ~6.5 MHz (no PLL in the demo), but with pico-sdk the
typical 125 MHz system clock is used.

### GPIO blink — NOT observable yet
The rp2040-demo firmware only does UART, not GPIO toggling. Even if it
did, the `labwired run` ARM path would not capture the transitions (see
§3). The LogicTap mechanism fires on SIO writes, so the data IS
generated — it's just not exposed via the CLI.

### ELF requirement
`labwired run --firmware` requires an ELF file. The stc-compiler service
returns raw `.bin` (base64). Options:
- `--flash-image <path>@0x20000000` supports raw binaries at an offset,
  but `--firmware` (which sets the entry point) must still be an ELF.
- For BW Pico artifacts: compile with the pico SDK (which produces ELF)
  rather than the hosted service, or wrap the bin in a minimal ELF.

## 5. nRF52840 and ESP32-C3 rows (for open adjudications)

### nRF52840 — 🟢 silicon-verified (2026-08-09)
- Bench board: Seeed XIAO nRF52840 Sense, ST-LINK V2
- DEVICEID 707dc298 (same part re-captured, not cross-board)
- ALL 11 hw-oracle suites pass (NRF52_STRICT=1): conformance,
  cpu_conformance, mmio 16/16, gpio, onboarding, power, spis_twis,
  timer_rtc, spim_easydma, full_register, ccm
- Re-capture found 3 real defects, all fixed:
  1. Seven tests hadn't compiled since 2026-07-18 bus consolidation
  2. SPIM0 PSEL_MISO sim=0x0 vs hw=0x2E (broadcast write, single read)
  3. SPIM PSEL.CSN (0x514) missing from register set
- Deep model: boots real Zephyr firmware, TWIM I2C with transfer-cycle
  latency, EasyDMA, BLE peripheral models
- Status: ⚠ drift acked 2026-08-10, re-capture pending

### ESP32-C3 — 🟢 silicon-verified (2026-08-09)
- Re-captured on a SECOND physical C3 (cross-board corroboration)
- MAC 9c:cc:01:d0:98:e0 (QFN32 rev v0.4)
- 1207 registers read: 84/84 RESET_VALUES matched, 0 mismatched
- **Reset-state oracle only**, not behavioural — captures register
  reset values, not runtime operation
- Radio note: JTAG reset is software-only, doesn't cold-reset
  peripherals; radio registers only valid before PHY bring-up
- Boots hello-world firmware
- Status: ⚠ drift acked 2026-08-10, re-capture pending

**Key distinction for adjudication:** nRF52840 has deep *behavioural*
silicon validation (11 suites, MMIO reads/writes, timing). ESP32-C3 has
*reset-state* silicon validation only (register values at boot, not
runtime behaviour). Both are genuinely silicon-verified but at different
depths.

## 6. Cross-emulator verification results

**Self-timestamping probe (bare-metal, no pico-sdk clock setup):**

| Emulator | Serial output (ms) | GP25 edges (ms) |
|---|---|---|
| rp2040js | 500 1000 1500 2000 2500 3000 | 500 1000 1500 2000 2500 3000 |
| labwired | 503 1013 1519 2022 2529 3032 | 503.6 1013.1 1519.1 2022.7 2529.1 3032.6 |
| **Delta** | **+1.2% (ROSC timer model gap)** | **Same pattern, same gap** |

Both emulators produce 6 GPIO transitions + 6 serial lines + DONE.
The 1.2% delta is the bare-metal ROSC-to-TIMER path difference — the
coordinator confirmed **exact agreement on pico-sdk-compiled programs**
(PLL → 125 MHz, TIMER at 1 µs/tick).

## 7. nRF52840 silicon validation (micro:bit-class assessment)

labwired-core's nRF52840 model is **the deepest silicon-verified model
in the project**: 🟢 silicon-verified (2026-08-09), **11 hw-oracle suites
pass** with NRF52_STRICT=1:

- conformance, cpu_conformance, mmio 16/16, gpio, onboarding, power,
  spis_twis, timer_rtc, spim_easydma, full_register, ccm
- Boots real Zephyr firmware end to end
- TWIM I2C with transfer-cycle latency modelled (the temporal-fidelity
  case study in FIDELITY.md — the ~5760-cycle I2C completion delay)
- EasyDMA, BLE peripheral models, UARTE with legacy UART mode
- Re-capture found + fixed 3 real defects (see VALIDATION_STATUS.md)

**For micro:bit-class assessment:** This is the strongest independent
Cortex-M simulation oracle currently available. The nRF52840 is the
micro:bit V2's MCU. labwired-core's silicon-verified model covers
GPIO, TIMER, RTC, SPI, TWI (I2C), and UART — the full micro:bit
peripheral surface.

## 8. Verdict for oracle layer 5

**labwired-core IS the right RP2040 second executor. Both GPIO and UART
paths work today via `labwired test --watch-gpio`.**

Deliverables in place:
- `tests/labwired_trace_runner.mjs` — canonical-trace adapter using
  test mode with --watch-gpio for GPIO + uart.log for serial
- `tests/rp2040js_probe_runner.mjs` — rp2040js canonical-trace adapter
- `tests/rung_rp2040_cross.sh` — cross-emulator differential test
- `tests/fixtures/pico_blink_probe.c` — flash + SRAM blink probes
- `tests/fixtures/pico_flash.ld` — flash linker script (0x10000000)

**Remaining to wire as nightly layer-5:**
1. Flash-link thunk for BW Pico artifacts (or hosted service `link=flash`)
2. Per-program × device loop: generate YAML, run test mode, parse
   logic_edges + uart.log → canonical trace → compareTraces
3. serialMsPerByte = 0 (PL011 32-deep FIFO, no blocking drift)

---
Evaluated: 2026-08-13. labwired-core cloned at HEAD.
Evaluator: ucsim-stc agent (simavr canonical-trace lane).
