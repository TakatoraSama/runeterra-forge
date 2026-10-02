#!/usr/bin/env bash
# lan_selftest.sh — LAN self-test for the M5a host-authoritative session.
#
# Runs two headless Godot peers of Main.tscn on localhost (one hosting, one
# joining), each with the new engine: the host owns MatchRules, the guest sends
# intents. Both peers autoplay with MatchBot and re-check their view against the
# host's snapshot every time the presenter goes idle ([VIEW] ok / [VIEW-MISMATCH]).
#
# It binds the LAN port (9999) — run it alone, not concurrently with another peer.
#
# Usage (from the repo root):
#   tools/lan_selftest.sh [SEED ...]     # positional args are SEEDS, not paths;
#                                        # defaults to 1 2 3 42
#                                        # logs always go to $OUT: seed_<SEED>_{host,guest}.log
#   tools/lan_selftest.sh 1 2            # -> only those two seeds
#
# Environment:
#   G47   Godot binary   (default /home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64;
#         override in tools/local.env — see tools/local.env.example)
#   OUT   log directory (default /tmp/lan_selftest)
#   PLAIN_SEEDS  seeds for the PLAIN-guest run (default "5"; empty to skip it)
#
# The plain-guest run is the GUI join path: the guest has NO --verify-view and NO
# --autoplay, so it does not ask for per-batch snapshots (want_snapshots = false) and
# builds its view from the opening snapshot alone. It only ends its turns (--autopass);
# the host autoplays. Its logs are plain_<SEED>_{host,guest}.log, and it PASSES when:
#   - both peers exit 0, no SCRIPT ERROR / Parse Error in either log
#   - the guest printed "[VIEW] built ... card_manager=true" (its view was set up)
#   - the guest never had to hold events back ("[NET] events before snapshot")
#   - the host has >= 1 [VIEW] ok and 0 [VIEW-MISMATCH]; 0 [LEAK]; 0 ack timeouts
#   - each side has exactly one [MATCH] game_ended, with the SAME winner
#   - both directions of the wire match, as for the normal seeds
#   - >= 1 [PLAY] for the host (the guest only passes)
#
# A seed PASSES only when every one of these holds:
#   - both peers exit 0
#   - no SCRIPT ERROR and no Parse Error in either log
#   - each side has >= 1 [VIEW] ok and 0 [VIEW-MISMATCH]
#   - each side has exactly one [MATCH] game_ended, with the SAME winner
#   - the guest's [NET-IN] list equals the host's [NET-OUT] list, and the guest's
#     [NET-OUT] list equals the host's [NET-IN] list, both non-empty
#   - 0 [LEAK] lines (the host ran MatchLeakCheck over every guest batch)
#   - 0 [NET] ack timeout lines (no viewer ever missed its presentation_done)
#   - >= 1 [PLAY] line for EACH player (both sides really played cards)
#
# Exits 0 when every seed passes, 1 otherwise.

set -uo pipefail

# tools/local.env, GNU timeout on Git Bash, fu_require_godot.
. "$(dirname -- "$0")/_env.sh"

G47="${G47:-/home/dev/Project/self/Godot_v4.7.2-stable_linux.x86_64}"
OUT="${OUT:-/tmp/lan_selftest}"
SEEDS=("$@")
if [ "${#SEEDS[@]}" -eq 0 ]; then
	SEEDS=(1 2 3 42)
fi
# shellcheck disable=SC2206
PLAIN_SEEDS=(${PLAIN_SEEDS-5})

# Seconds one seed's pair of peers may run before `timeout` gives up.
PEER_TIMEOUT=240

# Seconds between seeds, so the previous pair's port is really released before the
# next host calls create_server(). ENet has no SO_REUSEADDR here, so a lingering
# bind shows up as a failed host and a confusing cascade of join retries.
SEED_GAP=1

fu_require_godot

if [ ! -f project.godot ]; then
	echo "FAIL: run this from the repo root (no project.godot here)"
	exit 1
fi

mkdir -p "$OUT"

echo "== lan_selftest =="
echo "engine: $G47"
echo "out:    $OUT"
echo "seeds:  ${SEEDS[*]}"
echo "plain:  ${PLAIN_SEEDS[*]:-<none>}"

PASS=0
FAIL_COUNT=0
FIRST_SEED=1

