extends SceneTree
## Scene regression: a card you UNDO can be played again.
##
## Bug: MatchPresenter._on_play_undone only called _remove_from_zone_model(id), which
## takes the card out of the view's zone MODEL but never rebuilds the Board zone and
## never clears Card.card_slot_is_in. So the node that slid back into the hand stayed
## registered in Board.cards_by_zone with its slot marked occupied, and
## CardManager._start_drag_engine still saw card_slot_is_in != null, took it for a
## board card and let can_start_swap refuse it: no drag started at all.
##
## Drives the REAL Main.tscn, the REAL controller/presenter and the REAL CardManager,
## and asserts on the real slot objects rather than on a mock.
##
## Deck: eight Chip (cost 1, no ability) plus four HexCoreUpgrade (cost 0 Spell, no
## ability), so a spell is in hand alongside the units — it goes through the same board
## -> hand view path but lands in the SPELL column (col -1). Seed 3 deals a
## HexCoreUpgrade and three Chips into the opening hand.

const SEED := 3
const DECK_CHIPS := 8
const DECK_SPELLS := 4
const LANE := 0
const SPELL_COL := -1
const SPELL_CARD := "HexCoreUpgrade"
const UNIT_CARD := "Chip"
const BIG_MANA := 9
const LOCAL_ROW := 1

# CardState.Location, spelled out because a SceneTree script must not reference a
# class_name at parse time: that compiles Card.gd before the autoloads exist.
const LOC_HAND := 1
const LOC_BOARD := 2
const LOC_SPELL_ZONE := 3

var _failures := 0
var _main: Node
var _ctl: Node
var _pres: Node
var _cm: Node
var _im: Node
var _board: Node
var _mi: GDScript


func _initialize() -> void:
	_mi = load("res://Scripts/Match/MatchIntents.gd")
	await _boot()

	var st = _ctl.state
	var me: int = _ctl.local_player
	var by_id := _hand_ids_by_card_id(st, me)
	if by_id[UNIT_CARD].size() < 2 or by_id[SPELL_CARD].size() < 1:
		_fail("deck", "opening hand lacks 2 %s and 1 %s: %s" % [UNIT_CARD, SPELL_CARD, str(by_id)])
		_finish()
		return

	var unit_a: int = by_id[UNIT_CARD][0]
	var unit_b: int = by_id[UNIT_CARD][1]
	var spell: int = by_id[SPELL_CARD][0]

	# --- play two units into the SAME lane plus the spell -----------------------
	st.players[me].current_mana = BIG_MANA
	_expect(_ctl.submit_local(_mi.play_card(unit_a, LANE, -1)), "play unit A accepted")
	await _idle()
	_expect(_ctl.submit_local(_mi.play_card(unit_b, LANE, -1)), "play unit B accepted")
	await _idle()
	_expect(_ctl.submit_local(_mi.play_card(spell, SPELL_COL, -1)), "play spell accepted")
	await _idle()

	# Capture the slots BEFORE the undo: these are the objects that must be freed.
	var old_slots := {}
	for id: int in [unit_a, unit_b, spell]:
		var node = _pres.node_for(id)
		_expect(node != null, "node exists for #%d before undo" % id)
		if node == null:
			continue
		var slot = node.card_slot_is_in
		_expect(slot != null, "#%d sits in a slot before undo" % id)
		if slot != null:
			_expect(slot.card_in_slot, "#%d's slot is marked occupied before undo" % id)
			old_slots[id] = slot
	_expect(st.card(unit_a).location == LOC_BOARD, "unit A is on BOARD before undo (got %d)" % st.card(unit_a).location)
	_expect(st.card(spell).location == LOC_SPELL_ZONE, "spell is in SPELL_ZONE before undo (got %d)" % st.card(spell).location)

	# --- undo every play of the turn -------------------------------------------
	_expect(_ctl.submit_local(_mi.undo()), "undo accepted")
	await _idle()

	for id: int in [unit_a, unit_b, spell]:
		await _assert_back_in_hand(id, old_slots.get(id))

	# --- replay every card -----------------------------------------------------
	for id: int in [unit_a, unit_b, spell]:
		var is_spell: bool = str(st.card(id).card_id) == SPELL_CARD
		var col: int = SPELL_COL if is_spell else LANE
		# The undo's mana refund is clamped to the turn's max pool, which is 1 on turn
		# one, so each replay needs its budget handed out again.
		st.players[me].current_mana = BIG_MANA
		_expect(_ctl.submit_local(_mi.play_card(id, col, -1)), "replay #%d accepted" % id)
		await _idle()
		var node = _pres.node_for(id)
		_expect(node != null, "replayed #%d has a node" % id)
		if node == null:
			continue
		var slot = node.card_slot_is_in
		_expect(slot != null, "replayed #%d has a fresh slot" % id)
		if slot == null:
			continue
		_expect(slot.card_in_slot, "replayed #%d's new slot is occupied" % id)
		var zone: Array = _board.cards_by_zone.get(Vector2i(col, LOCAL_ROW), [])
		_expect(node in zone, "replayed #%d is in Board zone (%d,%d)" % [id, col, LOCAL_ROW])
		_expect(st.card(id).col == col, "replayed #%d engine col is %d (got %d)" % [id, col, st.card(id).col])

	_finish()


