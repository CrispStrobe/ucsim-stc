/**
 * labwired_trace_runner.mjs — canonical-trace adapter for labwired-core (RP2040).
 *
 * Runs labwired-core CLI on an RP2040 ELF and returns the canonical trace format
 * from sb3-creator's traceOracle.js:
 *
 *   { events: [{tMs, pin, level}], serial: [{tMs, line}],
 *     pwm: [], vars: {}, horizon }
 *
 * CURRENT LIMITATION: labwired's ARM CLI path does not expose GPIO pin
 * transitions (the SIO LogicTap fires but --gpio-trace is Xtensa-only).
 * This adapter captures UART output via --bus-trace-out (cycle-timestamped
 * JSON events). GPIO edges are a gap pending upstream work.
 *
 * Usage as module:
 *   import { runLabwired } from './labwired_trace_runner.mjs';
 *   const trace = await runLabwired('firmware.elf', declarations, { horizonMs: 2500 });
 *
 * labwired-core is MIT and linked dynamically — not vendored.
 */

import { execFileSync } from 'child_process';
import { readFileSync, unlinkSync, rmdirSync, mkdtempSync } from 'fs';
import { resolve, dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { tmpdir } from 'os';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Paths — adjust if labwired is installed elsewhere
const LABWIRED = resolve(__dirname, '../labwired-core/target/release/labwired');
const CHIP_YAML = resolve(__dirname, '../labwired-core/configs/chips/rp2040.yaml');

// Pico pin mapping: GP0..GP29 → logical names.
// BrickWright uses GP15 (LED), GP14 (LED2), GP26 (pot/ADC), GP3 (button).
function buildDeclMap(declarations) {
  const m = new Map();
  for (const d of declarations) {
    const where = String(d.where).toLowerCase();
    // Normalize: "GP15" → "gp15", "gp15" → "gp15"
    m.set(where, {
      name: String(d.name).toLowerCase(),
      activeLow: !!d.activeLow,
    });
  }
  return m;
}

/**
 * Run labwired-core on an RP2040 ELF and return a canonical trace.
 *
 * @param {string}  elfPath       Path to the .elf firmware
 * @param {Array}   declarations  Pin declarations [{where, name, activeLow}]
 * @param {object}  opts
 * @param {number}  opts.horizonMs    Trace horizon in ms (default 2500)
 * @param {number}  opts.freqHz       CPU frequency (default 125000000 for pico-sdk)
 * @param {number}  opts.maxSteps     Max simulation steps (default: computed from horizon)
 * @param {string}  opts.chipYaml     Path to chip descriptor (default: rp2040.yaml)
 * @param {string}  opts.labwiredBin  Path to labwired binary
 * @returns {{ events, serial, pwm, vars, horizon }}
 */
export function runLabwired(elfPath, declarations = [], opts = {}) {
  const horizonMs = opts.horizonMs ?? 2500;
  const freqHz = opts.freqHz ?? 125_000_000;
  const chipYaml = opts.chipYaml ?? CHIP_YAML;
  const labwiredBin = opts.labwiredBin ?? LABWIRED;

  // Estimate max steps from horizon.  Each step is roughly one instruction
  // (~1 cycle).  Add generous headroom for boot overhead.
  const maxSteps = opts.maxSteps ?? Math.ceil((horizonMs / 1000) * freqHz * 1.5 + 500000);

  const tmpDir = mkdtempSync(join(tmpdir(), 'labwired-'));
  const busTraceFile = join(tmpDir, 'bus_trace.json');

  try {
    execFileSync(labwiredBin, [
      'run',
      '--chip', chipYaml,
      '--firmware', elfPath,
      '--max-steps', String(maxSteps),
      '--bus-trace-out', busTraceFile,
    ], {
      timeout: 60000,
      maxBuffer: 8 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (e) {
    // labwired may exit non-zero on max-steps — that's fine if bus trace was written
    if (!e.stdout && !e.stderr) throw e;
  }

  let busTrace;
  try {
    busTrace = JSON.parse(readFileSync(busTraceFile, 'utf-8'));
  } catch {
    return { events: [], serial: [], pwm: [], vars: {}, horizon: horizonMs };
  }

  // Cleanup
  try { unlinkSync(busTraceFile); } catch {}
  try { rmdirSync(tmpDir); } catch {}

  return parseBusTrace(busTrace, declarations, horizonMs, freqHz);
}

/**
 * Parse labwired bus trace JSON into canonical trace format.
 *
 * Bus trace events look like:
 *   {"seq":N,"cycle":C,"bus":"uart0","payload":{"protocol":"uart","direction":"tx","byte":B}}
 */
function parseBusTrace(events, declarations, horizonMs, freqHz) {
  const trace = { events: [], serial: [], pwm: [], vars: {}, horizon: horizonMs };
  const uartBytes = [];

  for (const ev of events) {
    if (!ev.payload || ev.payload.protocol !== 'uart') continue;
    if (ev.payload.direction !== 'tx') continue;

    const tMs = (ev.cycle / freqHz) * 1000;
    if (tMs > horizonMs) continue;

    uartBytes.push({ tMs, byte: ev.payload.byte });
  }

  // Assemble UART bytes into lines, timestamped at first byte
  let buf = '', t0 = null;
  for (const { tMs, byte } of uartBytes) {
    const ch = String.fromCharCode(byte);
    if (ch === '\n') {
      trace.serial.push({ tMs: t0 ?? tMs, line: buf });
      buf = '';
      t0 = null;
    } else if (ch !== '\r') {
      if (t0 === null) t0 = tMs;
      buf += ch;
    }
  }
  if (buf.length > 0 && t0 !== null) {
    trace.serial.push({ tMs: t0, line: buf });
  }

  // NOTE: GPIO events are not available via bus trace for RP2040.
  // The SIO LogicTap fires on GPIO writes but the ARM CLI path
  // does not expose those events. trace.events stays empty for now.
  // Pending: labwired-core upstream --gpio-trace for ARM chips.

  return trace;
}

// ── Standalone mode ──
if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error('Usage: node labwired_trace_runner.mjs <elf-file> [declarations-json] [horizon-ms]');
    process.exit(1);
  }
  const elfPath = args[0];
  const declarations = args[1] ? JSON.parse(args[1]) : [];
  const horizonMs = args[2] ? parseInt(args[2], 10) : 2500;

  const trace = runLabwired(elfPath, declarations, { horizonMs });
  console.log(JSON.stringify(trace, null, 2));
}
