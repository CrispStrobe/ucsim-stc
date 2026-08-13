# 020 — labwired-core nRF52840 + ESP32-C3 silicon validation summary

Two open adjudications depend on the depth of labwired-core's silicon
verification for these chips. This note reports what `VALIDATION_STATUS.md`
and `FIDELITY.md` (commit HEAD, evaluated 2026-08-13) actually prove.

## nRF52840 — 🟢 silicon-verified (deep behavioural)

**Board:** Seeed XIAO nRF52840 Sense on ST-LINK V2 (V2J37S7, serial
48FF6B064884534929321087). FICR INFO.PART=0x00052840, DEVICEID 707dc298.
Re-captured 2026-08-09 with NRF52_STRICT=1 on the SAME physical part
(not a cross-board re-capture unlike ESP32-C3/S3).

**All 11 hw-oracle suites pass:**

| Suite | What it proves |
|---|---|
| conformance | Digest vs frozen 2026-06-09 silicon capture |
| cpu_conformance | Instruction-level CPU model fidelity |
| mmio 16/16 | Register read/write round-trip, including SPIM0 PSEL_MISO + PSEL.CSN (fixed during re-capture) |
| gpio | GPIO task register behaviour |
| onboarding | Board-level bring-up sequence |
| power | Power management model |
| spis_twis | SPI slave + TWI slave peripheral models |
| timer_rtc | Timer + RTC peripheral behaviour (clock-domain fidelity with fractional accumulator, LFCLK 32.768 kHz) |
| spim_easydma | SPIM EasyDMA transfer with byte-level completion timing |
| full_register | Full register sweep |
| ccm | AES-CCM encryption engine |

**Defects found and fixed during re-capture (2026-08-09):**
1. Seven `nrf52_*` tests hadn't compiled since 2026-07-18 bus
   consolidation (removed `read_u32`/`write_u32` shadows)
2. SPIM0 PSEL_MISO: sim=0x0 vs hw=0x2E (broadcast PSEL writes hit
   both TWIM+SPIM halves, but reads dispatched only to TWIM)
3. SPIM PSEL.CSN (0x514) missing from register set entirely —
   corroborated on silicon (wrote 0x2B, read 0x2B)

**Temporal fidelity (FIDELITY.md case study):**
TWIM I2C models wire time: `(bytes+1) × 9 bits × (core_hz / scl_hz)`
= ~5760 cycles for 1 byte at 100 kHz on the 64 MHz core. A
`busy_cycles` countdown holds the completion EVENT/IRQ until the
budget elapses. This was the fix for real Zephyr BME280 firmware
hanging at boot (recursive spinlock from instant IRQ delivery).
The SAME firmware on real silicon boots to `arch_cpu_idle` with
TWIM at ENABLE=6, all EVENTS=0.

**What this means for micro:bit V2 assessment:**
The nRF52840 IS the micro:bit V2's MCU. labwired-core's model covers:
- GPIO (output task registers, pin read/write, interrupt)
- TIMER + RTC (with correct LFCLK clock-domain ratio)
- SPIM/SPIS + TWIM/TWIS (EasyDMA with transfer-cycle latency)
- UARTE (EasyDMA TX, legacy UART TXD→TXDRDY for Arduino core)
- CCM (AES-CCM crypto engine)

This is the deepest independently silicon-verified Cortex-M simulation
currently available. Boots unmodified upstream Zephyr v3.7 hello_world.

**Drift status:** ⚠ drift acked 2026-08-10 (models changed after last
capture). Re-capture pending — the acknowledgement asserts "we know the
model changed; the silicon run is owed, not skipped."

---

## ESP32-C3 — 🟢 silicon-verified (reset-state only)

**Board:** ESP32-C3 QFN32 rev v0.4, MAC 9c:cc:01:d0:98:e0, on USB-JTAG
(built-in) + openocd-esp32 v0.12.0-esp32-20260703. Re-captured 2026-08-09
on a **second physical C3** (cross-board corroboration — the 2026-06-11
baseline came from MAC 38:44:be:42:f5:58, same QFN32 rev).

**What was captured:**
- 1207 registers read across 21 estate windows + 43 control registers +
  radio windows
- 84/84 RESET_VALUES matched, 0 mismatched
- 2 FREE_RUNNING_COUNTERS windows mapped (WiFi MAC counter — mapping
  only, no equality claim)
- Cross-board: second physical part confirms reset values are part-
  independent (not a re-read of the same fuse state)

**What this does NOT prove:**
- No runtime behavioural verification — this is register reset values
  at boot, not peripheral operation under firmware
- Radio registers only valid before PHY bring-up (JTAG reset is
  software-only, doesn't cold-reset peripherals)
- No register read/write round-trip (unlike nRF52840's mmio suite)
- ~40 peripherals declared, but the oracle coverage is reset state only

**Offline CI:**
- `esp32c3_reset_conformance::esp32c3_reset_values_match_silicon`
  (87 regs; 366/423 overlap matched silicon)
- `esp32c3_reset_conformance::esp32c3_free_running_counters_are_mapped`
  (2 WiFi MAC counter windows)

**What this means for adjudication:**
The ESP32-C3 silicon verification establishes that the **register map
is correctly laid out** and reset values are right — necessary but not
sufficient for behavioural oracle use. It does NOT prove that timers
count at the right rate, UART bytes land with correct timing, or GPIO
edges fire at the right cycles. For a behavioural cross-check (our use
case), the ESP32-C3 model would need a runtime differential, not just
a reset-state diff.

**Drift status:** ⚠ drift acked 2026-08-10 (re-capture pending).

---

## Key distinction for the two adjudications

| | nRF52840 | ESP32-C3 |
|---|---|---|
| **Tier** | 🟢 silicon-verified | 🟢 silicon-verified |
| **Depth** | **Deep behavioural** (11 suites, MMIO R/W, temporal fidelity) | **Reset-state only** (register values at boot) |
| **Runtime behaviour proven** | Yes — timer/RTC periods, SPI/I2C transfers, UART byte timing | No — reset values only |
| **Cross-board** | No (same DEVICEID re-read) | Yes (second physical C3) |
| **Firmware boots** | Zephyr hello_world end to end | hello-world firmware |
| **Useful as behavioural oracle** | **Yes — strongest ARM Cortex-M oracle available** | **Not yet — needs runtime differential** |

---
Extracted from labwired-core `docs/boards/VALIDATION_STATUS.md` and
`FIDELITY.md`, 2026-08-13. Cross-referenced against `validation/manifest.yaml`
and the tier-1 fixture results.
