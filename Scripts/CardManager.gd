extends Node2D

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const DEFAULT_CARD_MOVE_SPEED = 0.1
const DEFAULT_CARD_SCALE = 0.2
const CARD_BIGGER_SCALE = 0.21
const CARD_SMALLER_SCALE = 0.15
const CARD_PAUSE_TIMER = 0.7
const CARD_BOARD_Z_INDEX = 0

var screen_size
var card_being_dragged
var is_hovering_on_card
var player_hand_reference
var board_reference
var game_manager_reference
var current_player_id: int = 1  # 0 = top player, 1 = bottom player (default)
var flip_first_player_id: int = -1  # Synced from GameManager
var played_cards_order: Array = []  # Cards played this turn only (cleared after resolve)
var undo_stack: Array = []          # [{card, hand_index, mana_cost, zone_key, slot}] — cleared after resolve or undo
var undo_button: Button
var all_cards_in_play_order: Array = []  # Historical: all cards that ever entered the board (append-only, never removed)
var opponent_played_cards: Array = []  # Cards opponent played (face-down until resolve)
var _pending_opponent_cards: Array = []  # Deferred opponent card data [{card_id, zone_col, zone_row}] — see queue_opponent_card_play
var killed_cards: Array = []  # Tracks all cards killed during the game [{card_id, owner_player_id, killer_player_id, killer_card_id}]
var summoned_cards: Array = []  # Tracks all cards that entered the board [{card_id, owner_player_id, was_played_from_hand}]
var created_cards: Array = []  # Tracks all cards created (not from starting deck) [{card_id, owner_player_id, creator_player_id, creator_card_id, created_at_turn}]
var recalled_cards: Array = []  # Tracks all recalls triggered by cards [{card_id, owner_player_id, recaller_player_id, recaller_card_id}]
var discarded_cards: Array = []  # Tracks all cards discarded [{card_id, owner_player_id, discarded_by_card_id, discarded_at_turn}]
var drawn_cards: Array = []  # Tracks all cards drawn from deck [{card_id, owner_player_id, turn}]
var player_state: Dictionary = {}  # Per-player persistent state: {player_id: {"is_deep": bool, ...}}
var _level_up_in_progress: bool = false  # Global lock: only one level-up animation plays at a time
var _level_up_pending: int = 0           # Count of _perform_level_up calls still alive (waiting or animating)
var permanently_leveled_up: Dictionary = {}  # champion Name → current highest card_id (e.g. "Azir" → "Azir2")
var _is_swap_drag: bool = false           # True when dragging an Elusive board card for a lane swap
var _swap_drag_origin_slot = null         # The slot the Elusive card came from
var _swap_drag_origin_zone: Vector2i = Vector2i(-1, -1)  # The zone the Elusive card came from


# ── Engine mode (offline / LAN on the Match engine) ──────────────────────────
# Every branch below is inert unless a MatchController has started; `--engine=old` keeps
# running the code above untouched. In engine mode this script only turns input into
# intents and asks the PRESENTER whether the move is allowed. It deliberately does NOT
# read controller.state: a guest holds no MatchState, so every gate here has to be
# answerable from the view. Offline is unaffected (local 1, the view answers true for
# exactly the same cases the engine would).

const TOAST_FADE_TIME := 1.5
const TOAST_FONT_SIZE := 26
const TOAST_COLOR := Color(1.0, 0.85, 0.3, 1.0)


## The MatchController node when the game runs on the Match engine, else null.
func _match_controller() -> Node:
	if MatchController.active():
		return get_node_or_null("/root/Main/MatchController")
	return null


## The MatchPresenter node (view only) when the game runs on the Match engine.
func _match_presenter() -> Node:
	if _match_controller():
		return get_node_or_null("/root/Main/MatchPresenter")
	return null


## The engine instance id a card node stands for, or -1 when the presenter has none for
## it (a preview card, a card the view only knows face-down, or no presenter at all).
func _engine_instance_id(card) -> int:
	var presenter := _match_presenter()
	if presenter == null:
		return -1
	return int(presenter.call("instance_of", card))


## The screen row the LOCAL player's cards sit on. The board has no absolute ids: this
## script's old engine branches compared the drop row against local_player_id, which
## put a host's own plays on the wrong half of the board once the host became absolute
## player 0. Presenting local == bottom is the whole point of the mapping, so the row
## is a constant here rather than something derived per drop.
const ENGINE_OWN_ROW := 1


## Engine mode gate for swap-dragging a board card: the card must be ours, resolved and
## Elusive, not stunned, with no swap queued yet — the presenter's view model answers
## all of that, which is what lets a guest with no MatchState drag its own Elusive.
## Stun is deliberately NOT excluded: the engine rejects a stunned swap with reason
## "stunned", which the presenter turns into a toast and a snap back. The presenter
## does check it (so a stunned card does not start a drag), and the engine stays the
## authority on the final word.
func _engine_can_start_swap_drag(card) -> bool:
	var presenter := _match_presenter()
	if presenter == null:
		return false
	var instance_id := _engine_instance_id(card)
	if instance_id < 0:
		return false
	return bool(presenter.call("can_start_swap", instance_id))


