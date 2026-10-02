## Turns the Match engine's event stream into the game's existing visuals.
##
## The engine (Scripts/Match) owns every rule; this class owns nothing but the view. It
## keeps a view model — one entry per instance it knows about, plus the local hand order,
## the opponent's hand, both deck counts, both mana pools, the turn and the revealed lanes
## — and every handler updates that model first and then moves nodes with the SAME view-only
## helpers the old game used (CardDatabase.populate_card_visuals, PlayerHand.add_card_to_hand,
## Board.reposition_cards_in_zone, the Card animations), so an engine-mode board looks
## exactly like an old-engine one.
##
## It NEVER calls old game logic: no AbilityResolver, LevelUpManager, AuraSystem,
## LaneManager, SwapLaneManager, StunManager, BotManager, no Deck.draw_card /
## draw_specific_cards, no Board.create_lanes_from_ids, no Card._perform_level_up, no
## CardManager.recall_card / discard_card_from_hand / create_card_in_hand /
## resolve_played_cards / finish_drag and no GameManager mana or turn function. The engine is
## the single source of truth and this file only ever reacts to MatchEvents.
##
## Perspective: the engine's player ids are ABSOLUTE (0 = host, 1 = guest) and its
## zones are keyed Vector2i(col, owner). The SCREEN has no absolute ids: the local
## player's cards are always on the BOTTOM row and the opponent's on the TOP one,
## whoever they are. _row(owner) is the only place that mapping exists, and every
## Board touch point goes through it:
##     _row(owner)     = 1 if owner == local_player else 0
##     _board_zone(col, owner) = Vector2i(col, _row(owner))
## Offline the human is absolute 1 and the bot 0, so the mapping is the identity there
## and offline is unaffected; on a host it is what puts the host's own cards on the
## bottom row. The engine-keyed _zones dictionary stays keyed by (col, owner) — only
## the Board is addressed through _board_zone.
##
## The spell column -1 maps to (-1, 1) for the local player and (-1, 0) for the
## opponent, which is exactly BoardGeneration.SPELL_ZONE_ALLIED / SPELL_ZONE_ENEMY.
## The engine slot index equals the board slot index: a zone list is compact, and
## Board.reposition_cards_in_zone puts list index i on entry i of slots_by_zone —
## which is engine slot i on the BOTTOM row and engine slot (n - 1 - i) on the TOP
## one, because create_all_slots fills that row in reverse. _build_slot_order()
## measures that mapping from the live slot nodes instead of assuming it.
##
## Events arrive already redacted through MatchEvents.redact_for(event, local_player), so the
## opponent's plays only show up face-down in resolve_started and their identities arrive
## with card_revealed. One coroutine drains the queue in order, awaiting each handler's
## animation, and emits `idle` (deferred) once it is empty.
class_name MatchPresenter extends Node

## Emitted when the queue has drained and the view has caught up with the engine.
signal idle

# --- Animation timings (the values the old game used) ---
const DRAW_SPAWN_POSITION := Vector2(150, 940)
const CARD_DRAW_SPEED := 0.2
const CARD_CREATE_SPEED := 0.3
const HAND_CARD_SCALE := 0.2
## BoardGeneration.SPELL_SLOT_SCALE, kept here so the presenter never has to reach into
## the board script for a constant.
const SPELL_ZONE_SCALE := 0.1
const BOARD_CARD_SCALE := 0.15
const HAND_CARD_Z := 2
const DRAG_Z := 10
const RESOLVE_PAUSE := 0.5
const SWAP_PREVIEW_SPEED := 0.25
const SWAP_DURATION := 1.0
const RECALL_DURATION := 0.8
const SPELL_DISSOLVE := 0.4
const SHUFFLE_DISSOLVE := 0.5
## Upper bound on any single card animation wait. Longer than every animation in the card
## scenes, so it only fires when an animation can never finish (its node was freed).
const ANIMATION_LIMIT := 3.0
## Card.play_level_up_animation runs for about 5 s (1 fly out, 1.5 spin, 1 fly back,
## 0.5 settle); this caps how long the presenter waits for it.
const LEVEL_UP_LIMIT := 7.0
const CARD_PAUSE := 0.7
const TOAST_FADE_TIME := 1.5
const CARD_BACK_Z := 5

## Human-readable text for every reason an intent is refused or a session ends: the
## keys MatchRules rejects with, plus the SESSION-layer reasons of M5a (a refused
## handshake, a disconnect, a session closed before the turn opened). The session ones
## are read by session_reason_text() rather than _on_intent_rejected, because a
## session ending is not a rejected move and shows an overlay instead of a toast.
const REASON_TEXT := {
	"not_enough_mana": "Not enough mana",
	"zone_full": "That zone is full",
	"turn_ended": "You already ended your turn",
	"not_in_hand": "That card is not in your hand",
	"spell_needs_spell_zone": "Spells go in the spell zone",
	"unit_needs_lane": "Units go in a lane",
	"noxkraya": "Cards must be played in the active lane",
	"nothing_to_undo": "Nothing to undo",
	"not_your_card": "That is not your card",
	"not_on_board": "That card is not on the board",
	"not_resolved": "That card has not resolved yet",
	"not_elusive": "Only Elusive cards can swap lanes",
	"stunned": "That card is stunned",
	"already_swapping": "That card is already swapping",
	"same_column": "Pick a different column",
	"wrong_phase": "You cannot do that right now",
	"malformed": "That move is not legal",
	"bad_player": "Unknown player",
	"not_ready": "Waiting for your opponent",
	"disconnected": "Opponent disconnected",
	"opponent_left": "Opponent left",
	"bad_protocol": "Different game versions cannot play together",
	"second_guest": "That slot is already taken",
	"bad_deck": "That deck is not valid",
}

## Where a card sits, from the presenter's point of view.
enum ViewLocation { HAND, BOARD, GONE }

# ----------------------------
# Scene references
# ----------------------------

var _card_manager: Node = null
var _board: Node = null
var _hand: Node = null
var _deck: Node = null
var _victory_text: Node = null
var _turn_text: Node = null
var _mana_text: Node = null
var _flip_first_text: Node = null
var _end_turn_button: Node = null
var _undo_button: Node = null

# ----------------------------
# Match context
# ----------------------------

var local_player: int = 1
var controller: Node = null

var _game_phase: int = 0
var _round_phase: int = 0
var _turn: int = 0
var _flip_first: int = -1
## The three lane ids as THIS view knows them: "" for a column that is still hidden.
## The engine's state.lane_ids holds all three from the start, so this is the only
## copy of them that is allowed to be blank — a hidden column must not be readable
## from the view, and _verify_lanes() compares it against the snapshot.
var _lane_ids: Array = ["", "", ""]
var _lanes_revealed: Array[bool] = [false, false, false]
## The local player's queued lane swaps, as the snapshot lists them.
var _pending_swaps: Array = []

var _mana_by_player: Dictionary = {}
var _deck_by_player: Dictionary = {}

## The local player's pool, kept aside from _mana_by_player because the hand glow and the
## Mana label both need it on every mana change.
var _local_mana_current: int = 0
var _local_mana_max: int = 0

## absolute player id -> true once that player pressed End Turn this round. Fed by
## TURN_ENDED (public to both viewers, so each side can grey out its own button while
## the round waits for the other player) and cleared at every ROUND_START.
var _ended_turn: Dictionary = {0: false, 1: false}
## The turn whose PLAY phase this view has been OPENED for, or -1 when it has not.
## PLAY_OPENED is the session layer's own event (MatchHost holds it back until every
## peer has acked the previous turn), and it is what says the round may be acted in at
## all: the phase changes to PLAY in the same batch, so view_in_play() alone would let
## the local player submit into a turn the other peer has not finished animating.
var _play_open_turn: int = -1
## The local player's own undo stack depth, as the view understands it. Grown by our
## own card_played, zeroed by our own play_undone and by every round start (the engine
## clears the stack there). The guest holds no MatchState to ask, so can_undo() is
## answered from this.
var _own_undo_count: int = 0
## True once the session ended for a reason the rules do not own (a disconnect, a
## refused handshake). While it is set the local player may not act any more and the
## overlay stays up until they leave for the lobby.
var _session_over: bool = false

# ----------------------------
# View model
# ----------------------------

## instance_id -> model entry (see _make_entry).
var _entries: Dictionary = {}
## Node -> instance_id, the reverse of the entries' nodes.
var _instance_by_node: Dictionary = {}
## Engine zones Vector2i(col, owner) -> compact Array[int] of instance ids, slot == index.
var _zones: Dictionary = {}

var _local_hand: Array[int] = []
## The opponent's hand SIZE, reconciled from the snapshot. Their hand contents never
## reach this presenter, and neither does the moment a card leaves it (an opponent's
## CARD_PLAYED is redacted to null), so the size is the one hand fact that has to be taken
## from the authoritative snapshot rather than derived from the event stream.
var _opponent_hand_count: int = 0
## instance_id -> the position a swap preview is currently showing.
var _swap_preview: Dictionary = {}

# ----------------------------
# Queue
# ----------------------------

var _queue: Array = []
var _processing: bool = false
## Bumped by every drain, so a superseded one can tell that its deferred `idle` is stale.
var _drain_generation: int = 0
var _toast_label: Label = null
## The session-ended overlay, created on first use and freed by the next setup().
var _session_overlay: CanvasLayer = null

## board zone Vector2i(col, row) -> Array mapping engine slot index to index in slots_by_zone.
var _slot_order: Dictionary = {}


# ----------------------------
# Public API
# ----------------------------

