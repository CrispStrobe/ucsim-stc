/**
 * layer5_rp2040_sweep.mjs — layer-5 nightly: rp2040js vs labwired-core
 * differential on the gallery corpus (retarget amplification set).
 *
 * For each sampled program × pico: generate C → compile locally for both
 * SRAM (rp2040js) and flash (labwired) → run under both emulators →
 * compare traces via sb3-creator's compareTraces.
 *
 * Usage:
 *   node tests/layer5_rp2040_sweep.mjs             # all sampled programs
 *   node tests/layer5_rp2040_sweep.mjs blink        # one program
 *   COMPILER_URL=... overrides the compile service
 *
 * Requires:
 *   - arm-none-eabi-gcc (local compile for flash-link)
 *   - labwired-core built (labwired-core/target/release/labwired)
 *   - sb3-creator (read-only: SB3Creator, interpretTrace, compareTraces)
 *   - bw-board's rp2040js (read-only: rp2040js-adapter)
 */

import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'fs';
import { execFileSync, execSync } from 'child_process';
import { resolve, dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { tmpdir } from 'os';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Imports from the ecosystem (read-only) ──
import SB3Creator from '/mnt/volume1/code/sb3-creator/src/utils/sb3Creator.js';
import { interpretTrace, compareTraces } from '/mnt/volume1/code/sb3-creator/src/utils/traceOracle.js';
const { createRp2040jsAdapter } = await import('/mnt/volume1/code/lego/brickwright-lite/packages/scratch-gui/src/lib/bw-board/rp2040js-adapter.js');
import { runLabwired } from './labwired_trace_runner.mjs';

const COMPILER = process.env.COMPILER_URL || 'https://stc-compiler.vercel.app';
const LABWIRED = resolve(__dirname, '../labwired-core/target/release/labwired');
const FLASH_LD = resolve(__dirname, 'fixtures/pico_flash.ld');
const CRT0 = resolve(__dirname, 'fixtures/pico_crt0.c');

const HORIZON_MS = 2500;

// ── Sampled programs: pin-edge + serial + analog coverage ──
// Kept small for sane runtime (~2 min per program under labwired).
const PROGRAMS = {
  blink: {
    src: `DEVICE PICO
PIN led1 = GP15 OUTPUT

WHEN flag clicked:
  FOREVER:
    turn on led1
    wait 0.5 seconds
    turn off led1
    wait 0.5 seconds
`,
    pins: [{ where: 'GP15', name: 'led1', activeLow: false, mode: 'OUTPUT' }],
    stimulus: [],
  },

  'two-tasks': {
    src: `DEVICE PICO
PIN led1 = GP15 OUTPUT
PIN led2 = GP14 OUTPUT

WHEN flag clicked:
  FOREVER:
    toggle led1
    wait 0.3 seconds

WHEN flag clicked:
  FOREVER:
    toggle led2
    wait 0.7 seconds
`,
    pins: [
      { where: 'GP15', name: 'led1', activeLow: false, mode: 'OUTPUT' },
      { where: 'GP14', name: 'led2', activeLow: false, mode: 'OUTPUT' },
    ],
    stimulus: [],
  },

  'pot-print': {
    src: `DEVICE PICO
PIN pot1 = GP26 ANALOG

WHEN flag clicked:
  FOREVER:
    print read pot1
    wait 1 seconds
`,
    pins: [{ where: 'GP26', name: 'pot1', activeLow: false, mode: 'ANALOG' }],
    stimulus: [{ tMs: 0, pin: 'pot1', volts: 1.65 }],
  },

  button: {
    src: `DEVICE PICO
PIN btn = GP3 INPUT
PIN led1 = GP15 OUTPUT

WHEN flag clicked:
  FOREVER:
    IF read btn THEN:
      turn on led1
    ELSE:
      turn off led1
    wait 0.05 seconds
`,
    pins: [
      { where: 'GP3', name: 'btn', activeLow: false, mode: 'INPUT' },
      { where: 'GP15', name: 'led1', activeLow: false, mode: 'OUTPUT' },
    ],
    stimulus: [
      { tMs: 0, pin: 'btn', level: 0 },
      { tMs: 400, pin: 'btn', level: 1 },
      { tMs: 1200, pin: 'btn', level: 0 },
    ],
  },
};

// ── Compile C to binary via the hosted service ──
async function compileRemote(cCode) {
  const res = await fetch(`${COMPILER}/compile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: cCode, language: 'c', target: 'rp2040', format: 'bin' }),
  });
  const out = await res.json();
  if (!out.success) throw new Error(`compile failed: ${(out.error || out.log || '').slice(0, 200)}`);
  return out;
}

// ── Compile C locally for flash-link ──
function compileLocalFlash(cCode, outElfPath) {
  const tmpDir = mkdtempSync(join(tmpdir(), 'lw-compile-'));
  const srcPath = join(tmpDir, 'prog.c');
  writeFileSync(srcPath, cCode);

  try {
    execFileSync('arm-none-eabi-gcc', [
      '-mcpu=cortex-m0plus', '-mthumb', '-nostdlib', '-Os',
      '-T', FLASH_LD,
      '-o', outElfPath,
      srcPath,
    ], { timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (e) {
    const stderr = e.stderr ? e.stderr.toString() : '';
    throw new Error(`local compile failed: ${stderr.slice(0, 300)}`);
  }
}

// ── Run under rp2040js (SRAM binary) ──
function runUnderRp2040js(compileResult, creator, stimulus) {
  const adapter = createRp2040jsAdapter({});
  const bytes = Uint8Array.from(atob(compileResult.base64), c => c.charCodeAt(0));
  const padded = bytes.length & 1 ? new Uint8Array([...bytes, 0]) : bytes;
  adapter.loadProgram(new Uint16Array(padded.buffer, padded.byteOffset, padded.length / 2));

  // Build declarations from parsed program
  const decl = new Map();
  for (const p of creator.project.stc?.pins || []) {
    decl.set(String(p.where).toLowerCase(), {
      name: String(p.name).toLowerCase(),
      activeLow: !!p.activeLow,
    });
  }
  const stimFor = (where) => {
    const d = decl.get(String(where).toLowerCase());
    if (!d) return null;
    let hit = null;
    const nowMs = Number(adapter.timeNs() / 1000000n);
    for (const s of stimulus) {
      if (s.tMs > nowMs) break;
      if (String(s.pin).toLowerCase() === d.name) hit = s;
    }
    return hit;
  };

  const trace = { events: [], serial: [], pwm: [], vars: {}, horizon: HORIZON_MS };
  const lastIntent = new Map();
  const serialBytes = [];
  adapter.onSerial((b) => serialBytes.push({ tMs: Number(adapter.timeNs() / 1000000n), b }));

  adapter.attachBoard({
    setPin: (where, mode, high) => {
      const d = decl.get(String(where).toLowerCase());
      if (!d || mode !== 'pushpull') return;
      const intent = (high !== d.activeLow) ? 1 : 0;
      if (lastIntent.get(d.name) === intent) return;
      lastIntent.set(d.name, intent);
      trace.events.push({ tMs: Number(adapter.timeNs() / 1000000n), pin: d.name, level: intent });
    },
    advanceTo: () => {},
    readPin: (where) => { const s = stimFor(where); return s && s.level ? 1 : 0; },
    readAnalog: (where) => { const s = stimFor(where); return s && s.volts !== undefined ? s.volts : 0; },
  });

  for (let t = 0; t < HORIZON_MS; t += 50) adapter.advanceNs(50_000_000);

  let buf = '', t0 = null;
  for (const { tMs, b } of serialBytes) {
    const ch = String.fromCharCode(b);
    if (ch === '\n') { trace.serial.push({ tMs: t0 ?? tMs, line: buf }); buf = ''; t0 = null; }
    else if (ch !== '\r') { if (t0 === null) t0 = tMs; buf += ch; }
  }
  return trace;
}

// ── Main ──
const only = process.argv[2];
let passed = 0, failed = 0, skipped = 0;

console.log('=== Layer-5 RP2040 sweep: rp2040js vs labwired-core ===');
console.log(`Horizon: ${HORIZON_MS} ms, programs: ${only || 'all sampled'}\n`);

for (const [name, prog] of Object.entries(PROGRAMS)) {
  if (only && name !== only) continue;

  try {
    // 1. Parse + generate C
    const creator = new SB3Creator();
    creator.parse(prog.src);
    if (creator.warnings.length) throw new Error(`parse: ${creator.warnings[0]}`);

    // 2. Get referee trace
    const ref = interpretTrace(creator.project, {
      horizonMs: HORIZON_MS,
      stimulus: prog.stimulus,
      adc: { bits: 12, vref: 3.3 },
    });
    if (ref.unsupported.length) {
      console.log(`${name}: SKIP (referee refuses: ${[...new Set(ref.unsupported)]})`);
      skipped++;
      continue;
    }

    // 3. Generate C
    const c = creator.generateC(undefined, { debug: true });

    // 4. Compile (remote for rp2040js SRAM binary)
    const compileResult = await compileRemote(c);

    // 5. Run under rp2040js
    const rp2040jsTrace = runUnderRp2040js(compileResult, creator, prog.stimulus);

    // 6. Compare referee vs rp2040js
    const rp2040jsResult = compareTraces(ref, rp2040jsTrace, { tolMs: 5, serialMsPerByte: 0 });

    // 7. Try labwired (flash-link compile locally + test mode)
    let lwTag = 'SKIP';
    if (existsSync(LABWIRED)) {
      try {
        const tmpDir = mkdtempSync(join(tmpdir(), 'lw-l5-'));
        const elfPath = join(tmpDir, 'prog.elf');

        // Compile for flash-link locally
        const srcPath = join(tmpDir, 'prog.c');
        writeFileSync(srcPath, c);
        execFileSync('arm-none-eabi-gcc', [
          '-mcpu=cortex-m0plus', '-mthumb', '-nostdlib', '-Os',
          '-Wl,--no-warn-rwx-segments',
          '-T', FLASH_LD, '-o', elfPath, CRT0, srcPath, '-lgcc',
        ], { timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] });

        const labwiredTrace = runLabwired(elfPath, prog.pins, { horizonMs: HORIZON_MS });
        const labwiredResult = compareTraces(ref, labwiredTrace, { tolMs: 5, serialMsPerByte: 0 });
        lwTag = labwiredResult.ok ? 'AGREE' : 'DIFF';
        if (!labwiredResult.ok) {
          lwTag += '\n    ' + labwiredResult.diffs.slice(0, 3).join('\n    ');
        }
      } catch (e) {
        lwTag = `ERR(${String(e.message || e).slice(0, 80)})`;
      }
    }

    // Report
    const rpTag = rp2040jsResult.ok ? 'AGREE' : 'DIFF';
    console.log(`${name}:` +
      ` rp2040js=${rpTag}(ev=${rp2040jsTrace.events.length},ser=${rp2040jsTrace.serial.length})` +
      ` labwired=${lwTag}` +
      (rp2040jsResult.ok ? '' : '\n  rp2040js diffs: ' + rp2040jsResult.diffs.slice(0, 3).join('; ')));

    if (rp2040jsResult.ok) passed++;
    else failed++;

  } catch (e) {
    console.log(`${name}: ERROR ${String(e.message || e).slice(0, 200)}`);
    failed++;
  }
}

console.log(`\n=== Results: ${passed} pass, ${failed} fail, ${skipped} skip ===`);
process.exit(failed ? 1 : 0);