## Small centred message under the cards, fading out (engine mode only).
func _show_toast(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TOAST_FONT_SIZE)
	label.add_theme_color_override("font_color", TOAST_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(700, 40)
	label.position = Vector2(610, 1010)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 50
	add_child(label)
	var tween := create_tween()
	tween.tween_interval(TOAST_FADE_TIME - 0.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	await tween.finished
	label.queue_free()


func _notify_zone_power_changed() -> void:
	"""Recalculate auras via AuraSystem, then ask GameManager to refresh zone power labels."""
	AuraSystem.recalculate_auras()
	LevelUpManager.check_conditional_buff_level_ups()
	if game_manager_reference and game_manager_reference.has_method("_update_zone_power_display"):
		game_manager_reference._update_zone_power_display()


func _wait_for_level_up() -> void:
	"""Suspend the current coroutine until any in-progress level-up animation finishes.
	Call this after any ability or level-up check that may have started _perform_level_up
	so the next card's ability doesn't fire while the animation is still playing."""
	while _level_up_in_progress or _level_up_pending > 0:
		await get_tree().create_timer(0.05).timeout


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_reference = $"../PlayerHand"
	board_reference = $"../Board"
	game_manager_reference = $"../GameManager"
	$"../InputManager".connect("left_mouse_button_released", on_left_click_released)
	game_manager_reference.mana_changed.connect(_on_mana_changed)
	undo_button = $Undo
	undo_button.pressed.connect(_on_undo_button_pressed)
	undo_button.disabled = true
	# Initialize per-player state (extensible: add new keys here as needed)
	player_state = {
		0: {"is_deep": false},
		1: {"is_deep": false}
	}

func _on_mana_changed(player_id: int, current_mana: int, _max_mana: int) -> void:
	if player_id != current_player_id:
		return
	for card in player_hand_reference.player_hand:
		if is_instance_valid(card) and card.has_method("update_glow"):
			card.update_glow(current_mana)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if card_being_dragged:
		var mouse_pos = get_global_mouse_position()
		card_being_dragged.position = Vector2(clamp(mouse_pos.x, 0, screen_size.x), clamp(mouse_pos.y, 0, screen_size.y))
			
func start_drag(card):
	# Engine mode: only the play phase and the swap gate are checked here — mana,
	# stun and every other rule are the engine's to answer.
	if _match_controller():
		_start_drag_engine(card)
		return

	# Only allow dragging during PLAY phase
	if game_manager_reference and game_manager_reference.has_method("is_play_phase"):
		if not game_manager_reference.is_play_phase():
			return

	if card.card_slot_is_in:
		# Board card: only resolved Elusive cards owned by the local player can be swap-dragged
		if not card.is_resolved:
			return
		if not _has_elusive_keyword(card):
			return
		if card.owner_player_id != current_player_id:
			return
		if SwapLaneManager.has_pending_swap(card):
			return
		if StunManager.has_stun(card):  # Stunned cards cannot self-swap
			return
		# Initiate swap drag: temporarily free the origin slot
		_is_swap_drag = true
		_swap_drag_origin_slot = card.card_slot_is_in
		_swap_drag_origin_zone = board_reference.get_zone_for_slot(_swap_drag_origin_slot)
		_swap_drag_origin_slot.card_in_slot = false
		card.card_slot_is_in = null
		board_reference.remove_card_from_zone(_swap_drag_origin_zone, card)
	else:
		_is_swap_drag = false

	card_being_dragged = card
	card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card.z_index = 10


func _start_drag_engine(card) -> void:
	"""Engine mode drag start. The board model belongs to the presenter, so the
	origin slot is NOT freed here — only the drag bookkeeping is set up."""
	var controller := _match_controller()
	if not controller.is_play_phase():
		return
	if card.card_slot_is_in:
		if not _engine_can_start_swap_drag(card):
			return
		_is_swap_drag = true
		_swap_drag_origin_slot = card.card_slot_is_in
		_swap_drag_origin_zone = board_reference.get_zone_for_slot(_swap_drag_origin_slot)
	else:
		_is_swap_drag = false
	card_being_dragged = card
	card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card.z_index = 10
	
func _return_card_to_hand():
	"""Reset card scale/z_index and return it to the player's hand."""
	card_being_dragged.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card_being_dragged.z_index = 2
	player_hand_reference.add_card_to_hand(card_being_dragged, DEFAULT_CARD_MOVE_SPEED)
	card_being_dragged = null

func cancel_active_drag() -> void:
	"""Cancel any card currently being dragged and return it to hand (or origin slot for swap drags)."""
	if card_being_dragged:
		if _is_swap_drag:
			_return_swap_card_to_origin()
		else:
			_return_card_to_hand()

func _has_elusive_keyword(card) -> bool:
	"""Return true if this card has the Elusive keyword."""
	var card_data = CardDatabase.CARDS.get(str(card.card_id), null)
	if not card_data:
		return false
	return "Elusive" in card_data.get("Keyword", [])


func _finish_swap_drag() -> void:
	"""Handle releasing a swap drag. Validates the destination and either registers
	the swap (card moves to dest slot temporarily) or cancels (card snaps to origin)."""
	if _match_controller():
		_finish_swap_drag_engine()
		return

	_is_swap_drag = false
	var dest_slot = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	if dest_slot:
		var dest_zone = board_reference.get_zone_for_slot(dest_slot)
		# Valid destination: same player row, different column, owned by local player
		if dest_zone != Vector2i(-1, -1) \
				and dest_zone.y == _swap_drag_origin_zone.y \
				and dest_zone.x != _swap_drag_origin_zone.x \
				and board_reference.is_zone_owned_by_player(dest_zone, current_player_id):
			# Move card to destination temporarily (animate at SWAP_LANE phase)
			card_being_dragged.scale = Vector2(CARD_SMALLER_SCALE, CARD_SMALLER_SCALE)
			card_being_dragged.card_slot_is_in = dest_slot
			dest_slot.card_in_slot = true
			board_reference.add_card_to_zone(dest_zone, card_being_dragged)
			card_being_dragged.position = dest_slot.position
			card_being_dragged.z_index = CARD_BOARD_Z_INDEX
		SwapLaneManager.register_swap(
			card_being_dragged,
			_swap_drag_origin_zone, _swap_drag_origin_slot,
			dest_zone, dest_slot,
			current_player_id
		)
		board_reference.reposition_cards_in_zone(_swap_drag_origin_zone)
		board_reference.reposition_cards_in_zone(dest_zone)
		card_being_dragged = null
		_swap_drag_origin_slot = null
		_swap_drag_origin_zone = Vector2i(-1, -1)
		return
	# Invalid destination — return card to its origin slot
	_return_swap_card_to_origin()


func _return_swap_card_to_origin() -> void:
	"""Snap the swap-dragged card back to its origin slot without any tween."""
	card_being_dragged.scale = Vector2(CARD_SMALLER_SCALE, CARD_SMALLER_SCALE)
	_swap_drag_origin_slot.card_in_slot = true
	card_being_dragged.card_slot_is_in = _swap_drag_origin_slot
	board_reference.add_card_to_zone(_swap_drag_origin_zone, card_being_dragged)
	card_being_dragged.position = _swap_drag_origin_slot.position
	card_being_dragged.z_index = CARD_BOARD_Z_INDEX
	card_being_dragged = null
	_is_swap_drag = false
	_swap_drag_origin_slot = null
	_swap_drag_origin_zone = Vector2i(-1, -1)


func _finish_swap_drag_engine() -> void:
	"""Engine mode swap release. The card itself never moves here: a valid drop
	becomes a swap_card intent (the engine keeps the card where it is until the
	SWAP_LANE phase and the presenter animates it), an invalid one snaps back."""
	_is_swap_drag = false
	var controller := _match_controller()
	var instance_id := _engine_instance_id(card_being_dragged)
	var dest_slot = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	var dest_zone: Vector2i = board_reference.get_zone_for_slot(dest_slot) if dest_slot else Vector2i(-1, -1)
	# Valid destination: our own row, a different column, a lane (not the spell zone).
	# The row is the SCREEN row, so ENGINE_OWN_ROW and not local_player_id — a host is
	# absolute player 0 and its cards belong on the bottom row all the same.
	if instance_id >= 0 \
			and dest_zone != Vector2i(-1, -1) \
			and dest_zone.y == ENGINE_OWN_ROW \
			and dest_zone.x != _swap_drag_origin_zone.x \
			and dest_zone.x >= 0:
		card_being_dragged = null
		_swap_drag_origin_slot = null
		_swap_drag_origin_zone = Vector2i(-1, -1)
		controller.submit_local(MatchIntents.swap_card(instance_id, dest_zone.x))
		return
	# Invalid destination — return card to its origin slot
	_return_swap_card_to_origin()


func finish_drag():
	if _is_swap_drag:
		_finish_swap_drag()
		return
	# Engine mode: the drop becomes a play_card intent, the engine validates it.
	if _match_controller():
		_finish_drag_engine()
		return
	var card_slot_found = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	if card_slot_found:
		# Check zone ownership before placing
		var zone_key = board_reference.get_zone_for_slot(card_slot_found)
		if zone_key != Vector2i(-1, -1):
			# Validate that the zone belongs to the current player
			if not board_reference.is_zone_owned_by_player(zone_key, current_player_id):
				print("Cannot place card in opponent's zone!")
				_return_card_to_hand()
				return

		# Card type vs zone restriction
		var _drag_data = CardDatabase.CARDS.get(card_being_dragged.card_id, {})
		var _drag_type: String = _drag_data.get("Type", "")
		if board_reference.is_spell_zone(zone_key):
			if _drag_type != "Spell":
				print("Only spell cards can be played in the spell zone!")
				_return_card_to_hand()
				return
		else:
			if _drag_type == "Spell":
				print("Spell cards must be played in the spell zone!")
				_return_card_to_hand()
				return

		# Check lane placement restriction (e.g. Noxkraya Arena turn 5) — not for spell zones
		if not board_reference.is_spell_zone(zone_key) and LaneManager.is_placement_restricted(zone_key):
			print("Cards must be played in the active lane this turn (Noxkraya Arena)!")
			_return_card_to_hand()
			return

		# Validate it's currently PLAY phase (turn system)
		if game_manager_reference and game_manager_reference.has_method("is_play_phase"):
			if not game_manager_reference.is_play_phase():
				print("Cannot play cards right now (not in PLAY phase).")
				_return_card_to_hand()
				return

		# Mana check + spend
		var card_cost := 0
		if card_being_dragged and card_being_dragged.has_method("get_current_cost"):
			card_cost = card_being_dragged.get_current_cost()
		if card_cost > 0 and game_manager_reference and game_manager_reference.has_method("spend_player_mana"):
			var ok = game_manager_reference.spend_player_mana(current_player_id, card_cost)
			if not ok:
				print("Not enough mana to play card. Need: ", card_cost)
				_return_card_to_hand()
				return
		
		var place_scale: float = board_reference.SPELL_SLOT_SCALE if board_reference.is_spell_zone(zone_key) else CARD_SMALLER_SCALE
		card_being_dragged.scale = Vector2(place_scale, place_scale)
		card_being_dragged.z_index = CARD_BOARD_Z_INDEX
		card_being_dragged.card_slot_is_in = card_slot_found
		var _hand_index_before_remove: int = player_hand_reference.player_hand.find(card_being_dragged)
		player_hand_reference.remove_card_from_hand(card_being_dragged)
		card_being_dragged.position = card_slot_found.position
		if not _has_elusive_keyword(card_being_dragged):
			card_being_dragged.get_node("Area2D/CollisionShape2D").disabled = true
		card_slot_found.card_in_slot = true
		
		# Set card ownership
		card_being_dragged.owner_player_id = current_player_id
		
		# Register card in zone tracking
		if zone_key != Vector2i(-1, -1):
			board_reference.add_card_to_zone(zone_key, card_being_dragged)

		# Queue for resolve phase (abilities fire when card flips during resolve)
		played_cards_order.append(card_being_dragged)
		# Also add to persistent play order (duplicate-safe: handles recall+replay)
		add_card_to_play_order(card_being_dragged)
		# Track as summoned (was_played_from_hand = true)
		track_summoned_card(card_being_dragged, true)
		# Snapshot for undo
		undo_stack.append({
			"card": card_being_dragged,
			"hand_index": _hand_index_before_remove,
			"mana_cost": card_cost,
			"zone_key": zone_key,
			"slot": card_slot_found
		})
		_update_undo_button()
		# Card left hand — hide its glow
		card_being_dragged.is_in_hand = false
		card_being_dragged.hide_glow()

		card_being_dragged = null
	else:
		_return_card_to_hand()


func _finish_drag_engine() -> void:
	"""Engine mode drop. The drop slot resolves to a board zone (col, row); only our
	own row is playable, everything else goes back to the hand with a toast. The
	engine decides the rest (mana, card type, lane, turn) and the presenter either
	places the card or hands it back on intent_rejected."""
	var controller := _match_controller()
	var card = card_being_dragged
	var instance_id := _engine_instance_id(card)
	var dest_slot = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	var zone_key: Vector2i = board_reference.get_zone_for_slot(dest_slot) if dest_slot else Vector2i(-1, -1)
	# ENGINE_OWN_ROW, not local_player_id: the drop row is a screen row, and a host is
	# absolute player 0 whose cards belong on the bottom row all the same.
	if instance_id < 0 or zone_key == Vector2i(-1, -1) or zone_key.y != ENGINE_OWN_ROW:
		if zone_key != Vector2i(-1, -1) and zone_key.y != ENGINE_OWN_ROW:
			_show_toast("Play on your side")
		_return_card_to_hand()
		return
	# Lane columns are 0..2, the spell zone is -1 (MatchState.SPELL_COL).
	card_being_dragged = null
	controller.submit_local(MatchIntents.play_card(instance_id, zone_key.x, -1))


func resolve_played_cards() -> void:
	# Spawn any pending opponent cards (hidden during PLAY, shown now as face-down)
	_spawn_pending_opponent_cards()
	
	# Sort cards so flip_first player's cards resolve first
	var sorted_cards := _sort_cards_by_flip_first(played_cards_order)
	
	# First pass: show ALL cards as face-down (card back covering front)
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		if card.has_method("set_card_back_z_index"):
			card.set_card_back_z_index(5)
	
	# Brief pause so players can see all cards face-down before flipping
	await get_tree().create_timer(0.5).timeout

	# Second pass: flip and trigger abilities one by one in flip_first order
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		var anim_player = card.get_node_or_null("AnimationPlayer")
		if anim_player:
			anim_player.play("card_flip_play")
			await anim_player.animation_finished
		if card.has_method("hide_card_back"):
			card.hide_card_back()
		else:
			var card_back = card.get_node_or_null("CardBack")
			if card_back:
				card_back.visible = false
		# Mark card as resolved before triggering abilities so other cards
		# can see it, but cards later in the queue remain unresolved.
		card.is_resolved = true
		# Trigger ability after reveal/flip animation (await so multi-step abilities
		# like mass-recall fully complete before the next card flips)
		await card.on_summon()
		# Track Spinning Axe plays for Draven level-up (must happen BEFORE level-up checks)
		if card.card_id == "SpinningAxe":
			for c in all_cards_in_play_order:
				if is_instance_valid(c) and c.is_resolved and c.card_slot_is_in \
						and c.owner_player_id == card.owner_player_id \
						and "axe_play_count" in c:
					var c_data = CardDatabase.CARDS.get(c.card_id)
					if c_data and c_data.get("Name", "") == "Draven":
						c.axe_play_count += 1
						print("Draven (%s) has seen %d Spinning Axe(s) played" % [c.card_id, c.axe_play_count])
		# Mark this card's summoned_cards entry as resolved so power-based level-up
		# checks (e.g. Sion) only count cards that have actually flipped this turn.
		for _i in range(summoned_cards.size() - 1, -1, -1):
			var _e = summoned_cards[_i]
			if _e.get("card_id") == card.card_id and not _e.get("is_resolved", true):
				_e["is_resolved"] = true
				break
		# Check if this resolve triggers any level-ups (e.g. Ice Pillar → Trundle, Draven → Spinning Axe count)
		check_level_ups_after_resolve(card)
		# Wait for any level-up animation triggered by this resolve to finish
		await _wait_for_level_up()
		# Spell cleanup: spells remove themselves from the zone after resolving
		var card_type: String = str(CardDatabase.CARDS.get(card.card_id, {}).get("Type", ""))
		if card_type == "Spell" and card.has_method("on_spell_resolved"):
			if card.card_slot_is_in:
				var zone_key: Vector2i = board_reference.get_zone_for_slot(card.card_slot_is_in)
				card.card_slot_is_in.card_in_slot = false
				if zone_key != Vector2i(-1, -1):
					board_reference.remove_card_from_zone(zone_key, card)
					board_reference.reposition_cards_in_zone(zone_key)
				card.card_slot_is_in = null
			await get_tree().create_timer(0.3).timeout
			await card.on_spell_resolved()
		# Update zone power display after each card resolves
		_notify_zone_power_changed()
		# Pause between each card so play effects (e.g. card created in hand) can finish animating
		await get_tree().create_timer(CARD_PAUSE_TIMER).timeout
	played_cards_order.clear()
	undo_stack.clear()

func connect_card_signals(card):
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)


# ── Undo Actions ───────────────────────────────────────────────────────────────

func _update_undo_button() -> void:
	if not undo_button:
		return
	var controller := _match_controller()
	if controller:
		undo_button.disabled = not controller.can_undo()
		return
	var in_play_phase: bool = (
		game_manager_reference != null and
		game_manager_reference.game_phase == game_manager_reference.GamePhase.TURN_LOOP and
		game_manager_reference.round_phase == game_manager_reference.RoundPhase.PLAY
	)
	undo_button.disabled = undo_stack.is_empty() or not in_play_phase


func _remove_undone_summoned_entry(card) -> void:
	"""Undo the summoned_cards entry that finish_drag's track_summoned_card(card, true)
	created for a card that is going back to hand.
	Played-from-hand entries start unresolved and only flip to resolved during the
	resolve phase, so an undone play can never own a resolved entry. Only the local
	player's entries are ours to drop — the opponent's live on their own client.
	Duplicates: removes exactly one entry per call, so playing the same card_id twice
	and undoing twice removes exactly two entries."""
	if not is_instance_valid(card):
		return
	for i in range(summoned_cards.size() - 1, -1, -1):
		var entry: Dictionary = summoned_cards[i]
		if not entry.get("was_played_from_hand", false):
			continue
		if entry.get("is_resolved", false):
			continue
		if str(entry.get("card_id", "")) != str(card.card_id):
			continue
		if int(entry.get("owner_player_id", -1)) != current_player_id:
			continue
		summoned_cards.remove_at(i)
		print("Undo: dropped summoned_cards entry for %s (total: %d)" % [
			card.card_id, summoned_cards.size()])
		return


func _on_undo_button_pressed() -> void:
	# Engine mode: the engine owns the undo stack and refunds the mana itself;
	# the presenter sends the cards back to the hand in the right order.
	var controller := _match_controller()
	if controller:
		if not controller.can_undo():
			return
		controller.submit_local(MatchIntents.undo())
		return
	if undo_stack.is_empty():
		return

	# Collect total mana to refund
	var total_mana_refund: int = 0
	for entry in undo_stack:
		total_mana_refund += int(entry.get("mana_cost", 0))

	var undone_cards: Array = []

	# Remove all played cards from board and tracking
	for entry in undo_stack:
		var card = entry["card"]
		var zone_key: Vector2i = entry["zone_key"]
		var slot = entry["slot"]
		if not is_instance_valid(card):
			continue
		slot.card_in_slot = false
		card.card_slot_is_in = null
		board_reference.remove_card_from_zone(zone_key, card)
		all_cards_in_play_order.erase(card)
		# Restore visual state to hand
		card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
		card.z_index = 2
		card.get_node("Area2D/CollisionShape2D").disabled = false
		card.is_in_hand = true
		undone_cards.append(card)
		# finish_drag() called track_summoned_card(..., true) — drop that entry again
		_remove_undone_summoned_entry(card)

	# Re-insert cards into hand at their original indices (ascending order keeps indices correct)
	var sorted_entries: Array = undo_stack.duplicate()
	sorted_entries.sort_custom(func(a, b): return a["hand_index"] < b["hand_index"])
	for entry in sorted_entries:
		var card = entry["card"]
		var original_index: int = entry["hand_index"]
		if not is_instance_valid(card) or card in player_hand_reference.player_hand:
			continue
		var clamped_index: int = mini(original_index, player_hand_reference.player_hand.size())
		player_hand_reference.player_hand.insert(clamped_index, card)

	player_hand_reference.update_hand_position(0.3)

	# Refund mana
	if game_manager_reference and total_mana_refund > 0:
		game_manager_reference.refund_player_mana(current_player_id, total_mana_refund)

	# finish_drag() hid the hand glow on play — restore it now that mana is back
	if game_manager_reference:
		var refunded_mana: int = game_manager_reference.get_player_current_mana(current_player_id)
		for card in undone_cards:
			if is_instance_valid(card) and card.has_method("update_glow"):
				card.update_glow(refunded_mana)

	# Clear turn tracking
	played_cards_order.clear()
	undo_stack.clear()

	_notify_zone_power_changed()
	_update_undo_button()
	print("Undo: returned all played cards to hand, %d mana refunded" % total_mana_refund)


func on_left_click_released():
	if card_being_dragged:
		finish_drag()
	
func on_hovered_over_card(card):
	if !is_hovering_on_card: 
		is_hovering_on_card = true
		highlight_card(card, true)
	
func on_hovered_off_card(card):
	if !card.card_slot_is_in && !card_being_dragged:
		highlight_card(card, false)
		var new_card_hovered = raycast_check_for_card()
		if new_card_hovered:
			highlight_card(new_card_hovered, true)
		else:
			is_hovering_on_card = false
	
func highlight_card(card, hovered):
	if hovered:
		card.scale = Vector2(CARD_BIGGER_SCALE, CARD_BIGGER_SCALE)
		card.z_index = 3
	else:
		card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
		card.z_index = 2

func raycast_check_for_card_slot():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:		
		return result[0].collider.get_parent()
	return null

func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:		
		#return result[0].collider.get_parent()
		return get_card_with_highest_z_index(result)
	return null
	
func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card


# Persistent play order management
func add_card_to_play_order(card) -> void:
	"""Add a card to the persistent play order (for summoned cards, etc.)"""
	if card and not all_cards_in_play_order.has(card):
		all_cards_in_play_order.append(card)


func recall_card(card, recaller_player_id: int = -1, recaller_card_id: String = "") -> void:
	"""Return a board card to its owner's hand (Recall mechanic).
	Removes the card from its slot and zone, then animates it flying back to
	the local player's hand. Only adds to hand when the card belongs to the
	local player — opponent cards are simply removed from the board (the
	opponent's client manages their own hand). Recall also clears any Stun on the
	card (StunManager.clear_stun) before the owner check, on both clients.
	Reusable for any card ability that recalls an ally (Ahri, future cards…)."""
	if not is_instance_valid(card):
		return

	# Recall clears Stun. Must run before the owner check below so the entry goes even
	# for a card that is about to leave the board. has_stun gates self-swaps, so the
	# board and the stun table must not disagree about a card that is being removed.
	StunManager.clear_stun(card)

	# Release slot and remove from zone tracking
	var zone_key := Vector2i(-1, -1)
	if card.card_slot_is_in:
		zone_key = board_reference.get_zone_for_slot(card.card_slot_is_in)
		card.card_slot_is_in.card_in_slot = false
	card.card_slot_is_in = null

	if zone_key != Vector2i(-1, -1):
		board_reference.remove_card_from_zone(zone_key, card)
		board_reference.reposition_cards_in_zone(zone_key)

	# Opponent cards are only removed from the board — do not add to local hand
	if card.owner_player_id != current_player_id:
		print("Recalled opponent card %s — removed from board" % card.card_id)
		return

	# Reset board state before the flight animation
	card.is_resolved = false
	card.z_index = 10  # elevated so it renders above other cards during flight

	# Re-enable collision so the card can be dragged from hand
	var col_shape = card.get_node_or_null("Area2D/CollisionShape2D")
	if col_shape:
		col_shape.disabled = false

	# Scale tween: board size (0.15) → hand size (0.2) over the flight duration
	var scale_tween = card.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	scale_tween.tween_property(card, "scale", Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE), 0.8)

	# Position tween: fly from board position directly to the correct hand slot
	# (same mechanic as create_card_in_hand / Trundle Ice Pillar)
	player_hand_reference.add_card_to_hand(card, 0.8)

	await scale_tween.finished
	card.z_index = 2
	card.is_in_hand = true
	var current_mana: int = game_manager_reference.get_player_current_mana(current_player_id)
	card.update_glow(current_mana)
	print("Recalled: %s to player %d's hand" % [card.card_id, card.owner_player_id])
	if recaller_card_id != "":
		track_recalled_card(card, recaller_player_id, recaller_card_id)


