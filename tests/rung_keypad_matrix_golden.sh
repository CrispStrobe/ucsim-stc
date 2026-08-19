#!/bin/bash
# rung_keypad_matrix_golden.sh — combined KEYPAD4X4 + MATRIX8X8 golden trace.
#
# Verifies that a keypress updates the matrix frame buffer and the ISR
# scans the new pattern correctly, cross-emu byte/pin-exact.
#
# Initial pattern: row0=0xAA(P0=55), row1=0x55(P0=AA), rows2-7=dark(FF)
# After key 5 debounces (ms=15): row5=0xFF → P0=0x00
#
# Golden P0 per-tick:
#   Pre-key frame:  55 AA FF FF FF FF FF FF
#   Post-key frame: 55 AA FF FF FF 00 FF FF
#
# Usage: ./tests/rung_keypad_matrix_golden.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/keypad_matrix_combined.ihx"
FOSC=11059200
UNTIL_NS=30000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

echo "=== Keypad + Matrix Combined Golden Trace (STC89) ==="
echo ""

# Golden frames
PRE_KEY=(55 AA FF FF FF FF FF FF)
POST_KEY=(55 AA FF FF FF 00 FF FF)

# Extract column byte per tick (last P0 between TFs; FF if no P0 event)
extract_col_per_tick() {
    awk '
    $2 == "SFR" && $3 == "80" { last_p0 = toupper($4) }
    $2 == "TF" {
        if (NR > 1) {
            if (last_p0 != "") print last_p0
            else print "FF"
        }
        last_p0 = ""
    }
    END { if (last_p0 != "") print last_p0; else if (NR > 0) print "FF" }
    ' "$1"
}

# Run both emulators
timeout 15 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80" || $2 == "TF"' > "$TMP/emu.sfr"
timeout 15 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80" || $2 == "TF"' > "$TMP/ucsim.sfr"

extract_col_per_tick "$TMP/emu.sfr"   > "$TMP/emu_cols.txt"
extract_col_per_tick "$TMP/ucsim.sfr" > "$TMP/ucsim_cols.txt"

emu_count=$(wc -l < "$TMP/emu_cols.txt")
ucs_count=$(wc -l < "$TMP/ucsim_cols.txt")
echo "Ticks captured: emu=$emu_count ucsim=$ucs_count"
echo ""

# --- Section 1: Pre-key frame (first 8 ticks) ---
echo "--- Section 1: Pre-key frame (ticks 0-7) ---"
printf "%-6s %-4s %-10s %-8s %-8s %-6s\n" "Tick" "Row" "golden" "emu" "ucsim" "Match"
printf "%-6s %-4s %-10s %-8s %-8s %-6s\n" "----" "---" "------" "---" "-----" "-----"

for tick in $(seq 0 7); do
    gold="${PRE_KEY[$tick]}"
    ev=$(sed -n "$((tick+1))p" "$TMP/emu_cols.txt")
    uv=$(sed -n "$((tick+1))p" "$TMP/ucsim_cols.txt")
    if [ "$ev" = "$gold" ] && [ "$uv" = "$gold" ]; then
        m="PASS"; PASS=$((PASS+1))
    else
        m="FAIL"; FAIL=$((FAIL+1))
    fi
    printf "%-6d %-4d %-10s %-8s %-8s %-6s\n" "$tick" "$tick" "P0=0x$gold" "0x$ev" "0x$uv" "$m"
done

# --- Section 2: Post-key frame ---
echo ""
echo "--- Section 2: Post-key frame (first frame with row 5 = 0x00) ---"

# Find the first tick where row 5 shows 00 (key effect visible)
# Row 5 appears on ticks 5, 13, 21, 29, ...
emu_key_tick=""
for t in 5 13 21 29; do
    val=$(sed -n "$((t+1))p" "$TMP/emu_cols.txt")
    if [ "$val" = "00" ]; then
        emu_key_tick=$t
        break
    fi
done

ucs_key_tick=""
for t in 5 13 21 29; do
    val=$(sed -n "$((t+1))p" "$TMP/ucsim_cols.txt")
    if [ "$val" = "00" ]; then
        ucs_key_tick=$t
        break
    fi
done

echo "Key effect visible at: emu=tick $emu_key_tick ucsim=tick $ucs_key_tick"

if [ "$emu_key_tick" = "$ucs_key_tick" ] && [ -n "$emu_key_tick" ]; then
    echo "Both emulators agree on key-effect tick — PASS"
    PASS=$((PASS+1))
else
    echo "Key-effect tick disagreement — FAIL"
    FAIL=$((FAIL+1))
fi

# Verify the complete post-key frame (8 ticks starting at frame boundary)
if [ -n "$emu_key_tick" ]; then
    frame_start=$(( (emu_key_tick / 8) * 8 ))
    echo ""
    printf "%-6s %-4s %-10s %-8s %-8s %-6s\n" "Tick" "Row" "golden" "emu" "ucsim" "Match"
    printf "%-6s %-4s %-10s %-8s %-8s %-6s\n" "----" "---" "------" "---" "-----" "-----"

    for row in $(seq 0 7); do
        tick=$((frame_start + row))
        gold="${POST_KEY[$row]}"
        ev=$(sed -n "$((tick+1))p" "$TMP/emu_cols.txt")
        uv=$(sed -n "$((tick+1))p" "$TMP/ucsim_cols.txt")
        if [ "$ev" = "$gold" ] && [ "$uv" = "$gold" ]; then
            m="PASS"; PASS=$((PASS+1))
        else
            m="FAIL"; FAIL=$((FAIL+1))
        fi
        printf "%-6d %-4d %-10s %-8s %-8s %-6s\n" "$tick" "$row" "P0=0x$gold" "0x$ev" "0x$uv" "$m"
    done
fi

# --- Section 3: Cross-emulator full column sequence ---
echo ""
echo "--- Section 3: Cross-emulator column sequence ---"
min_both=$((emu_count < ucs_count ? emu_count : ucs_count))
if head -n "$min_both" "$TMP/emu_cols.txt" \
   | diff - <(head -n "$min_both" "$TMP/ucsim_cols.txt") > /dev/null 2>&1; then
    echo "Cross-emulator: EXACT match on first $min_both ticks"
    PASS=$((PASS+1))
else
    echo "Cross-emulator: DIVERGENCE"
    diff "$TMP/emu_cols.txt" "$TMP/ucsim_cols.txt" | head -10
    FAIL=$((FAIL+1))
fi

# --- Section 4: 595 edges cross-emu ---
echo ""
echo "--- Section 4: 595 shift register edges (tick 0→1) ---"
timeout 15 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/emu_595.pin"
timeout 15 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/ucsim_595.pin"

emu_595=$(wc -l < "$TMP/emu_595.pin")
if diff "$TMP/emu_595.pin" "$TMP/ucsim_595.pin" > /dev/null 2>&1; then
    echo "595 edges: EXACT match ($emu_595 events)"
    PASS=$((PASS+1))
else
    echo "595 edges: DIVERGENCE"
    diff "$TMP/emu_595.pin" "$TMP/ucsim_595.pin" | head -10
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
