#!/usr/bin/env node
// census_gen_hex.mjs — generate hex files for all boot census examples.
// Two-step: sb3Creator.parse(.bw) → generateC() → stc-compiler /compile (language: "c")
// Output: one .hex file per example in the output directory.
//
// Usage: node tests/census_gen_hex.mjs [output_dir]

import SB3Creator from '/mnt/volume1/code/sb3-creator/src/utils/sb3Creator.js';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';

const EXAMPLES_DIR = '/mnt/volume1/code/sb3-creator/examples';
const COMPILER_URL = 'https://stc-compiler.vercel.app/compile';
const OUTPUT_DIR = process.argv[2] || '/tmp/census-hex';

const CENSUS_EXAMPLES = [
    { name: '01-blink', device: 'stc12c5a60s2' },
    { name: '02-dimmer', device: 'stc12c5a60s2' },
    { name: '03-night-light', device: 'stc12c5a60s2' },
    { name: '04-thermostat', device: 'stc12c5a60s2' },
    { name: '05-counter', device: 'stc12c5a60s2' },
    { name: '06-active-low-high', device: 'stc12c5a60s2' },
    { name: '07-buzzer-siren', device: 'stc12c5a60s2' },
    { name: '08-led-chaser-595', device: 'stc12c5a60s2' },
    { name: '09-relay-clicker', device: 'stc12c5a60s2' },
    { name: '10-motor-speed', device: 'stc12c5a60s2' },
    { name: '11-toggle-button', device: 'stc12c5a60s2' },
    { name: '12-dual-blink', device: 'stc12c5a60s2' },
    { name: '13-sos-morse', device: 'stc12c5a60s2' },
    { name: '14-traffic-light', device: 'stc12c5a60s2' },
    { name: '15-voltage-divider', device: 'stc12c5a60s2' },
    { name: '16-ldr-bargraph', device: 'stc12c5a60s2' },
    { name: '17-comparator', device: 'stc12c5a60s2' },
    { name: '18-logic-and-gate', device: 'stc12c5a60s2' },
    { name: '19-logic-or-gate', device: 'stc12c5a60s2' },
    { name: '20-shift-register-binary', device: 'stc12c5a60s2' },
    { name: '24-pwm-fade', device: 'stc12c5a60s2' },
    { name: '25-reaction-timer', device: 'stc12c5a60s2' },
    { name: '26-debounce', device: 'stc12c5a60s2' },
    { name: '27-led-dice', device: 'stc12c5a60s2' },
    { name: '30-multi-led-pattern', device: 'stc12c5a60s2' },
    { name: '32-source-vs-sink', device: 'stc12c5a60s2' },
    { name: '33-inductive-no-flyback', device: 'stc12c5a60s2' },
    { name: '46-port-overcurrent', device: 'stc12c5a60s2' },
    { name: '49-lcd-hello', device: 'stc12c5a60s2' },
    { name: '50-7seg-chase', device: 'stc12c5a60s2' },
    { name: '53-servo-sweep', device: 'stc12c5a60s2' },
    { name: '54-motor-driver', device: 'stc12c5a60s2' },
    { name: '60-retro-console', device: 'stc15f2k60s2' },
    { name: '61-console-pong', device: 'stc15f2k60s2' },
];

if (!existsSync(OUTPUT_DIR)) mkdirSync(OUTPUT_DIR, { recursive: true });

let ok = 0, fail = 0;

for (const ex of CENSUS_EXAMPLES) {
    const bwPath = join(EXAMPLES_DIR, ex.name, 'program.bw');
    if (!existsSync(bwPath)) {
        console.error(`SKIP ${ex.name}: no program.bw`);
        fail++;
        continue;
    }

    // Step 1: parse .bw → generateC()
    let cCode;
    try {
        const bw = readFileSync(bwPath, 'utf8');
        const creator = new SB3Creator();
        creator.parse(bw);
        cCode = creator.generateC();
        if (!cCode || cCode.length < 10) throw new Error('empty C output');
    } catch (e) {
        console.error(`GENC-FAIL ${ex.name}: ${e.message}`);
        fail++;
        continue;
    }

    // Step 2: compile C via stc-compiler API
    try {
        const resp = await fetch(COMPILER_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                code: cCode,
                language: 'c',
                target: ex.device,
                format: 'hex',
                fosc: 11059200,
            }),
            signal: AbortSignal.timeout(30000),
        });
        const data = await resp.json();
        if (!data.success) {
            console.error(`CC-FAIL ${ex.name}: ${(data.log || data.error || '').substring(0, 120)}`);
            fail++;
            continue;
        }
        const hexData = Buffer.from(data.base64, 'base64').toString('utf8');
        writeFileSync(join(OUTPUT_DIR, `${ex.name}.hex`), hexData);
        console.log(`OK ${ex.name}: ${data.bytes} bytes`);
        ok++;
    } catch (e) {
        console.error(`API-FAIL ${ex.name}: ${e.message}`);
        fail++;
    }
}

console.log(`\nDone: ${ok} ok, ${fail} fail out of ${CENSUS_EXAMPLES.length}`);
process.exit(fail > 0 ? 1 : 0);