func create_card_in_hand(card_id_to_create: String, creator_card_id: String = "", creator_player_id: int = -1) -> void:
	"""Create a card by ID and add it to the local player's hand. Reusable for any
	'create card in hand' ability (Trundle -> Ice Pillar, etc.).
	creator_card_id: which card created this (empty = unknown/no tracking).
	creator_player_id: which player created this (-1 = same as owner, -999 = unknown)."""
	var card_data = CardDatabase.CARDS.get(card_id_to_create)
	if not card_data:
		print("create_card_in_hand: unknown card id ", card_id_to_create)
		return

	# If this champion has already globally leveled up, create the upgraded version instead.
	var _upgrade_name: String = card_data.get("Name", "")
	if _upgrade_name != "" and permanently_leveled_up.has(_upgrade_name):
		card_id_to_create = permanently_leveled_up[_upgrade_name]
		card_data = CardDatabase.CARDS.get(card_id_to_create)
		if not card_data:
			print("create_card_in_hand: upgraded card not found ", card_id_to_create)
			return

	var card_scene = CardDatabase.get_card_scene(card_data)
	var new_card = card_scene.instantiate()
	if new_card.get_script() == null:
		new_card.set_script(CardDatabase.get_card_script(card_data))

	new_card.card_id = card_id_to_create
	new_card.owner_player_id = current_player_id  # belongs to the local player

	# Spawn at screen center so the player sees where it came from
	var viewport_size = get_viewport_rect().size
	new_card.position = Vector2(viewport_size.x / 2.0, viewport_size.y / 2.0)

	# Populate card visuals
	CardDatabase.populate_card_visuals(new_card, card_data)

	add_child(new_card)
	new_card.name = "Card"
	new_card.get_node("AnimationPlayer").play("card_flip")

	# Add to hand — this tweens the card from screen center to the hand position
	player_hand_reference.add_card_to_hand(new_card, 0.3)
	new_card.is_in_hand = true
	var current_mana: int = game_manager_reference.get_player_current_mana(current_player_id)
	new_card.update_glow(current_mana)

	# Track as created card if creator info provided
	if creator_card_id != "":
		var creator_player = creator_player_id if creator_player_id != -1 else current_player_id
		track_created_card(new_card, creator_player, creator_card_id)

	print("Created card in hand: ", card_data.get("Name", ""), " (ID: ", card_id_to_create, ")")


