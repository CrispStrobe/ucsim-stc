/**
 * avr8js_trace_runner.mjs — canonical-trace adapter for avr8js.
 *
 * Runs avr8js on an ATmega328P hex file and returns the canonical trace
 * format (events, serial, pwm, vars, horizon) so that compareTraces from
 * sb3-creator's traceOracle.js can diff it directly against simavr or the
 * referee.
 *
 * Uses avr8js from bw-board's node_modules (read-only reference).
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire('/mnt/volume1/code/bw-board/');
const {
  CPU, avrInstruction, AVRIOPort, AVRTimer, AVRADC, AVRUSART,
  portBConfig, portCConfig, portDConfig,
  timer0Config, timer1Config, timer2Config,
  adcConfig, usart0Config,
} = require('avr8js');

// ATmega328P port-bit → Arduino Nano digital pin name.
const PORT_TO_NANO = new Map();
for (let i = 0; i < 8; i++) {
  PORT_TO_NANO.set(`portb.${i}`, `d${8 + i}`);
  PORT_TO_NANO.set(`portd.${i}`, `d${i}`);
  PORT_TO_NANO.set(`portc.${i}`, `a${i}`);
}

function parseIHex(hexStr) {
  const lines = hexStr.trim().split('\n');
  let maxAddr = 0;
  const chunks = [];
  for (const line of lines) {
    if (!line.startsWith(':')) continue;
    const len = parseInt(line.slice(1, 3), 16);
    const addr = parseInt(line.slice(3, 7), 16);
    const type = parseInt(line.slice(7, 9), 16);
    if (type !== 0) continue;
    const data = [];
    for (let i = 0; i < len; i++) {
      data.push(parseInt(line.slice(9 + i * 2, 11 + i * 2), 16));
    }
    chunks.push({ addr, data });
    if (addr + len > maxAddr) maxAddr = addr + len;
  }
  const flash = new Uint8Array(maxAddr);
  for (const { addr, data } of chunks) {
    for (let i = 0; i < data.length; i++) flash[addr + i] = data[i];
  }
  const words = new Uint16Array(maxAddr / 2);
  for (let i = 0; i < maxAddr; i += 2) {
    words[i / 2] = flash[i] | (flash[i + 1] << 8);
  }
  return words;
}

function buildDeclMap(declarations) {
  const m = new Map();
  for (const d of declarations) {
    m.set(String(d.where).toLowerCase(), {
      name: String(d.name).toLowerCase(),
      activeLow: !!d.activeLow,
    });
  }
  return m;
}

/**
 * Run avr8js on a hex file and return a canonical trace.
 *
 * @param {string}  hexPath       Path to the .ihx file
 * @param {Array}   declarations  Pin declarations [{where, name, activeLow}]
 * @param {object}  opts
 * @param {number}  opts.horizonMs  Trace horizon in ms (default 2500)
 * @param {number}  opts.freqHz     CPU frequency (default 16000000)
 * @returns {{ events, serial, pwm, vars, horizon }}
 */
export async function runAvr8js(hexPath, declarations = [], opts = {}) {
  const horizonMs = opts.horizonMs ?? 2500;
  const freqHz = opts.freqHz ?? 16000000;
  const declMap = buildDeclMap(declarations);

  const hexStr = readFileSync(hexPath, 'utf-8');
  const program = parseIHex(hexStr);

  const cpu = new CPU(program, freqHz);
  const portB = new AVRIOPort(cpu, portBConfig);
  const portC = new AVRIOPort(cpu, portCConfig);
  const portD = new AVRIOPort(cpu, portDConfig);
  const timer0 = new AVRTimer(cpu, timer0Config);
  const timer1 = new AVRTimer(cpu, timer1Config);
  const timer2 = new AVRTimer(cpu, timer2Config);
  const adc = new AVRADC(cpu, adcConfig);
  const usart = new AVRUSART(cpu, usart0Config, freqHz);

  const trace = { events: [], serial: [], pwm: [], vars: {}, horizon: horizonMs };
  const lastIntent = new Map();
  const uartBytes = [];
  let lastPortB = 0, lastPortD = 0, lastPortC = 0;

  const recordPinChange = (port, portName, lastVal) => {
    const ddr = cpu.data[port === 'B' ? 0x24 : port === 'D' ? 0x2A : 0x27];
    const val = cpu.data[port === 'B' ? 0x25 : port === 'D' ? 0x2B : 0x28];
    const output = val & ddr;
    const changed = output ^ lastVal;
    const tMs = (cpu.cycles / freqHz) * 1000;
    if (tMs > horizonMs) return output;

    for (let i = 0; i < 8; i++) {
      if (!(changed & (1 << i))) continue;
      const portPin = `port${portName.toLowerCase()}.${i}`;
      const nanoPinName = PORT_TO_NANO.get(portPin);
      if (!nanoPinName) continue;
      const decl = declMap.get(nanoPinName);
      if (!decl) continue;
      const high = (output >> i) & 1;
      const intent = (high !== (decl.activeLow ? 1 : 0)) ? 1 : 0;
      if (lastIntent.get(decl.name) === intent) continue;
      lastIntent.set(decl.name, intent);
      trace.events.push({ tMs, pin: decl.name, level: intent });
    }
    return output;
  };

  portB.addListener(() => { lastPortB = recordPinChange('B', 'B', lastPortB); });
  portD.addListener(() => { lastPortD = recordPinChange('D', 'D', lastPortD); });
  portC.addListener(() => { lastPortC = recordPinChange('C', 'C', lastPortC); });

  usart.onByteTransmit = (byte) => {
    const tMs = (cpu.cycles / freqHz) * 1000;
    if (tMs <= horizonMs) uartBytes.push({ tMs, byte });
  };

  // Run for horizon + 5% headroom
  const maxCycles = Math.ceil((horizonMs / 1000) * freqHz * 1.05);
  const startCycle = cpu.cycles;
  while ((cpu.cycles - startCycle) < maxCycles) {
    avrInstruction(cpu);
    cpu.tick();
  }

  // Assemble UART bytes into lines
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

  return trace;
}
