#!/bin/bash
# generated_cube_diff.sh — blocks → C → measured behaviour for the LED cube.
#
# Emits C from a cube pseudocode program via sb3-creator's generateC(),
# builds with SDCC, runs both emulators, and diffs the P0/P2 events.
#
# THE CANONICAL HARNESS for the blocks→C→behaviour claim in RESULTS.md.
#
# Usage: ./tests/generated_cube_diff.sh [sb3-creator-path] [until_ns]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
EMU_TRACE="${EMU_TRACE:-$(command -v emu_trace 2>/dev/null || echo "")}"
SB3="${1:-/mnt/volume1/code/sb3-creator}"
UNTIL_NS="${2:-100000000}"
FOSC=11059200

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ -z "$EMU_TRACE" ] || [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 77; fi
if [ ! -d "$SB3/src" ]; then echo "SKIP: sb3-creator not found at $SB3" >&2; exit 77; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# The cube pseudocode fixture — inline so it is versioned with the test
cat > "$TMP/cube.bw" << 'BWEOF'
DEVICE STC12C5A60S2
CLOCK 11059200
LEDCUBE 4

WHEN flag clicked:
  set voxel 0 0 0 to red
  set voxel 1 1 1 to blue
  set voxel 2 2 2 to red
  set voxel 3 3 3 to blue
  hold frame for 500 ms
  clear cube
  fill layer 0 with red
  hold frame for 500 ms
  clear cube
  fill layer 3 with blue
  hold frame for 500 ms
BWEOF

# Step 1: emit C via generateC()
SB3_COMMIT=$(git -C "$SB3" rev-parse --short HEAD 2>/dev/null || echo "unknown")
node --input-type=module -e "
import SB3Creator from '$SB3/src/utils/sb3Creator.js';
import fs from 'fs';
const src = fs.readFileSync('$TMP/cube.bw', 'utf8');
const c = new SB3Creator();
c.parse(src);
const result = c.generateC();
if (c.warnings.length) { console.error('WARNINGS:', c.warnings); process.exit(1); }
process.stdout.write(result);
" > "$TMP/cube_gen.c" 2>"$TMP/emit_err.txt"

if [ $? -ne 0 ]; then
    echo "FAIL: generateC() failed"
    cat "$TMP/emit_err.txt"
    exit 1
fi

# Step 2: build with SDCC — NO edits to the generated C
sdcc -mmcs51 --model-small -o "$TMP/cube_gen.ihx" "$TMP/cube_gen.c" 2>"$TMP/build_err.txt"
if [ $? -ne 0 ]; then
    echo "FAIL: SDCC build failed on unedited emitter output"
    cat "$TMP/build_err.txt"
    exit 1
fi
HEX_SIZE=$(wc -c < "$TMP/cube_gen.ihx")

echo "generated_cube_diff (sb3-creator $SB3_COMMIT, span ${UNTIL_NS} ns)"
echo "  emitter: $(wc -l < "$TMP/cube_gen.c") lines C, $HEX_SIZE bytes hex"

# Step 3: run both emulators
"$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$TMP/cube_gen.ihx" 2>/dev/null \
    | awk '$2 == "SFR" && ($3 == "80" || $3 == "A0")' | cut -f2- > "$TMP/emu.ev"

timeout 120 "$STC12_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$TMP/cube_gen.ihx" 2>/dev/null \
    | awk '$2 == "SFR" && ($3 == "80" || $3 == "A0")' | cut -f2- > "$TMP/ucsim.ev"

EN=$(wc -l < "$TMP/emu.ev"); UN=$(wc -l < "$TMP/ucsim.ev")

# Step 4: diff
if [ "$EN" -eq "$UN" ] && diff "$TMP/emu.ev" "$TMP/ucsim.ev" > /dev/null 2>&1; then
    echo "  PASS: $EN/$UN events strictly identical"
else
    echo "  FAIL: emu=$EN ucsim=$UN"
    diff "$TMP/emu.ev" "$TMP/ucsim.ev" 2>/dev/null | head -5
    exit 1
fi

# Timing
"$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$TMP/cube_gen.ihx" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "A0" && $4 != "FF"' | head -10 > "$TMP/scan.tsv"

python3 -c "
lines = open('$TMP/scan.tsv').readlines()
times = [int(l.split('\t')[0]) for l in lines]
if len(times) >= 9:
    line_ms = (times[1] - times[0]) / 1e6
    frame_ms = (times[8] - times[0]) / 1e6
    print(f'  per-line: {line_ms:.3f} ms, frame: {frame_ms:.3f} ms, refresh: {1e9/(times[8]-times[0]):.1f} Hz')
" 2>/dev/null || true

echo "  scan table: $(awk '$2 == "SFR" && $3 == "A0" && $4 != "FF" {printf "%s ", $4}' "$TMP/emu.ev" | head -c 40)"