func track_killed_card(card, killer_player_id: int = -1, killer_card_id: String = "") -> void:
	"""Record a killed card for ability tracking (e.g. Nasus level-up condition).
	killer_player_id: which player caused the kill (-1 = unknown/environment).
	killer_card_id: which card performed the kill (empty = unknown)."""
	if not is_instance_valid(card):
		return
	# Capture the zone the card died in (card still has its slot at this point)
	var zone_key: Vector2i = Vector2i(-1, -1)
	if board_reference and card.card_slot_is_in:
		zone_key = board_reference.get_zone_for_slot(card.card_slot_is_in)
	killed_cards.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner_player_id,
		"killer_player_id": killer_player_id,
		"killer_card_id": killer_card_id,
		"zone_key": zone_key,
		"is_revived": false
	})
	print("Card killed and tracked: %s (killed by player %d, card %s) (total killed: %d)" % [
		card.card_id, killer_player_id, killer_card_id, killed_cards.size()])
	# Re-check level-up conditions immediately when a real kill is recorded.
	LevelUpManager._check_nasus_levelup()


func track_summoned_card(card, was_played_from_hand: bool = false) -> void:
	"""Record a summoned card for ability tracking (e.g. Kennen level-up condition).
	was_played_from_hand: true if the card was dragged from hand to board,
	false if it was created/summoned directly onto the board."""
	if not is_instance_valid(card):
		return
	summoned_cards.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner_player_id,
		"was_played_from_hand": was_played_from_hand,
		"is_resolved": not was_played_from_hand  # played-from-hand cards wait for the resolve flip; created cards are already on board
	})
	print("Card summoned tracked: %s (from_hand: %s, total: %d)" % [
		card.card_id, was_played_from_hand, summoned_cards.size()])
	LevelUpManager._check_sion_levelup()


