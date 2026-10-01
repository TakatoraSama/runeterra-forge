## The five RPCs of M5a and nothing else.
##
## It is TRANSPORT + SENDER VALIDATION ONLY. It holds no MatchState, runs no rules,
## redacts nothing and decides nothing: the host's MatchHost owns the engine and has
## already filtered every batch per viewer before send_events() is called, so nothing
## hidden can leak through here. What this class does own is the identity rule:
##
##   THE PLAYER ID ALWAYS COMES FROM THE SENDER, NEVER FROM THE PAYLOAD.
##
## A guest's submit_intent and presentation_done carry no player field at all; the host
## derives the id from the peer that sent it, so a guest cannot play as the host by
## putting {"player": 0} in its intent. The host is the only peer whose events travel
## host -> guest, and the guest is the only one whose intents travel guest -> host.
##
## This is the ONLY file allowed to carry an @rpc annotation (M5a deleted every RPC of
## the old engine), and it is the only place that touches the MultiplayerAPI.
##
## PEER IDS AND PLAYER IDS ARE DIFFERENT THINGS: ENet numbers the server peer 1 and the
## client peer 2, while the MATCH player ids are fixed by role — host = 0, guest = 1.
## Nothing here converts between them: the host always knows it is player 0 and the
## guest always knows it is player 1, so the only peer number this file needs is
## SERVER_PEER_ID (the guest's destination) and guest_peer_id (the host's check).
class_name MatchNet extends Node

## ENet's server peer number. A client always addresses the server with this, and a
## sender id of 0 or 1 means "nobody remote" (a local call).
const SERVER_PEER_ID := 1

## Absolute PLAYER ids (M5a): 0 = host, 1 = guest.
const HOST_PLAYER := 0
const GUEST_PLAYER := 1

## The seq carried by the refusal batch. It is -1, which no real batch can have: real
## batches carry the guest's own counter starting at 0, so a refusal is always
## distinguishable from a match event in the [NET-OUT] / [NET-IN] logs.
const REFUSAL_SEQ := -1

## How long the host waits before dropping a refused peer, so the guest has time to
## read the session_ended batch that was just sent to it.
const REFUSE_KICK_DELAY := 2.0

## The guest is connected and its hello was accepted. `deck` is the validated card ids
## the host will start the guest with (MatchDecks.sanitize output), `want_snapshots`
## echoes what the guest asked for. Emitted on the HOST only, once per session.
signal guest_ready(deck: Array, want_snapshots: bool)
## The host refused the handshake ("bad_protocol", "second_guest", "bad_deck"). Emitted
## on the HOST only. The GUEST is told through the normal event stream: the host puts a
## session_ended(reason) event into a receive_events batch addressed to that guest,
## which reaches the guest as MatchEvents.SESSION_ENDED, and then disconnects the peer
## about 2 s later. The guest therefore shows its own session-ended overlay and never
## depends on this signal.
signal session_refused(reason: String)
## The session ended for a reason the rules do not own: "disconnected" when a peer drops,
## "opponent_left" once the match is over. Emitted on BOTH peers.
signal session_ended(reason: String)

## The MatchController of the local peer, set by LobbyUI before connecting. The RPC
## bodies route into it; it is typed as a plain Node and called dynamically, because
## this file must keep loading before MatchController exists.
var controller: Node = null

## True on the peer that owns the engine. LobbyUI sets this before connecting: it is
## the only thing that decides which direction a send goes and which RPCs are accepted.
var is_host: bool = false

## The guest's peer id on the host, 0 when nobody has connected yet. Only the peer in
## this field is allowed to send the guest -> host RPCs; anything else is dropped
## without touching the engine. LobbyUI forwards NetworkManager's player_connected, so
## the id always matches the peer that actually joined.
var guest_peer_id: int = 0