## Builds the lanes, the deck count and the opening hand/board from `snapshot` and binds
## this presenter to `controller`. Called once, before the first event is routed.
func setup(snapshot: Dictionary, local_player_id: int, p_controller: Node) -> void:
	local_player = local_player_id
	controller = p_controller

	_card_manager = get_node_or_null(^"/root/Main/CardManager")
	_board = get_node_or_null(^"/root/Main/Board")
	_hand = get_node_or_null(^"/root/Main/PlayerHand")
	_deck = get_node_or_null(^"/root/Main/Deck")
	_victory_text = get_node_or_null(^"/root/Main/VictoryText")
	_turn_text = get_node_or_null(^"/root/Main/CardManager/TurnText")
	_mana_text = get_node_or_null(^"/root/Main/CardManager/ManaText")
	_flip_first_text = get_node_or_null(^"/root/Main/CardManager/FlipFirstText")
	_end_turn_button = get_node_or_null(^"/root/Main/CardManager/Button")
	_undo_button = get_node_or_null(^"/root/Main/CardManager/Undo")

	_entries.clear()
	_instance_by_node.clear()
	_zones.clear()
	_local_hand.clear()
	_pending_swaps.clear()
	_swap_preview.clear()
	_queue.clear()
	_processing = false
	_game_phase = MatchState.GamePhase.GAME_START
	_round_phase = MatchState.RoundPhase.NONE
	_turn = 0
	_flip_first = -1
	_lanes_revealed = [false, false, false]
	_mana_by_player = {0: [0, 0], 1: [0, 0]}
	_deck_by_player = {0: 0, 1: 0}
	for col in range(MatchState.SPELL_COL, MatchState.COLUMNS):
		for owner in 2:
			_zones[Vector2i(col, owner)] = []
	_ended_turn = {0: false, 1: false}
	_play_open_turn = -1
	_own_undo_count = 0
	_session_over = false
	_session_overlay = null

	if _card_manager != null and "current_player_id" in _card_manager:
		_card_manager.current_player_id = local_player
	_build_slot_order()

	# Lanes: every column starts blank (a blank id means HIDDEN, column 0 included —
	# the old view assumed column 0 was always on screen, which is not true for a
	# viewer whose snapshot was taken before the first reveal). A column is filled in
	# only when lane_revealed names it.
	_lane_ids = ["", "", ""]
	for lane: Dictionary in snapshot.get("lanes", []):
		var col := int(lane.get("col", -1))
		if col < 0 or col >= MatchState.COLUMNS:
			continue
		var revealed := bool(lane.get("revealed", false))
		var lane_id := str(lane.get("lane_id", "")) if revealed else ""
		_lane_ids[col] = lane_id
		_lanes_revealed[col] = revealed
	_create_lane_views(_lane_ids)

	# Numbers first, so a hand node spawned below already glows against the right mana.
	for entry: Dictionary in snapshot.get("players", []):
		var pid := int(entry.get("player", -1))
		_deck_by_player[pid] = int(entry.get("deck_count", 0))
		_mana_by_player[pid] = [int(entry.get("current_mana", 0)), int(entry.get("max_mana", 0))]
		if pid == local_player:
			_local_mana_current = int(entry.get("current_mana", 0))
			_local_mana_max = int(entry.get("max_mana", 0))
	_apply_deck_counts()

	# The board and the local hand are normally empty here (the match has not started), but
	# a re-setup on a live state must rebuild the whole view rather than half of it.
	for row: Dictionary in snapshot.get("board", []):
		_build_from_snapshot_row(row)
	for entry: Dictionary in snapshot.get("players", []):
		if int(entry.get("player", -1)) != local_player:
			continue
		var hand: Variant = entry.get("hand", [])
		if not (hand is Array):
			continue
		for card: Dictionary in hand:
			var id := int(card.get("instance_id", -1))
			if id < 0:
				continue
			var model := _make_entry(id, str(card.get("card_id", "")), local_player, ViewLocation.HAND)
			model["cost"] = int(card.get("cost", _base_cost(str(card.get("card_id", "")))))
			_spawn_hand_node(id, model, Vector2(get_viewport().get_visible_rect().size.x / 2.0, 940.0))
			_local_hand.append(id)
	_sync_hand_nodes()
	if _hand != null:
		_hand.update_hand_position(0.1)

	_set_turn_text()
	_set_mana_text()
	_set_flip_first_text()
	_refresh_controls()
	_refresh_zone_power_texts()


## Appends `events` to the queue. Returns at once; a single coroutine drains the queue in
## order, so two handlers can never animate at the same time.
func enqueue(events: Array) -> void:
	for event: Variant in events:
		if event is Dictionary:
			_queue.append(event)
	if _processing:
		return
	# _drain_queue() is a coroutine: it runs synchronously up to its first await and then
	# suspends, leaving _processing true until the queue is empty. Anything enqueued in
	# that window is picked up by the SAME loop, so a batch can never be split across two
	# drains and lose its ordering.
	_drain_queue()


## True while the presenter is still working through its queue.
func is_busy() -> bool:
	return _processing or not _queue.is_empty()


## The Card node of that instance, or null when this presenter has none for it.
func node_for(instance_id: int) -> Node:
	var entry: Dictionary = _entries.get(instance_id, {})
	var node: Variant = entry.get("node", null)
	if node is Node and is_instance_valid(node):
		return node
	return null


## The instance a Card node belongs to, or -1 when this presenter does not know it.
func instance_of(node: Node) -> int:
	if node == null:
		return -1
	return int(_instance_by_node.get(node, -1))


## Compares the view model against `snapshot` and returns one message per difference.
## An empty Array means the view agrees with the engine.
func verify(snapshot: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	_verify_scalars(snapshot, problems)
	_verify_lanes(snapshot, problems)
	_verify_players(snapshot, problems)
	_verify_hands(snapshot, problems)
	_verify_board(snapshot, problems)
	_verify_pending_swaps(snapshot, problems)
	_verify_nodes(problems)
	return problems


# ----------------------------
# View model queries (M5a) — read by MatchController in every mode
# ----------------------------
#
# The guest holds NO MatchState, so is_play_phase() and can_undo() cannot be answered
# from the controller's engine in GUEST mode. They are answered from THIS view model
# instead, which is why these live here. Group B fills in the parts that need new
# tracking (ended_turn per player, the play_opened turn, the local undo count); the
# ones that are already exactly true of the current model are implemented.

## True while the local player may act, as the VIEW sees it:
##   the presenter is idle, the round is in TURN_LOOP / PLAY, play_opened has been
##   received for THIS turn, the local player has not ended the turn, and the session
##   is still alive.
## The presenter-idle half is what keeps the button greyed out while the board is still
## animating: the board the player is looking at would otherwise be one batch behind
## the engine they are submitting into.
func local_can_act() -> bool:
	if _session_over:
		return false
	if is_busy():
		return false
	if not view_in_play():
		return false
	if _play_open_turn != _turn:
		return false
	return not bool(_ended_turn.get(local_player, false))


## How many of the local player's plays this turn can still be undone.
func local_undo_count() -> int:
	return _own_undo_count


## The turn the view is showing, from the last turn_started / phase_changed event.
func view_turn() -> int:
	return _turn


## True while the view is in the PLAY phase of a running turn. This is the PHASE only:
## it says nothing about whether the local player may act (local_can_act) or about
## whether a guest's peer has acked.
func view_in_play() -> bool:
	return _game_phase == MatchState.GamePhase.TURN_LOOP \
		and _round_phase == MatchState.RoundPhase.PLAY


## True once the view has seen game_ended. Unlike the controller's is_match_over() this
## needs no MatchState, so the guest can answer it from its own view.
func is_match_over() -> bool:
	return _game_phase == MatchState.GamePhase.GAME_END


## True when the local player may start dragging card `instance_id` to another column:
## it is an own resolved Elusive card on the board, not stunned, with no pending swap.
## This is the VIEW-side gate CardManager's swap check uses instead of reading the
## controller's state (which the guest does not have). It is deliberately the same
## five conditions MatchRules._swap_card enforces, minus the target column: whether
## the drop is legal is answered when the card is released, and the engine's own
## intent_rejected is what tells the player about a same-column or full target.
func can_start_swap(instance_id: int) -> bool:
	var entry: Dictionary = _entries.get(instance_id, {})
	if entry.is_empty():
		return false
	if int(entry.get("owner", -1)) != local_player:
		return false
	if int(entry.get("location", ViewLocation.GONE)) != ViewLocation.BOARD:
		return false
	if not bool(entry.get("resolved", false)):
		return false
	if not _entry_has_keyword(entry, "Elusive"):
		return false
	if _entry_has_keyword(entry, "Stun"):
		return false
	for swap: Dictionary in _pending_swaps:
		if int(swap.get("instance_id", -1)) == instance_id:
			return false
	return true


## The card's keywords as the engine counts them: the printed ones from CardDatabase
## plus the runtime ones the event stream granted (Stun and Elusive can arrive either
## way, so the gate has to look at both).
func _entry_has_keyword(entry: Dictionary, keyword: String) -> bool:
	if _card_data_keywords(str(entry.get("card_id", ""))).has(keyword):
		return true
	return (entry.get("keywords", []) as Array).has(keyword)


## The single rule for whether a LOCAL-VIEW card node may be clicked: its Area2D is
## enabled only while the card is somewhere the player can pick it up — in our own
## hand, or on our own board when it is an Elusive unit (the one thing on the board
## CardManager.start_drag can do something with, and what can_start_swap gates).
##
## Every other board card is display-only: a non-Elusive unit has no legal drag off
## its lane and an opponent's card is not ours to touch at all. Disabling the shape
## is what makes that true in the INPUT path rather than in a check inside
## start_drag: InputManager.raycast_at_cursor only accepts collision_mask == 1 hits,
## so a card without one is never picked and the drag never begins.
func _refresh_collider(id: int) -> void:
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var node := node_for(id)
	if node == null:
		return
	var enabled := false
	match int(entry.get("location", ViewLocation.GONE)):
		ViewLocation.HAND:
			enabled = int(entry.get("owner", -1)) == local_player
		ViewLocation.BOARD:
			enabled = int(entry.get("owner", -1)) == local_player \
					and _entry_has_keyword(entry, "Elusive")
		_:
			enabled = false
	_set_collider(node, enabled)


## Shows the session-ended overlay: `message` is the human text ("Opponent
## disconnected", "Opponent left"), `match_over` says whether the finished result must
## stay visible underneath (true when the match had already reached GAME_END).
## Back to lobby on the overlay calls MatchController.leave_to_lobby().
##
## Built in code rather than from a .tscn: it is a dim panel, one line of text and a
## button, and a scene file would be a new asset that only this one caller ever loads.
## `match_over` moves the panel DOWN so it never covers the VictoryText the result was
## written into.
func show_session_ended(message: String, match_over: bool) -> void:
	_session_over = true
	_refresh_controls()
	if _session_overlay != null and is_instance_valid(_session_overlay):
		_session_overlay.queue_free()
	_session_overlay = null
	if not is_inside_tree():
		return

	var layer := CanvasLayer.new()
	layer.name = "SessionEndedOverlay"
	layer.layer = 100
	add_child(layer)
	_session_overlay = layer

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Below the centre when the result is showing, so VictoryText stays readable.
	panel.position = Vector2(0, 200 if match_over else 0)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	var label := Label.new()
	label.name = "Message"
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 6)
	box.add_child(label)

	var button := Button.new()
	button.name = "BackToLobby"
	button.text = "Back to lobby"
	button.custom_minimum_size = Vector2(260, 52)
	button.pressed.connect(_on_session_overlay_back_to_lobby)
	box.add_child(button)


## Hands control back to the controller, which closes the peer and reloads the scene.
## Called dynamically: the controller is a plain Node field so this file keeps loading
## without it.
func _on_session_overlay_back_to_lobby() -> void:
	if controller != null and controller.has_method("leave_to_lobby"):
		controller.call("leave_to_lobby")


# ----------------------------
# Queue processing
# ----------------------------

func _drain_queue() -> void:
	_drain_generation += 1
	var generation := _drain_generation
	_processing = true
	while not _queue.is_empty():
		var event: Dictionary = _queue.pop_front()
		await _process_event(event)
		_refresh_zone_power_texts()
	_processing = false
	_emit_idle_if_current(generation)


## Defers the `idle` announcement by one frame and re-checks THEN, not now.
##
## The engine is synchronous: submit_local() routes a batch and then immediately runs the
## bot, which enqueues the next batch. Checking at drain end would pass — the queue really
## is empty at that instant — but by the time a deferred emit landed, the NEXT drain would
## already be halfway through its animations, and the controller would then verify a
## half-updated view against a fully advanced engine. The generation counter is the only
## thing that tells the two apart, so it has to travel with the deferred call.
func _emit_idle_if_current(generation: int) -> void:
	call_deferred("_emit_idle_if_still_current", generation)


func _emit_idle_if_still_current(generation: int) -> void:
	if generation != _drain_generation or _processing or not _queue.is_empty():
		return
	_refresh_controls()
	emit_signal("idle")


