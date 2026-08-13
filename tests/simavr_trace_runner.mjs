/**
 * simavr_trace_runner.mjs — canonical-trace adapter for simavr.
 *
 * Spawns simavr_harness (C binary), parses its PIN_EDGE / UART_TX output,
 * and returns the canonical trace format defined by sb3-creator's
 * traceOracle.js:
 *
 *   { events: [{tMs, pin, level}], serial: [{tMs, line}],
 *     pwm: [], vars: {}, horizon }
 *
 * Pin mapping: physical ATmega328P port bits → Arduino Nano digital/analog
 * names → logical program names via the declarations map.
 *
 * Usage as module:
 *   import { runSimavr } from './simavr_trace_runner.mjs';
 *   const trace = await runSimavr('fixture.ihx', declarations, { horizonMs: 2500 });
 *
 * Usage standalone (raw trace dump):
 *   node tests/simavr_trace_runner.mjs <hex> <declarations-json> [horizon-ms]
 *
 * simavr is LGPL-2.1+, linked dynamically — not vendored.
 */

import { execFileSync } from 'child_process';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const HARNESS = resolve(__dirname, 'simavr_harness');

// ATmega328P port-bit → Arduino Nano digital pin name.
// PBn → D(8+n), PCn → A(n), PDn → D(n).
const PORT_TO_NANO = new Map();
for (let i = 0; i < 8; i++) {
  PORT_TO_NANO.set(`portb.${i}`, `d${8 + i}`);
  PORT_TO_NANO.set(`portd.${i}`, `d${i}`);
  PORT_TO_NANO.set(`portc.${i}`, `a${i}`);
}

/**
 * Build a lookup from Arduino pin name (lower, e.g. "d13") to
 * { logicalName, activeLow } from the program's pin declarations.
 *
 * Declarations are an array of:
 *   { where: "D13", name: "led1", activeLow: true }
 * (the shape from SB3Creator's project.stc.pins or equivalent).
 */
function buildDeclMap(declarations) {
  const m = new Map();
  for (const d of declarations) {
    const where = String(d.where).toLowerCase();
    m.set(where, {
      name: String(d.name).toLowerCase(),
      activeLow: !!d.activeLow,
    });
  }
  return m;
}

/**
 * Run simavr_harness on a hex file and return a canonical trace.
 *
 * @param {string}  hexPath       Path to the .ihx file
 * @param {Array}   declarations  Pin declarations [{where, name, activeLow}]
 * @param {object}  opts
 * @param {number}  opts.horizonMs  Trace horizon in ms (default 2500)
 * @param {number}  opts.freqHz     CPU frequency (default 16000000)
 * @returns {{ events, serial, pwm, vars, horizon }}
 */
export function runSimavr(hexPath, declarations = [], opts = {}) {
  const horizonMs = opts.horizonMs ?? 2500;
  const freqHz = opts.freqHz ?? 16000000;

  // Compute max cycles from horizon.  Add 5% headroom so the harness
  // doesn't cut off events right at the boundary.
  const maxCycles = Math.ceil((horizonMs / 1000) * freqHz * 1.05);

  const stdout = execFileSync(HARNESS, [hexPath, String(maxCycles), String(freqHz)], {
    timeout: 30000,
    maxBuffer: 4 * 1024 * 1024,
    stdio: ['pipe', 'pipe', 'pipe'],
  }).toString('utf-8');

  return parseHarnessOutput(stdout, declarations, horizonMs, freqHz);
}

/**
 * Parse simavr_harness stdout into canonical trace format.
 */
export function parseHarnessOutput(stdout, declarations, horizonMs, freqHz) {
  const declMap = buildDeclMap(declarations);
  const trace = { events: [], serial: [], pwm: [], vars: {}, horizon: horizonMs };
  const lastIntent = new Map();  // logical pin → last intent level
  const uartBytes = [];          // { tMs, byte }

  for (const line of stdout.split('\n')) {
    // PIN_EDGE cy=123 ns=456 portb.5=1
    const pinMatch = line.match(/^PIN_EDGE\s+cy=(\d+)\s+ns=(\d+)\s+(port[bcd]\.\d)=(\d)$/);
    if (pinMatch) {
      const cy = parseInt(pinMatch[1], 10);
      const tMs = (cy / freqHz) * 1000;
      if (tMs > horizonMs) continue;

      const portPin = pinMatch[3];       // e.g. "portb.5"
      const high = parseInt(pinMatch[4], 10);

      // Map physical → Arduino → logical
      const nanoPinName = PORT_TO_NANO.get(portPin);
      if (!nanoPinName) continue;

      const decl = declMap.get(nanoPinName);
      if (!decl) continue;  // pin not declared by program

      // Polarity normalization: intent = high XOR activeLow
      const intent = (high !== (decl.activeLow ? 1 : 0)) ? 1 : 0;

      // Deduplicate: skip if same intent as last for this logical pin
      if (lastIntent.get(decl.name) === intent) continue;
      lastIntent.set(decl.name, intent);

      trace.events.push({ tMs, pin: decl.name, level: intent });
      continue;
    }

    // UART_TX cy=123 ns=456 byte=0x48 'H'
    const uartMatch = line.match(/^UART_TX\s+cy=(\d+)\s+ns=(\d+)\s+byte=0x([0-9a-f]{2})/);
    if (uartMatch) {
      const cy = parseInt(uartMatch[1], 10);
      const tMs = (cy / freqHz) * 1000;
      if (tMs > horizonMs) continue;

      const byte = parseInt(uartMatch[3], 16);
      uartBytes.push({ tMs, byte });
    }
  }

  // Assemble UART bytes into serial lines, timestamped at first byte
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
  // Flush unterminated line
  if (buf.length > 0 && t0 !== null) {
    trace.serial.push({ tMs: t0, line: buf });
  }

  return trace;
}

// ── Standalone mode ──
if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node simavr_trace_runner.mjs <hex-file> <declarations-json> [horizon-ms]');
    console.error('  declarations-json: [{"where":"D13","name":"led1","activeLow":true}]');
    process.exit(1);
  }
  const hexPath = args[0];
  const declarations = JSON.parse(args[1]);
  const horizonMs = args[2] ? parseInt(args[2], 10) : 2500;

  const trace = runSimavr(hexPath, declarations, { horizonMs });
  console.log(JSON.stringify(trace, null, 2));
}
