## The host-authoritative session layer around MatchRules (M5a). STUB — M5a Group A
## implements the bodies; this file fixes the signatures the three groups code against.
##
## WHY a session layer: MatchRules._end_turn emits nothing for the player who did not
## end the turn, so one END_TURN submit returns the resolve AND the next turn's opening
## in a single batch. Over a network the two peers would then animate that batch at
## different speeds, and the faster peer could already be submitting into a turn the
## slower peer has not opened yet. MatchHost owns the extra state that fixes it:
##
##   - it owns MatchState + MatchRules and is the ONLY thing that calls rules.submit();
##   - it redacts every batch per viewer with MatchEvents.redact_for(event, viewer)
##     and delivers it with a monotone `seq`;
##   - it holds the resolve-and-open batch back until every required viewer has acked
##     the previous one (presentation_done), then delivers it with a play_opened;
##   - it routes an intent_rejected to the sender alone, and an intent that arrives
##     while the session is not accepting one (not_ready) to the sender alone.
##
## TRANSPORT-AGNOSTIC BY CONTRACT: MatchHost never touches the network and never names
## MatchNet or a Node. It reaches the outside world only through the two Callables given
## to _init, so the same class drives offline (both view = the local presenter) and LAN
## (host's own presenter + MatchNet for the guest):
##
##   deliver_events(viewer: int, events: Array, seq: int)
##       One batch, already redacted for `viewer`. `events` are plain Dictionaries of
##       primitives and `seq` is that viewer's batch counter, incremented once per
##       delivery and starting at 0. A viewer compares seq to tell a gap from a stall.
##   deliver_snapshot(viewer: int, snapshot: Dictionary)
##       A full state for `viewer` from MatchSnapshot.for_viewer(state, viewer). Sent
##       BEFORE any event batch for a viewer: seq 0 of the event stream is the first
##       batch after the snapshot, so a snapshot always precedes the events it explains.
##
## ENGINE RULES (Scripts/Match, mandatory): RefCounted only, no Node, no get_node, no
## await, no timers, no autoload identifiers, no scene-tree access, no global randi()
## / randf() (all randomness through MatchState.rng). It is synchronous: the ack
## timeout is NOT a timer inside this class (that would need await); the session layer
## above calls ack_timeout(turn) from a SceneTreeTimer that ignores time scale.
class_name MatchHost extends RefCounted

## Wire format of the join handshake. The guest's hello carries the same number and the
## host refuses a mismatch (see check_hello), so two different builds never talk.
const PROTOCOL_VERSION := 1

## The authoritative state and the rules that own it. Null until start().
var state: MatchState = null
var rules: MatchRules = null

## Viewers whose presentation_done is required before the held batch is released.
## Offline is [] (nothing to wait for); the host is [0, 1]. Player ids are absolute:
## 0 = host, 1 = guest.
var acks_required: Array[int] = []

## Viewers that receive snapshots (join, and --verify-view). A viewer outside this list
## only ever gets event batches.
var snapshot_viewers: Array[int] = []

var _deliver_events: Callable
var _deliver_snapshot: Callable


## `deliver_events(viewer, events, seq)` and `deliver_snapshot(viewer, snapshot)` are
## the two delivery Callables described at the top of this file. Both are required: the
## host always delivers to its own viewer, offline delivers events only.
func _init(deliver_events: Callable, deliver_snapshot: Callable) -> void:
	_deliver_events = deliver_events
	_deliver_snapshot = deliver_snapshot
	push_error("MatchHost: not implemented (M5a Group A)")


## Builds the match from `deck0` (host) and `deck1` (guest) and runs MatchRules
## .start_match(lane_ids), delivering the opening snapshot to every snapshot viewer
## before the opening event batch. `seed` is the match seed: the host picks it and it
## never leaves the host. `scramble_ids` (M5a Group A) permutes instance-id creation
## with a separate RNG so the guest cannot map the host's deck from draw ids; the main
## state.rng must stay untouched, or a --seed run stops replaying exactly.
func start(deck0: Array, deck1: Array, seed: int, scramble_ids: bool = false, lane_ids: Array = []) -> void:
	push_error("MatchHost: not implemented (M5a Group A)")


## Submits `intent` for absolute `player` and delivers the answer per viewer.
## Returns false when the session refused it outright: the player is unknown, or the
## session is not accepting input (before the first play_opened, while a batch is held
## for an ack, or after the match ended). A refusal the RULES made is a successful
## submit that produced an intent_rejected event routed to `player` alone — that is
## still a true return.
func submit(player: int, intent: Dictionary) -> bool:
	push_error("MatchHost: not implemented (M5a Group A)")
	return false


## Viewer `player` has animated the batch carrying turn `turn` to completion. Releases
## the held batch once every id in acks_required has acked, and opens the next PLAY
## with a play_opened event. A stale (already released) or duplicate ack is ignored
## rather than opening a turn twice; an ack for a turn that is not the pending one is
## dropped.
func presentation_done(player: int, turn: int) -> void:
	push_error("MatchHost: not implemented (M5a Group A)")


## True when the pending turn has waited past its timeout (~10 s). The session layer
## calls this from a SceneTreeTimer that ignores time scale, then releases the held
## batch anyway, so one stuck viewer cannot freeze the match. Returns false when
## nothing is pending.
func ack_timeout(turn: int) -> bool:
	push_error("MatchHost: not implemented (M5a Group A)")
	return false


## The turn whose play_opened is still waiting for acks, or -1 when nothing is held.
## Matches the `turn` argument of presentation_done() and ack_timeout().
func pending_turn() -> int:
	push_error("MatchHost: not implemented (M5a Group A)")
	return -1


## True once the match reached GAME_END (or the session ended for another reason).
func is_over() -> bool:
	push_error("MatchHost: not implemented (M5a Group A)")
	return true


## The winner of the finished match: 0 host, 1 guest, -1 for a tie. -1 while the match
## is still running.
func winner() -> int:
	push_error("MatchHost: not implemented (M5a Group A)")
	return -1


## The full state `viewer` is allowed to see, from MatchSnapshot.for_viewer. Never
## sent to a viewer outside snapshot_viewers. This is the authoritative view --verify-view
## compares the presenter's model against.
func snapshot_for(viewer: int) -> Dictionary:
	push_error("MatchHost: not implemented (M5a Group A)")
	return {}


## Validates a guest's join payload BEFORE any MatchState exists, so a bad handshake
## cannot start a match. `payload` is what the guest's hello sent:
##   {protocol: int, deck: Array[String], want_snapshots: bool}
## Returns a Dictionary with exactly these keys:
##   ok              bool    - true only when the match may start
##   reason: String  - "" when ok, else a REASON_TEXT key of MatchPresenter
##                       ("bad_protocol", "second_guest", "bad_deck")
##   deck: Array[String] - MatchDecks.sanitize(payload.deck): the validated 12 ids to
##                       start with, or DEFAULT_DECK_IDS when the guest sent none
##   want_snapshots: bool  - echoed back from the payload; false for anything that is
##                       not a real bool, so a hostile payload cannot force snapshots
## The deck is validated with MatchDecks.sanitize, the same rule as an offline saved
## deck. The guest's list never reaches the host's presenter, and the host's own deck
## and seed are never sent back.
static func check_hello(payload: Dictionary) -> Dictionary:
	push_error("MatchHost: not implemented (M5a Group A)")
	return {"ok": false, "reason": "bad_protocol", "deck": [], "want_snapshots": false}