# --- assertions ------------------------------------------------------------------

## Everything an undone card must satisfy: the engine says it is in hand again, the
## vacated slot is free, the node is in no board zone, the drop lookup that
## CardManager._finish_drag_engine uses finds a free slot in that lane, the click area
## is live, a click at the node lands on it, and a drag starts as a HAND drag.
func _assert_back_in_hand(id: int, old_slot: Variant) -> void:
	var node = _pres.node_for(id)
	_expect(node != null, "#%d still has its node after undo" % id)
	if node == null:
		return
	var card = _ctl.state.card(id)
	_expect(card.location == LOC_HAND, "#%d engine location is HAND (got %d)" % [id, card.location])

	if old_slot != null:
		_expect(not old_slot.card_in_slot, "#%d's vacated slot is free (card_in_slot=%s)" % [id, str(old_slot.card_in_slot)])
	var in_zone := false
	for key: Vector2i in _board.cards_by_zone:
		if node in _board.cards_by_zone[key]:
			in_zone = true
	_expect(not in_zone, "#%d is in no Board.cards_by_zone after undo" % id)
	_expect(node.card_slot_is_in == null, "#%d has card_slot_is_in cleared (got %s)" % [id, str(node.card_slot_is_in)])

	var collider = node.get_node_or_null("Area2D/CollisionShape2D")
	_expect(collider != null, "#%d has a CollisionShape2D" % id)
	if collider != null:
		_expect(not collider.disabled, "#%d collider is enabled after undo" % id)

	await _settle(node)
	var hit: bool = await _click_hits(node)
	_expect(hit, "#%d is among the mask==1 hits at its own position" % id)

	if old_slot != null:
		var found = _board.get_next_available_slot_for_position(old_slot.global_position)
		_expect(found != null, "#%d's old position still resolves to a drop slot" % id)
		if found != null:
			# Not necessarily old_slot itself: the lookup hands back the FIRST free slot
			# of the zone, and with two units undone the back unit's own slot is no longer
			# the first one. What matters is that the lane can take a card again.
			_expect(not found.card_in_slot, "#%d's drop lookup lands on a free slot" % id)
			_expect(_board.get_zone_for_slot(found) == _board.get_zone_for_slot(old_slot), "#%d's drop lookup stays in its own zone" % id)

	_reset_drag()
	_cm.start_drag(node)
	_expect(_cm.card_being_dragged == node, "#%d start_drag began a drag" % id)
	_expect(not bool(_cm.get("_is_swap_drag")), "#%d start_drag is a HAND drag (is_swap=%s)" % [id, str(_cm.get("_is_swap_drag"))])
	_reset_drag()

	# The same thing again, but the way the PLAYER does it: put the real mouse on the
	# card and let InputManager.raycast_at_cursor() pick it. This is the path the
	# inverted collider broke, so asserting only on a direct start_drag would miss it.
	var clicked: Dictionary = await _left_click_via_input(node)
	_expect(clicked["dragged"] == node, "#%d a real left click on it starts ITS drag (got %s)" % [id, str(clicked["dragged"])])
	_expect(not bool(clicked["is_swap"]), "#%d a real left click on it is a HAND drag (is_swap=%s)" % [id, str(clicked["is_swap"])])