func _process_event(event: Dictionary) -> void:
	match event.get("type", &""):
		MatchEvents.TURN_STARTED:
			_on_turn_started(event)
		MatchEvents.PHASE_CHANGED:
			_on_phase_changed(event)
		MatchEvents.TURN_ENDED:
			_on_turn_ended(event)
		MatchEvents.PLAY_OPENED:
			_on_play_opened(event)
		MatchEvents.SESSION_ENDED:
			_on_session_ended(event)
		MatchEvents.MANA_CHANGED:
			_on_mana_changed(event)
		MatchEvents.PRIORITY_CHANGED:
			_on_priority_changed(event)
		MatchEvents.LANE_ASSIGNED:
			_on_lane_assigned(event)
		MatchEvents.LANE_REVEALED:
			_on_lane_revealed(event)
		MatchEvents.LANE_EFFECT:
			_on_lane_effect(event)
		MatchEvents.CARD_DRAWN:
			await _on_card_drawn(event)
		MatchEvents.CARD_CREATED_IN_HAND:
			await _on_card_created_in_hand(event)
		MatchEvents.CARD_SHUFFLED_INTO_DECK:
			await _on_card_shuffled_into_deck(event)
		MatchEvents.CARD_PLAYED:
			_on_card_played(event)
		MatchEvents.PLAY_UNDONE:
			await _on_play_undone(event)
		MatchEvents.INTENT_REJECTED:
			_on_intent_rejected(event)
		MatchEvents.SWAP_STARTED:
			await _on_swap_started(event)
		MatchEvents.CARD_SWAPPED:
			await _on_card_swapped(event)
		MatchEvents.RESOLVE_STARTED:
			await _on_resolve_started(event)
		MatchEvents.CARD_REVEALED:
			await _on_card_revealed(event)
		MatchEvents.POWER_CHANGED:
			_on_power_changed(event)
		MatchEvents.COST_CHANGED:
			_on_cost_changed(event)
		MatchEvents.KEYWORD_ADDED:
			_on_keyword(event, true)
		MatchEvents.KEYWORD_REMOVED:
			_on_keyword(event, false)
		MatchEvents.CARD_SUMMONED:
			await _on_card_summoned(event)
		MatchEvents.CARD_LEVELED_UP:
			await _on_card_leveled_up(event)
		MatchEvents.CARD_RECALLED:
			await _on_card_recalled(event)
		MatchEvents.CARD_KILLED:
			await _on_card_killed(event)
		MatchEvents.DEATH_PREVENTED:
			_on_death_prevented(event)
		MatchEvents.CARD_DISCARDED:
			await _on_card_discarded(event)
		MatchEvents.SPELL_RESOLVED:
			await _on_spell_resolved(event)
		MatchEvents.DEEP_CHANGED:
			pass  # no visual of its own; the aura it feeds arrives as power_changed
		MatchEvents.SUN_DISC_RESTORED:
			pass  # the restored card's own visuals already show it
		MatchEvents.GAME_ENDED:
			_on_game_ended(event)
		_:
			push_warning("MatchPresenter: unhandled event '%s'" % str(event.get("type", "")))


# ----------------------------
# Turn / phase / mana
# ----------------------------

func _on_turn_started(event: Dictionary) -> void:
	_turn = int(event.get("turn", _turn))
	# A new round is a new turn's business: neither player has ended it, neither has any
	# play to take back, and the play_opened that will reopen input belongs to the turn
	# that is starting. Clearing it here is what keeps local_can_act() false until the
	# session layer releases the new turn.
	_ended_turn = {0: false, 1: false}
	_own_undo_count = 0
	_play_open_turn = -1
	_set_turn_text()
	_refresh_controls()


func _on_phase_changed(event: Dictionary) -> void:
	_game_phase = int(event.get("game_phase", _game_phase))
	_round_phase = int(event.get("round_phase", _round_phase))
	_turn = int(event.get("turn", _turn))
	# The engine clears its pending swaps inside the SWAP_LANE phase, right after this
	# event, so the view drops them here too.
	if _round_phase >= MatchState.RoundPhase.SWAP_LANE:
		_pending_swaps.clear()
		_swap_preview.clear()
	_set_turn_text()
	_refresh_controls()


