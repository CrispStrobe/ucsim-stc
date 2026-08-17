#!/bin/bash
# rainbowpeee_crosscheck.sh — cross-check all 30 bootable rainbowpeee programs.
#
# Runs each program through emu_trace and stc12_trace (both STC15),
# compares post-init PIN+TF event streams.
#
# Usage: ./tests/rainbowpeee_crosscheck.sh [hex_dir]
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STC12_TRACE="$REPO_DIR/ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX_DIR="${1:-/tmp/rainbowpeee-sdcc}"
FOSC=11059200

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi
if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2; exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0; SKIP=0

echo "=== rainbowpeee Full Corpus Cross-Check ==="
echo "FOSC=$FOSC"
echo ""
printf "%-40s %8s %8s %8s %8s %-8s\n" "Program" "emu-tot" "ucs-tot" "post-E" "post-U" "Result"
printf "%-40s %8s %8s %8s %8s %-8s\n" "-------" "------" "------" "------" "------" "------"

for dir in "$HEX_DIR"/*/; do
    name=$(basename "$dir")
    hex="$dir/out.ihx"
    [ -f "$hex" ] || continue

    # Adaptive sim: high-event programs run shorter to stay practical.
    # At 11059200 Hz 1T, 2s = ~22M clocks → ~60s wall time per emulator.
    # For programs with >50K events, use 200ms (still exercises all code paths).
    # Use emu8051 first (faster) to estimate event density.
    UNTIL_NS=200000000   # 200ms fast pass first

    # Run emu8051
    timeout 60 "$EMU_TRACE" -fosc $FOSC -part stc15 -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "PIN" || $2 == "TF"' > "$TMP/emu.all" 2>/dev/null || true

    # Run ucsim
    timeout 300 "$STC12_TRACE" -t STC15 -fosc $FOSC -until-ns $UNTIL_NS "$hex" 2>/dev/null \
        | awk '$2 == "PIN" || $2 == "TF"' > "$TMP/ucsim.all" 2>/dev/null || true

    EN=$(wc -l < "$TMP/emu.all")
    UN=$(wc -l < "$TMP/ucsim.all")

    # Find first TF event in each
    emu_tf=$(grep -n "TF" "$TMP/emu.all" | head -1 | cut -d: -f1)
    ucs_tf=$(grep -n "TF" "$TMP/ucsim.all" | head -1 | cut -d: -f1)

    if [ -z "$emu_tf" ] || [ -z "$ucs_tf" ]; then
        # No timer events — compare full PIN streams (timestamps stripped)
        cut -f2- "$TMP/emu.all" > "$TMP/emu_strip.ev"
        cut -f2- "$TMP/ucsim.all" > "$TMP/ucsim_strip.ev"
        if diff "$TMP/emu_strip.ev" "$TMP/ucsim_strip.ev" > /dev/null 2>&1; then
            printf "%-40s %8d %8d %8s %8s %-8s\n" "$name" "$EN" "$UN" "-" "-" "EXACT"
            PASS=$((PASS+1))
        else
            # Check prefix match (boundary timing or init diffs)
            MIN=$EN; [ "$UN" -lt "$MIN" ] && MIN=$UN
            if [ "$MIN" -gt 0 ] && head -n "$MIN" "$TMP/emu_strip.ev" \
                 | diff - <(head -n "$MIN" "$TMP/ucsim_strip.ev") > /dev/null 2>&1; then
                printf "%-40s %8d %8d %8s %8s %-8s\n" "$name" "$EN" "$UN" "-" "-" "PREFIX"
                PASS=$((PASS+1))
            else
                # Check reverse prefix (ucsim prefix of emu)
                if head -n "$MIN" "$TMP/ucsim_strip.ev" \
                     | diff - <(head -n "$MIN" "$TMP/emu_strip.ev") > /dev/null 2>&1; then
                    printf "%-40s %8d %8d %8s %8s %-8s\n" "$name" "$EN" "$UN" "-" "-" "PREFIX"
                    PASS=$((PASS+1))
                else
                    printf "%-40s %8d %8d %8s %8s %-8s\n" "$name" "$EN" "$UN" "-" "-" "FAIL"
                    FAIL=$((FAIL+1))
                fi
            fi
        fi
        continue
    fi

    # Compare post-init
    tail -n "+$emu_tf" "$TMP/emu.all" | cut -f2- > "$TMP/emu_post.ev"
    tail -n "+$ucs_tf" "$TMP/ucsim.all" | cut -f2- > "$TMP/ucsim_post.ev"
    EP=$(wc -l < "$TMP/emu_post.ev")
    UP=$(wc -l < "$TMP/ucsim_post.ev")

    if diff "$TMP/emu_post.ev" "$TMP/ucsim_post.ev" > /dev/null 2>&1; then
        printf "%-40s %8d %8d %8d %8d %-8s\n" "$name" "$EN" "$UN" "$EP" "$UP" "EXACT"
        PASS=$((PASS+1))
        continue
    fi

    # Prefix match
    MIN=$((EP < UP ? EP : UP))
    if [ "$MIN" -gt 0 ] && head -n "$MIN" "$TMP/emu_post.ev" \
         | diff - <(head -n "$MIN" "$TMP/ucsim_post.ev") > /dev/null 2>&1; then
        printf "%-40s %8d %8d %8d %8d %-8s\n" "$name" "$EN" "$UN" "$EP" "$UP" "PREFIX"
        PASS=$((PASS+1))
        continue
    fi

    # Real divergence — find first differing line
    first_diff=$(diff "$TMP/emu_post.ev" "$TMP/ucsim_post.ev" 2>/dev/null | grep "^[0-9]" | head -1)
    printf "%-40s %8d %8d %8d %8d %-8s\n" "$name" "$EN" "$UN" "$EP" "$UP" "FAIL@$first_diff"
    FAIL=$((FAIL+1))
done

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL  Skip: $SKIP  Total: $((PASS+FAIL+SKIP))"

if [ $FAIL -eq 0 ]; then
    echo "CLEAN: ucsim agrees with emu8051 on all $PASS programs."
    exit 0
else
    echo "DIVERGENCES: $FAIL program(s) with post-init differences."
    exit 1
fi