## The exact left-click path the player uses: warp the real mouse onto the card and let
## InputManager.raycast_at_cursor() decide, rather than calling CardManager.start_drag
## directly. raycast_at_cursor accepts only a collision_mask == 1 hit and a board/hand
## card overlaps other things at the same point, so this is what proves the card is
## reachable by a click at all.
##
## Returns {"dragged": the node CardManager took, or null, "is_swap": bool}. Drag state is
## reset before and after, so later steps are unaffected.
func _left_click_via_input(node: Node) -> Dictionary:
	await _mouse_on(node)
	_reset_drag()
	_im.raycast_at_cursor()
	var out := {
		"dragged": _cm.card_being_dragged,
		"is_swap": bool(_cm.get("_is_swap_drag")),
	}
	_reset_drag()
	return out


## Headless runs in a tiny window, so a card's world position is NOT its screen position.
## The viewport's final transform bridges the two; without it warp_mouse would leave the
## cursor nowhere near the card and the raycast would find whatever is under (0, 0).
func _mouse_on(node: Node) -> void:
	var screen: Vector2 = _main.get_viewport().get_final_transform() * node.get_global_transform_with_canvas().origin
	_main.get_viewport().warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	await process_frame
	await physics_frame


## True when `node` is among the mask == 1 hits at its own global position. Hand cards
## overlap, so being merely the FIRST hit proves nothing.
func _click_hits(node: Node) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = node.global_position
	q.collide_with_areas = true
	await physics_frame
	var hits: Array = _main.get_world_2d().direct_space_state.intersect_point(q)
	for hit: Dictionary in hits:
		var collider = hit.get("collider", null)
		if collider == null or int(collider.collision_mask) != 1:
			continue
		if collider.get_parent() == node:
			return true
	return false


# --- harness ---------------------------------------------------------------------

func _boot() -> void:
	_main = load("res://Scenes/Main.tscn").instantiate()
	_main.name = "Main"
	root.add_child(_main)
	await process_frame
	_ctl = load("res://Scripts/Presentation/MatchController.gd").new()
	_ctl.name = "MatchController"
	_pres = load("res://Scripts/Presentation/MatchPresenter.gd").new()
	_pres.name = "MatchPresenter"
	_main.add_child(_ctl)
	_main.add_child(_pres)
	_main.get_node("LobbyUI").get_node("Panel").visible = false
	_cm = _main.get_node("CardManager")
	_im = _main.get_node("InputManager")
	_board = _main.get_node("Board")
	_ctl.start_offline(_chips_and_spells(), _chips_and_spells(), SEED)
	await _wait_play_phase()


func _chips_and_spells() -> Array:
	var deck: Array = []
	for i in DECK_CHIPS:
		deck.append(UNIT_CARD)
	for i in DECK_SPELLS:
		deck.append(SPELL_CARD)
	return deck


func _wait_play_phase() -> void:
	for i in 4000:
		await process_frame
		if _ctl.is_play_phase() and not _pres.is_busy():
			return
	_fail("harness", "never reached an idle play phase")


func _idle() -> void:
	for i in 2000:
		await process_frame
		if not _pres.is_busy():
			return


## The presenter going idle does NOT mean the hand has stopped moving: _sync_hand_nodes
## and update_hand_position run their own tweens outside the presenter's queue. A physics
## query taken mid-slide would test a position the card is not going to rest at, so wait
## for the node to actually stop moving. Bounded: three stable frames, at most 600.
func _settle(node: Node) -> void:
	var last: Vector2 = node.global_position
	var stable := 0
	for i in 600:
		await process_frame
		if node.global_position == last:
			stable += 1
			if stable >= 3:
				return
		else:
			stable = 0
			last = node.global_position


func _reset_drag() -> void:
	_cm.card_being_dragged = null
	_cm.set("_is_swap_drag", false)


func _hand_ids_by_card_id(st, me: int) -> Dictionary:
	# Both keys always present: a card missing from the opening hand must come back as
	# an empty list, not as a key error that aborts the run before it can report.
	var out := {UNIT_CARD: [], SPELL_CARD: []}
	for id: int in st.players[me].hand:
		var key := str(st.card(id).card_id)
		if not out.has(key):
			out[key] = []
		out[key].append(int(id))
	return out


func _expect(condition: bool, name: String) -> void:
	if condition:
		print("[PASS] %s" % name)
	else:
		_fail(name, "condition was false")


func _fail(name: String, detail: String) -> void:
	_failures += 1
	print("[FAIL] %s: %s" % [name, detail])


func _finish() -> void:
	print("[DONE] %s" % ("PASS" if _failures == 0 else "FAIL (%d assertions)" % _failures))
	quit(0 if _failures == 0 else 1)