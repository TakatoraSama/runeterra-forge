#!/usr/bin/env bash
# offline_selftest.sh — offline engine-mode self-test.
#
# Runs Main.tscn headless with the Match engine playing both sides: the bot
# (MatchBot as player 0) and the human slot driven by --autoplay. Every time the
# presenter goes idle it re-checks its view model against the engine snapshot
# ([VIEW] ok / [VIEW-MISMATCH] …), so a whole match is played out and checked.
#
# Usage (from the repo root):
#   tools/offline_selftest.sh [SEED ...]     # positional args are SEEDS, not paths;
#                                            # defaults to 1 2 3 42 777 2024
#                                            # logs always go to $OUT: <OUT>/seed_<SEED>.log
#   tools/offline_selftest.sh 1 2            # -> $OUT/seed_1.log, $OUT/seed_2.log
#
# Environment:
#   G47   Godot binary   (default /home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64;
#         override in tools/local.env — see tools/local.env.example)
#   OUT   log directory (default /tmp/offline_selftest) — the only place to put logs;
#         there is no per-run output directory argument
#
# Exits 0 on PASS, 1 on FAIL.

set -uo pipefail

# tools/local.env, GNU timeout on Git Bash, fu_require_godot.
. "$(dirname -- "$0")/_env.sh"

G47="${G47:-/home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64}"
OUT="${OUT:-/tmp/offline_selftest}"
SEEDS=("$@")
if [ "${#SEEDS[@]}" -eq 0 ]; then
	SEEDS=(1 2 3 42 777 2024)
fi

fu_require_godot

if [ ! -f project.godot ]; then
	echo "FAIL: run this from the repo root (no project.godot here)"
	exit 1
fi

mkdir -p "$OUT"

echo "== offline_selftest =="
echo "engine: $G47"
echo "out:    $OUT"
echo "seeds:  ${SEEDS[*]}"

PASS=0
FAIL_COUNT=0

for SEED in "${SEEDS[@]}"; do
	LOG="$OUT/seed_$SEED.log"
	timeout 240 "$G47" --headless --path . res://Scenes/Main.tscn -- \
		--offline --autoplay --verify-view --fast --quit-on-end --seed="$SEED" > "$LOG" 2>&1
	RC=$?

	VIEWS=$(grep -c '^\[VIEW\] ok' "$LOG" 2>/dev/null || true)
	MISMATCH=$(grep -c '^\[VIEW-MISMATCH\]' "$LOG" 2>/dev/null || true)
	ENDED=$(grep -c '^\[MATCH\] game_ended' "$LOG" 2>/dev/null || true)
	ERRORS=$(grep -c -e 'SCRIPT ERROR' -e 'Parse Error' "$LOG" 2>/dev/null || true)
	DECK_LINE=$(grep -m1 -e '^Deck: ' -e '^\[MATCH\] deck' "$LOG" 2>/dev/null || echo "Deck: (no deck line)")
	WINNER=$(grep -m1 '^\[MATCH\] game_ended' "$LOG" 2>/dev/null || echo "")

	PROBLEMS=""
	if [ "$ERRORS" -gt 0 ]; then PROBLEMS="${PROBLEMS} script-errors($ERRORS),"; fi
	if [ "$MISMATCH" -gt 0 ]; then PROBLEMS="${PROBLEMS} view-mismatch($MISMATCH),"; fi
	if [ "$ENDED" -lt 1 ]; then PROBLEMS="${PROBLEMS} no-game_ended,"; fi
	if [ "$RC" -eq 124 ]; then
		PROBLEMS="${PROBLEMS} timeout,"
	elif [ "$RC" -ne 0 ]; then
		PROBLEMS="${PROBLEMS} exit=$RC,"
	fi

	if [ -z "$PROBLEMS" ]; then
		echo "seed $SEED: PASS  views=$VIEWS  ${DECK_LINE}  ${WINNER}  (log: $LOG)"
		PASS=$((PASS + 1))
	else
		echo "seed $SEED: FAIL  ${PROBLEMS%,}  views=$VIEWS  ${DECK_LINE}  (log: $LOG)"
		grep -m5 -e 'SCRIPT ERROR' -e 'Parse Error' -e '^\[VIEW-MISMATCH\]' "$LOG" | sed 's/^/    /'
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
done

echo "---"
echo "seeds: $((PASS + FAIL_COUNT))  pass: $PASS  fail: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
	echo "FAIL: $FAIL_COUNT of $((PASS + FAIL_COUNT)) seeds failed (logs in $OUT)"
	exit 1
fi

echo "PASS: all $PASS seeds played to game end with a matching view (logs in $OUT)"
exit 0