## Every batch this node sends or receives is logged as one line, in the order it
## crossed the wire, so tools/lan_selftest.sh can diff the two peers:
##   [NET-OUT n] <kind> <seq> <JSON>   a payload this peer put on the wire
##   [NET-IN n] <kind> <seq> <JSON>    a payload this peer took off the wire
## `n` counts from 0 per direction. Debug builds only. The guest's [NET-IN] list must
## equal the host's [NET-OUT] list exactly (and the guest's [NET-OUT] the host's
## [NET-IN]), which proves nothing was reordered, dropped or added in transit.
var debug_logs: bool = false

## Monotone counter for this peer's [NET-OUT] lines.
var _out_seq: int = 0

## Monotone counter for this peer's [NET-IN] lines.
var _in_seq: int = 0

## Optional JSONL mirror of the same lines, written to user://logs/. Null unless the
## session asked for it, so a normal play run never opens a file.
var _batch_log: FileAccess = null


func _ready() -> void:
	debug_logs = OS.is_debug_build()
	# A drop is the end of the match (M5a has no reconnect): tell whoever is listening
	# on this peer, and let the controller close the session.
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# Host -> guest senders
# ---------------------------------------------------------------------------

## Host -> guest: one event batch, already redacted for the guest. `seq` is the guest's
## own batch counter starting at 0 and incremented once per batch; a gap means packets
## were lost and the guest cannot trust its view. Nothing is sent unless the peer is
## the guest.
func send_events(events: Array, seq: int) -> void:
	if not _can_send_to_guest():
		return
	_log_out("events", events, seq)
	receive_events.rpc_id(guest_peer_id, events, seq)


## Host -> guest: the full state for the guest, from MatchHost.snapshot_for(1). Always
## delivered BEFORE that guest's first event batch, because seq 0 is the first batch
## after the snapshot.
func send_snapshot(snapshot: Dictionary) -> void:
	if not _can_send_to_guest():
		return
	_log_out("snapshot", snapshot, -1)
	receive_snapshot.rpc_id(guest_peer_id, snapshot)


# ---------------------------------------------------------------------------
# Guest -> host senders
# ---------------------------------------------------------------------------

## Guest -> host: one intent from the local player. No player id is sent; the host
## reads it from the sender. Returns immediately — the answer comes back later as an
## event batch, possibly with an intent_rejected addressed to the guest alone.
func send_intent(intent: Dictionary) -> void:
	if is_host:
		return
	_log_out("intent", intent, -1)
	submit_intent.rpc_id(SERVER_PEER_ID, intent)


## Guest -> host: the guest's presenter has animated the batch for `turn` to the end.
## The host counts the ack; it releases play_opened(turn) once every id in
## acks_required has acked that turn, or when ack_timeout(turn) fires.
func send_presentation_done(turn: int) -> void:
	if is_host:
		return
	_log_out("presentation_done", {"turn": turn}, turn)
	presentation_done.rpc_id(SERVER_PEER_ID, turn)


## Guest -> host: the join handshake. Deliberately NOT one of the three senders the
## Step 0 contract listed: it is a session-control message rather than match traffic,
## and only LobbyUI ever sends it. It lives here, rather than being an rpc_id call
## from LobbyUI, because the guest has to LOG it exactly like every other message it
## puts on the wire — tools/lan_selftest.sh compares the guest's [NET-OUT] list with
## the host's [NET-IN] list byte for byte, and an unlogged hello would make that
## comparison fail on every single run.
func send_hello(payload: Dictionary) -> void:
	if is_host:
		return
	_log_out("hello", payload, -1)
	hello.rpc_id(SERVER_PEER_ID, payload)


# ---------------------------------------------------------------------------
# The five RPCs
# ---------------------------------------------------------------------------

## Guest -> host, any_peer, reliable. The join handshake, kept out of the intent stream
## so the rules engine never has to validate session control:
##   payload = {protocol: MatchHost.PROTOCOL_VERSION, deck: Array[String],
##              want_snapshots: bool}
## The host answers through the static MatchHost.check_hello(payload) and emits
## guest_ready or session_refused. A payload that arrives from anyone but the guest
## peer is dropped without a reply.
@rpc("any_peer", "reliable")
func hello(payload: Dictionary) -> void:
	# A host never receives a hello, and a guest must never be able to open the match.
	if not is_host:
		return
	if not _is_guest_sender():
		return
	_log_in("hello", payload, -1)
	var check: Dictionary = MatchHost.check_hello(payload)
	if not bool(check.get("ok", false)):
		_refuse(str(check.get("reason", "bad_protocol")))
		return
	guest_ready.emit(check.get("deck", []) as Array, bool(check.get("want_snapshots", false)))


