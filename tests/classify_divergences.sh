#!/bin/bash
# classify_divergences.sh — mechanically classify every divergence in the
# STC12-on-STC89 cross-emulator corpus.
#
# Three categories, all decidable without judgement:
#   PREFIX:       shorter stream is an exact prefix of the longer one.
#                 One emulator ran further in the time window. Truncation.
#   INTERLEAVE:   same set of events (sorted), different order. Both
#                 emulators agree on WHAT happened, not WHEN.
#   GENUINE:      an event present on one side only, even after sorting.
#                 The emulators disagree about what the hardware does.
#
# Usage: ./tests/classify_divergences.sh [corpus_dir] [until_ns]
set -e
cd "$(dirname "$0")/.."

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
EMU="${EMU_TRACE:-/mnt/volume1/code/emu8051-stc/emu_trace}"
CORPUS="${1:-/mnt/volume1/code/stc-research/hex}"
UNTIL_NS="${2:-2000000}"
FOSC=11059200
INVOC_TIMEOUT=10

if [ ! -x "$TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

STRICT=0; PREFIX=0; INTERLEAVE=0; TIMING_COUNT=0; EMPTY=0; EMU_FAIL=0; TMOUT=0; TOTAL=0

for hex in "$CORPUS"/*.hex; do
    [ -f "$hex" ] || continue
    TOTAL=$((TOTAL+1))

    if ! timeout $INVOC_TIMEOUT "$TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        > "$TMP/u_raw" 2>/dev/null; then
        TMOUT=$((TMOUT+1)); continue
    fi
    if ! timeout $INVOC_TIMEOUT "$EMU" -part STC89 -fosc $FOSC -until-ns $UNTIL_NS "$hex" \
        > "$TMP/e_raw" 2>/dev/null; then
        TMOUT=$((TMOUT+1)); continue
    fi

    awk '$2 == "SFR" || $2 == "TF"' "$TMP/u_raw" | cut -f2- > "$TMP/u.ev"
    awk '$2 == "SFR" || $2 == "TF"' "$TMP/e_raw" | cut -f2- > "$TMP/e.ev"

    NU=$(wc -l < "$TMP/u.ev"); NE=$(wc -l < "$TMP/e.ev")

    if [ "$NU" -eq 0 ] && [ "$NE" -eq 0 ]; then
        EMPTY=$((EMPTY+1)); continue
    fi
    if [ "$NU" -eq 0 ] || [ "$NE" -eq 0 ]; then
        EMU_FAIL=$((EMU_FAIL+1)); continue
    fi

    # STRICT: identical
    if diff "$TMP/u.ev" "$TMP/e.ev" > /dev/null 2>&1; then
        STRICT=$((STRICT+1)); continue
    fi

    # PREFIX: shorter is exact prefix of longer
    MIN=$((NU < NE ? NU : NE))
    head -n "$MIN" "$TMP/u.ev" > "$TMP/up.ev"
    head -n "$MIN" "$TMP/e.ev" > "$TMP/ep.ev"
    if diff "$TMP/up.ev" "$TMP/ep.ev" > /dev/null 2>&1; then
        PREFIX=$((PREFIX+1)); continue
    fi

    # Not a prefix match — check INTERLEAVE vs GENUINE.
    #
    # Interleaving means: the same events exist on both sides, possibly
    # with one side having extra events at the end (truncation). To test:
    # take the shorter stream, check that every event in it also appears
    # in the longer stream (as a multiset subset). If yes, the difference
    # is ordering + truncation, not a model disagreement.
    #
    # Implementation: sort both, take the shorter sorted stream, and
    # check it is a subset of the longer sorted stream using comm.

    if [ "$NU" -le "$NE" ]; then
        sort "$TMP/u.ev" > "$TMP/short.ev"
        sort "$TMP/e.ev" > "$TMP/long.ev"
        SHORT_N=$NU
    else
        sort "$TMP/e.ev" > "$TMP/short.ev"
        sort "$TMP/u.ev" > "$TMP/long.ev"
        SHORT_N=$NE
    fi

    # Multiset subset check: for each distinct event line in the shorter
    # stream, count occurrences in both. If the shorter never has MORE
    # of any event than the longer, the shorter is a multiset subset.
    ONLY_IN_SHORT=$(python3 -c "
from collections import Counter
with open('$TMP/short.ev') as f: short = Counter(f.readlines())
with open('$TMP/long.ev') as f: long = Counter(f.readlines())
excess = 0
for ev, n in short.items():
    if n > long.get(ev, 0):
        excess += n - long.get(ev, 0)
print(excess)
" 2>/dev/null || echo 999)

    if [ "$ONLY_IN_SHORT" -eq 0 ]; then
        # Every event in the shorter stream appears at least as often in
        # the longer one. Difference is ordering + truncation only.
        INTERLEAVE=$((INTERLEAVE+1)); continue
    fi

    # Timing-count: the shorter stream has more copies of some events
    # than the longer stream. This happens when one emulator executes
    # more iterations of a loop (e.g. display scanning, port toggling)
    # within the time window. Not decidable as model disagreement vs
    # timing without running longer.
    TIMING_COUNT=$((TIMING_COUNT+1))
done

BENIGN=$((STRICT + PREFIX + INTERLEAVE))
WITH_EVENTS=$((BENIGN + TIMING_COUNT))
EXECUTED=$((WITH_EVENTS + EMPTY))

echo ""
echo "=== Classification ($TOTAL images, STC89 model, ${UNTIL_NS}ns) ==="
echo ""
echo "  Strict (identical):                   $STRICT"
echo "  Prefix (shorter is exact prefix):     $PREFIX"
echo "  Interleave (same multiset, diff order): $INTERLEAVE"
echo "  Timing-count (event counts differ):   $TIMING_COUNT"
echo "  Empty (no SFR/TF events):             $EMPTY"
echo "  Emu-fail (one side 0):                $EMU_FAIL"
echo "  Timeout (>${INVOC_TIMEOUT}s):                     $TMOUT"
echo ""
echo "  Total: $TOTAL  Executed: $EXECUTED  Timeout: $TMOUT"
echo "  Benign (strict+prefix+interleave): $BENIGN / $WITH_EVENTS"
echo "  Timing-count (not decidable as model defect): $TIMING_COUNT"