## A player pressed End Turn. The engine emits this for BOTH players (unlike the old
## engine, which said nothing for the player who did not end it), so the view can grey
## out the local button as soon as the local player is done instead of waiting for the
## round to resolve.
func _on_turn_ended(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	if pid < 0 or pid > 1:
		return
	_ended_turn[pid] = true
	_refresh_controls()


## PLAY is open for `turn`: the session layer has released this turn and the local
## player may submit into it. Until this arrives the round is in PLAY as far as the
## PHASE is concerned but closed as far as input is, which is the whole point of the
## presentation_done gate — one peer must never submit into a turn the other is still
## animating.
func _on_play_opened(event: Dictionary) -> void:
	_play_open_turn = int(event.get("turn", _turn))
	_refresh_controls()


## The session ended for a reason the rules do not own. `reason` is a REASON_TEXT key;
## the overlay is the same one the controller's end_session() shows, so a guest that
## learns about a disconnect from the event stream and one that learns about it from
## MatchNet look identical to the player.
func _on_session_ended(event: Dictionary) -> void:
	show_session_ended(session_reason_text(str(event.get("reason", ""))), is_match_over())


func _on_mana_changed(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	_mana_by_player[pid] = [int(event.get("current", 0)), int(event.get("max", 0))]
	if pid == local_player:
		_local_mana_current = int(event.get("current", 0))
		_local_mana_max = int(event.get("max", 0))
		_set_mana_text()
		_glow_hand()


func _on_priority_changed(event: Dictionary) -> void:
	_flip_first = int(event.get("player", -1))
	_set_flip_first_text()


func _set_turn_text() -> void:
	if _turn_text == null:
		return
	if _game_phase == MatchState.GamePhase.GAME_END:
		_turn_text.text = "Game End"
	else:
		_turn_text.text = "Turn: %d" % _turn


func _set_mana_text() -> void:
	if _mana_text != null:
		_mana_text.text = "Mana: %d/%d" % [_local_mana_current, _local_mana_max]


func _set_flip_first_text() -> void:
	if _flip_first_text == null:
		return
	if _flip_first == local_player:
		_flip_first_text.text = "Priority: You"
	elif _flip_first >= 0:
		_flip_first_text.text = "Priority: Opponent"
	else:
		_flip_first_text.text = "Priority: —"


## End Turn and Undo follow the engine, never this file's own idea of the phase.
func _refresh_controls() -> void:
	if controller == null:
		return
	var can_play: bool = bool(controller.call("is_play_phase"))
	var can_undo: bool = bool(controller.call("can_undo"))
	if _end_turn_button != null:
		_end_turn_button.disabled = not can_play
	if _undo_button != null:
		_undo_button.disabled = not can_undo


## The overlay text for a session reason key. An unknown key falls back to the generic
## disconnect message rather than to an empty overlay: every reason this project
## invents means the same thing to the player — the match they were in is over and the
## only way forward is the lobby — and a blank panel with no button would be a dead end.
static func session_reason_text(reason: String) -> String:
	if REASON_TEXT.has(reason):
		return str(REASON_TEXT[reason])
	return "Opponent disconnected"


func _on_game_ended(event: Dictionary) -> void:
	# game_ended is the last event of a match, and the drain carrying it can be superseded
	# before its deferred idle lands (the controller's autoplay submits once more on the
	# way out). Announcing here is what --quit-on-end waits for, and nothing can follow a
	# match that has ended.
	call_deferred("emit_signal", "idle")
	_game_phase = MatchState.GamePhase.GAME_END
	_set_turn_text()
	_refresh_controls()
	if _victory_text == null:
		return
	var winner := int(event.get("winner", -1))
	if winner == -1:
		_victory_text.text = "TIE"
	elif winner == local_player:
		_victory_text.text = "VICTORY"
	else:
		_victory_text.text = "DEFEAT"
	if "visible" in _victory_text:
		_victory_text.visible = true


# ----------------------------
# Lanes
# ----------------------------

## The three lanes were assigned, all still hidden. The event's lane_ids are NOT used:
## they are the engine's full list and naming them here would put an unrevealed lane
## on screen. Every column is created blank instead and filled in by lane_revealed.
func _on_lane_assigned(_event: Dictionary) -> void:
	_lane_ids = ["", "", ""]
	_lanes_revealed = [false, false, false]
	_create_lane_views(_lane_ids)


func _on_lane_revealed(event: Dictionary) -> void:
	var col := int(event.get("col", -1))
	if col < 0 or col >= MatchState.COLUMNS:
		return
	# The id comes from THIS event, which is the only place a lane's name is published.
	_lane_ids[col] = str(event.get("lane_id", ""))
	_lanes_revealed[col] = true
	_reveal_lane_view(col, str(_lane_ids[col]))


## A short flash on the lane that just fired; no state of its own.
func _on_lane_effect(event: Dictionary) -> void:
	if _board == null:
		return
	var lane: Variant = _board.lane_nodes_by_col.get(int(event.get("col", -1)), null)
	if not (lane is Node) or not is_instance_valid(lane):
		return
	var lane_node: Node = lane
	var tween: Tween = lane_node.create_tween()
	tween.tween_property(lane_node, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.15)
	tween.tween_property(lane_node, "modulate", Color(1, 1, 1, 1), 0.35)


func _create_lane_views(lane_ids: Array) -> void:
	if _board == null or not _board.has_method("create_lane_views"):
		return
	_board.call("create_lane_views", lane_ids)


## Fills lane `col` in with `lane_id`'s name, sprite and description. The id is passed
## rather than read back from the board because a hidden column was created blank and
## the board deliberately kept no copy of the engine's hidden ids.
func _reveal_lane_view(col: int, lane_id: String) -> void:
	if _board == null or not _board.has_method("reveal_lane_view"):
		return
	_board.call("reveal_lane_view", col, lane_id)


# ----------------------------
# Hand: draw / create / shuffle away / discard
# ----------------------------

func _on_card_drawn(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	_deck_by_player[pid] = maxi(0, int(_deck_by_player.get(pid, 0)) - 1)
	_apply_deck_counts()
	if pid != local_player:
		# Nothing to show: their hand has no faces. verify() reconciles the size.
		return
	if id < 0:
		return
	# The engine always draws into index 0, so the new card lands on the left.
	_spawn_hand_card(id, str(event.get("card_id", "")), DRAW_SPAWN_POSITION, CARD_DRAW_SPEED)



func _on_card_created_in_hand(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	if pid != local_player:
		# Nothing to show: their hand has no faces. verify() reconciles the size.
		return
	if id < 0:
		return
	_spawn_hand_card(id, str(event.get("card_id", "")),
		get_viewport().get_visible_rect().size / 2.0, CARD_CREATE_SPEED)


## Puts a card into our hand as a fresh face.
##
## The PERMANENT cost modifier survives a trip through the deck: Janna's Updraft discounts
## a card, shuffles it away and draws it again, and MatchOps.draw never clears
## CardState.cost_modifier. Rebuilding the entry from the printed cost alone would drop
## that discount, so any modifier this presenter already learned about is carried over.
func _spawn_hand_card(id: int, card_id: String, from: Vector2, speed: float) -> void:
	var carried: Dictionary = _entries.get(id, {})
	_release_entry(id)
	var entry := _make_entry(id, card_id, local_player, ViewLocation.HAND)
	if not carried.is_empty():
		entry["cost_mod"] = int(carried.get("cost_mod", 0))
		entry["power_mod"] = int(carried.get("power_mod", 0))
		entry["cost"] = maxi(0, _base_cost(card_id) + int(entry["cost_mod"]))
		entry["power"] = _base_power(card_id) + int(entry["power_mod"])
	_spawn_hand_node(id, entry, from)
	# The node must carry the same modifiers, or its Cost/Power labels would show the
	# printed values while the model (and the engine) show the discounted ones.
	_apply_modifiers(entry)
	if _hand != null:
		_hand.add_card_to_hand(entry["node"], speed)
	_play_anim(entry["node"], &"card_flip")
	entry["node"].is_in_hand = true
	entry["node"].hide_glow()
	_glow_node(entry["node"])
	_local_hand.insert(0, id)
	_sync_hand_nodes()


## Builds the node, parents it to CardManager (so hover, drag and the right-click preview
## keep working) and lays out the hand, exactly like Deck.draw_card did.
func _spawn_hand_node(id: int, entry: Dictionary, from: Vector2) -> void:
	var node := _create_node(str(entry["card_id"]), int(entry["owner"]))
	if node == null:
		_entries.erase(id)
		return
	node.position = from
	entry["node"] = node
	_instance_by_node[node] = id
	_card_manager.add_child(node)
	node.name = "Card"


func _on_card_shuffled_into_deck(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	_deck_by_player[pid] = int(_deck_by_player.get(pid, 0)) + 1
	_apply_deck_counts()
	if pid != local_player:
		return
	var entry: Dictionary = _entries.get(id, {})
	var node: Variant = entry.get("node", null)
	if node is Node and is_instance_valid(node):
		if _hand != null:
			_hand.remove_card_from_hand(node, false)
		node.is_in_hand = false
		if node.has_method("play_discard_dissolve"):
			await _await_dissolve(node, SHUFFLE_DISSOLVE)
		_release_node(id, node)
	_drop_from_hand_model(id)
	entry["location"] = ViewLocation.GONE


func _on_card_discarded(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	if pid != local_player:
		return
	var entry: Dictionary = _entries.get(id, {})
	var node: Variant = entry.get("node", null)
	if node is Node and is_instance_valid(node):
		# Dissolve in place first, then slide the rest of the hand across, like
		# CardManager.discard_card_from_hand did.
		if _hand != null:
			_hand.remove_card_from_hand(node, false)
		node.is_in_hand = false
		if node.has_method("play_discard_dissolve"):
			await _await_dissolve(node, SHUFFLE_DISSOLVE)
		_release_node(id, node)
	_drop_from_hand_model(id)
	entry["location"] = ViewLocation.GONE


# ----------------------------
# Playing / undoing
# ----------------------------

func _on_card_played(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	if pid != local_player or id < 0:
		return
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		entry = _make_entry(id, str(event.get("card_id", "")), pid, ViewLocation.BOARD)
	var node := _ensure_node(id, entry, str(event.get("card_id", "")))
	if node == null:
		return

	_drop_from_hand_model(id)
	_place_in_zone(entry, int(event.get("col", -1)), int(event.get("slot", -1)))
	entry["resolved"] = false
	entry["face_down"] = false
	# The engine pushed this play onto the local undo stack, one entry per play. Counting
	# it here is what lets can_undo() answer for a guest, which has no MatchState: the
	# guest's own plays are the only ones that ever reach this view.
	_own_undo_count += 1
	node.is_in_hand = false
	node.hide_glow()
	node.z_index = 0
	_refresh_collider(id)
	await get_tree().process_frame


## play_undone carries hand_after, the engine's own hand order once every card is back, so
## the view never has to re-derive it.
func _on_play_undone(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	if pid != local_player:
		return
	# An undo takes back EVERY play of the turn and empties the engine's stack.
	_own_undo_count = 0
	for raw: Variant in event.get("instance_ids", []):
		var id := int(raw)
		var entry: Dictionary = _entries.get(id, {})
		if entry.is_empty():
			continue
		var node: Variant = entry.get("node", null)
		_move_board_card_to_hand_view(id, node)
		_swap_preview.erase(id)
		entry["location"] = ViewLocation.HAND
		entry["resolved"] = false
		entry["face_down"] = false
		if node is Node and is_instance_valid(node):
			node.is_in_hand = true
			node.scale = Vector2(HAND_CARD_SCALE, HAND_CARD_SCALE)
			node.z_index = HAND_CARD_Z
			_refresh_collider(id)

	var hand_after: Variant = event.get("hand_after", [])
	_local_hand.clear()
	if hand_after is Array:
		for raw: Variant in hand_after:
			_local_hand.append(int(raw))
	else:
		# Older MatchEvents without hand_after: keep the model order, it is unchanged.
		for raw: Variant in event.get("instance_ids", []):
			_local_hand.append(int(raw))
	_sync_hand_nodes()
	if _hand != null:
		_hand.update_hand_position(0.3)
	_glow_hand()


# ----------------------------
# Swaps
# ----------------------------

## The preview: the card slides to where it would land, but the model keeps it at its
## origin — the engine only commits the move at SWAP_LANE.
func _on_swap_started(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	if pid != local_player or id < 0:
		return
	_pending_swaps.append({"instance_id": id, "to_col": int(event.get("to_col", -1))})
	var node := node_for(id)
	if node == null:
		return
	var destination := _first_free_slot_position(int(event.get("to_col", -1)), pid)
	if destination == Vector2.INF:
		return
	_swap_preview[id] = destination
	node.z_index = DRAG_Z
	var tween := node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position", destination, SWAP_PREVIEW_SPEED)
	await _race([tween.finished], SWAP_PREVIEW_SPEED + 1.0)
	node.z_index = 0


## The old swap dance: snap the card back to its origin slot, then tween it across.
func _on_card_swapped(event: Dictionary) -> void:
	var id := int(event.get("instance_id", -1))
	var from_col := int(event.get("from_col", -1))
	var to_col := int(event.get("to_col", -1))
	var slot := int(event.get("slot", -1))
	_erase_pending_swap(id)
	_swap_preview.erase(id)
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var node := node_for(id)
	var owner := int(entry["owner"])
	# Where the model says the card is now: its origin, which the preview may have moved.
	var origin := _slot_position(int(entry["col"]), owner, int(entry["slot"]))

	_place_in_zone(entry, to_col, slot)
	_sync_zone(from_col, owner)
	if node == null:
		return
	var destination := _slot_position(to_col, owner, slot)
	if destination == Vector2.INF:
		destination = node.position
	if origin != Vector2.INF:
		node.position = origin
	node.z_index = DRAG_Z
	var tween := node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position", destination, SWAP_DURATION)
	await _race([tween.finished], SWAP_DURATION + 1.0)
	node.z_index = 0
	# The card kept its Elusive on the way across, so the click area it needs is the one
	# it had: re-derive it from the model rather than assume every earlier path ran.
	_refresh_collider(id)


func _erase_pending_swap(id: int) -> void:
	for i in range(_pending_swaps.size() - 1, -1, -1):
		if int(_pending_swaps[i].get("instance_id", -1)) == id:
			_pending_swaps.remove_at(i)
			return


# ----------------------------
# Resolve
# ----------------------------

## Everyone's plays show face-down for a beat: the opponent's are spawned here for the
## first time, ours already sit on the board and just get their back raised.
func _on_resolve_started(event: Dictionary) -> void:
	var plays: Variant = event.get("plays", [])
	if plays is Array:
		for raw: Variant in plays:
			if raw is Dictionary:
				_prepare_resolve_play(raw)
	await get_tree().create_timer(RESOLVE_PAUSE).timeout


func _prepare_resolve_play(play: Dictionary) -> void:
	var id := int(play.get("instance_id", -1))
	var owner := int(play.get("player", -1))
	var col := int(play.get("col", -1))
	var slot := int(play.get("slot", -1))
	var entry: Dictionary = _entries.get(id, {})
	var node: Variant = entry.get("node", null)
	if owner != local_player and not bool(entry.get("resolved", false)):
		# An opponent's play is secret until it is revealed, even when this instance is
		# already known: a lane effect (Rockfall Path's Chip) can put a face-up card on the
		# board in the same round the opponent plays theirs, and reusing that identity here
		# would show the opponent's card before card_revealed does. A card the engine has
		# ALREADY resolved (the summoned Chip) keeps its identity: resolve_started only
		# ever lists cards that have not been revealed yet, so re-hiding it would be wrong.
		if node is Node and is_instance_valid(node):
			entry["card_id"] = ""
			entry["face_down"] = true
			entry["resolved"] = false
			_place_in_zone(entry, col, slot)
			node.set_card_back_z_index(CARD_BACK_Z)
			return
		entry = _make_entry(id, "", owner, ViewLocation.BOARD)
		var stand_in := _create_node("", owner)
		if stand_in == null:
			_entries.erase(id)
			return
		entry["node"] = stand_in
		_instance_by_node[stand_in] = id
		_card_manager.add_child(stand_in)
		stand_in.name = "Card"
		entry["cost"] = 0
		_place_in_zone(entry, col, slot)
		stand_in.set_card_back_z_index(CARD_BACK_Z)
		entry["face_down"] = true
		entry["resolved"] = false
		return
	if node is Node and is_instance_valid(node):
		# Our own play: it is on the board already, only the back goes up.
		_place_in_zone(entry, col, slot)
		node.set_card_back_z_index(CARD_BACK_Z)
		entry["face_down"] = true
		return


func _on_card_revealed(event: Dictionary) -> void:
	var id := int(event.get("instance_id", -1))
	var card_id := str(event.get("card_id", ""))
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		entry = _make_entry(id, card_id, int(event.get("player", -1)), ViewLocation.BOARD)
	var node := _ensure_node(id, entry, card_id)
	if node == null:
		return
	entry["card_id"] = card_id
	# A card can be discounted while it sits in a hand (Janna's Updraft, a cost-reduction
	# aura) and that PERMANENT modifier survives being played, so the revealed cost is base
	# + cost_mod rather than the printed base.
	entry["cost"] = maxi(0, _base_cost(card_id) + int(entry["cost_mod"]))
	entry["power"] = _base_power(card_id) + int(entry["power_mod"])
	_apply_revealed_values(entry, event)
	_place_in_zone(entry, int(event.get("col", -1)), int(event.get("slot", -1)))
	entry["resolved"] = true
	entry["face_down"] = false
	_apply_modifiers(entry)
	# The reveal is where a card's real identity lands: its card_id and its final
	# keyword list are only known from here, so this is the first moment Elusive is
	# knowable for a card that sat face down.
	_refresh_collider(id)
	await _await_anim(node, &"card_flip_play", ANIMATION_LIMIT)
	node.hide_card_back()
	await get_tree().create_timer(CARD_PAUSE).timeout


## Takes the FINAL power / cost / keywords a card_revealed or card_summoned event
## carries, when it carries them at all.
##
## These keys are optional (M5a): the event omits power and cost at their -1 sentinel
## and keywords when empty, so a 5-argument call still produces the old event and this
## is a no-op for it. When they ARE present they are the engine's own totals, and they
## are the only correct source for a viewer: a face-down card's cost and keywords never
## reached this view as events, so base + the modifiers the view happens to know about
## would be a guess, while a power buff applied while the card was face down is simply
## unknowable. Deriving the modifiers from the final totals (total - printed base) keeps
## the node's coloured labels and the model in step.
func _apply_revealed_values(entry: Dictionary, event: Dictionary) -> void:
	var card_id := str(entry.get("card_id", ""))
	if event.has("power"):
		entry["power"] = int(event["power"])
		entry["power_mod"] = int(event["power"]) - _base_power(card_id)
	if event.has("cost"):
		entry["cost"] = int(event["cost"])
		entry["cost_mod"] = int(event["cost"]) - _base_cost(card_id)
	if event.has("keywords"):
		entry["keywords"] = _runtime_keywords(card_id, event["keywords"])
		_push_runtime_keywords(entry)


## The RUNTIME half of the engine's keyword list: what the event reported minus the
## keywords the card is printed with. CardState.keywords() is the printed list followed
## by the runtime one, and _verify_board compares in that same order, so the two halves
## have to be stored apart.
func _runtime_keywords(card_id: String, engine_keywords: Array) -> Array:
	var runtime: Array = []
	for raw: Variant in engine_keywords:
		if not runtime.has(str(raw)):
			runtime.append(str(raw))
	for printed: Variant in _card_data_keywords(card_id):
		runtime.erase(str(printed))
	return runtime


## Brings the node's runtime keyword badges in line with the model entry, which a
## reveal replaces wholesale (a face-down card that resolves to a Stunned Elusive has
## never had either badge, and one whose stun expired while it was hidden has to lose
## it). Diffed against what the node already carries rather than cleared, because
## Card.gd exposes only add/remove_runtime_keyword and this file must not assume a
## clear_runtime_keywords that Group C does not own.
func _push_runtime_keywords(entry: Dictionary) -> void:
	var node := node_for(int(entry.get("instance_id", -1)))
	if node == null or not node.has_method("add_runtime_keyword"):
		return
	var wanted: Array = entry.get("keywords", [])
	if "runtime_keywords" in node:
		for old: Variant in node.runtime_keywords:
			if not wanted.has(str(old)) and node.has_method("remove_runtime_keyword"):
				node.remove_runtime_keyword(str(old))
	for keyword: Variant in wanted:
		node.add_runtime_keyword(str(keyword))


# ----------------------------
# Stats and keywords
# ----------------------------

## power_changed carries the new TOTAL, so the node's modifier is total - base and the aura
## modifier goes back to zero: the label then matches the engine by construction, whichever
## mix of permanent and aura buffs produced it.
func _on_power_changed(event: Dictionary) -> void:
	var id := int(event.get("instance_id", -1))
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var new_power := int(event.get("new_power", 0))
	entry["power_mod"] = new_power - _base_power(str(entry["card_id"]))
	entry["power"] = new_power
	var node := node_for(id)
	if node == null:
		return
	if "power_modifier" in node:
		node.power_modifier = entry["power_mod"]
	if "aura_power_modifier" in node:
		node.aura_power_modifier = 0
	_refresh_power_label(node, entry)
	_glow_node(node)


func _on_cost_changed(event: Dictionary) -> void:
	var id := int(event.get("instance_id", -1))
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var new_cost := int(event.get("new_cost", 0))
	entry["cost_mod"] = new_cost - _base_cost(str(entry["card_id"]))
	entry["cost"] = new_cost
	var node := node_for(id)
	if node == null:
		return
	if "cost_modifier" in node:
		node.cost_modifier = entry["cost_mod"]
	if "aura_cost_modifier" in node:
		node.aura_cost_modifier = 0
	_refresh_cost_label(node)
	_glow_node(node)


func _on_keyword(event: Dictionary, added: bool) -> void:
	var id := int(event.get("instance_id", -1))
	var keyword := str(event.get("keyword", ""))
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var keywords: Array = entry["keywords"]
	if added:
		if not keywords.has(keyword):
			keywords.append(keyword)
	elif keywords.has(keyword):
		keywords.erase(keyword)
	var node := node_for(id)
	if node == null:
		return
	# The Stun swirl lives inside these two, exactly as the old game had it.
	if added:
		if node.has_method("add_runtime_keyword"):
			node.add_runtime_keyword(keyword)
	elif node.has_method("remove_runtime_keyword"):
		node.remove_runtime_keyword(keyword)
	# Elusive can arrive or leave at runtime (Janna's Quickdraw): the click area has to
	# follow it, because a node whose collider is stale either cannot be dragged off its
	# lane or offers a swap start that can_start_swap will refuse.
	_refresh_collider(id)


func _on_death_prevented(event: Dictionary) -> void:
	var node := node_for(int(event.get("instance_id", -1)))
	if node == null:
		return
	var tween := node.create_tween()
	tween.tween_property(node, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.15)
	tween.tween_property(node, "modulate", Color(1, 1, 1, 1), 0.3)


# ----------------------------
# Summon / level up / recall / kill
# ----------------------------

## Covers both a brand-new card landing face-up (Chip, the Sun Disc) and a card that went
## from our hand straight onto the board (Sion's put into play).
func _on_card_summoned(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	var card_id := str(event.get("card_id", ""))
	var col := int(event.get("col", -1))
	var slot := int(event.get("slot", -1))
	if id < 0:
		return
	var from_hand: bool = false
	if pid == local_player:
		from_hand = _local_hand.has(id)
		if from_hand:
			_drop_from_hand_model(id)
	# An opponent summon never came from a hand we track: their hand has no faces here.
	from_hand = false
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		entry = _make_entry(id, card_id, pid, ViewLocation.BOARD)
	var node := _ensure_node(id, entry, card_id)
	if node == null:
		return
	if from_hand and _hand != null:
		_hand.remove_card_from_hand(node, false)
	_sync_hand_nodes()
	entry["card_id"] = card_id
	# A card summoned straight out of our hand (Sion's put into play) keeps the permanent
	# modifiers it already had, exactly as it would if it had been played normally.
	entry["cost"] = maxi(0, _base_cost(card_id) + int(entry["cost_mod"]))
	entry["power"] = _base_power(card_id) + int(entry["power_mod"])
	entry["keywords"] = []
	# Same as a reveal: when the event carries the final values they win over anything
	# this view reconstructed. A summon is public for both players, so an opponent's
	# summoned card is the one case where the view would otherwise show a wrong number
	# it had no way to correct.
	_apply_revealed_values(entry, event)
	entry["resolved"] = true
	entry["face_down"] = false
	_place_in_zone(entry, col, slot)
	node.hide_card_back()
	node.is_in_hand = false
	node.hide_glow()
	_apply_modifiers(entry)
	_refresh_collider(id)


func _on_card_leveled_up(event: Dictionary) -> void:
	var id := int(event.get("instance_id", -1))
	var new_id := str(event.get("new_card_id", ""))
	var silent := bool(event.get("silent", false))
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var node := node_for(id)
	entry["card_id"] = new_id
	# Base cost and base power both change with the level, but the PERMANENT modifier
	# survives the level-up in the engine (CardState.cost_modifier is untouched by
	# MatchOps.level_up). Recomputing from base + cost_mod — not from base alone — is what
	# keeps a discounted card discounted instead of snapping back to its printed cost.
	entry["cost"] = maxi(0, _base_cost(new_id) + int(entry["cost_mod"]))
	if node == null:
		return
	node.card_id = new_id
	# The base Power just changed; the modifiers stay, so the shown power follows the engine.
	entry["power"] = _base_power(new_id) + int(entry["power_mod"])
	if silent or int(entry["location"]) != ViewLocation.BOARD:
		# A secondary copy, or one still in hand: repopulate and flip, no fly-to-centre.
		CardDatabase.populate_card_visuals(node, _card_data(new_id))
		_play_anim(node, &"card_flip")
		_refresh_keyword_display(node)
	elif node.has_method("play_level_up_animation"):
		# Bounded: Card.play_level_up_animation awaits animation_finished, which never
		# fires if the card is freed mid-spin (killed during the same resolve). Racing it
		# against a timer keeps one dead node from stalling the whole queue.
		await _await_level_up(node, new_id)
	# Both branches repopulate the card (the animation does it mid-spin), which resets Cost
	# and Power to the new level's printed values; the modifiers have to go back on.
	_refresh_keyword_display(node)
	_apply_modifiers(entry)
	# The new level prints its own keyword set (Janna1 -> Janna2 gains Elusive),
	# so the click area has to be re-derived from the new card_id, not kept.
	_refresh_collider(id)


func _on_card_recalled(event: Dictionary) -> void:
	var pid := int(event.get("player", -1))
	var id := int(event.get("instance_id", -1))
	var entry: Dictionary = _entries.get(id, {})
	if pid != local_player:
		# Their client owns that hand, so the card just leaves our board.
		# The zone must be captured BEFORE _remove_from_zone_model() clears the entry's col:
		# read afterwards it is already -1, the sync silently does nothing, and the recalled
		# card's node stays registered in the board zone — a face-up ghost left behind for a
		# card that went back to the opponent's hand. _move_board_card_to_hand_view is the
		# shared cleanup and captures it in that order for us.
		#
		# Once the card is off the board and back in a hand we cannot see, the view can no
		# longer vouch for what is public about it: it may be drawn, discarded, or played
		# face-down again. Dropping the identity and the resolution flag keeps the model
		# honest — a stale "Chip, resolved" would make verify report a card the engine has
		# deliberately hidden, and would leak it face-up if it came back to the board.
		#
		# Clearing card_slot_is_in here is a no-op in practice: the node is released
		# immediately below, so no drag can ever start from it. It goes through the shared
		# helper rather than being special-cased so the zone bookkeeping exists in exactly
		# one place.
		_move_board_card_to_hand_view(id, entry.get("node", null))
		_swap_preview.erase(id)
		_release_node(id, entry.get("node", null))
		entry["card_id"] = ""
		entry["resolved"] = false
		entry["face_down"] = false
		entry["keywords"] = []
		entry["location"] = ViewLocation.GONE
		return
	if entry.is_empty():
		return
	var node := node_for(id)
	_move_board_card_to_hand_view(id, node)
	entry["location"] = ViewLocation.HAND
	entry["resolved"] = false
	entry["face_down"] = false
	if node == null:
		return
	if _hand != null:
		_hand.remove_card_from_hand(node, false)
	node.is_resolved = false
	node.z_index = DRAG_Z
	_refresh_collider(id)
	_local_hand.insert(0, id)
	_sync_hand_nodes()
	var scale_tween := node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	scale_tween.tween_property(node, "scale", Vector2(HAND_CARD_SCALE, HAND_CARD_SCALE), RECALL_DURATION)
	if _hand != null:
		_hand.add_card_to_hand(node, RECALL_DURATION)
	await _race([scale_tween.finished], RECALL_DURATION + 1.0)
	if not is_instance_valid(node):
		return
	node.z_index = HAND_CARD_Z
	node.is_in_hand = true
	_glow_node(node)


func _on_card_killed(event: Dictionary) -> void:
	var id := int(event.get("instance_id", -1))
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var node := node_for(id)
	var owner := int(entry["owner"])
	var col := int(entry["col"])
	if node != null:
		await _play_or_fade(node, &"card_killed", 0.5)
	_remove_from_zone_model(id)
	_swap_preview.erase(id)
	_release_node(id, node)
	entry["location"] = ViewLocation.GONE
	entry["face_down"] = false
	_sync_zone(col, owner)


func _on_spell_resolved(event: Dictionary) -> void:
	var id := int(event.get("instance_id", -1))
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var node := node_for(id)
	var owner := int(entry["owner"])
	var col := int(entry["col"])
	_remove_from_zone_model(id)
	_swap_preview.erase(id)
	entry["location"] = ViewLocation.GONE
	entry["face_down"] = false
	_sync_zone(col, owner)
	# The dissolve has to happen BEFORE the free: play_discard_dissolve tweens a
	# ShaderMaterial on the node, and awaiting it on an already queue_free()d node never
	# completes — its tween dies with the node and `finished` is never emitted, which
	# stalled the whole drain (seed 3 hung here).
	if node != null and is_instance_valid(node) and node.has_method("play_discard_dissolve"):
		await _await_dissolve(node, SPELL_DISSOLVE)
	_release_node(id, node)


# ----------------------------
# Rejections
# ----------------------------

func _on_intent_rejected(event: Dictionary) -> void:
	if int(event.get("player", -1)) != local_player:
		return
	var id := int(event.get("instance_id", -1))
	_toast(str(REASON_TEXT.get(str(event.get("reason", "")), "That move is not allowed")))
	_refresh_controls()
	if id < 0:
		return
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var node := node_for(id)
	if node == null:
		return
	if str(event.get("intent_type", "")) == str(MatchIntents.SWAP_CARD):
		_snap_back_to_origin(entry, node)
	elif _local_hand.has(id):
		# A refused play: the card never left the hand, so put it back where it belongs.
		_return_node_to_hand(node)


func _snap_back_to_origin(entry: Dictionary, node: Node) -> void:
	_swap_preview.erase(int(entry["instance_id"]))
	var origin := _slot_position(int(entry["col"]), int(entry["owner"]), int(entry["slot"]))
	if origin != Vector2.INF:
		node.position = origin
	node.scale = Vector2(BOARD_CARD_SCALE, BOARD_CARD_SCALE)
	node.z_index = 0


func _return_node_to_hand(node: Node) -> void:
	node.scale = Vector2(HAND_CARD_SCALE, HAND_CARD_SCALE)
	node.z_index = HAND_CARD_Z
	if _hand != null:
		_hand.add_card_to_hand(node, 0.2)
	node.is_in_hand = true
	_glow_node(node)


# ----------------------------
# Nodes
# ----------------------------

## Builds a Card node for `card_id` ("" = a face-down stand-in, which uses the plain card
## scene) exactly like Deck.draw_card and CardManager.create_card_in_hand did.
func _create_node(card_id: String, owner: int) -> Node:
	var data := _card_data(card_id)
	var scene: PackedScene = CardDatabase.get_card_scene(data)
	if scene == null:
		push_warning("MatchPresenter: no card scene for '%s'" % card_id)
		return null
	var node: Node = scene.instantiate()
	if node.get_script() == null:
		node.set_script(CardDatabase.get_card_script(data))
	node.set("card_id", card_id)
	node.set("owner_player_id", owner)
	CardDatabase.populate_card_visuals(node, data)
	return node


## The node this instance should be showing, creating it or swapping the scene when a
## face-down stand-in turns out to be a Spell or a Landmark.
func _ensure_node(id: int, entry: Dictionary, card_id: String) -> Node:
	var current := node_for(id)
	if current != null and _script_path(current) == _script_path_for(card_id):
		entry["card_id"] = card_id
		# populate_card_visuals() paints the labels but never writes the node's own
		# card_id, so a face-down stand-in that turns out to be the same card type would
		# keep showing the identity it was born with (empty) while the model says otherwise.
		current.set("card_id", card_id)
		CardDatabase.populate_card_visuals(current, _card_data(card_id))
		# Repainting resets Cost and Power to the printed values, so the model's modifiers
		# have to go back on or the labels stop matching what the engine reports.
		_apply_modifiers(entry)
		return current
	var replacement := _create_node(card_id, int(entry.get("owner", -1)))
	if replacement == null:
		return current
	if current != null:
		replacement.position = current.position
		replacement.set("z_index", int(current.get("z_index")))
		replacement.scale = current.scale
		_copy_modifiers(current, replacement)
		_release_node(id, current)
	replacement.set("owner_player_id", int(entry.get("owner", -1)))
	entry["node"] = replacement
	entry["card_id"] = card_id
	_instance_by_node[replacement] = id
	_card_manager.add_child(replacement)
	replacement.name = "Card"
	return replacement


func _copy_modifiers(from_node: Node, to_node: Node) -> void:
	for property: String in ["power_modifier", "aura_power_modifier", "cost_modifier",
			"aura_cost_modifier", "runtime_keywords", "is_in_hand", "is_resolved"]:
		if property in from_node and property in to_node:
			to_node.set(property, from_node.get(property))


## Writes the model's permanent modifiers onto the card node and repaints both labels.
##
## populate_card_visuals() resets Cost and Power to the printed values, so any card that is
## repainted after gaining a modifier (a level-up, a re-drawn Updraft card, a stand-in that
## turned out to be a real card) needs them put back or its labels stop matching the model.
func _apply_modifiers(entry: Dictionary) -> void:
	var node: Variant = entry.get("node", null)
	if not (node is Node) or not is_instance_valid(node):
		return
	if "power_modifier" in node:
		node.power_modifier = int(entry.get("power_mod", 0))
	if "aura_power_modifier" in node:
		node.aura_power_modifier = 0
	if "cost_modifier" in node:
		node.cost_modifier = int(entry.get("cost_mod", 0))
	if "aura_cost_modifier" in node:
		node.aura_cost_modifier = 0
	_refresh_power_label(node, entry)
	_refresh_cost_label(node)


func _release_entry(id: int) -> void:
	_release_node(id, _entries.get(id, {}).get("node", null))


## Frees a node and drops it from the reverse index. The model entry is kept: the card
## still exists in the engine, it just has no face on screen.
func _release_node(id: int, node: Variant) -> void:
	if node is Node and is_instance_valid(node):
		_instance_by_node.erase(node)
		node.queue_free()
	var entry: Dictionary = _entries.get(id, {})
	if entry.get("node", null) == node:
		entry["node"] = null


func _set_collider(node: Node, enabled: bool) -> void:
	var collider := node.get_node_or_null("Area2D/CollisionShape2D")
	if collider != null:
		collider.disabled = not enabled


## The Power label, green above base and red below, like Card.get_power_display_text.
func _refresh_power_label(node: Node, entry: Dictionary) -> void:
	var card_id := str(entry.get("card_id", ""))
	var data := _card_data(card_id)
	var value := _base_power(card_id) + int(entry.get("power_mod", 0))
	entry["power"] = value
	if node == null:
		return
	var label := node.get_node_or_null("CardFront/Power")
	if label == null:
		return
	if not data.has("Power"):
		# Spells and landmarks have no Power at all; apply_power_visual hides the label.
		label.text = ""
		entry["power"] = 0
		return
	var modifier := int(entry.get("power_mod", 0))
	if modifier > 0:
		label.text = "[color=green]%d[/color]" % value
	elif modifier < 0:
		label.text = "[color=red]%d[/color]" % value
	else:
		label.text = str(value)


## CardManager._update_cost_label's colours, without calling into old game logic.
func _refresh_cost_label(node: Node) -> void:
	if node == null or not node.has_method("get_current_cost"):
		return
	var label := node.get_node_or_null("CardFront/Cost")
	if label == null:
		return
	var current: int = node.get_current_cost()
	var modifier: int = int(node.get("cost_modifier")) if "cost_modifier" in node else 0
	if modifier < 0:
		label.text = "[color=green]%d[/color]" % current
	elif modifier > 0:
		label.text = "[color=red]%d[/color]" % current
	else:
		label.text = str(current)


func _refresh_keyword_display(node: Node) -> void:
	if node != null and node.has_method("_refresh_keyword_display"):
		node.call("_refresh_keyword_display")


func _glow_node(node: Node) -> void:
	if node != null and node.has_method("update_glow"):
		node.update_glow(_local_mana_current)


func _glow_hand() -> void:
	if _hand == null:
		return
	for card: Node in _hand.player_hand:
		_glow_node(card)


func _play_anim(node: Node, anim: StringName) -> bool:
	var player := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(anim):
		return false
	player.play(anim)
	return true


## Waits for an animation, but never forever.
##
## `animation_finished` does not fire when the node is freed while the animation is still
## running (a card killed mid-flip, a spell dissolved while flipping), and an unbounded
## await there would stall the drain loop for good: the queue never empties, `idle` is
## never emitted and `--quit-on-end` waits forever. The cap is generous — longer than any
## animation in the card scenes — so it only ever fires in the pathological case.
func _await_anim(node: Node, anim: StringName, limit: float) -> bool:
	var player := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(anim):
		return false
	player.play(anim)
	await _race([player.animation_finished], limit)
	return true


## Returns once `signal` fires or `limit` seconds pass, whichever comes first.
##
## Only Signals may be passed: GDScript evaluates an Array literal eagerly, so putting a
## coroutine call in one would start it without an await (a hard error). Start a coroutine
## on its own line, connect to it, then race [] against the timer.
func _race(signal_list: Array, limit: float) -> void:
	var done := [false]
	for awaited: Signal in signal_list:
		var one_shot := func() -> void:
			if not done[0]:
				done[0] = true
		awaited.connect(one_shot, CONNECT_ONE_SHOT)
	if done[0]:
		return
	await get_tree().create_timer(limit).timeout



## Dissolves a card, but never waits for good.
##
## Card.play_discard_dissolve awaits its own tween, and that tween dies with the node: a card
## freed or reparented mid-dissolve never emits `finished`, so an unbounded await there wedges
## the drain loop for good (seed 3 hung exactly this way in spell_resolved). The node is freed
## right after either way, so giving up late costs a few frames of fade and nothing else.
func _await_dissolve(node: Node, duration: float) -> void:
	node.play_discard_dissolve(duration)
	await _race([], duration + 1.0)


## The old kill flow's fallback: the animation when the scene has one, a plain fade when
## it does not (spells and landmarks).
func _play_or_fade(node: Node, anim: StringName, fade: float) -> void:
	if await _await_anim(node, anim, fade + 1.0):
		return
	if not is_instance_valid(node):
		return
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 0.0, fade)
	await _race([tween.finished], fade + 1.0)


## Runs Card.play_level_up_animation and waits for it, but never for good.
##
## That coroutine awaits `animation_finished` mid-spin, which never fires when the card is
## freed while the animation runs (a card killed during the same resolve). An unbounded
## await there stalls the whole drain: later events pile up, `idle` is never emitted and
## `--quit-on-end` waits forever. Polling the AnimationPlayer keeps the normal timing and
## only ever costs the full budget when the card is already dead.
func _await_level_up(node: Node, new_card_id: String) -> void:
	node.play_level_up_animation(new_card_id)
	var elapsed := 0.0
	var spin_started := false
	while elapsed < LEVEL_UP_LIMIT:
		if not is_instance_valid(node):
			return
		var player := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if player != null:
			if player.is_playing():
				spin_started = true
			elif spin_started:
				return
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1


# ----------------------------
# Zones
# ----------------------------

## Writes `entry` into the engine zone (col, owner) at `slot`, then rebuilds that zone's
## Board.cards_by_zone list so reposition_cards_in_zone puts every card on the slot the
## engine gave it.
func _place_in_zone(entry: Dictionary, col: int, slot: int) -> void:
	var id := int(entry["instance_id"])
	var owner := int(entry["owner"])
	var previous_col := int(entry["col"])
	var zone_key := Vector2i(col, owner)
	if not _zones.has(zone_key):
		_zones[zone_key] = []
	var ids: Array = _zones[zone_key]
	var at := ids.find(id)
	if at >= 0:
		ids.remove_at(at)
	var index: int = ids.size() if slot < 0 else mini(maxi(slot, 0), ids.size())
	ids.insert(index, id)
	entry["col"] = col
	entry["slot"] = index
	entry["location"] = ViewLocation.BOARD
	var node: Variant = entry.get("node", null)
	if node is Node and is_instance_valid(node):
		node.is_in_hand = false
		node.hide_glow()
		var place_scale: float = SPELL_ZONE_SCALE if _is_spell_zone(col) else BOARD_CARD_SCALE
		node.scale = Vector2(place_scale, place_scale)
	_sync_zone(previous_col, owner)
	_sync_zone(col, owner)


## Takes a card out of its zone and COMPACTS the zone behind it.
##
## The engine's zones are compact (MatchState.remove_from_zone) and it emits no event for
## the cards that shift up, so the model has to renumber them itself — otherwise every card
## behind a dead one keeps a slot the engine has already given away.
func _remove_from_zone_model(id: int) -> void:
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var col := int(entry["col"])
	var owner := int(entry["owner"])
	var zone_key := Vector2i(col, owner)
	var ids: Array = _zones.get(zone_key, [])
	ids.erase(id)
	for index in ids.size():
		var shifted: Dictionary = _entries.get(int(ids[index]), {})
		shifted["slot"] = index
	entry["col"] = -1
	entry["slot"] = -1


## The shared board -> hand view cleanup for a card the engine took back off the board
## (an undone play, our own card recalled by an ability): drop it from the model zone,
## rebuild that zone so the slot it vacated is marked free again, and clear the node's
## card_slot_is_in.
##
## The zone MUST be captured before _remove_from_zone_model, which clears entry["col"]:
## read afterwards it is -1, _sync_zone silently does nothing, and the returned card stays
## registered in Board.cards_by_zone with its slot still marked occupied — a ghost that
## blocks the drop the next play makes into that lane.
##
## card_slot_is_in matters as much: CardManager._start_drag_engine reads it to decide
## whether a click starts a board swap or a hand drag, so a node that went back to the
## hand still pointing at a slot is still treated as a board card and can_start_swap
## refuses it.
## `node` is Variant, not Node, for the same reason _release_node's is: a caller can hand
## over an entry whose node was freed earlier in this same batch, and a typed parameter
## would raise at the call boundary BEFORE the is_instance_valid guard below could run.
func _move_board_card_to_hand_view(id: int, node: Variant) -> void:
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty():
		return
	var col := int(entry["col"])
	var owner := int(entry["owner"])
	_remove_from_zone_model(id)
	if col >= MatchState.SPELL_COL:
		_sync_zone(col, owner)
	if node is Node and is_instance_valid(node):
		node.card_slot_is_in = null


## Rebuilds one board zone from the model and lets the old repositioner lay the cards
## out. Swap previews are re-applied afterwards: the model keeps a previewing card at
## its origin, so a plain reposition would yank it back mid-gesture.
##
## The model is keyed by the engine's absolute (col, owner); the Board is addressed by
## the screen (col, row), which is the same thing only for the local player.
func _sync_zone(col: int, owner: int) -> void:
	if _board == null or col < MatchState.SPELL_COL:
		return
	var ids: Array = _zones.get(Vector2i(col, owner), [])
	var nodes: Array = []
	for raw: Variant in ids:
		var node := node_for(int(raw))
		if node != null:
			nodes.append(node)
	var board_zone := _board_zone(col, owner)
	_board.cards_by_zone[board_zone] = nodes
	_board.reposition_cards_in_zone(board_zone)
	for id: Variant in _swap_preview:
		var entry: Dictionary = _entries.get(int(id), {})
		if entry.is_empty() or int(entry.get("col", -1)) != col:
			continue
		if int(entry.get("owner", -1)) != owner:
			continue
		var preview := node_for(int(id))
		if preview != null:
			preview.position = _swap_preview[id]


## The six lane power labels, summed from the model: resolved cards only, like
## GameManager._get_zone_total_power.
func _refresh_zone_power_texts() -> void:
	if _board == null or not _board.has_method("update_zone_power_texts"):
		return
	var power_by_zone := {}
	for col in MatchState.COLUMNS:
		for owner in 2:
			var total := 0
			for raw: Variant in _zones.get(Vector2i(col, owner), []):
				var entry: Dictionary = _entries.get(int(raw), {})
				if entry.is_empty() or not bool(entry.get("resolved", false)):
					continue
				if not _card_data(str(entry.get("card_id", ""))).has("Power"):
					continue
				total += int(entry.get("power", 0))
			power_by_zone[_board_zone(col, owner)] = total
	_board.call("update_zone_power_texts", power_by_zone)


func _is_spell_zone(col: int) -> bool:
	return col == MatchState.SPELL_COL


## The screen row absolute `owner`'s cards sit on: 1 (bottom) for the local player,
## 0 (top) for the opponent. This and _board_zone() are the ONLY places an absolute
## engine id becomes a screen row — offline the human is 1 so this is the identity, and
## on a host it is what puts the host's own cards on the bottom instead of the top.
func _row(owner: int) -> int:
	return 1 if owner == local_player else 0


## The Board zone Vector2i for engine column `col` and absolute `owner`. Matches
## BoardGeneration.SPELL_ZONE_ALLIED / SPELL_ZONE_ENEMY for the spell column.
func _board_zone(col: int, owner: int) -> Vector2i:
	return Vector2i(col, _row(owner))


## (col, owner) -> Array mapping engine slot index to the index in
## slots_by_zone that holds it. Measured from the live slot positions rather than
## assumed, because the TOP row fills its slot list in reverse. _slot_order stays keyed
## by the engine's (col, owner); only the Board lookup inside is a screen row.
func _build_slot_order() -> void:
	_slot_order.clear()
	if _board == null:
		return
	for col in range(MatchState.SPELL_COL, MatchState.COLUMNS):
		for owner in 2:
			var zone := Vector2i(col, owner)
			var row := _row(owner)
			var slots: Array = _board.slots_by_zone.get(_board_zone(col, owner), [])
			var order: Array = []
			order.resize(slots.size())
			for s in slots.size():
				var fallback: int = s if (col == MatchState.SPELL_COL or row == 1) \
					else (slots.size() - 1 - s)
				order[s] = fallback
				if col == MatchState.SPELL_COL:
					continue
				var want: Vector2 = _board.get_slot_position(col, row, s)
				for i in slots.size():
					if slots[i].position.is_equal_approx(want):
						order[s] = i
						break
			_slot_order[zone] = order


func _slot_for(col: int, owner: int, slot: int) -> Variant:
	if _board == null or slot < 0 or col < MatchState.SPELL_COL:
		return null
	var slots: Array = _board.slots_by_zone.get(_board_zone(col, owner), [])
	var order: Array = _slot_order.get(Vector2i(col, owner), [])
	if slot >= order.size() or slot >= slots.size():
		return null
	var index := int(order[slot])
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func _slot_position(col: int, owner: int, slot: int) -> Vector2:
	var slot_node: Variant = _slot_for(col, owner, slot)
	if slot_node is Node and is_instance_valid(slot_node):
		return slot_node.position
	return Vector2.INF


## Where a swap preview would drop the card: the first free slot in that column.
func _first_free_slot_position(col: int, owner: int) -> Vector2:
	if _board == null:
		return Vector2.INF
	var slots: Array = _board.slots_by_zone.get(_board_zone(col, owner), [])
	for slot_node in slots:
		if is_instance_valid(slot_node) and not bool(slot_node.card_in_slot):
			return slot_node.position
	return Vector2.INF


# ----------------------------
# Hand model
# ----------------------------

## Takes a card out of the hand model and from PlayerHand, then re-lays the rest.
func _drop_from_hand_model(id: int) -> void:
	if not _local_hand.has(id):
		return
	_local_hand.erase(id)
	var node := node_for(id)
	if node != null and _hand != null and node in _hand.player_hand:
		_hand.remove_card_from_hand(node, false)
	_sync_hand_nodes()
	if _hand != null:
		_hand.update_hand_position(0.1)


## Makes PlayerHand.player_hand hold exactly our hand, in the engine's order.
func _sync_hand_nodes() -> void:
	if _hand == null:
		return
	var nodes: Array = []
	for id in _local_hand:
		var node := node_for(id)
		if node != null:
			nodes.append(node)
	_hand.player_hand = nodes


func _apply_deck_counts() -> void:
	if _deck == null:
		return
	var count := int(_deck_by_player.get(local_player, 0))
	if _deck.has_method("set_view_count"):
		_deck.call("set_view_count", count)
		return
	# Fallback for a Deck.gd without set_view_count().
	var label := _deck.get_node_or_null("RichTextLabel")
	if label != null:
		label.text = str(count)


# ----------------------------
# Model helpers
# ----------------------------

func _make_entry(id: int, card_id: String, owner: int, location: int) -> Dictionary:
	var entry := {
		"instance_id": id,
		"node": null,
		"card_id": card_id,
		"owner": owner,
		"location": location,
		"col": -1,
		"slot": -1,
		"resolved": false,
		"face_down": false,
		"power": _base_power(card_id),
		"power_mod": 0,
		"cost": _base_cost(card_id),
		"cost_mod": 0,
		"keywords": [],
	}
	_entries[id] = entry
	return entry


func _build_from_snapshot_row(row: Dictionary) -> void:
	var id := int(row.get("instance_id", -1))
	if id < 0:
		return
	var owner := int(row.get("owner", -1))
	var col := int(row.get("col", -1))
	var resolved := bool(row.get("resolved", false))
	var shown: Variant = row.get("card_id", null)
	var card_id := str(shown) if shown != null else ""
	var face_down := owner != local_player and not resolved
	var entry := _make_entry(id, card_id, owner, ViewLocation.BOARD)
	var node := _create_node(card_id, owner)
	if node == null:
		return
	entry["node"] = node
	# A hidden opponent card has cost = null in M5a (and keywords = null): the engine
	# is saying "you do not know this", not "this is zero". int(null) is a hard error,
	# so both are read through the sentinel first — an unknown cost falls back to the
	# printed value, which is what a face-down stand-in shows anyway, and unknown
	# keywords are an empty set, exactly like a card that has no runtime keywords.
	var shown_cost: Variant = row.get("cost", null)
	entry["cost"] = int(shown_cost) if shown_cost != null \
		else _base_cost(card_id)
	var shown_power: Variant = row.get("power", null)
	entry["power"] = int(shown_power) if shown_power != null else 0
	entry["power_mod"] = entry["power"] - _base_power(card_id)
	entry["keywords"] = []
	_instance_by_node[node] = id
	_card_manager.add_child(node)
	node.name = "Card"
	if face_down:
		node.set_card_back_z_index(CARD_BACK_Z)
	entry["face_down"] = face_down
	entry["resolved"] = resolved
	_place_in_zone(entry, col, int(row.get("slot", -1)))


func _card_data(card_id: String) -> Dictionary:
	if card_id == "":
		return {}
	return CardDatabase.CARDS.get(card_id, {})


func _base_power(card_id: String) -> int:
	return int(_card_data(card_id).get("Power", 0))


func _base_cost(card_id: String) -> int:
	return int(_card_data(card_id).get("Cost", 0))


func _card_data_keywords(card_id: String) -> Array:
	return _card_data(card_id).get("Keyword", [])


func _script_path(node: Node) -> String:
	var script: Variant = node.get_script()
	return str(script.resource_path) if script != null else ""


func _script_path_for(card_id: String) -> String:
	if _card_data(card_id).is_empty():
		return ""
	return str(CardDatabase.get_card_script(_card_data(card_id)).resource_path)


# ----------------------------
# Toast
# ----------------------------

## A small centred message under the cards that fades out. Created on first use.
func _toast(message: String) -> void:
	if _card_manager == null:
		return
	if _toast_label == null or not is_instance_valid(_toast_label):
		var label := Label.new()
		label.name = "EngineToast"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 26)
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 6)
		label.size = Vector2(700, 40)
		label.position = Vector2(610, 1010)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 50
		_card_manager.add_child(label)
		_toast_label = label
	_toast_label.text = message
	_toast_label.modulate = Color(1, 1, 1, 1)
	var tween := _toast_label.create_tween()
	tween.tween_interval(TOAST_FADE_TIME - 0.5)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


# ----------------------------
# verify
# ----------------------------

func _verify_scalars(snapshot: Dictionary, problems: Array[String]) -> void:
	var model := {
		"turn": _turn,
		"game_phase": _game_phase,
		"round_phase": _round_phase,
		"flip_first": _flip_first,
		"local": local_player,
	}
	for key: String in model:
		if not snapshot.has(key):
			continue
		var expected := int(snapshot[key])
		if int(model[key]) != expected:
			problems.append("%s view=%d engine=%d" % [key, int(model[key]), expected])


## A lane is right when the view agrees on BOTH whether it is revealed and which lane it
## is: the id is the part a hidden-info leak would actually expose, and a view that
## showed a lane the snapshot still calls "" would pass a revealed-only check.
func _verify_lanes(snapshot: Dictionary, problems: Array[String]) -> void:
	for lane: Dictionary in snapshot.get("lanes", []):
		var col := int(lane.get("col", -1))
		var expected := bool(lane.get("revealed", false))
		var got: bool = col >= 0 and col < _lanes_revealed.size() and bool(_lanes_revealed[col])
		if got != expected:
			problems.append("lane %d revealed view=%s engine=%s" % [col, got, expected])
		var engine_id := str(lane.get("lane_id", ""))
		var view_id := "" if col < 0 or col >= _lane_ids.size() else str(_lane_ids[col])
		if view_id != engine_id:
			problems.append("lane %d id view='%s' engine='%s'" % [col, view_id, engine_id])


func _verify_players(snapshot: Dictionary, problems: Array[String]) -> void:
	for entry: Dictionary in snapshot.get("players", []):
		var pid := int(entry.get("player", -1))
		var mana: Array = _mana_by_player.get(pid, [0, 0])
		var view_mana := int(mana[0])
		var view_max := int(mana[1])
		if view_mana != int(entry.get("current_mana", 0)):
			problems.append("player %d mana view=%d engine=%d" % [
				pid, view_mana, int(entry.get("current_mana", 0))])
		if view_max != int(entry.get("max_mana", 0)):
			problems.append("player %d max mana view=%d engine=%d" % [
				pid, view_max, int(entry.get("max_mana", 0))])
		var view_deck := int(_deck_by_player.get(pid, 0))
		if view_deck != int(entry.get("deck_count", 0)):
			problems.append("player %d deck count view=%d engine=%d" % [
				pid, view_deck, int(entry.get("deck_count", 0))])
		# ended_turn is public (TURN_ENDED reaches both viewers), so BOTH players are
		# checked, not just the local one: the opponent's flag is what the view uses to
		# know the round is waiting on the other peer.
		if entry.has("ended_turn"):
			var view_ended := bool(_ended_turn.get(pid, false))
			if view_ended != bool(entry["ended_turn"]):
				problems.append("player %d ended_turn view=%s engine=%s" % [
					pid, view_ended, bool(entry["ended_turn"])])
		# The engine's own undo depth for the local player. A mismatch here means the
		# view's _own_undo_count drifted, which would leave Undo enabled with nothing to
		# undo (or hide it when there is).
		if pid == local_player and entry.has("undo_count"):
			if _own_undo_count != int(entry["undo_count"]):
				problems.append("undo_count view=%d engine=%d" % [
					_own_undo_count, int(entry["undo_count"])])

func _verify_hands(snapshot: Dictionary, problems: Array[String]) -> void:
	for entry: Dictionary in snapshot.get("players", []):
		var pid := int(entry.get("player", -1))
		var hand: Variant = entry.get("hand", [])
		if pid != local_player:
			if hand is Array:
				continue
			# The opponent's hand is only a COUNT in the snapshot, and their plays are
			# redacted away entirely (MatchEvents.redact_for returns null for an opponent's
			# CARD_PLAYED), so the moment a card leaves their hand is simply not in the event
			# stream this presenter is allowed to see. The count cannot be derived from the
			# stream, so it is reconciled from the authoritative snapshot instead of being
			# asserted against it — a mismatch here would be reporting our own blindness.
			_opponent_hand_count = int(hand)
			continue
		if not (hand is Array):
			continue
		var engine_hand: Array = hand
		var engine_ids: Array = []
		for card: Dictionary in engine_hand:
			engine_ids.append(int(card.get("instance_id", -1)))
		var view_ids := _local_hand.duplicate()
		if view_ids != engine_ids:
			problems.append("hand order view=%s engine=%s" % [str(view_ids), str(engine_ids)])
		for i in mini(view_ids.size(), engine_hand.size()):
			var card: Dictionary = engine_hand[i]
			var id := int(view_ids[i])
			var model: Dictionary = _entries.get(id, {})
			if model.is_empty():
				problems.append("hand #%d (%d): view has no entry, engine=%s" % [
					i, id, str(card.get("card_id", ""))])
				continue
			var view_card := str(model.get("card_id", ""))
			if view_card != str(card.get("card_id", "")):
				problems.append("hand #%d (%d): view=%s engine=%s" % [
					i, id, view_card, str(card.get("card_id", ""))])
			var view_cost := int(model.get("cost", 0))
			if view_cost != int(card.get("cost", 0)):
				problems.append("hand cost #%d (%d): view=%d engine=%d" % [
					i, id, view_cost, int(card.get("cost", 0))])




func _verify_board(snapshot: Dictionary, problems: Array[String]) -> void:
	for row: Dictionary in snapshot.get("board", []):
		var id := int(row.get("instance_id", -1))
		var owner := int(row.get("owner", -1))
		var col := int(row.get("col", -1))
		var slot := int(row.get("slot", -1))
		var where := "(%d,%d) slot%d" % [col, owner, slot]
		var shown: Variant = row.get("card_id", null)
		if shown == null:
			# The engine hides an opponent card that has not resolved. The view is ALLOWED to
			# be missing it entirely — an opponent's play is redacted away, so a face-down
			# replay stays invisible until resolve_started — but it must never be showing
			# that instance face-up. So only a model entry that still claims an identity is a
			# problem; an entry that knows nothing is the correct "I can't see this" state.
			var hidden: Dictionary = _entries.get(id, {})
			if not hidden.is_empty() and not str(hidden.get("card_id", "")).is_empty():
				problems.append("board %s #%d: view=%s engine=<hidden>" % [
					where, id, str(hidden["card_id"])])
			continue
		var model: Dictionary = _entries.get(id, {})
		if model.is_empty():
			problems.append("board %s #%d: view is missing, engine=%s" % [
				where, id, str(shown)])
			continue
		if int(model.get("owner", -1)) != owner:
			problems.append("board %s #%d: owner view=%d engine=%d" % [
				where, id, int(model.get("owner", -1)), owner])
		if int(model.get("col", -1)) != col:
			problems.append("board %s #%d: col view=%d engine=%d" % [
				where, id, int(model.get("col", -1)), col])
		if int(model.get("slot", -1)) != slot:
			problems.append("board %s #%d: slot view=%d engine=%d" % [
				where, id, int(model.get("slot", -1)), slot])
		if bool(model.get("resolved", false)) != bool(row.get("resolved", false)):
			problems.append("board %s #%d: resolved view=%s engine=%s" % [
				where, id, bool(model.get("resolved", false)), bool(row.get("resolved", false))])
		var view_card := str(model.get("card_id", ""))
		if view_card != str(shown):
			problems.append("board %s #%d: view=%s engine=%s" % [where, id, view_card, str(shown)])
		var power: Variant = row.get("power", null)
		var view_power := int(model.get("power", 0))
		if power != null and view_power != int(power):
			problems.append("power #%d: view=%d engine=%d" % [id, view_power, int(power)])
		# cost and keywords are null on a hidden row in M5a (an opponent's face-down card
		# keeps no identity, and a cost is an identity). A null means the engine is
		# telling this viewer it knows nothing, which is not something to compare — the
		# same way a null card_id is not a mismatch above. Comparing it as 0 would report
		# a leak fix working correctly as a bug.
		var cost: Variant = row.get("cost", null)
		var view_cost := int(model.get("cost", 0))
		if cost != null and view_cost != int(cost):
			problems.append("cost #%d: view=%d engine=%d" % [id, view_cost, int(cost)])
		var shown_keywords: Variant = row.get("keywords", null)
		if shown_keywords != null:
			var engine_keywords: Array = []
			engine_keywords.assign(shown_keywords)
			var view_keywords: Array = []
			view_keywords.assign(_card_data_keywords(view_card))
			view_keywords.append_array(model.get("keywords", []))
			if engine_keywords != view_keywords:
				problems.append("keywords #%d: view=%s engine=%s" % [
					id, str(view_keywords), str(engine_keywords)])


func _verify_pending_swaps(snapshot: Dictionary, problems: Array[String]) -> void:
	var expected: Array = []
	for raw: Variant in snapshot.get("pending_swaps_own", []):
		if raw is Dictionary:
			expected.append({
				"instance_id": int(raw.get("instance_id", -1)),
				"to_col": int(raw.get("to_col", -1)),
			})
	if expected.size() != _pending_swaps.size():
		problems.append("pending swaps view=%s engine=%s" % [str(_pending_swaps), str(expected)])
		return
	for i in expected.size():
		var view_swap: Dictionary = _pending_swaps[i]
		if int(view_swap.get("instance_id", -1)) != int(expected[i].get("instance_id", -1)) \
				or int(view_swap.get("to_col", -1)) != int(expected[i].get("to_col", -1)):
			problems.append("pending swap #%d: view=%s engine=%s" % [
				i, str(view_swap), str(expected[i])])


## The nodes themselves must agree with the model entry they carry.
func _verify_nodes(problems: Array[String]) -> void:
	for raw_id: Variant in _entries:
		var id := int(raw_id)
		var entry: Dictionary = _entries[id]
		var node := node_for(id)
		if node == null:
			# A card that left the board keeps its model entry without a face; that is fine.
			if int(entry.get("location", ViewLocation.GONE)) == ViewLocation.BOARD:
				problems.append("board #%d: view model has no node" % id)
			continue
		var node_card := str(node.get("card_id"))
		if node_card != str(entry.get("card_id", "")):
			problems.append("node #%d card_id: view=%s engine=%s" % [
				id, node_card, str(entry.get("card_id", ""))])
		var back := node.get_node_or_null("CardBack")
		var face_down := bool(entry.get("face_down", false))
		if back != null and bool(back.visible) != face_down:
			problems.append("node #%d card back: view=%s engine=%s" % [
				id, bool(back.visible), face_down])
		if face_down:
			continue
		var power_label := node.get_node_or_null("CardFront/Power")
		# A Spell or Landmark has no Power at all: CardDatabase.apply_power_visual hides the
		# label for it, so an empty label here is correct and parsing it as a number would
		# read -1 and look like a mismatch.
		var has_power := _card_data(str(entry.get("card_id", ""))).has("Power")
		if power_label != null and bool(power_label.visible) and has_power:
			var shown_power := _label_number(str(power_label.text))
			var model_power := int(entry.get("power", 0))
			if shown_power != model_power:
				problems.append("node #%d power label: view=%d engine=%d" % [
					id, shown_power, model_power])
		var cost_label := node.get_node_or_null("CardFront/Cost")
		if cost_label != null and node.has_method("get_current_cost"):
			var shown_cost := _label_number(str(cost_label.text))
			var node_cost := int(node.get_current_cost())
			if shown_cost != node_cost:
				problems.append("node #%d cost label: view=%d engine=%d" % [
					id, shown_cost, node_cost])


## The number behind a label.
##
## The old game wraps a changed stat in BBCode ("[color=red]-1[/color]"), so the tags have
## to go before the digits can be read — and a debuffed card really is negative, so the sign
## matters. Collecting "leading digits" out of the raw text instead would read the "1" out
## of "red" and turn -1 into 1, which is exactly the false mismatch this avoided.
func _label_number(text: String) -> int:
	var stripped := ""
	var inside_tag := false
	for i in text.length():
		var ch := text[i]
		if ch == "[":
			inside_tag = true
		elif ch == "]":
			inside_tag = false
		elif not inside_tag:
			stripped += ch
	var number := ""
	for i in stripped.length():
		var ch := stripped[i]
		if ch == "-" and number.is_empty():
			number += ch
		elif ch >= "0" and ch <= "9":
			number += ch
		elif not number.is_empty():
			break
	return int(number) if number.is_valid_int() else -1

