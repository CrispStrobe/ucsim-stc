# 019 — labwired-core RP2040 evaluation for oracle layer 5

Status: **promising with caveats** — UART path usable today; GPIO path
needs minor upstream work or a polling adapter.

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

## 3. GPIO observation gap — the blocking issue

**What works:** The SIO model correctly tracks `gpio_out` state and has a
`LogicTap` push-capture mechanism (snapshots before SIO writes, reports
changes after). This powers the bus-trace/VCD logic-capture system.

**What doesn't work for us:** The `labwired run --gpio-trace` flag is
**ESP32-S3-only** — it hooks the Xtensa GPIO observer interface, which
does not exist in the ARM `run_firmware_arm` path. The ARM path wires:
- UART TX sink → stdout (works)
- Bus trace → JSON/VCD (UART events only for RP2040; no GPIO in bus trace)

The LogicTap IS fired on SIO writes (`tap_snapshot` / `tap_report` around
GPIO_OUT_SET/CLR/XOR), but no CLI path exposes those events for ARM chips
on `labwired run`. The `labwired test` command (YAML-driven) likely does
wire logic capture, but that path requires a test script, not a raw run.

**Options to close the gap:**
1. **Upstream PR**: Add `--gpio-trace` to the ARM path by reading
   `bus.logic_tap` events after the step loop. The SIO already fires tap
   events; the CLI just doesn't collect them. Estimated: ~30 lines of Rust.
2. **Polling adapter**: A custom firmware that reads SIO `GPIO_IN` at a
   known rate and reports over UART. Ugly, changes the firmware.
3. **Test-script path**: Use `labwired test` with a YAML that watches
   specific GPIO pads. Requires learning the test-script schema.

**Recommendation:** Option 1 is the right move. The SIO tap mechanism is
already wired; the ARM run command just needs to drain the `LogicTap`
event buffer after the run completes. This is a small, clean contribution
upstream and benefits all ARM-chip users. File an issue first.

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

## 6. Verdict for oracle layer 5

**labwired-core IS the right RP2040 second executor**, pending:
1. GPIO observation in the ARM CLI path (~30 lines of Rust upstream)
2. An ELF wrapper or pico-sdk build path for BW Pico artifacts
3. A canonical-trace adapter (same shape as `simavr_trace_runner.mjs`)

The UART path works today. If BW programs only did `print` (serial-only),
we could write the adapter now. The GPIO observation gap is the blocker
for pin-edge programs (blink, two-tasks, button).

**Compared to alternatives:**
- **rp2040js** (already in use): Pure JS, no native deps, but single-source
  — we want an independent second opinion, which is the whole point
- **Renode**: Heavier (Mono/.NET), similar "needs GPIO hook" problem
- **labwired-core**: Rust, MIT, fast, already passes tier-1 for all
  peripherals we need (GPIO/TIMER/UART/ADC/PWM), just needs the CLI
  plumbing to expose GPIO events on ARM

**Next step:** File a labwired-core issue requesting `--gpio-trace` for ARM
chips. Reference the SIO `tap_snapshot`/`tap_report` mechanism already in
place. If accepted, the canonical-trace adapter is straightforward.

---
Evaluated: 2026-08-13. labwired-core cloned at HEAD.
Evaluator: ucsim-stc agent (simavr canonical-trace lane).
