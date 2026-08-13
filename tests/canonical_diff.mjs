/**
 * canonical_diff.mjs — compare simavr vs avr8js canonical traces.
 *
 * Usage: node tests/canonical_diff.mjs <hex-file> <declarations-json> \
 *            <horizon-ms> [serial-ms-per-byte]
 *
 * Prints AGREE or DIFF with details. Exit 0 on agree, 1 on diff.
 */

import { runSimavr } from './simavr_trace_runner.mjs';
import { runAvr8js } from './avr8js_trace_runner.mjs';
import { compareTraces } from '/mnt/volume1/code/sb3-creator/src/utils/traceOracle.js';

const args = process.argv.slice(2);
if (args.length < 3) {
  console.error('Usage: node tests/canonical_diff.mjs <hex> <decl-json> <horizon-ms> [serialMsPerByte]');
  process.exit(2);
}

const hexPath = args[0];
const declarations = JSON.parse(args[1]);
const horizonMs = parseInt(args[2], 10);
const serialMsPerByte = args[3] ? parseFloat(args[3]) : 0;

const simTrace = runSimavr(hexPath, declarations, { horizonMs });
const avrTrace = await runAvr8js(hexPath, declarations, { horizonMs });

const r = compareTraces(simTrace, avrTrace, { tolMs: 5, serialMsPerByte });

if (r.ok) {
  console.log(`AGREE events=${simTrace.events.length}/${avrTrace.events.length} serial=${simTrace.serial.length}/${avrTrace.serial.length}`);
  process.exit(0);
} else {
  console.log('DIFF');
  for (const d of r.diffs.slice(0, 5)) console.log('  ' + d);
  process.exit(1);
}
