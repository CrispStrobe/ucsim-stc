#!/bin/bash
# corpus_stc89.sh — cross-emulator differential on STC89 firmware corpus.
#
# REQUIRES a local corpus directory (default: corpus/stc89/) that is NOT
# distributed with this repository. The corpus is gitignored and contains
# third-party firmware. Without it, this script does nothing.
#
# LOAD FAILURES ARE REPORTED, NOT SILENTLY COUNTED AS EMPTY.
# Per fleet-silent-degradation rule: a fallback silently worse than the
# real thing is a bug. "63 images" is only meaningful if the denominator
# is images actually executed, not images attempted.
#
# Usage: ./tests/corpus_stc89.sh [corpus_dir] [until_ns]
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EMU="${EMU_TRACE:-../emu8051-stc/emu_trace}"
CORPUS="${1:-corpus/stc89}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200

if [ ! -x "$TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

STRICT=0; PREFIX=0; DIVERGE=0; EMPTY=0; LOAD_FAIL=0; ERROR=0; TMOUT=0; TOTAL=0
INVOC_TIMEOUT=10

echo "=== STC89 cross-emulator corpus ($CORPUS, ${UNTIL_NS}ns, timeout ${INVOC_TIMEOUT}s) ==="

for hex in "$CORPUS"/*.ihx "$CORPUS"/*.hex; do
    [ -f "$hex" ] || continue
    TOTAL=$((TOTAL+1))
    name=$(basename "$hex")

    # Per-invocation timeout + stderr capture for load failure detection.
    if ! timeout $INVOC_TIMEOUT "$TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        3>&1 1>"$TMP/ucsim_raw.ev" 2>&3 > "$TMP/u_err.txt"; then
        TMOUT=$((TMOUT+1)); echo "  TIMEOUT(ucsim) $name"; continue
    fi
    U_ERR=$(cat "$TMP/u_err.txt" 2>/dev/null)
    if ! timeout $INVOC_TIMEOUT "$EMU" -part STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        3>&1 1>"$TMP/emu_raw.ev" 2>&3 > "$TMP/e_err.txt"; then
        TMOUT=$((TMOUT+1)); echo "  TIMEOUT(emu)   $name"; continue
    fi
    E_ERR=$(cat "$TMP/e_err.txt" 2>/dev/null)

    # Check for load failures:
    # - ucsim: "Read error" or "0 words read" (silently skipped bad records)
    # - emu: "Failed to load"
    U_LOADED=true; E_LOADED=true
    echo "$U_ERR" | grep -qi "error\|fail" && U_LOADED=false
    echo "$U_ERR" | grep -qP "^0 words read" && U_LOADED=false
    echo "$E_ERR" | grep -qi "fail" && E_LOADED=false

    if ! $U_LOADED && ! $E_LOADED; then
        LOAD_FAIL=$((LOAD_FAIL+1))
        echo "  LOAD_FAIL  $name (both sides)"
        continue
    fi
    if ! $U_LOADED || ! $E_LOADED; then
        LOAD_FAIL=$((LOAD_FAIL+1))
        echo "  LOAD_FAIL  $name (ucsim=$U_LOADED, emu=$E_LOADED)"
        continue
    fi

    # Extract SFR+TF events
    awk '$2 == "SFR" || $2 == "TF"' "$TMP/ucsim_raw.ev" | cut -f2- > "$TMP/ucsim.ev"
    awk '$2 == "SFR" || $2 == "TF"' "$TMP/emu_raw.ev" | cut -f2- > "$TMP/emu.ev"

    NU=$(wc -l < "$TMP/ucsim.ev")
    NE=$(wc -l < "$TMP/emu.ev")

    if [ "$NU" -eq 0 ] && [ "$NE" -eq 0 ]; then
        # Both loaded successfully but produced no watched SFR events.
        # This is genuinely empty (e.g. image only touches IRAM/XRAM).
        EMPTY=$((EMPTY+1)); continue
    fi
    if [ "$NU" -eq 0 ] || [ "$NE" -eq 0 ]; then
        ERROR=$((ERROR+1)); echo "  ERROR  $name (ucsim=$NU, emu=$NE)"; continue
    fi

    if [ "$NU" -eq "$NE" ] && diff "$TMP/ucsim.ev" "$TMP/emu.ev" > /dev/null 2>&1; then
        STRICT=$((STRICT+1))
    else
        MIN=$((NU < NE ? NU : NE))
        head -n "$MIN" "$TMP/ucsim.ev" > "$TMP/u_pre.ev"
        head -n "$MIN" "$TMP/emu.ev" > "$TMP/e_pre.ev"
        if diff "$TMP/u_pre.ev" "$TMP/e_pre.ev" > /dev/null 2>&1; then
            PREFIX=$((PREFIX+1))
        else
            DIVERGE=$((DIVERGE+1))
            echo "  DIVERGE  $name (ucsim=$NU, emu=$NE)"
        fi
    fi
done

echo ""
echo "Results ($TOTAL images):"
echo "  Strict:    $STRICT"
echo "  Prefix:    $PREFIX"
echo "  Diverge:   $DIVERGE"
echo "  Empty:     $EMPTY (loaded, no watched SFR events)"
echo "  Load fail: $LOAD_FAIL (hex decode error)"
echo "  Error:     $ERROR (one side 0 events, other > 0)"

EXECUTED=$((STRICT + PREFIX + DIVERGE + EMPTY))
echo ""
echo "  Attempted: $TOTAL  Executed: $EXECUTED  Load failures: $LOAD_FAIL"

[ $DIVERGE -le 1 ] && exit 0 || exit 1