func track_created_card(card, creator_player_id: int, creator_card_id: String) -> void:
	"""Record a card that was created (not from starting deck).
	creator_player_id: which player created it (-1 = environment/lane effect).
	creator_card_id: which card created it (or lane ID for lane effects)."""
	if not is_instance_valid(card):
		return
	var game_manager = get_node_or_null("/root/Main/GameManager")
	var current_turn = 0
	if game_manager and "turn_number" in game_manager:
		current_turn = game_manager.turn_number

	created_cards.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner_player_id,
		"creator_player_id": creator_player_id,
		"creator_card_id": creator_card_id,
		"created_at_turn": current_turn
	})
	print("Card created tracked: %s (created by %s, creator: %s, turn: %d, total: %d)" % [
		card.card_id, creator_card_id, creator_player_id, current_turn, created_cards.size()])


func track_discarded_card(card_id: String, owner_player_id: int, discarded_by_card_id: String = "") -> void:
	"""Record a discarded card for ability tracking (e.g. Rumble level-up condition).
	discarded_by_card_id: which card triggered the discard (empty = unknown)."""
	var game_manager = get_node_or_null("/root/Main/GameManager")
	var current_turn = 0
	if game_manager and "turn_number" in game_manager:
		current_turn = game_manager.turn_number
	discarded_cards.append({
		"card_id": card_id,
		"owner_player_id": owner_player_id,
		"discarded_by_card_id": discarded_by_card_id,
		"discarded_at_turn": current_turn
	})
	print("Card discarded and tracked: %s (by %s, owner %d, turn %d, total: %d)" % [
		card_id, discarded_by_card_id, owner_player_id, current_turn, discarded_cards.size()])