## Guest -> host, any_peer, reliable. `intent` is one MatchIntents entry
## ({type, ...fields}). The sender MUST be the guest peer and the payload MUST NOT name
## a player: anything else is dropped without touching the engine. Routed to
## controller.on_remote_intent(intent).
@rpc("any_peer", "reliable")
func submit_intent(intent: Dictionary) -> void:
	if not is_host:
		return
	if not _is_guest_sender():
		return
	if _names_a_player(intent):
		return
	_log_in("intent", intent, -1)
	if controller != null:
		controller.call("on_remote_intent", intent)


## Guest -> host, any_peer, reliable. `turn` is the turn the guest finished animating.
## The sender MUST be the guest peer. Routed to
## controller.on_remote_presentation_done(turn).
@rpc("any_peer", "reliable")
func presentation_done(turn: int) -> void:
	if not is_host:
		return
	if not _is_guest_sender():
		return
	_log_in("presentation_done", {"turn": turn}, turn)
	if controller != null:
		controller.call("on_remote_presentation_done", turn)


## Host -> guest, authority, reliable. `events` is one batch of redacted event
## Dictionaries, `seq` that guest's batch counter. Routed to
## controller.on_remote_events(events).
@rpc("authority", "reliable")
func receive_events(events: Array, seq: int) -> void:
	# Only the authority sends event batches; a guest may never answer with its own.
	if is_host:
		return
	_log_in("events", events, seq)
	if controller != null:
		controller.call("on_remote_events", events)


## Host -> guest, authority, reliable. `snapshot` is MatchSnapshot.for_viewer(state, 1),
## sent before the guest's first event batch. Routed to
## controller.on_remote_snapshot(snapshot).
@rpc("authority", "reliable")
func receive_snapshot(snapshot: Dictionary) -> void:
	if is_host:
		return
	_log_in("snapshot", snapshot, -1)
	if controller != null:
		controller.call("on_remote_snapshot", snapshot)


# ---------------------------------------------------------------------------
# Session control (not transport): the handshake answer and the disconnect signals
# ---------------------------------------------------------------------------

## Refuses a handshake. The GUEST is told through the normal event stream (it must not
## depend on a HOST-only signal), the HOST gets the local signal so the lobby can
## re-enable its buttons, and the peer is dropped REFUSE_KICK_DELAY seconds later so
## the guest has time to read the refusal it was just sent.
func _refuse(reason: String) -> void:
	var batch: Array = [MatchEvents.session_ended(reason)]
	# Logged under "events", not "refuse": this batch travels through receive_events, so
	# the guest logs it as "events" too, and tools/lan_selftest.sh compares the two
	# [NET-OUT] / [NET-IN] lists byte for byte.
	_log_out("events", batch, REFUSAL_SEQ)
	receive_events.rpc_id(guest_peer_id, batch, REFUSAL_SEQ)
	session_refused.emit(reason)
	_kick_later(guest_peer_id)


## Disconnects `peer_id` after REFUSE_KICK_DELAY seconds, so the guest can read the
## refusal batch that was just sent. A SceneTreeTimer, not a sleep in the RPC: the RPC
## returns immediately and the match logic never blocks.
func _kick_later(peer_id: int) -> void:
	var tree := get_tree()
	if tree == null or peer_id <= SERVER_PEER_ID:
		return
	await tree.create_timer(REFUSE_KICK_DELAY).timeout
	if multiplayer.multiplayer_peer == null:
		return
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## A peer went away. On the host that is the guest; on the guest the host is reported
## through server_disconnected instead, so both of these only fire on the host side.
func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host or peer_id != guest_peer_id:
		return
	guest_peer_id = 0
	session_ended.emit("disconnected")


