#!/bin/bash
# rung_keypad_bcm_golden.sh — KEYPAD + MATRIX8X8 BCM brightness golden trace.
#
# Keypress upgrades row 2 from brightness 1 to 3, changing its BCM duty
# from 1/3 to 3/3. Verifies the phase renders reflect the change.
#
# Pre-key (rows 0-3 at levels 3,2,1,0):
#   Phase 0 (p0|p1): 00 00 00 FF FF FF FF FF
#   Phase 1 (p1):    00 00 FF FF FF FF FF FF  ← row2 dark (level 1)
#   Phase 2 (p0&p1): 00 FF FF FF FF FF FF FF  ← row2 dark
#
# Post-key (row 2 upgraded to level 3):
#   Phase 0 (p0|p1): 00 00 00 FF FF FF FF FF  (unchanged)
#   Phase 1 (p1):    00 00 00 FF FF FF FF FF  ← row2 now lit!
#   Phase 2 (p0&p1): 00 FF 00 FF FF FF FF FF  ← row2 now lit!
#
# Usage: ./tests/rung_keypad_bcm_golden.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/keypad_bcm_combined.ihx"
FOSC=11059200
# 55ms: two full BCM cycles (48 ticks) + margin
UNTIL_NS=55000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

echo "=== Keypad + BCM Brightness Golden Trace (STC89) ==="
echo ""

# Golden BCM column values
# Transitional cycle (ticks 0-23): key fires at ms=15 (between ticks 14-15)
# so phases 0-1 are pre-key, phase 2 is already post-key.
PRE_P0=(00 00 00 FF FF FF FF FF)   # phase 0 (pre-key)
PRE_P1=(00 00 FF FF FF FF FF FF)   # phase 1 (pre-key, row 2 dark: level 1)
PRE_P2=(00 FF 00 FF FF FF FF FF)   # phase 2 (POST-key, row 2 now lit: level 3)

# Post-key cycle (row 2 → level 3)
POST_P0=(00 00 00 FF FF FF FF FF)  # phase 0 (unchanged)
POST_P1=(00 00 00 FF FF FF FF FF)  # phase 1 (row 2 now lit!)
POST_P2=(00 FF 00 FF FF FF FF FF)  # phase 2 (row 2 now lit!)

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

# --- Section 1: Transitional BCM cycle (ticks 0-23) ---
echo "--- Section 1: Transitional BCM cycle (phases 0-1 pre-key, phase 2 post-key) ---"
PHASE_NAMES=("p0|p1" "p1" "p0&p1")
printf "%-6s %-7s %-4s %-10s %-8s %-8s %-6s\n" \
    "Tick" "Phase" "Row" "golden" "emu" "ucsim" "Match"
printf "%-6s %-7s %-4s %-10s %-8s %-8s %-6s\n" \
    "----" "-----" "---" "------" "---" "-----" "-----"

for tick in $(seq 0 23); do
    p=$((tick / 8))
    row=$((tick % 8))
    case $p in
        0) gold="${PRE_P0[$row]}" ;;
        1) gold="${PRE_P1[$row]}" ;;
        2) gold="${PRE_P2[$row]}" ;;
    esac
    ev=$(sed -n "$((tick+1))p" "$TMP/emu_cols.txt")
    uv=$(sed -n "$((tick+1))p" "$TMP/ucsim_cols.txt")
    if [ "$ev" = "$gold" ] && [ "$uv" = "$gold" ]; then
        m="PASS"; PASS=$((PASS+1))
    else
        m="FAIL"; FAIL=$((FAIL+1))
    fi
    # Only print phase-boundary rows and rows 0-2 (interesting ones)
    if [ "$row" -le 2 ] || [ "$row" -eq 7 ]; then
        printf "%-6d %-7s %-4d %-10s %-8s %-8s %-6s\n" \
            "$tick" "${PHASE_NAMES[$p]}" "$row" "P0=0x$gold" "0x$ev" "0x$uv" "$m"
    fi
done

# --- Section 2: Post-key BCM cycle (ticks 24-47) ---
echo ""
echo "--- Section 2: Post-key BCM cycle (row 2 upgraded to level 3) ---"
printf "%-6s %-7s %-4s %-10s %-8s %-8s %-6s\n" \
    "Tick" "Phase" "Row" "golden" "emu" "ucsim" "Match"
printf "%-6s %-7s %-4s %-10s %-8s %-8s %-6s\n" \
    "----" "-----" "---" "------" "---" "-----" "-----"

min_post=$((emu_count < 48 ? emu_count : 48))
for tick in $(seq 24 $((min_post - 1))); do
    p=$(( (tick - 24) / 8 ))
    row=$(( (tick - 24) % 8 ))
    case $p in
        0) gold="${POST_P0[$row]}" ;;
        1) gold="${POST_P1[$row]}" ;;
        2) gold="${POST_P2[$row]}" ;;
    esac
    ev=$(sed -n "$((tick+1))p" "$TMP/emu_cols.txt")
    uv=$(sed -n "$((tick+1))p" "$TMP/ucsim_cols.txt")
    if [ "$ev" = "$gold" ] && [ "$uv" = "$gold" ]; then
        m="PASS"; PASS=$((PASS+1))
    else
        m="FAIL"; FAIL=$((FAIL+1))
    fi
    if [ "$row" -le 2 ] || [ "$row" -eq 7 ]; then
        printf "%-6d %-7s %-4d %-10s %-8s %-8s %-6s\n" \
            "$tick" "${PHASE_NAMES[$p]}" "$row" "P0=0x$gold" "0x$ev" "0x$uv" "$m"
    fi
done

# --- Section 3: Duty change verification ---
echo ""
echo "--- Section 3: Row 2 duty change (1/3 → 3/3) ---"

for src in emu ucsim; do
    # Pre-key phases only (phase 0 tick 2, phase 1 tick 10): row 2 at level 1
    pre_lit=0
    for t in 2 10; do
        val=$(sed -n "$((t+1))p" "$TMP/${src}_cols.txt")
        [ "$val" != "FF" ] && pre_lit=$((pre_lit+1))
    done
    # Post-key full cycle (ticks 26, 34, 42): row 2 at level 3
    post_lit=0
    for t in 26 34 42; do
        val=$(sed -n "$((t+1))p" "$TMP/${src}_cols.txt")
        [ "$val" != "FF" ] && post_lit=$((post_lit+1))
    done
    # Pre-key: level 1 → lit in 1/2 pure pre-key phases (phase 0 yes, phase 1 no)
    # Post-key: level 3 → lit in 3/3 phases
    if [ "$pre_lit" -eq 1 ] && [ "$post_lit" -eq 3 ]; then
        printf "%s: row 2 pre-key 1/2 phases, post-key %d/3 phases — PASS\n" "$src" "$post_lit"
        PASS=$((PASS+1))
    else
        printf "%s: row 2 pre=%d/2 post=%d/3 (expected 1/2 → 3/3) — FAIL\n" \
            "$src" "$pre_lit" "$post_lit"
        FAIL=$((FAIL+1))
    fi
done

# --- Section 4: Cross-emulator full sequence ---
echo ""
echo "--- Section 4: Cross-emulator column sequence ---"
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

# --- Section 5: 595 edges cross-emu ---
echo ""
echo "--- Section 5: 595 edges cross-emu ---"
timeout 15 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/emu_595.pin"
timeout 15 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/ucsim_595.pin"

if diff "$TMP/emu_595.pin" "$TMP/ucsim_595.pin" > /dev/null 2>&1; then
    echo "595 edges: EXACT match ($(wc -l < "$TMP/emu_595.pin") events)"
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
