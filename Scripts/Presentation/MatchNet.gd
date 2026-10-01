## The five RPCs of M5a and nothing else. STUB — M5a Group C implements the bodies;
## this file fixes the signatures and the wire contract the other groups code against.
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
## This is the ONLY file allowed to carry an @rpc annotation (M5a deletes every RPC
## of the old engine), and it is the only place that touches the MultiplayerAPI.
class_name MatchNet extends Node

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
## The session ended for a reason the rules do not own: "Opponent disconnected" when a
## peer drops, "Opponent left" once the match is over. Emitted on BOTH peers.
signal session_ended(reason: String)

## The MatchController of the local peer, set by LobbyUI before connecting. The RPC
## bodies route into it; it is typed as a plain Node and called dynamically, because
## this file must keep loading before MatchController exists.
var controller: Node = null

## Optional debug log of every batch, written as JSONL to user://logs/ by Group C
## ([NET-OUT n] / [NET-IN n]). Null in a release run.
var _batch_log: FileAccess = null


## Host -> guest: one event batch, already redacted for the guest. `seq` is the guest's
## own batch counter starting at 0 and incremented once per batch; a gap means packets
## were lost and the guest cannot trust its view. Nothing is sent unless the peer is
## the guest.
func send_events(events: Array, seq: int) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Host -> guest: the full state for the guest, from MatchHost.snapshot_for(1). Always
## delivered BEFORE that guest's first event batch, because seq 0 is the first batch
## after the snapshot.
func send_snapshot(snapshot: Dictionary) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Guest -> host: one intent from the local player. No player id is sent; the host
## reads it from the sender. Returns immediately — the answer comes back later as an
## event batch, possibly with an intent_rejected addressed to the guest alone.
func send_intent(intent: Dictionary) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Guest -> host: the guest's presenter has animated the batch for `turn` to the end.
## The host counts the ack; it releases play_opened(turn) once every id in
## acks_required has acked that turn, or when ack_timeout(turn) fires.
func send_presentation_done(turn: int) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Guest -> host, any_peer, reliable. The join handshake, kept out of the intent stream
## so the rules engine never has to validate session control:
##   payload = {protocol: MatchHost.PROTOCOL_VERSION, deck: Array[String],
##              want_snapshots: bool}
## The host answers through the static MatchHost.check_hello(payload) and emits
## guest_ready or session_refused. A payload that is not a Dictionary, or that arrives
## from anyone but the guest peer, is dropped without a reply.
@rpc("any_peer", "reliable")
func hello(payload: Dictionary) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Guest -> host, any_peer, reliable. `intent` is one MatchIntents entry
## ({type, ...fields}). The sender MUST be the guest peer and the payload MUST NOT name
## a player: anything else is dropped without touching the engine. Routed to
## controller.on_remote_intent(intent).
@rpc("any_peer", "reliable")
func submit_intent(intent: Dictionary) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Guest -> host, any_peer, reliable. `turn` is the turn the guest finished animating.
## The sender MUST be the guest peer. Routed to
## controller.on_remote_presentation_done(turn).
@rpc("any_peer", "reliable")
func presentation_done(turn: int) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Host -> guest, authority, reliable. `events` is one batch of redacted event
## Dictionaries, `seq` that guest's batch counter. Routed to
## controller.on_remote_events(events).
@rpc("authority", "reliable")
func receive_events(events: Array, seq: int) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")


## Host -> guest, authority, reliable. `snapshot` is MatchSnapshot.for_viewer(state, 1),
## sent before the guest's first event batch. Routed to
## controller.on_remote_snapshot(snapshot).
@rpc("authority", "reliable")
func receive_snapshot(snapshot: Dictionary) -> void:
	push_error("MatchNet: not implemented (M5a Group C)")