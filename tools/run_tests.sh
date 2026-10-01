#!/usr/bin/env bash
# run_tests.sh — run the headless GDScript test suite (res://Tests/test_*.gd).
#
# Imports the project first so new `class_name` scripts land in the global
# class cache, then runs Tests/run_all.gd. Because GDScript has no exceptions,
# a runtime error inside a test would otherwise look like a pass — so the log
# is scanned for "SCRIPT ERROR" / "Parse Error" too.
#
# Usage (from the repo root):
#   tools/run_tests.sh [name_filter]     # only run tests whose path contains name_filter
#
# Environment:
#   G47   Godot binary   (default /home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64)
#   OUT   log directory  (default /tmp)
#
# Exits 0 on PASS, 1 on FAIL.

set -uo pipefail

G47="${G47:-/home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64}"
OUT="${OUT:-/tmp}"

if [ ! -x "$G47" ]; then
	echo "FAIL: Godot binary not found or not executable: $G47"
	exit 1
fi
if [ ! -f project.godot ]; then
	echo "FAIL: run this from the repo root (no project.godot here)"
	exit 1
fi

mkdir -p "$OUT"
LOG="$OUT/run_tests.log"

# --- Import ----------------------------------------------------------------
# Registers new class_name scripts; quiet, quick and safe.
"$G47" --headless --path . --import > /dev/null 2>&1

# --- Run -------------------------------------------------------------------
"$G47" --headless --path . -s res://Tests/run_all.gd -- "$@" 2>&1 | tee "$LOG"
RUNNER_RC=${PIPESTATUS[0]}

if grep -q -e 'SCRIPT ERROR' -e 'Parse Error' "$LOG"; then
	echo "FAIL: script errors (see log: $LOG)"
	exit 1
fi
if [ "$RUNNER_RC" -ne 0 ]; then
	echo "FAIL: test runner exited $RUNNER_RC (see log: $LOG)"
	exit 1
fi

echo "PASS (log: $LOG)"
exit 0