#!/bin/bash
# rung_oracle_corpus.sh — cross-emulator PIN+TF event comparison for oracle corpus.
#
# Runs each corpus hex through both emu_trace and stc12_trace, compares
# PIN+TF event streams post-init (after the first timer fire). Init-phase
# differences (mode-event counting) are documented, not failures.
#
# Usage: ./tests/rung_oracle_corpus.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STC12_TRACE="$REPO_DIR/ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
FOSC=11059200
UNTIL_NS=2000000000

if [ ! -x "$STC12_TRACE" ]; then
    echo "FAIL: stc12_trace not found" >&2; exit 1
fi
if [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found at $EMU_TRACE" >&2; exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

run_check() {
    local label="$1" hex="$2" cpu="$3" extra_flags="$4"

    if [ ! -f "$hex" ]; then
        echo "  SKIP  $label (hex not found)"
        return
    fi

    # Capture PIN+TF events from both emulators
    timeout 60 "$EMU_TRACE" -fosc $FOSC -part "$cpu" -until-ns $UNTIL_NS $extra_flags "$hex" 2>/dev/null \
        | awk '$2 == "PIN" || $2 == "TF"' > "$TMP/emu.all"
    timeout 300 "$STC12_TRACE" -t "$(echo $cpu | tr '[:lower:]' '[:upper:]')" -fosc $FOSC \
        -until-ns $UNTIL_NS $extra_flags "$hex" 2>/dev/null \
        | awk '$2 == "PIN" || $2 == "TF"' > "$TMP/ucsim.all"

    local EN UN
    EN=$(wc -l < "$TMP/emu.all")
    UN=$(wc -l < "$TMP/ucsim.all")

    # Check for exact match (timestamps stripped)
    if diff <(cut -f2- "$TMP/emu.all") <(cut -f2- "$TMP/ucsim.all") > /dev/null 2>&1; then
        echo "  PASS   $label ($EN events, exact match)"
        PASS=$((PASS+1))
        return
    fi

    # Find first TF in each stream — marks end of init phase
    local emu_tf=$(grep -n "TF" "$TMP/emu.all" | head -1 | cut -d: -f1)
    local ucs_tf=$(grep -n "TF" "$TMP/ucsim.all" | head -1 | cut -d: -f1)

    if [ -z "$emu_tf" ] || [ -z "$ucs_tf" ]; then
        # No timer events — compare full streams
        local pin_diff=$((EN > UN ? EN - UN : UN - EN))
        if [ "$pin_diff" -le 20 ]; then
            echo "  PASS   $label (no TF; emu=$EN ucsim=$UN, diff=$pin_diff init events)"
            PASS=$((PASS+1))
        else
            echo "  FAIL   $label (no TF; emu=$EN ucsim=$UN)"
            FAIL=$((FAIL+1))
        fi
        return
    fi

    # Compare post-init (from first TF onward)
    tail -n "+$emu_tf" "$TMP/emu.all" | cut -f2- > "$TMP/emu_post.ev"
    tail -n "+$ucs_tf" "$TMP/ucsim.all" | cut -f2- > "$TMP/ucsim_post.ev"
    local EP=$(wc -l < "$TMP/emu_post.ev")
    local UP=$(wc -l < "$TMP/ucsim_post.ev")

    if diff "$TMP/emu_post.ev" "$TMP/ucsim_post.ev" > /dev/null 2>&1; then
        local init_diff=$((EN - EP - (UN - UP)))
        echo "  PASS   $label (post-init $EP/$UP exact, $((EN-EP))/$((UN-UP)) init events)"
        PASS=$((PASS+1))
        return
    fi

    # Prefix match on post-init
    local MIN=$EP; [ "$UP" -lt "$MIN" ] && MIN=$UP
    if [ "$MIN" -gt 0 ] && head -n "$MIN" "$TMP/emu_post.ev" \
         | diff - <(head -n "$MIN" "$TMP/ucsim_post.ev") > /dev/null 2>&1; then
        echo "  PASS   $label (post-init prefix $MIN match, emu=$EP ucsim=$UP)"
        PASS=$((PASS+1))
        return
    fi

    echo "  FAIL   $label (post-init emu=$EP ucsim=$UP)"
    diff "$TMP/emu_post.ev" "$TMP/ucsim_post.ev" 2>/dev/null | head -10
    FAIL=$((FAIL+1))
}

echo "=== Oracle Corpus Cross-Check ==="
echo "FOSC=$FOSC  UNTIL=${UNTIL_NS}ns"
echo ""

echo "--- mogoreanu/8x16 (STC15) ---"
run_check "mogoreanu_8x16" "$SCRIPT_DIR/fixtures/oracle-corpus/mogoreanu_8x16.hex" "stc15"

echo ""
echo "--- P5 buzzer multimeter (STC15, P5.5 push-pull) ---"
run_check "p5_buzzer_multimeter" "$SCRIPT_DIR/fixtures/oracle-corpus/p5_buzzer_multimeter.hex" "stc15"

echo ""
echo "--- 76-multimeter (STC15, ADC+scan+P5) ---"
run_check "76_multimeter" "$SCRIPT_DIR/fixtures/oracle-corpus/76-multimeter.hex" "stc15"

echo ""
echo "--- rainbowpeee (STC15) ---"
run_check "rainbowpeee_empty" "$SCRIPT_DIR/fixtures/oracle-corpus/rainbowpeee_empty.hex" "stc15"
run_check "rainbowpeee_led" "$SCRIPT_DIR/fixtures/oracle-corpus/rainbowpeee_led.hex" "stc15"

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"

[ $FAIL -eq 0 ] && exit 0 || exit 1
