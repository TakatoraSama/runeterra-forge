#!/usr/bin/env bash
# lan_selftest.sh — LAN desync self-test.
#
# Runs two headless Godot peers of Main.tscn on localhost (one hosting, one
# joining), lets both auto-end every turn, then compares their [SYNC] log lines.
# Both peers must produce byte-identical [SYNC] output and reach game_end.
#
# Usage (from the repo root):
#   tools/lan_selftest.sh [OUT_DIR]      # OUT_DIR defaults to /tmp/lan_selftest
#
# Exits 0 on PASS, 1 on FAIL.

set -uo pipefail

G47="${G47:-/home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64}"
OUT="${1:-/tmp/lan_selftest}"
mkdir -p "$OUT"

echo "== lan_selftest =="
echo "engine: $G47"
echo "out:    $OUT"

# --- Host -------------------------------------------------------------------
timeout 180 "$G47" --headless --path . res://Scenes/Main.tscn -- \
	--autohost --autoendturn --quit-on-end > "$OUT/host.log" 2>&1 &
HOST_PID=$!

# Give the host time to open the port before the client tries to reach it.
sleep 2

# --- Guest ------------------------------------------------------------------
timeout 180 "$G47" --headless --path . res://Scenes/Main.tscn -- \
	--autojoin=127.0.0.1 --autoendturn --quit-on-end > "$OUT/guest.log" 2>&1 &
GUEST_PID=$!

wait "$HOST_PID";  HOST_RC=$?
wait "$GUEST_PID"; GUEST_RC=$?
echo "host exit=$HOST_RC  guest exit=$GUEST_RC"

# --- Compare [SYNC] output --------------------------------------------------
grep '^\[SYNC\]' "$OUT/host.log"  > "$OUT/host.sync"  2>/dev/null || true
grep '^\[SYNC\]' "$OUT/guest.log" > "$OUT/guest.sync" 2>/dev/null || true

HOST_N=$(wc -l < "$OUT/host.sync")
GUEST_N=$(wc -l < "$OUT/guest.sync")
echo "host [SYNC] lines:  $HOST_N"
echo "guest [SYNC] lines: $GUEST_N"

FAIL=""
[ "$HOST_N" -gt 0 ]  || FAIL="host produced no [SYNC] lines"
[ "$GUEST_N" -gt 0 ] || FAIL="${FAIL:+$FAIL; }guest produced no [SYNC] lines"

if [ "$HOST_N" -gt 0 ] && [ "$GUEST_N" -gt 0 ]; then
	echo "--- diff host.sync guest.sync ---"
	diff "$OUT/host.sync" "$OUT/guest.sync"
	DIFF_RC=$?
	[ "$DIFF_RC" -eq 0 ] || FAIL="${FAIL:+$FAIL; }peers diverged (see diff above)"
fi

grep -q 'phase=game_end' "$OUT/host.sync"  || FAIL="${FAIL:+$FAIL; }host has no phase=game_end line"
grep -q 'phase=game_end' "$OUT/guest.sync" || FAIL="${FAIL:+$FAIL; }guest has no phase=game_end line"

if [ -z "$FAIL" ]; then
	echo "PASS: peers are in sync ($HOST_N identical [SYNC] lines, game_end reached)"
	exit 0
fi

echo "FAIL: $FAIL"
exit 1
