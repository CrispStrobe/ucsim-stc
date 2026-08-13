/**
 * picobb_boot_rp2040js.mjs — boot PicoBB (BBC BASIC) under rp2040js.
 *
 * Loads the real RP2040 B1 bootrom, parses the PicoBB UF2 into flash,
 * and runs with the Simulator class (clock-aware, handles WFI/WFE).
 * Captures UART0 TX for the BBC BASIC banner/prompt.
 *
 * Usage: node tests/picobb_boot_rp2040js.mjs [max-seconds] [--send "PRINT 2+2"]
 */

import { readFileSync, openSync, readSync, closeSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Import rp2040js from bw-board's node_modules (read-only reference)
const RP2040JS_BASE = '/mnt/volume1/code/lego/brickwright-lite/packages/scratch-gui/node_modules/rp2040js/dist/esm';
const { RP2040, ConsoleLogger, LogLevel, USBCDC } = await import(`${RP2040JS_BASE}/index.js`);
const { Simulator } = await import(`${RP2040JS_BASE}/simulator.js`);
const { SimulationClock } = await import(`${RP2040JS_BASE}/clock/simulation-clock.js`);

const UF2_FILE = resolve(__dirname, 'fixtures/picobb/bbcbasic_console_pico.uf2');
const BOOTROM_FILE = resolve(__dirname, 'fixtures/picobb/rp2040_bootrom_b1.bin');
const MAX_SECONDS = parseInt(process.argv[2] || '30', 10);
const FLASH_START = 0x10000000;

// --- Parse UF2 ---
function loadUF2(path, mcu) {
  const fd = openSync(path, 'r');
  const buf = new Uint8Array(512);
  let blocks = 0;
  while (readSync(fd, buf) === 512) {
    const dv = new DataView(buf.buffer);
    const magic0 = dv.getUint32(0, true);
    const magic1 = dv.getUint32(4, true);
    if (magic0 !== 0x0A324655 || magic1 !== 0x9E5D5157) continue;
    const addr = dv.getUint32(12, true);
    const sz = dv.getUint32(16, true);
    const payload = buf.slice(32, 32 + sz);
    mcu.flash.set(payload, addr - FLASH_START);
    blocks++;
  }
  closeSync(fd);
  return blocks;
}

// --- Load bootrom ---
const bootromBin = readFileSync(BOOTROM_FILE);
const bootromWords = new Uint32Array(
  bootromBin.buffer, bootromBin.byteOffset,
  Math.floor(bootromBin.length / 4)
);

// --- Create simulator ---
const clock = new SimulationClock();
const simulator = new Simulator(clock);
const mcu = simulator.rp2040;
mcu.logger = new ConsoleLogger(LogLevel.Error);

// Suppress SIO address warnings (interpolator reads — console.warn in sio.js)
let sioErrorCount = 0;
const origWarn = console.warn;
console.warn = (...args) => {
  const msg = args.join(' ');
  if (msg.includes('SIO address')) {
    sioErrorCount++;
    return;
  }
  origWarn(...args);
};

// Load bootrom (this calls reset() internally, which wipes flash)
mcu.loadBootrom(bootromWords);
console.log('Bootrom loaded (B1 revision)');

// Load UF2 AFTER bootrom (since loadBootrom calls reset which wipes flash)
const blocks = loadUF2(UF2_FILE, mcu);
console.log(`UF2 loaded: ${blocks} blocks into flash`);

// Verify app vector table
const sp = mcu.flash[0x100] | (mcu.flash[0x101] << 8) | (mcu.flash[0x102] << 16) | (mcu.flash[0x103] << 24);
const pc = mcu.flash[0x104] | (mcu.flash[0x105] << 8) | (mcu.flash[0x106] << 16) | (mcu.flash[0x107] << 24);
console.log(`App vector table (+0x100): SP=0x${(sp >>> 0).toString(16)}, PC=0x${(pc >>> 0).toString(16)}`);

// --- Wire UART0 TX ---
let uartBuf = '';
let uartLines = [];
let totalBytes = 0;
let gotPrompt = false;

// ANSI escape sequence detection for cursor position query (ESC[6n)
let escBuf = '';
let pendingCPR = 0; // count of cursor position requests to respond to

function handleByte(byte, source) {
  totalBytes++;
  const ch = String.fromCharCode(byte);

  // Detect ESC sequences
  if (byte === 0x1B) {
    escBuf = '\x1B';
    return;
  }
  if (escBuf.length > 0) {
    escBuf += ch;
    if (escBuf === '\x1B[6n') {
      // Cursor position query — respond with ESC[24;80R (24 rows, 80 cols)
      pendingCPR++;
      escBuf = '';
      return;
    }
    if (escBuf.length >= 10 || (escBuf.length >= 2 && escBuf[1] !== '[')) {
      // Not a recognized sequence, flush
      for (const c of escBuf) {
        process.stdout.write(c);
      }
      escBuf = '';
      return;
    }
    // Still accumulating escape sequence
    if (escBuf.length < 10 && /^\x1B\[\d*;?\d*[A-Za-z]?$/.test(escBuf) === false
        && /^\x1B\[\d*;?\d*$/.test(escBuf) === false
        && escBuf !== '\x1B' && escBuf !== '\x1B[') {
      // Unknown sequence, flush
      for (const c of escBuf) process.stdout.write(c);
      escBuf = '';
    }
    return;
  }

  process.stdout.write(ch);
  if (ch === '\n') {
    uartLines.push(uartBuf);
    uartBuf = '';
  } else if (ch !== '\r') {
    uartBuf += ch;
  }
  // Detect the BBC BASIC prompt
  if (uartBuf === '>') {
    gotPrompt = true;
  }
}

mcu.uart[0].onByte = (byte) => handleByte(byte, 'uart0');

// --- Wire USB CDC (many pico-sdk programs use USB serial) ---
const cdc = new USBCDC(mcu.usbCtrl);
let usbConnected = false;
cdc.onDeviceConnected = () => {
  usbConnected = true;
  process.stderr.write('[USB CDC connected]\n');
  // Send a newline to trigger prompt
  cdc.sendSerialByte('\r'.charCodeAt(0));
  cdc.sendSerialByte('\n'.charCodeAt(0));
};
cdc.onSerialData = (data) => {
  for (const byte of data) {
    handleByte(byte, 'usb');
  }
};

// --- Monkey-patch SIO to handle FIFO and spinlock registers ---
// rp2040js returns 0xFFFFFFFF for unknown SIO addresses, which makes
// FIFO_ST.VLD=1 (always data available) causing infinite polling.
// Patch: FIFO_ST returns 0x02 (RDY=1, VLD=0), FIFO_RD returns 0.
const sio = mcu.sio;
const origRead = sio.readUint32.bind(sio);
sio.readUint32 = (offset) => {
  switch (offset) {
    case 0x050: return 0x02;     // FIFO_ST: RDY=1, VLD=0
    case 0x058: return 0;        // FIFO_RD: empty
    case 0x05c: return 0;        // SPINLOCK_ST: all free
    default: return origRead(offset);
  }
};
const origWrite = sio.writeUint32.bind(sio);
sio.writeUint32 = (offset, value) => {
  if (offset === 0x054) return; // FIFO_WR: discard
  origWrite(offset, value);
};
console.log('SIO patched: FIFO stub (VLD=0, RDY=1)');

// --- Boot from boot2 (0x10000000) as rp2040js demo does ---
mcu.core.PC = 0x10000000;
console.log(`Boot: PC=0x${mcu.core.PC.toString(16)}`);
console.log(`Running for up to ${MAX_SECONDS}s...`);
console.log('--- UART output ---');

// Schedule sending a CR after ~2 seconds to trigger the REPL
let sentInitCR = false;
let waitingForInit = true;

// --- Run using the simulator's execute loop (clock-aware, handles WFI) ---
// We'll use a manual loop similar to Simulator.execute() but synchronous
const cycleNanos = 1e9 / 125_000_000; // 125 MHz
const maxNanos = MAX_SECONDS * 1e9;
const t0 = Date.now();
let totalCycles = 0;
let lastProgressNs = 0;

while (clock.nanos < maxNanos) {
  if (mcu.core.waiting) {
    // Fast-forward clock to next alarm (handles WFI/WFE)
    const skip = clock.nanosToNextAlarm;
    if (skip > 0 && skip < Infinity) {
      clock.tick(skip);
    } else {
      // No pending alarms — nothing will wake the core
      console.log('\n[Core waiting with no pending alarms — halted]');
      break;
    }
  } else {
    const cycles = mcu.core.executeInstruction();
    clock.tick(cycles * cycleNanos);
    totalCycles += cycles;
  }

  // After seeing "Waiting for connection", send CR to trigger REPL
  if (!sentInitCR && uartLines.some(l => l.includes('Waiting for connection'))) {
    sentInitCR = true;
    process.stderr.write('[Sending CR to trigger REPL]\n');
    mcu.uart[0].feedByte(0x0D); // CR
  }

  // Respond to cursor position queries (ESC[6n → ESC[24;80R)
  if (pendingCPR > 0) {
    pendingCPR--;
    const response = '\x1B[24;80R';
    for (const c of response) {
      mcu.uart[0].feedByte(c.charCodeAt(0));
    }
  }

  // Progress report every 100ms simulated
  if (clock.nanos - lastProgressNs > 100_000_000) {
    lastProgressNs = clock.nanos;
    const simMs = (clock.nanos / 1e6).toFixed(0);
    const wallS = ((Date.now() - t0) / 1000).toFixed(1);
    // Only report to stderr to not mix with UART output
    process.stderr.write(`  [sim=${simMs}ms, wall=${wallS}s, ${totalBytes} UART bytes, ${sioErrorCount} SIO errs]\n`);
  }

  // If we got the prompt, send input and wait for response
  if (gotPrompt) {
    gotPrompt = false;
    const sendArg = process.argv.indexOf('--send');
    if (sendArg >= 0 && process.argv[sendArg + 1]) {
      const text = process.argv[sendArg + 1] + '\r';
      console.log(`\n[Sending: ${text.trim()}]`);
      for (const ch of text) {
        if (usbConnected) {
          cdc.sendSerialByte(ch.charCodeAt(0));
        } else {
          mcu.uart[0].feedByte(ch.charCodeAt(0));
        }
      }
      // Continue running to get the response, then stop after next prompt
      // Set a flag to stop after we see another prompt
      const waitForResponse = true;
      let responseLines = 0;
      const origOnByte = mcu.uart[0].onByte;
      mcu.uart[0].onByte = (byte) => {
        origOnByte(byte);
        if (String.fromCharCode(byte) === '\n') responseLines++;
        if (uartBuf === '>' && responseLines > 0) {
          // Got response + new prompt
          console.log('\n[Response received, stopping]');
          // Signal to break
          gotPrompt = true;
        }
      };
      // Run for up to 5 more seconds for response
      const responseDeadline = clock.nanos + 5e9;
      while (clock.nanos < responseDeadline && !gotPrompt) {
        if (mcu.core.waiting) {
          const skip = clock.nanosToNextAlarm;
          if (skip > 0 && skip < Infinity) clock.tick(Math.min(skip, responseDeadline - clock.nanos));
          else break;
        } else {
          const cycles = mcu.core.executeInstruction();
          clock.tick(cycles * cycleNanos);
          totalCycles += cycles;
        }
      }
      break;
    } else {
      console.log('\n[BBC BASIC prompt detected! No --send arg, stopping.]');
      break;
    }
  }

  // Safety: wall-clock timeout
  if (Date.now() - t0 > MAX_SECONDS * 2000) {
    console.log('\n[Wall-clock timeout]');
    break;
  }
}

const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
const simMs = (clock.nanos / 1e6).toFixed(0);
console.log(`\n--- Summary ---`);
console.log(`Simulated: ${simMs}ms, wall: ${elapsed}s, ${totalCycles} cycles`);
console.log(`UART: ${totalBytes} bytes, ${uartLines.length} lines`);
for (const line of uartLines.slice(0, 30)) {
  console.log(`  | ${line}`);
}
if (uartBuf.length > 0) {
  console.log(`  | (partial) ${uartBuf}`);
}
console.log(`Final PC=0x${mcu.core.PC.toString(16)}`);
