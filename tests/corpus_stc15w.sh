#!/bin/bash
# corpus_stc15w.sh — cross-emulator differential on STC15W firmware corpus.
#
# REQUIRES a local corpus directory (default: corpus/stc15w/) that is NOT
# distributed with this repository. The corpus is gitignored and contains
# third-party firmware. Without it, this script does nothing.
#
# Usage: ./tests/corpus_stc15w.sh [corpus_dir] [until_ns]
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EMU="${EMU_TRACE:-../emu8051-stc/emu_trace}"
CORPUS="${1:-corpus/stc15w}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200

if [ ! -x "$TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi

# Detect -part support
EMU_HAS_PART=false
EMU_OUT=$("$EMU" -part STC15W -fosc $FOSC -until-ns 5000 \
    "$CORPUS"/$(ls "$CORPUS" | head -1) 2>/dev/null | head -3)
[ -n "$EMU_OUT" ] && EMU_HAS_PART=true

if ! $EMU_HAS_PART; then
    echo "SKIP: emu_trace does not support -part STC15W" >&2; exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

STRICT=0; PREFIX=0; DIVERGE=0; EMPTY=0; LOAD_FAIL=0; ERROR=0; TOTAL=0

echo "=== STC15W cross-emulator corpus ($CORPUS, ${UNTIL_NS}ns) ==="

for hex in "$CORPUS"/*.ihx "$CORPUS"/*.hex; do
    [ -f "$hex" ] || continue
    TOTAL=$((TOTAL+1))
    name=$(basename "$hex")

    U_ERR=$("$TRACE" -t STC15W -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        3>&1 1>"$TMP/ucsim_raw.ev" 2>&3)
    E_ERR=$("$EMU" -part STC15W -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        3>&1 1>"$TMP/emu_raw.ev" 2>&3)

    U_LOADED=true; E_LOADED=true
    echo "$U_ERR" | grep -qi "error\|fail" && U_LOADED=false
    echo "$U_ERR" | grep -qP "^0 words read" && U_LOADED=false
    echo "$E_ERR" | grep -qi "fail" && E_LOADED=false

    if ! $U_LOADED || ! $E_LOADED; then
        LOAD_FAIL=$((LOAD_FAIL+1))
        echo "  LOAD_FAIL  $name (ucsim=$U_LOADED, emu=$E_LOADED)"
        continue
    fi

    awk '$2 == "SFR" || $2 == "TF"' "$TMP/ucsim_raw.ev" | cut -f2- > "$TMP/ucsim.ev"
    awk '$2 == "SFR" || $2 == "TF"' "$TMP/emu_raw.ev" | cut -f2- > "$TMP/emu.ev"

    NU=$(wc -l < "$TMP/ucsim.ev")
    NE=$(wc -l < "$TMP/emu.ev")

    if [ "$NU" -eq 0 ] && [ "$NE" -eq 0 ]; then
        EMPTY=$((EMPTY+1)); continue
    fi
    if [ "$NU" -eq 0 ] || [ "$NE" -eq 0 ]; then
        ERROR=$((ERROR+1)); echo "  ERROR  $name (ucsim=$NU, emu=$NE)"; continue
    fi

    if [ "$NU" -eq "$NE" ] && diff "$TMP/ucsim.ev" "$TMP/emu.ev" > /dev/null 2>&1; then
        STRICT=$((STRICT+1))
        echo "  STRICT $name ($NU events)"
    else
        MIN=$((NU < NE ? NU : NE))
        head -n "$MIN" "$TMP/ucsim.ev" > "$TMP/u_pre.ev"
        head -n "$MIN" "$TMP/emu.ev" > "$TMP/e_pre.ev"
        if diff "$TMP/u_pre.ev" "$TMP/e_pre.ev" > /dev/null 2>&1; then
            PREFIX=$((PREFIX+1))
            echo "  PREFIX $name (ucsim=$NU, emu=$NE, prefix=$MIN)"
        else
            # Check near-prefix: off by 1-2 events at the boundary
            NEAR_MIN=$((MIN - 2))
            [ "$NEAR_MIN" -lt 0 ] && NEAR_MIN=0
            head -n "$NEAR_MIN" "$TMP/ucsim.ev" > "$TMP/u_near.ev"
            head -n "$NEAR_MIN" "$TMP/emu.ev" > "$TMP/e_near.ev"
            if [ "$NEAR_MIN" -gt 0 ] && diff "$TMP/u_near.ev" "$TMP/e_near.ev" > /dev/null 2>&1; then
                PREFIX=$((PREFIX+1))
                echo "  PREFIX $name (ucsim=$NU, emu=$NE, agree on first $NEAR_MIN)"
            else
                DIVERGE=$((DIVERGE+1))
                echo "  DIVERGE $name (ucsim=$NU, emu=$NE)"
            fi
        fi
    fi
done

EXECUTED=$((STRICT + PREFIX + DIVERGE + EMPTY))
echo ""
echo "Results ($TOTAL images):"
echo "  Strict:    $STRICT"
echo "  Prefix:    $PREFIX"
echo "  Diverge:   $DIVERGE"
echo "  Empty:     $EMPTY (loaded, no watched SFR events)"
echo "  Load fail: $LOAD_FAIL"
echo "  Error:     $ERROR"
echo "  Attempted: $TOTAL  Executed: $EXECUTED"

[ $DIVERGE -eq 0 ] && exit 0 || exit 1
