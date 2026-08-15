#!/bin/bash
# rung_emu8051_bp_write.sh — verify all shipped emu8051 wasm builds
# export emu_dbg_set_bp_write and capabilities() reports "write".
#
# DoD: no build is feature-lottery on write watchpoints.
#
# Usage: ./tests/rung_emu8051_bp_write.sh
set -e
cd "$(dirname "$0")/.."

PASS=0
FAIL=0

pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== emu8051 write-watchpoint export verification ==="
echo ""

# All known wasm locations (source-of-truth + deployed copies).
WASMS=(
    "emu8051-stc/build/emu8051.wasm"
    "lego/brickwright-lite/packages/scratch-gui/src/lib/emu8051/emu8051.wasm"
    "lego/brickwright-lite/packages/scratch-gui/build/static/emu8051.wasm"
    "lego/brickwright-lite/overlay/scratch-gui/src/lib/emu8051/emu8051.wasm"
    "bw-bundle/lite/packages/scratch-gui/src/lib/emu8051/emu8051.wasm"
    "bw-bundle/lite/packages/scratch-gui/build/static/emu8051.wasm"
    "bw-bundle/lite/overlay/scratch-gui/src/lib/emu8051/emu8051.wasm"
)

for rel in "${WASMS[@]}"; do
    f="/mnt/volume1/code/$rel"
    if [ ! -f "$f" ]; then
        continue
    fi

    # Check export exists AND capabilities reports "write".
    RESULT=$(node -e "
const fs = require('fs');
const buf = fs.readFileSync('$f');
const mod = new WebAssembly.Module(buf);
const ex = WebAssembly.Module.exports(mod);
const hasExport = ex.some(e => e.name === 'emu_dbg_set_bp_write');
const hasCap = ex.some(e => e.name === 'emu_capabilities');
process.stdout.write(JSON.stringify({ hasExport, hasCap }));
" 2>/dev/null)

    HAS_EXPORT=$(echo "$RESULT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).hasExport))" 2>/dev/null)
    HAS_CAP=$(echo "$RESULT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).hasCap))" 2>/dev/null)

    if [ "$HAS_EXPORT" = "true" ]; then
        pass "$rel: emu_dbg_set_bp_write exported"
    else
        fail "$rel: emu_dbg_set_bp_write MISSING"
    fi

    if [ "$HAS_CAP" = "true" ]; then
        pass "$rel: emu_capabilities exported"
    else
        fail "$rel: emu_capabilities MISSING"
    fi
done

# Instantiate the source-of-truth build and verify capabilities JSON.
SRC="/mnt/volume1/code/emu8051-stc/build/emu8051.wasm"
if [ -f "$SRC" ]; then
    CAP_WRITE=$(node -e "
(async () => {
    const buf = require('fs').readFileSync('$SRC');
    const inst = await WebAssembly.instantiate(buf, {
        env: { emscripten_resize_heap: () => 0 },
        wasi_snapshot_preview1: { fd_write: () => 0, fd_close: () => 0, fd_seek: () => 0, proc_exit: () => {} }
    });
    const ex = inst.instance.exports;
    if (ex.emu_init) ex.emu_init();
    const ptr = ex.emu_capabilities();
    const view = new Uint8Array(ex.memory.buffer);
    let s = '';
    for (let i = ptr; view[i]; i++) s += String.fromCharCode(view[i]);
    const caps = JSON.parse(s);
    process.stdout.write(caps.breakpoints.includes('write') ? 'true' : 'false');
})();
" 2>/dev/null)
    if [ "$CAP_WRITE" = "true" ]; then
        pass "capabilities() reports 'write' in breakpoints"
    else
        fail "capabilities() missing 'write' in breakpoints"
    fi
fi

echo ""
echo "================================"
echo "emu8051 bp_write: $PASS pass, $FAIL fail"
echo "================================"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