func discard_card_from_hand(card: Node, discarded_by_card_id: String = "") -> void:
	"""Discard a card from the player's hand with dissolve animation, track it, and free it."""
	var card_id = card.card_id
	var owner_id = card.owner_player_id
	player_hand_reference.remove_card_from_hand(card, false)  # remove from array, no reposition yet
	card.is_in_hand = false
	await card.play_discard_dissolve()
	player_hand_reference.update_hand_position(0.1)  # slide remaining cards after dissolve
	track_discarded_card(card_id, owner_id, discarded_by_card_id)

	# Trigger on-discard abilities (e.g. Sion1)
	var card_data = CardDatabase.CARDS.get(card_id)
	if card_data and card_data.get("AbilityType", "") == "on_discard_buff_create":
		await AbilityResolver.execute_on_discard_ability(card)
		LevelUpManager._check_sion_levelup()

	card.queue_free()


func adjust_cost(cards, delta: int) -> void:
	"""Adjust the mana cost of one or more cards by delta (negative = cheaper, positive = more expensive).
	Accepts a single card Node or an Array of card Nodes.
	Cost is clamped to minimum 0 by get_current_cost()."""
	var card_list: Array = cards if cards is Array else [cards]
	for card in card_list:
		if not is_instance_valid(card):
			continue
		card.cost_modifier += delta
		_update_cost_label(card)
		if game_manager_reference and card.has_method("update_glow"):
			var current_mana: int = game_manager_reference.get_player_current_mana(current_player_id)
			card.update_glow(current_mana)


func _update_cost_label(card: Node) -> void:
	"""Refresh the CardFront/Cost label to reflect the current cost with color coding.
	Green = discounted, Red = increased, plain = base cost."""
	var cost_label = card.get_node_or_null("CardFront/Cost")
	if not cost_label:
		return
	var current_cost = card.get_current_cost()
	if card.cost_modifier < 0:
		cost_label.text = "[color=green]%d[/color]" % current_cost
	elif card.cost_modifier > 0:
		cost_label.text = "[color=red]%d[/color]" % current_cost
	else:
		cost_label.text = str(current_cost)


func track_recalled_card(card: Node, recaller_player_id: int, recaller_card_id: String) -> void:
	"""Record a recall triggered by a card ability.
	recaller_player_id: which player's card triggered the recall.
	recaller_card_id: which card triggered the recall (e.g. 'Ahri1')."""
	if not is_instance_valid(card):
		return
	recalled_cards.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner_player_id,
		"recaller_player_id": recaller_player_id,
		"recaller_card_id": recaller_card_id
	})
	print("Recall tracked: %s recalled by %s (player %d, total: %d)" % [
		card.card_id, recaller_card_id, recaller_player_id, recalled_cards.size()])


func track_drawn_card(card_id: String, p_owner_player_id: int) -> void:
	"""Record a card drawn from the deck. Used by Janna level-up condition."""
	var gm = get_node_or_null("/root/Main/GameManager")
	var current_turn = gm.turn_number if gm else 0
	drawn_cards.append({
		"card_id": card_id,
		"owner_player_id": p_owner_player_id,
		"turn": current_turn
	})
	print("Draw tracked: %s (player %d, turn %d, total: %d)" % [
		card_id, p_owner_player_id, current_turn, drawn_cards.size()])


func _sort_cards_by_flip_first(cards: Array) -> Array:
	"""Sort cards so that flip_first player's cards come first, preserving play order within each group."""
	if flip_first_player_id < 0:
		return cards  # No flip first set, use original order
	
	var first_player_cards: Array = []
	var second_player_cards: Array = []
	
	for card in cards:
		if not is_instance_valid(card):
			continue
		if card.owner_player_id == flip_first_player_id:
			first_player_cards.append(card)
		else:
			second_player_cards.append(card)
	
	var sorted: Array = []
	sorted.append_array(first_player_cards)
	sorted.append_array(second_player_cards)
	return sorted


# Trigger abilities in play order
func trigger_round_start_abilities() -> void:
	"""Trigger Round Start abilities for all cards in play order (flip first player first)"""
	var sorted_cards := _sort_cards_by_flip_first(all_cards_in_play_order)
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		# Re-check: card may have been killed by a prior ability this phase (slot is cleared on kill)
		if not card.card_slot_is_in:
			continue
		if StunManager.has_stun(card):  # Stunned cards skip round start
			continue
		if card.has_method("on_round_start"):
			var did_fire = await card.on_round_start()
			# Wait for any level-up triggered by this ability before continuing
			await _wait_for_level_up()
			if did_fire:
				_notify_zone_power_changed()
				await get_tree().create_timer(CARD_PAUSE_TIMER).timeout
	# After all round-start abilities, re-check state-based level-up conditions
	check_level_ups_after_abilities()
	await _wait_for_level_up()


