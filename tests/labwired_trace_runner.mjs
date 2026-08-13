/**
 * labwired_trace_runner.mjs — canonical-trace adapter for labwired-core (RP2040).
 *
 * Runs labwired-core in TEST mode with --watch-gpio for declared output pins
 * and returns the canonical trace format from sb3-creator's traceOracle.js:
 *
 *   { events: [{tMs, pin, level}], serial: [{tMs, line}],
 *     pwm: [], vars: {}, horizon }
 *
 * Test mode captures GPIO transitions in result.json logic_edges (via the
 * in-engine LogicTap) and UART bytes in uart.log.  This is the same path
 * the browser logic analyzer uses.
 *
 * Pin edge timing: logic_edges cycles ~= microseconds (labwired TIMER model),
 * so tMs = cycle / 1000.
 *
 * The firmware must be flash-linked (.vector_table at 0x10000000, word 0 = SP
 * 0x20041000, word 1 = reset thunk).  The RP2040 BOOTROM at address 0 stages
 * the image — SRAM-linked ELFs do NOT work.
 *
 * labwired-core is MIT and linked dynamically — not vendored.
 */

import { execFileSync } from 'child_process';
import { readFileSync, unlinkSync, rmdirSync, mkdtempSync, writeFileSync, existsSync } from 'fs';
import { resolve, dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { tmpdir } from 'os';

const __dirname = dirname(fileURLToPath(import.meta.url));

const LABWIRED = resolve(__dirname, '../labwired-core/target/release/labwired');

/**
 * Run labwired-core on an RP2040 ELF and return a canonical trace.
 *
 * @param {string}  elfPath       Path to the flash-linked .elf firmware
 * @param {Array}   declarations  Pin declarations [{where, name, activeLow, mode}]
 *                                where = "GP15", name = "led1", mode = "OUTPUT"
 * @param {object}  opts
 * @param {number}  opts.horizonMs    Trace horizon in ms (default 2500)
 * @param {number}  opts.maxSteps     Max simulation steps (default 50000000)
 * @param {string}  opts.labwiredBin  Path to labwired binary
 * @returns {{ events, serial, pwm, vars, horizon }}
 */
export function runLabwired(elfPath, declarations = [], opts = {}) {
  const horizonMs = opts.horizonMs ?? 2500;
  const maxSteps = opts.maxSteps ?? 50_000_000;
  const labwiredBin = opts.labwiredBin ?? LABWIRED;

  const tmpDir = mkdtempSync(join(tmpdir(), 'labwired-'));
  const scriptFile = join(tmpDir, 'test.yaml');
  const outDir = join(tmpDir, 'out');

  // Write test script YAML
  const scriptYaml = [
    'schema_version: "1.0"',
    'inputs:',
    `  firmware: "${resolve(elfPath)}"`,
    '  chip: "rp2040"',
    'limits:',
    `  max_steps: ${maxSteps}`,
    'assertions:',
    '  - expected_stop_reason: max_steps',
  ].join('\n');
  writeFileSync(scriptFile, scriptYaml);

  // Build --watch-gpio flags for declared OUTPUT pins
  const watchArgs = [];
  for (const d of declarations) {
    if (d.mode && d.mode.toLowerCase() !== 'output') continue;
    const match = String(d.where).match(/^gp(\d+)$/i);
    if (match) watchArgs.push('--watch-gpio', `sio:${match[1]}`);
  }

  try {
    execFileSync(labwiredBin, [
      'test',
      '--script', scriptFile,
      '--output-dir', outDir,
      '--no-uart-stdout',
      ...watchArgs,
    ], {
      timeout: 120000,
      maxBuffer: 16 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (e) {
    // test may exit non-zero on assertion failure — results may still be valid
  }

  const resultPath = join(outDir, 'result.json');
  const uartPath = join(outDir, 'uart.log');

  let result = null, uartLog = '';
  try { result = JSON.parse(readFileSync(resultPath, 'utf-8')); } catch {}
  try { uartLog = readFileSync(uartPath, 'utf-8'); } catch {}

  // Cleanup
  try { unlinkSync(scriptFile); } catch {}
  try { unlinkSync(resultPath); } catch {}
  try { unlinkSync(uartPath); } catch {}
  try { unlinkSync(join(outDir, 'junit.xml')); } catch {}
  try { unlinkSync(join(outDir, 'snapshot.json')); } catch {}
  try { rmdirSync(outDir); } catch {}
  try { rmdirSync(tmpDir); } catch {}

  return buildTrace(result, uartLog, declarations, horizonMs);
}

/**
 * Build canonical trace from labwired result.json + uart.log.
 */
function buildTrace(result, uartLog, declarations, horizonMs) {
  const trace = { events: [], serial: [], pwm: [], vars: {}, horizon: horizonMs };

  // Map GPIO pin numbers → logical names with polarity
  const declByGpio = new Map();
  for (const d of declarations) {
    const match = String(d.where).match(/^gp(\d+)$/i);
    if (match) {
      declByGpio.set(parseInt(match[1], 10), {
        name: String(d.name).toLowerCase(),
        activeLow: !!d.activeLow,
      });
    }
  }

  // Parse logic_edges from result.json
  if (result && result.logic_edges) {
    const lastIntent = new Map();
    for (const ch of result.logic_edges.channels || []) {
      const pin = ch.pin;
      const decl = declByGpio.get(pin);
      if (!decl) continue;

      for (const t of ch.transitions) {
        const tMs = t.cycle / 1000;  // cycle ~= microseconds
        if (tMs > horizonMs) continue;

        // Polarity normalization: intent = high XOR activeLow
        const high = t.value;
        const intent = (high !== (decl.activeLow ? 1 : 0)) ? 1 : 0;

        // Deduplicate
        if (lastIntent.get(decl.name) === intent) continue;
        lastIntent.set(decl.name, intent);

        trace.events.push({ tMs, pin: decl.name, level: intent });
      }
    }
  }

  // Parse UART log into serial lines
  // uart.log contains the raw UART output (no timestamps from labwired).
  // For self-timestamping programs, the content IS the timestamp.
  // For cycle-level timestamps, use bus-trace mode.
  const lines = uartLog.split('\n').filter(l => l.length > 0);
  // Without cycle-level timestamps from test mode, we can only timestamp
  // serial lines at 0.  For proper timing, the bus-trace JSON path gives
  // cycle-accurate UART timestamps.
  for (const line of lines) {
    trace.serial.push({ tMs: 0, line });
  }

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
  const horizonMs = args[2] ? parseInt(args[2], 10) : 5000;

  const trace = runLabwired(elfPath, declarations, { horizonMs });
  console.log(JSON.stringify(trace, null, 2));
}
