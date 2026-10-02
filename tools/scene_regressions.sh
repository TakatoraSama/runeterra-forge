#!/usr/bin/env bash
# scene_regressions.sh — scene-level regression tests (Tests/scene/regress_*.gd).
#
# The headless GDScript suite in tools/run_tests.sh has no scene tree: it exercises
# MatchState / MatchRules / CardState as plain objects. These three scripts do need a
# real SceneTree — they instantiate Scenes/Main.tscn, drive the real MatchController,
# MatchPresenter and CardManager, and then ask the real physics server what a click at
# a card's position would hit. That is the only way to test the two presenter bugs
# these cover, because both of them live between the view model and the input path
# (card_slot_is_in, Board.cards_by_zone, the Area2D collision shape) and none of that
# exists without the scene.
#
# They live in Tests/scene/ and are named regress_*.gd, so Tests/run_all.gd — which
# collects res://Tests/test_*.gd — does not pick them up. Run them from here.
#
# Usage (from the repo root):
#   tools/scene_regressions.sh [name]     # only scripts whose path contains name
#
# Environment:
#   G47   Godot binary   (default /home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64;
#         override in tools/local.env — see tools/local.env.example)
#   OUT   log directory  (default /tmp/scene_regressions) — <script>.log per script
#
# A script passes only if it exits 0, printed at least one [PASS], printed no [FAIL],
# and logged no SCRIPT ERROR / Parse Error. Exits 0 only when every script passes.

set -uo pipefail

# tools/local.env, GNU timeout on Git Bash, fu_require_godot.
. "$(dirname -- "$0")/_env.sh"

G47="${G47:-/home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64}"
OUT="${OUT:-/tmp/scene_regressions}"
FILTER="${1:-}"

fu_require_godot

if [ ! -f project.godot ]; then
	echo "FAIL: run this from the repo root (no project.godot here)"
	exit 1
fi

mkdir -p "$OUT"

SCRIPTS=()
for path in Tests/scene/regress_*.gd; do
	if [ -z "$FILTER" ] || [[ "$path" == *"$FILTER"* ]]; then
		SCRIPTS+=("$path")
	fi
done

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
	echo "FAIL: no Tests/scene/regress_*.gd scripts found (filter: '${FILTER}')"
	exit 1
fi

echo "== scene_regressions =="
echo "engine: $G47"
echo "out:    $OUT"
echo "scripts: ${SCRIPTS[*]}"

PASS=0
FAIL_COUNT=0

for SCRIPT in "${SCRIPTS[@]}"; do
	NAME=$(basename "$SCRIPT" .gd)
	LOG="$OUT/$NAME.log"

	# --fast makes Engine.time_scale 8, which is what keeps the card animations inside
	# the timeout; these scripts still assert on settled positions, never mid-tween.
	timeout 180 "$G47" --headless --path . -s "res://$SCRIPT" -- --fast > "$LOG" 2>&1
	RC=$?

	PASSES=$(grep -c '^\[PASS\]' "$LOG" 2>/dev/null || true)
	FAILS=$(grep -c '^\[FAIL\]' "$LOG" 2>/dev/null || true)
	ERRORS=$(grep -c -e 'SCRIPT ERROR' -e 'Parse Error' "$LOG" 2>/dev/null || true)

	PROBLEMS=""
	if [ "$RC" -eq 124 ]; then PROBLEMS="${PROBLEMS} timeout,";
	elif [ "$RC" -ne 0 ]; then PROBLEMS="${PROBLEMS} exit=$RC,"; fi
	if [ "$PASSES" -lt 1 ]; then PROBLEMS="${PROBLEMS} no-pass-assertions,"; fi
	if [ "$FAILS" -gt 0 ]; then PROBLEMS="${PROBLEMS} failed-assertions($FAILS),"; fi
	if [ "$ERRORS" -gt 0 ]; then PROBLEMS="${PROBLEMS} script-errors($ERRORS),"; fi

	if [ -z "$PROBLEMS" ]; then
		echo "$NAME: PASS  assertions=$PASSES  (log: $LOG)"
		PASS=$((PASS + 1))
	else
		echo "$NAME: FAIL  ${PROBLEMS%,}  assertions=$PASSES  (log: $LOG)"
		grep -m5 -e '^\[FAIL\]' -e 'SCRIPT ERROR' -e 'Parse Error' "$LOG" | sed 's/^/    /'
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
done

echo "---"
echo "scripts: $((PASS + FAIL_COUNT))  pass: $PASS  fail: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
	echo "FAIL: $FAIL_COUNT of $((PASS + FAIL_COUNT)) scene regressions failed (logs in $OUT)"
	exit 1
fi

echo "PASS: all $PASS scene regressions passed (logs in $OUT)"
exit 0