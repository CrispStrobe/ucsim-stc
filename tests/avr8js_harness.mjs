/**
 * avr8js_harness.mjs — differential-oracle harness for avr8js.
 *
 * Loads an ATmega328P hex, runs for a bounded number of cycles,
 * and reports pin edges and UART bytes in the same format as
 * simavr_harness.c for direct comparison.
 *
 * Usage: node tests/avr8js_harness.mjs <hex-file> <max-cycles> [freq-hz]
 *
 * Requires avr8js from bw-board's node_modules (read-only).
 */

import { readFileSync } from 'fs';
import { resolve } from 'path';

// Use avr8js from bw-board (read-only reference)
import { createRequire } from 'module';
const require = createRequire('/mnt/volume1/code/bw-board/');
const {
  CPU, avrInstruction, AVRIOPort, AVRTimer, AVRADC, AVRUSART,
  portBConfig, portCConfig, portDConfig,
  timer0Config, timer1Config, timer2Config,
  adcConfig, usart0Config,
} = require('avr8js');

function parseIHex(hexStr) {
  const lines = hexStr.trim().split('\n');
  let maxAddr = 0;
  const chunks = [];
  for (const line of lines) {
    if (!line.startsWith(':')) continue;
    const len = parseInt(line.slice(1, 3), 16);
    const addr = parseInt(line.slice(3, 7), 16);
    const type = parseInt(line.slice(7, 9), 16);
    if (type !== 0) continue;  // only data records
    const data = [];
    for (let i = 0; i < len; i++) {
      data.push(parseInt(line.slice(9 + i * 2, 11 + i * 2), 16));
    }
    chunks.push({ addr, data });
    if (addr + len > maxAddr) maxAddr = addr + len;
  }
  const flash = new Uint8Array(maxAddr);
  for (const { addr, data } of chunks) {
    for (let i = 0; i < data.length; i++) {
      flash[addr + i] = data[i];
    }
  }
  // Convert to Uint16Array (little-endian words)
  const words = new Uint16Array(maxAddr / 2);
  for (let i = 0; i < maxAddr; i += 2) {
    words[i / 2] = flash[i] | (flash[i + 1] << 8);
  }
  return words;
}

// Parse arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('Usage: node tests/avr8js_harness.mjs <hex-file> <max-cycles> [freq-hz]');
  process.exit(1);
}

const hexFile = args[0];
const maxCycles = parseInt(args[1], 10);
const freq = args[2] ? parseInt(args[2], 10) : 16000000;

const hexStr = readFileSync(hexFile, 'utf-8');
const program = parseIHex(hexStr);

console.error(`Loaded ${program.length * 2} bytes from ${hexFile}`);

// Create CPU
const cpu = new CPU(program, freq);

// Set up peripherals
const portB = new AVRIOPort(cpu, portBConfig);
const portC = new AVRIOPort(cpu, portCConfig);
const portD = new AVRIOPort(cpu, portDConfig);
const timer0 = new AVRTimer(cpu, timer0Config);
const timer1 = new AVRTimer(cpu, timer1Config);
const timer2 = new AVRTimer(cpu, timer2Config);
const adc = new AVRADC(cpu, adcConfig);
const usart = new AVRUSART(cpu, usart0Config, freq);

// Event recording
const events = [];
let lastPortB = 0;
let lastPortD = 0;

portB.addListener(() => {
  const val = cpu.data[0x25]; // PORTB
  const ddr = cpu.data[0x24]; // DDRB
  const output = val & ddr;   // only output pins matter
  const changed = output ^ lastPortB;
  for (let i = 0; i < 8; i++) {
    if (changed & (1 << i)) {
      events.push({
        type: 'P', cycle: cpu.cycles, pin: i,
        value: (output >> i) & 1
      });
    }
  }
  lastPortB = output;
});

portD.addListener(() => {
  const val = cpu.data[0x2B]; // PORTD
  const ddr = cpu.data[0x2A]; // DDRD
  const output = val & ddr;
  const changed = output ^ lastPortD;
  for (let i = 0; i < 8; i++) {
    if (changed & (1 << i)) {
      events.push({
        type: 'D', cycle: cpu.cycles, pin: i,
        value: (output >> i) & 1
      });
    }
  }
  lastPortD = output;
});

// Hook UART TX
usart.onByteTransmit = (byte) => {
  events.push({
    type: 'U', cycle: cpu.cycles, pin: 0, value: byte
  });
};

// Run
const startCycle = cpu.cycles;
while ((cpu.cycles - startCycle) < maxCycles) {
  avrInstruction(cpu);
  cpu.tick();
}

// Output
console.log(`AVR8JS_CYCLES=${cpu.cycles}`);
console.log(`AVR8JS_FREQ=${freq}`);
console.log(`AVR8JS_EVENTS=${events.length}`);

for (const ev of events) {
  const ns = BigInt(ev.cycle) * 1000000000n / BigInt(freq);
  if (ev.type === 'P') {
    console.log(`PIN_EDGE cy=${ev.cycle} ns=${ns} portb.${ev.pin}=${ev.value}`);
  } else if (ev.type === 'D') {
    console.log(`PIN_EDGE cy=${ev.cycle} ns=${ns} portd.${ev.pin}=${ev.value}`);
  } else {
    const ch = (ev.value >= 0x20 && ev.value < 0x7f)
      ? String.fromCharCode(ev.value) : '.';
    console.log(`UART_TX cy=${ev.cycle} ns=${ns} byte=0x${ev.value.toString(16).padStart(2, '0')} '${ch}'`);
  }
}
