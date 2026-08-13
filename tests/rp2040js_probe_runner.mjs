/**
 * rp2040js_probe_runner.mjs — run an SRAM-linked binary under rp2040js.
 *
 * Uses the bw-board rp2040js-adapter (same path oracle-differential.mjs uses).
 * Captures UART output as canonical-trace serial[] lines.
 *
 * For self-timestamping firmware the serial LINE CONTENT is the timestamp;
 * serialMsPerByte=0 (PL011 has a 32-deep FIFO, no blocking drift).
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Use the bw-board adapter (read-only reference)
const BW_BOARD_ADAPTER = resolve('/mnt/volume1/code/lego/brickwright-lite/packages/scratch-gui/src/lib/bw-board/rp2040js-adapter.js');

/**
 * Run a binary under rp2040js and return canonical trace.
 *
 * @param {string}  binPath     Path to raw binary (loaded at SRAM 0x20000000)
 * @param {object}  opts
 * @param {number}  opts.horizonMs  Trace horizon in ms (default 5000)
 * @returns {{ events, serial, pwm, vars, horizon }}
 */
export async function runRp2040js(binPath, opts = {}) {
  const horizonMs = opts.horizonMs ?? 5000;

  const { createRp2040jsAdapter, RAM_START } = await import(BW_BOARD_ADAPTER);
  const adapter = createRp2040jsAdapter({});

  // Load binary as Uint16Array halfwords
  const bin = readFileSync(binPath);
  const padded = bin.length & 1 ? Buffer.concat([bin, Buffer.alloc(1)]) : bin;
  const halfwords = new Uint16Array(padded.buffer, padded.byteOffset, padded.length / 2);
  adapter.loadProgram(halfwords);

  const trace = { events: [], serial: [], pwm: [], vars: {}, horizon: horizonMs };
  const serialBytes = [];

  adapter.onSerial((byte) => {
    serialBytes.push({ tMs: Number(adapter.timeNs() / 1000000n), byte });
  });

  // Advance in 50ms slices
  const sliceNs = 50_000_000;
  for (let t = 0; t < horizonMs; t += 50) {
    adapter.advanceNs(sliceNs);
  }

  // Assemble UART bytes into serial lines
  let buf = '', t0 = null;
  for (const { tMs, byte } of serialBytes) {
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

  return trace;
}

// ── Standalone mode ──
if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error('Usage: node rp2040js_probe_runner.mjs <bin-file> [horizon-ms]');
    process.exit(1);
  }
  const trace = await runRp2040js(args[0], { horizonMs: args[1] ? parseInt(args[1], 10) : 5000 });
  console.log(JSON.stringify(trace, null, 2));
}