func trigger_round_end_abilities() -> void:
	"""Trigger Round End abilities for all cards in play order (flip first player first)"""
	var sorted_cards := _sort_cards_by_flip_first(all_cards_in_play_order)
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		# Re-check: card may have been killed by a prior ability this phase (slot is cleared on kill)
		if not card.card_slot_is_in:
			continue
		if StunManager.has_stun(card):  # Stunned cards skip round end
			continue
		if card.has_method("on_round_end"):
			var did_fire = await card.on_round_end()
			# Wait for any level-up triggered by this ability before continuing
			await _wait_for_level_up()
			if did_fire:
				_notify_zone_power_changed()
				await get_tree().create_timer(CARD_PAUSE_TIMER).timeout
	# After all round-end abilities, re-check state-based level-up conditions
	check_level_ups_after_abilities()
	await _wait_for_level_up()


func trigger_game_end_abilities() -> void:
	"""Trigger Game End abilities for all cards in play order (flip first player first).
	Azir Lv3 causes other Ascended allies to fire their Game End a second time.
	A guard dictionary prevents any card from double-firing more than once,
	blocking infinite loops even if multiple Azir Lv3s somehow exist."""
	var sorted_cards := _sort_cards_by_flip_first(all_cards_in_play_order)

	# First pass — every card fires once (normal)
	var game_end_fired: Dictionary = {}  # Guard against duplicate entries in all_cards_in_play_order
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		# Re-check: card may have been killed by a prior ability this phase (slot is cleared on kill)
		if not card.card_slot_is_in:
			continue
		if game_end_fired.has(card):  # Skip if already fired (handles recall+replay duplicates)
			continue
		game_end_fired[card] = true
		if card.has_method("on_game_end"):
			var did_fire = await card.on_game_end()
			# Wait for any level-up triggered by this ability before continuing
			await _wait_for_level_up()
			if did_fire:
				_notify_zone_power_changed()
				await get_tree().create_timer(CARD_PAUSE_TIMER).timeout

	# Second pass — Azir Lv3: other Ascended allies fire their Game End a second time
	# Guard set prevents any card from being double-fired more than once.
	var double_game_end_fired: Dictionary = {}

	for azir_card in all_cards_in_play_order:
		if not is_instance_valid(azir_card):
			continue
		if not azir_card.card_slot_is_in:  # killed earlier this phase
			continue
		if not azir_card.is_resolved:
			continue
		var azir_data = CardDatabase.CARDS.get(azir_card.card_id)
		if not azir_data:
			continue
		if azir_data.get("Name", "") != "Azir" or azir_data.get("Level", 1) != 3:
			continue

		var owner_id = azir_card.owner_player_id
		print("Azir Lv3: triggering second Game End for allied Ascended units (owner %d)" % owner_id)

		for card in sorted_cards:
			if not is_instance_valid(card) or card == azir_card:
				continue
			if not card.card_slot_is_in:  # card was killed earlier this phase
				continue
			if card.owner_player_id != owner_id:
				continue
			if not card.is_resolved:
				continue
			# Only Ascended subtype (case-insensitive)
			var c_data = CardDatabase.CARDS.get(card.card_id)
			if not c_data or c_data.get("SubType", "").to_lower() != "ascended":
				continue
			# Only if the card actually has a {Game End} in its skill text
			if not ("{Game End}" in c_data.get("Skill", "")):
				continue
			# Guard: skip if this card already received its bonus second fire this game
			if double_game_end_fired.has(card):
				continue
			double_game_end_fired[card] = true  # mark BEFORE firing to block re-entry
			if card.has_method("on_game_end"):
				var did_fire = await card.on_game_end()
				# Wait for any level-up triggered by this ability before continuing
				await _wait_for_level_up()
				if did_fire:
					_notify_zone_power_changed()
					await get_tree().create_timer(CARD_PAUSE_TIMER).timeout

	# Third pass — hand cards with {Game End} abilities (e.g. Sion2, SionReturned)
	# These fire after all board Game End abilities, per player in flip-first order.
	var player_ids: Array = [flip_first_player_id, 1 - flip_first_player_id] if flip_first_player_id >= 0 else [1, 0]
	for player_id in player_ids:
		if player_hand_reference:
			# Snapshot hand cards since the ability may remove cards from hand
			var hand_snapshot: Array = []
			for c in player_hand_reference.player_hand:
				if is_instance_valid(c) and c.owner_player_id == player_id:
					hand_snapshot.append(c)

			for hand_card in hand_snapshot:
				if not is_instance_valid(hand_card):
					continue
				var hc_data = CardDatabase.CARDS.get(hand_card.card_id)
				if not hc_data:
					continue
				# Check if this card has a {Game End} ability meant for hand cards
				var ability_type: String = hc_data.get("AbilityType", "none")
				var hand_ability_type: String = hc_data.get("HandAbilityType", "")
				var effective_type = hand_ability_type if hand_ability_type != "" else ability_type
				if effective_type != "game_end_summon_from_hand":
					continue
				# Check if the skill text actually contains {Game End}
				var skill: String = hc_data.get("Skill", "")
				if not ("{Game End}" in skill):
					continue

				print("Hand {Game End} triggered for: %s (player %d)" % [hc_data.get("Name", hand_card.card_id), player_id])
				await AbilityResolver.execute_game_end_hand_ability(hand_card.card_id, hc_data, player_id)
				await _wait_for_level_up()
				_notify_zone_power_changed()
				await get_tree().create_timer(CARD_PAUSE_TIMER).timeout


## --- Deferred opponent plays (old engine's offline bot, until M5b) ---


func queue_opponent_card_play(card_id: String, zone_col: int, zone_row: int, power_mod: int = 0) -> void:
	"""Queue an opponent card to appear face-down at resolve time (hidden during PLAY).

	On M5a LAN the opponent's plays arrive as engine events, so nothing sends this any
	more. The offline bot still does — it plays its own cards locally — so the queue and
	_spawn_pending_opponent_cards stay until M5b deletes the old engine."""
	_pending_opponent_cards.append({
		"card_id": card_id,
		"zone_col": zone_col,
		"zone_row": zone_row,
		"power_mod": power_mod
	})
	print("Opponent card play queued: ", card_id, " for zone: ", Vector2i(zone_col, zone_row))


func get_upgraded_card_id(card_id: String) -> String:
	"""Return the globally-upgraded card_id for this card if its champion has permanently
	leveled up, otherwise return the original card_id unchanged."""
	var card_data = CardDatabase.CARDS.get(card_id)
	if not card_data:
		return card_id
	var champ_name: String = card_data.get("Name", "")
	return permanently_leveled_up.get(champ_name, card_id)