# Runs one seed's two peers and checks every criterion. Echoes one summary line and
# leaves the verdict in $FAIL (empty means the seed passed).
run_seed() {
	SEED="$1"
	# "normal": both peers autoplay and verify. "plain": the guest joins like the GUI
	# does (no snapshots requested) and only passes its turns.
	MODE="${2:-normal}"
	if [ "$MODE" = "plain" ]; then
		TAG="plain_${SEED}"
		GUEST_FLAGS=(--autopass)
	else
		TAG="seed_${SEED}"
		GUEST_FLAGS=(--autoplay --verify-view)
	fi
	HOST_LOG="$OUT/${TAG}_host.log"
	GUEST_LOG="$OUT/${TAG}_guest.log"
	rm -f "$HOST_LOG" "$GUEST_LOG"

	timeout "$PEER_TIMEOUT" "$G47" --headless --path . res://Scenes/Main.tscn -- \
		--autohost --autoplay --verify-view --fast --quit-on-end --seed="$SEED" > "$HOST_LOG" 2>&1 &
	HOST_PID=$!

	# The host needs a moment to bind the port before the guest connects to it.
	sleep 2

	timeout "$PEER_TIMEOUT" "$G47" --headless --path . res://Scenes/Main.tscn -- \
		--autojoin=127.0.0.1 "${GUEST_FLAGS[@]}" --fast --quit-on-end --seed="$SEED" > "$GUEST_LOG" 2>&1 &
	GUEST_PID=$!

	wait "$HOST_PID";  HOST_RC=$?
	wait "$GUEST_PID"; GUEST_RC=$?

	# --- extract the evidence -----------------------------------------------------
	# Only the marker lines, so a diff is about the wire and not about timestamps.
	# The raw lines are "[NET-OUT 0] events 3 [...]" on the sending side and
	# "[NET-IN 0] events 3 [...]" on the receiving one, so the leading tag AND its
	# per-direction counter are stripped before comparing: what must be identical is
	# the payload, not the local label. What is left is "<kind> <seq> <JSON>".
	net_lines() {
		grep -E "^\[$1 " "$2" 2>/dev/null \
			| sed -e "s/^\[$1 [0-9-]*\] //" || true
	}
	net_lines NET-OUT "$HOST_LOG"  > "$OUT/${TAG}_host.netout"
	net_lines NET-IN  "$HOST_LOG"  > "$OUT/${TAG}_host.netin"
	net_lines NET-OUT "$GUEST_LOG" > "$OUT/${TAG}_guest.netout"
	net_lines NET-IN  "$GUEST_LOG" > "$OUT/${TAG}_guest.netin"

	HOST_OUT_N=$(wc -l < "$OUT/${TAG}_host.netout")
	HOST_IN_N=$(wc -l < "$OUT/${TAG}_host.netin")
	GUEST_OUT_N=$(wc -l < "$OUT/${TAG}_guest.netout")
	GUEST_IN_N=$(wc -l < "$OUT/${TAG}_guest.netin")

	HOST_VIEWS=$(grep -c '^\[VIEW\] ok' "$HOST_LOG" 2>/dev/null || true)
	GUEST_VIEWS=$(grep -c '^\[VIEW\] ok' "$GUEST_LOG" 2>/dev/null || true)
	HOST_MM=$(grep -c '^\[VIEW-MISMATCH\]' "$HOST_LOG" 2>/dev/null || true)
	GUEST_MM=$(grep -c '^\[VIEW-MISMATCH\]' "$GUEST_LOG" 2>/dev/null || true)
	HOST_ENDED=$(grep -c '^\[MATCH\] game_ended' "$HOST_LOG" 2>/dev/null || true)
	GUEST_ENDED=$(grep -c '^\[MATCH\] game_ended' "$GUEST_LOG" 2>/dev/null || true)
	HOST_WINNER=$(grep -m1 -o 'winner=-\?[0-9]*' "$HOST_LOG" 2>/dev/null || echo "")
	GUEST_WINNER=$(grep -m1 -o 'winner=-\?[0-9]*' "$GUEST_LOG" 2>/dev/null || echo "")
	LEAKS=$(grep -ch '^\[LEAK\]' "$HOST_LOG" "$GUEST_LOG" 2>/dev/null | awk '{s+=$1} END {print s+0}')
	ACK_TIMEOUTS=$(grep -ch '^\[NET\] ack timeout' "$HOST_LOG" "$GUEST_LOG" 2>/dev/null | awk '{s+=$1} END {print s+0}')
	HOST_PLAYS=$(grep -c '^\[PLAY\] player=0' "$HOST_LOG" 2>/dev/null || true)
	GUEST_PLAYS=$(grep -c '^\[PLAY\] player=1' "$HOST_LOG" 2>/dev/null || true)
	ERRORS=$(grep -ch -e 'SCRIPT ERROR' -e 'Parse Error' "$HOST_LOG" "$GUEST_LOG" 2>/dev/null | awk '{s+=$1} END {print s+0}')

	# --- the criteria -------------------------------------------------------------
	PROBLEMS=""

	if [ "$HOST_RC" -eq 124 ] || [ "$GUEST_RC" -eq 124 ]; then
		PROBLEMS="${PROBLEMS} timeout(host=$HOST_RC guest=$GUEST_RC),"
	elif [ "$HOST_RC" -ne 0 ] || [ "$GUEST_RC" -ne 0 ]; then
		PROBLEMS="${PROBLEMS} exit(host=$HOST_RC guest=$GUEST_RC),"
	fi
	[ "$ERRORS" -eq 0 ]   || PROBLEMS="${PROBLEMS} script-errors($ERRORS),"

	[ "$HOST_VIEWS" -gt 0 ]  || PROBLEMS="${PROBLEMS} host-no-VIEW-ok,"
	if [ "$MODE" = "plain" ]; then
		# A plain guest never verifies, so a never-built view could only show up as a
		# crash or a hang; this line is what proves setup() really ran.
		grep -q '^\[VIEW\] built player=1 card_manager=true' "$GUEST_LOG" 2>/dev/null \
			|| PROBLEMS="${PROBLEMS} guest-view-never-built,"
		EARLY=$(grep -c '^\[NET\] events before snapshot' "$GUEST_LOG" 2>/dev/null || true)
		[ "$EARLY" -eq 0 ] || PROBLEMS="${PROBLEMS} guest-events-before-snapshot($EARLY),"
	else
		[ "$GUEST_VIEWS" -gt 0 ] || PROBLEMS="${PROBLEMS} guest-no-VIEW-ok,"
	fi
	[ "$HOST_MM" -eq 0 ]      || PROBLEMS="${PROBLEMS} host-view-mismatch($HOST_MM),"
	[ "$GUEST_MM" -eq 0 ]     || PROBLEMS="${PROBLEMS} guest-view-mismatch($GUEST_MM),"

	[ "$HOST_ENDED" -eq 1 ]   || PROBLEMS="${PROBLEMS} host game_ended x$HOST_ENDED,"
	[ "$GUEST_ENDED" -eq 1 ]  || PROBLEMS="${PROBLEMS} guest game_ended x$GUEST_ENDED,"
	[ "$HOST_WINNER" = "$GUEST_WINNER" ] \
		|| PROBLEMS="${PROBLEMS} winner-mismatch(host='$HOST_WINNER' guest='$GUEST_WINNER'),"

	# Both directions of the wire must match exactly, and neither may be empty: an
	# empty list would "match" trivially while proving nothing was ever exchanged.
	if [ "$HOST_OUT_N" -gt 0 ] && cmp -s "$OUT/${TAG}_host.netout" "$OUT/${TAG}_guest.netin"; then
		NET_FWD=ok
	else
		NET_FWD="mismatch(host-out=$HOST_OUT_N guest-in=$GUEST_IN_N)"
	fi
	if [ "$GUEST_OUT_N" -gt 0 ] && cmp -s "$OUT/${TAG}_guest.netout" "$OUT/${TAG}_host.netin"; then
		NET_BACK=ok
	else
		NET_BACK="mismatch(guest-out=$GUEST_OUT_N host-in=$HOST_IN_N)"
	fi
	[ "$NET_FWD" = "ok" ]  || PROBLEMS="${PROBLEMS} net host->guest $NET_FWD,"
	[ "$NET_BACK" = "ok" ] || PROBLEMS="${PROBLEMS} net guest->host $NET_BACK,"

	[ "$LEAKS" -eq 0 ]        || PROBLEMS="${PROBLEMS} leaks($LEAKS),"
	[ "$ACK_TIMEOUTS" -eq 0 ] || PROBLEMS="${PROBLEMS} ack-timeouts($ACK_TIMEOUTS),"
	[ "$HOST_PLAYS" -gt 0 ]   || PROBLEMS="${PROBLEMS} no-host-plays,"
	if [ "$MODE" != "plain" ]; then
		[ "$GUEST_PLAYS" -gt 0 ]  || PROBLEMS="${PROBLEMS} no-guest-plays,"
	fi

	# --- report -------------------------------------------------------------------
	if [ -z "$PROBLEMS" ]; then
		echo "$TAG: PASS  views=$HOST_VIEWS/$GUEST_VIEWS  $HOST_WINNER  net=$HOST_OUT_N/$GUEST_OUT_N msgs  plays=p0:$HOST_PLAYS p1:$GUEST_PLAYS  (logs: $OUT/${TAG}_*.log)"
		FAIL=""
	else
		echo "$TAG: FAIL  ${PROBLEMS%,}  (logs: $OUT/${TAG}_*.log)"
		grep -m3 -e 'SCRIPT ERROR' -e 'Parse Error' -e '^\[VIEW-MISMATCH\]' -e '^\[LEAK\]' \
			"$HOST_LOG" "$GUEST_LOG" 2>/dev/null | sed 's/^/    /'
		FAIL="${PROBLEMS%,}"
	fi
}

for SEED in "${SEEDS[@]}"; do
	if [ "$FIRST_SEED" -eq 0 ]; then
		sleep "$SEED_GAP"
	fi
	FIRST_SEED=0
	run_seed "$SEED"
	if [ -z "$FAIL" ]; then
		PASS=$((PASS + 1))
	else
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
done

for SEED in "${PLAIN_SEEDS[@]}"; do
	if [ "$FIRST_SEED" -eq 0 ]; then
		sleep "$SEED_GAP"
	fi
	FIRST_SEED=0
	run_seed "$SEED" plain
	if [ -z "$FAIL" ]; then
		PASS=$((PASS + 1))
	else
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
done

echo "---"
echo "seeds: $((PASS + FAIL_COUNT))  pass: $PASS  fail: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
	echo "FAIL: $FAIL_COUNT of $((PASS + FAIL_COUNT)) seeds failed (logs in $OUT)"
	exit 1
fi

echo "PASS: all $PASS seeds played to game end with matching views and an intact wire (logs in $OUT)"
exit 0