## The host went away (or the connection was refused by the network). M5a has no
## reconnect: the match is over and the guest is told so through its own signal.
func _on_server_disconnected() -> void:
	if is_host:
		return
	session_ended.emit("disconnected")


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

## True when this peer may send a host -> guest batch: it is the host AND the guest is
## actually connected. Without the connection check the RPC would be dropped in transit
## and the guest would sit waiting for a batch that was never delivered.
func _can_send_to_guest() -> bool:
	if not is_host:
		return false
	if guest_peer_id <= SERVER_PEER_ID:
		push_warning("MatchNet: not sending, no guest is connected")
		return false
	return true


## True when the RPC that just arrived came from the one peer allowed to speak to us.
## Everything the guest sends is a bare message with no player id, so the peer it came
## from IS the identity: without this check any peer could submit intents.
func _is_guest_sender() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > SERVER_PEER_ID and sender == guest_peer_id:
		return true
	push_warning("MatchNet: dropped a message from peer %d (the guest is %d)" % [
		sender, guest_peer_id])
	return false


## The identity rule, enforced: an intent carrying a "player" key is dropped unread.
## The host reads the player id from the sender, so a guest trying to play as the host
## by naming {"player": 0} gets nothing at all — not even a rejection, because the
## message never reaches the engine.
func _names_a_player(payload: Dictionary) -> bool:
	if not payload.has("player"):
		return false
	push_warning("MatchNet: dropped an intent that names a player (the id comes from the sender)")
	return true


# ---------------------------------------------------------------------------
# Debug logs
# ---------------------------------------------------------------------------

## One [NET-OUT n] line: this peer is putting `payload` on the wire. `seq` is the batch
## counter the wire itself carries (-1 for the point-to-point control messages), so the
## guest's [NET-IN] list can be diffed line by line against the host's [NET-OUT].
func _log_out(kind: String, payload: Variant, seq: int) -> void:
	if not debug_logs:
		return
	print("[NET-OUT %d] %s %s %s" % [_out_seq, kind, str(seq), JSON.stringify(payload)])
	_out_seq += 1
	_write_log_line("out", kind, seq, payload)


## One [NET-IN n] line: this peer took `payload` off the wire. Deliberately the same
## shape as _log_out so the two lists compare as plain text.
func _log_in(kind: String, payload: Variant, seq: int) -> void:
	if not debug_logs:
		return
	print("[NET-IN %d] %s %s %s" % [_in_seq, kind, str(seq), JSON.stringify(payload)])
	_in_seq += 1
	_write_log_line("in", kind, seq, payload)


## Opens user://logs/match_<n>.jsonl for the JSONL mirror. A no-op without debug_logs,
## so a normal play session never opens a file. Best effort: an unwritable log dir must
## never take the match down, so a failure is a warning and nothing else.
func open_batch_log() -> void:
	if _batch_log != null or not debug_logs:
		return
	var dir := "user://logs"
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_warning("MatchNet: could not create %s for the batch log" % dir)
		return
	var path: String = "%s/match_%d.jsonl" % [dir, Time.get_ticks_msec()]
	_batch_log = FileAccess.open(path, FileAccess.WRITE)
	if _batch_log == null:
		push_warning("MatchNet: could not open %s for the batch log" % path)


## Closes the JSONL mirror, if one was opened.
func close_batch_log() -> void:
	if _batch_log == null:
		return
	_batch_log.close()
	_batch_log = null


## Appends one JSON line to the mirror. A write error closes the file rather than
## retrying every batch: a full disk must not turn into a stall in the middle of a match.
func _write_log_line(direction: String, kind: String, seq: int, payload: Variant) -> void:
	if _batch_log == null:
		return
	var entry: Dictionary = {"dir": direction, "kind": kind, "seq": seq, "payload": payload}
	if not _batch_log.store_line(JSON.stringify(entry)):
		push_warning("MatchNet: batch log write failed, closing it")
		close_batch_log()