func upgrade_all_copies(old_card_id: String, new_card_id: String) -> void:
	"""After a champion plays its level-up animation, silently upgrade every remaining copy
	owned by the local player: other board cards, hand cards (with flip animation), and deck
	entries. On M5a LAN the opponent learns about the level-up from an engine event."""
	# ── Board copies ──────────────────────────────────────────────────────────────
	for card in all_cards_in_play_order:
		if not is_instance_valid(card) or not card.card_slot_is_in:
			continue
		if card.card_id == old_card_id and card.owner_player_id == current_player_id:
			card._apply_level_up_silently(new_card_id)

	# ── Hand copies (flip animation so the player notices) ────────────────────────
	if player_hand_reference:
		for card in player_hand_reference.player_hand:
			if not is_instance_valid(card) or card.card_id != old_card_id:
				continue
			card.card_id = new_card_id
			var hand_data = CardDatabase.CARDS.get(new_card_id)
			if hand_data:
				CardDatabase.populate_card_visuals(card, hand_data)
			var hand_anim = card.get_node_or_null("AnimationPlayer")
			if hand_anim and hand_anim.has_animation("card_flip"):
				hand_anim.play("card_flip")
			print("[GLOBAL_LEVELUP] hand card upgraded: %s → %s" % [old_card_id, new_card_id])

	# ── Deck entries ──────────────────────────────────────────────────────────────
	var deck = get_node_or_null("/root/Main/Deck")
	if deck and "player_deck" in deck:
		for entry in deck.player_deck:
			if entry.get("id", "") == old_card_id:
				entry["id"] = new_card_id
		print("[GLOBAL_LEVELUP] deck entries upgraded: %s → %s" % [old_card_id, new_card_id])


func set_player_deep(player_id: int) -> void:
	"""Permanently mark a player as Deep (runs out of deck cards).
	Once Deep, the state never reverts — even if cards re-enter the deck.
	Triggers the Deep aura (+3 power on Deep-keyword units) and Nautilus level-up check."""
	if not player_state.has(player_id):
		return
	if player_state[player_id].get("is_deep", false):
		return  # Already Deep — guard once-only
	player_state[player_id]["is_deep"] = true
	print("Player %d is now Deep!" % player_id)
	_notify_zone_power_changed()
	LevelUpManager.check_level_ups_after_deep_state_change(player_id)


func _spawn_pending_opponent_cards() -> void:
	"""Spawn all pending opponent cards face-down on the board (called at resolve start)."""
	for data in _pending_opponent_cards:
		var card_id_str: String = data["card_id"]
		var zone_key = Vector2i(data["zone_col"], data["zone_row"])
		var zone_slots = board_reference.slots_by_zone.get(zone_key, [])

		var available_slot = null
		for slot in zone_slots:
			if not slot.card_in_slot:
				available_slot = slot
				break

		if not available_slot:
			print("No available slot for opponent card in zone: ", zone_key)
			continue

		var card_data = CardDatabase.CARDS.get(card_id_str)
		var card_scene = CardDatabase.get_card_scene(card_data)
		var opp_card = card_scene.instantiate()
		if opp_card.get_script() == null:
			opp_card.set_script(CardDatabase.get_card_script(card_data))

		opp_card.card_id = card_id_str
		opp_card.owner_player_id = 0  # Opponent is always player 0 from our view

		if card_data:
			CardDatabase.populate_card_visuals(opp_card, card_data)

		var power_mod: int = data.get("power_mod", 0)
		if power_mod != 0 and "power_modifier" in opp_card:
			opp_card.power_modifier = power_mod
			var power_label = opp_card.get_node_or_null("CardFront/Power")
			if power_label:
				power_label.text = opp_card.get_power_display_text()

		opp_card.position = available_slot.position
		var opp_scale: float = board_reference.SPELL_SLOT_SCALE if board_reference.is_spell_zone(zone_key) else CARD_SMALLER_SCALE
		opp_card.scale = Vector2(opp_scale, opp_scale)
		opp_card.z_index = 0
		opp_card.card_slot_is_in = available_slot
		opp_card.get_node("Area2D/CollisionShape2D").disabled = true

		# Spawn face-down
		if opp_card.has_method("set_card_back_z_index"):
			opp_card.set_card_back_z_index(5)

		add_child(opp_card)
		available_slot.card_in_slot = true

		board_reference.add_card_to_zone(zone_key, opp_card)

		played_cards_order.append(opp_card)
		all_cards_in_play_order.append(opp_card)
		opponent_played_cards.append(opp_card)
		# Track opponent's card as summoned (was_played_from_hand = true — they played it from their hand)
		track_summoned_card(opp_card, true)

		print("Opponent card spawned face-down: ", card_id_str, " in zone: ", zone_key)

	_pending_opponent_cards.clear()


# ---- Behold helpers ----

func get_beheld_cards(player_id: int) -> Array:
	"""Return all cards a player 'beholds' — cards in their hand + on the board.
	Behold includes unresolved cards (face-down on board).
	Only cards this peer actually has a node for are returned: the opponent's hand used
	to arrive as a synced id list, which was one of the hidden-info leaks M5a removes.
	Beholding an opponent card now means the card is on the board."""
	var result: Array = []
	var seen: Dictionary = {}  # card instance -> true, to avoid duplicates

	# Cards in hand (local player's hand is tracked by PlayerHand)
	if player_id == current_player_id and player_hand_reference:
		for card in player_hand_reference.player_hand:
			if is_instance_valid(card):
				result.append(card)
				seen[card] = true

	# Cards on the board belonging to this player
	if board_reference:
		var ally_zones = board_reference.get_ally_zones(player_id)
		for zone_key in ally_zones:
			for card in board_reference.get_cards_in_zone(zone_key):
				if is_instance_valid(card) and not seen.has(card):
					result.append(card)
					seen[card] = true

	# Fallback: scan all CardManager children for cards belonging to this player
	# that weren't already found (catches cards in limbo)
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if not ("card_id" in child and "owner_player_id" in child):
			continue
		if child.owner_player_id == player_id and not seen.has(child):
			result.append(child)
			seen[child] = true


	return result


func get_beheld_cards_filtered(player_id: int, filter_func: Callable) -> Array:
	"""Return beheld cards that pass a filter function.
	filter_func receives a card node and returns bool."""
	var all_beheld = get_beheld_cards(player_id)
	var filtered: Array = []
	for card in all_beheld:
		if filter_func.call(card):
			filtered.append(card)
	return filtered


func count_beheld_matching(player_id: int, filter_func: Callable) -> int:
	"""Count how many beheld cards pass the filter."""
	return get_beheld_cards_filtered(player_id, filter_func).size()


# ---- Level-up checks (delegated to LevelUpManager) ----

func check_level_ups_after_resolve(resolved_card) -> void:
	"""Called after each card resolves. Delegates to LevelUpManager."""
	LevelUpManager.check_level_ups_after_resolve(resolved_card)


func check_level_ups_after_abilities() -> void:
	"""Called after round-start / round-end ability loops. Delegates to LevelUpManager."""
	LevelUpManager.check_level_ups_after_abilities()


# ---- Aura system (see AuraSystem.gd) ----
# recalculate_auras() and individual _apply_aura_* methods have moved to AuraSystem.
# CardManager calls _notify_zone_power_changed() → AuraSystem.recalculate_auras().

