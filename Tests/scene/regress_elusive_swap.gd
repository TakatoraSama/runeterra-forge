extends SceneTree
## Scene regression: a resolved Elusive card can be dragged to another lane.
##
## Bug: MatchPresenter._on_card_played ended with
##   _set_collider(node, not _card_data_keywords(...).has("Elusive"))
## which is inverted: it DISABLED the click area on the Elusive card and enabled it on
## every other card. InputManager.raycast_at_cursor only accepts collision_mask == 1
## hits, and a board card overlaps its slot (mask 2), so the Elusive card was never the
## hit that started anything and no swap drag could begin.
##
## Drives the REAL Main.tscn, controller, presenter and CardManager. Ahri1 (cost 1,
## printed Elusive) is the subject; Chip (cost 1, no keywords, no ability) is the own
## non-Elusive control, and the bot plays Chips of its own so there is a resolved
## opponent card to control as well.
##
## Deck: ten Ahri1 plus two Chip; seed 4 deals Ahri1, Chip, Ahri1, Ahri1. Bot: twelve
## Chip, which it can afford and play from its first turn.

const SEED := 4
const LANE := 0
const OTHER_LANE := 1
const LANE_TWO := 2
const BIG_MANA := 9
const LOCAL_ROW := 1
const ELUSIVE_CARD := "Ahri1"
const PLAIN_CARD := "Chip"

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
	var foe: int = 1 - me
	var by_id := _hand_ids_by_card_id(st, me)
	if by_id[ELUSIVE_CARD].is_empty() or by_id[PLAIN_CARD].is_empty():
		_fail("deck", "opening hand lacks %s and %s: %s" % [ELUSIVE_CARD, PLAIN_CARD, str(by_id)])
		_finish()
		return
	var ahri: int = by_id[ELUSIVE_CARD][0]
	var plain: int = by_id[PLAIN_CARD][0]

	# --- turn 1: play Ahri and a plain unit, then let both resolve -------------
	# Ahri's own {Play} is nothing; its swap ability recalls the weakest ally in the lane
	# it LEFT, so the plain unit goes in lane 2 to stay out of that.
	st.players[me].current_mana = BIG_MANA
	_expect(_ctl.submit_local(_mi.play_card(ahri, LANE, -1)), "play %s accepted" % ELUSIVE_CARD)
	await _idle()
	_expect(_ctl.submit_local(_mi.play_card(plain, LANE_TWO, -1)), "play %s accepted" % PLAIN_CARD)
	await _idle()
	_expect(_ctl.submit_local(_mi.end_turn()), "end turn 1 accepted")
	await _next_play_phase()

	var ahri_node = _pres.node_for(ahri)
	_expect(ahri_node != null, "%s #%d has a node" % [ELUSIVE_CARD, ahri])
	if ahri_node == null:
		_finish()
		return
	_expect(st.card(ahri).is_resolved, "%s is resolved" % ELUSIVE_CARD)
	_expect(st.card(ahri).has_keyword("Elusive"), "%s reports the Elusive keyword" % ELUSIVE_CARD)
	_expect(ahri_node.card_slot_is_in != null, "%s sits in a board slot" % ELUSIVE_CARD)
	_expect(bool(_pres.call("can_start_swap", ahri)), "can_start_swap allows the Elusive card")

	# --- the swap drag must be reachable from a click --------------------------
	await _settle(ahri_node)
	_assert_collider_enabled(ahri_node, ELUSIVE_CARD)
	_expect(await _click_hits(ahri_node), "%s is among the mask==1 hits at its own position" % ELUSIVE_CARD)
	_reset_drag()
	_cm.start_drag(ahri_node)
	_expect(_cm.card_being_dragged == ahri_node, "%s start_drag began a drag" % ELUSIVE_CARD)
	_expect(bool(_cm.get("_is_swap_drag")), "%s start_drag is a SWAP drag (is_swap=%s)" % [ELUSIVE_CARD, str(_cm.get("_is_swap_drag"))])
	_reset_drag()

	# And the same through the REAL left-click path: warp the mouse onto the card and let
	# InputManager.raycast_at_cursor() pick it. raycast_at_cursor accepts only a
	# collision_mask == 1 hit, which is exactly what the inverted collider removed, so a
	# direct start_drag() call alone would NOT catch this bug.
	var ahri_click: Dictionary = await _left_click_via_input(ahri_node)
	_expect(ahri_click["dragged"] == ahri_node, "a real left click on %s starts ITS drag (got %s)" % [ELUSIVE_CARD, str(ahri_click["dragged"])])
	_expect(bool(ahri_click["is_swap"]), "a real left click on %s is a SWAP drag (is_swap=%s)" % [ELUSIVE_CARD, str(ahri_click["is_swap"])])

	# --- the swap itself, and where it lands ----------------------------------
	_expect(_ctl.submit_local(_mi.swap_card(ahri, OTHER_LANE)), "swap to lane %d accepted" % OTHER_LANE)
	await _idle()
	_expect(_ctl.submit_local(_mi.end_turn()), "end turn 2 accepted")
	await _next_play_phase()

	_expect(st.card(ahri).col == OTHER_LANE, "%s engine col is %d after the swap (got %d)" % [ELUSIVE_CARD, OTHER_LANE, st.card(ahri).col])
	var moved = _pres.node_for(ahri)
	_expect(moved != null, "%s still has a node after the swap" % ELUSIVE_CARD)
	if moved != null:
		var zone: Array = _board.cards_by_zone.get(Vector2i(OTHER_LANE, LOCAL_ROW), [])
		_expect(moved in zone, "%s is registered in Board zone (%d,%d)" % [ELUSIVE_CARD, OTHER_LANE, LOCAL_ROW])
		_expect(moved.card_slot_is_in != null, "%s has a slot in its new lane" % ELUSIVE_CARD)
		_assert_collider_enabled(moved, "%s after the swap" % ELUSIVE_CARD)
		# Ahri keeps its collider, so its right-click goes down the mask-1 physics branch
		# of _handle_right_click rather than the _get_in_play_card_at_cursor fallback.
		_expect(await _right_click_targets(moved) == moved, "right-click on %s after the swap previews it" % ELUSIVE_CARD)

	# --- control 1: a resolved own non-Elusive unit is display-only -----------
	var plain_node = _pres.node_for(plain)
	_expect(plain_node != null, "%s #%d has a node" % [PLAIN_CARD, plain])
	if plain_node != null:
		_expect(st.card(plain).is_resolved, "%s is resolved" % PLAIN_CARD)
		_expect(not st.card(plain).has_keyword("Elusive"), "%s has no Elusive keyword" % PLAIN_CARD)
		await _settle(plain_node)
		_assert_collider_disabled(plain_node, "resolved own non-Elusive %s" % PLAIN_CARD)
		_expect(not await _click_hits(plain_node), "resolved own non-Elusive %s is not a mask==1 click hit" % PLAIN_CARD)
		_reset_drag()
		_cm.start_drag(plain_node)
		_expect(_cm.card_being_dragged == null, "resolved own non-Elusive %s starts no drag" % PLAIN_CARD)
		_reset_drag()
		var plain_click: Dictionary = await _left_click_via_input(plain_node)
		_expect(plain_click["dragged"] == null, "a real left click on own non-Elusive %s starts nothing (got %s)" % [PLAIN_CARD, str(plain_click["dragged"])])
		# Disabling the collider must NOT have cost the card its right-click preview: that
		# path falls back to _get_in_play_card_at_cursor, which needs card_slot_is_in.
		_expect(await _right_click_targets(plain_node) == plain_node, "right-click on own non-Elusive %s previews it" % PLAIN_CARD)

	# --- control 2: an opponent card is display-only too ----------------------
	var foe_card := _first_opponent_board_card(st, foe)
	if foe_card == null:
		_fail("opponent", "the bot put nothing on the board, so the opponent control could not be checked")
	else:
		var foe_node = _pres.node_for(foe_card)
		_expect(foe_node != null, "opponent #%d has a node" % foe_card)
		if foe_node != null:
			await _settle(foe_node)
			_expect(not bool(_pres.call("can_start_swap", foe_card)), "can_start_swap refuses an opponent card")
			_assert_collider_disabled(foe_node, "resolved opponent #%d" % foe_card)
			_expect(not await _click_hits(foe_node), "opponent #%d is not a mask==1 click hit" % foe_card)
			_reset_drag()
			_cm.start_drag(foe_node)
			_expect(_cm.card_being_dragged == null, "opponent #%d starts no drag" % foe_card)
			_reset_drag()
			var foe_click: Dictionary = await _left_click_via_input(foe_node)
			_expect(foe_click["dragged"] == null, "a real left click on opponent #%d starts nothing (got %s)" % [foe_card, str(foe_click["dragged"])])
			_expect(await _right_click_targets(foe_node) == foe_node, "right-click on opponent #%d previews it" % foe_card)

	_finish()


# --- assertions ------------------------------------------------------------------

func _assert_collider_enabled(node: Node, what: String) -> void:
	var collider = node.get_node_or_null("Area2D/CollisionShape2D")
	_expect(collider != null, "%s has a CollisionShape2D" % what)
	if collider != null:
		_expect(not collider.disabled, "%s collider is enabled" % what)


func _assert_collider_disabled(node: Node, what: String) -> void:
	var collider = node.get_node_or_null("Area2D/CollisionShape2D")
	_expect(collider != null, "%s has a CollisionShape2D" % what)
	if collider != null:
		_expect(collider.disabled, "%s collider is disabled" % what)


## The exact left-click path the player uses: warp the real mouse onto the card and let
## InputManager.raycast_at_cursor() decide, rather than calling CardManager.start_drag
## directly. raycast_at_cursor accepts only a collision_mask == 1 hit, and a board card
## overlaps its slot (mask 2), so this is the only assertion that actually covers the
## input path the inverted collider broke.
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


## The right-click preview path, asserted on the card the signal actually carries.
## _handle_right_click() first tries a mask-1 physics hit and otherwise falls back to
## InputManager._get_in_play_card_at_cursor(), which requires card_slot_is_in — so this is
## what proves that disabling a board card's collider did not cost it its preview.
##
## CardPreviewManager is connected to the same signal and opens its overlay, which makes
## InputManager._input ignore every later event, so the overlay is closed again here before
## returning. It also disables its own Area2D, so it cannot pollute a physics query.
##
## The mouse is warped onto `node` first: _handle_right_click reads the live cursor, and a
## card that has since moved (Ahri, just after a lane swap) is no longer under wherever the
## cursor was left.
func _right_click_targets(node: Node) -> Node:
	await _mouse_on(node)
	var seen: Array = []
	var collect := func(card: Node) -> void: seen.append(card)
	_im.card_right_clicked.connect(collect)
	_im._handle_right_click()
	await process_frame
	var preview := _main.get_node_or_null("CardPreview")
	if preview != null:
		preview.visible = false
	_im.card_right_clicked.disconnect(collect)
	if seen.is_empty():
		return null
	var got = seen[0]
	return got if got is Node and is_instance_valid(got) else null


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


## True when `node` is among the mask == 1 hits at its own global position. A board card
## overlaps its slot (mask 2), so being merely the FIRST hit proves nothing — which is
## exactly how the inverted collider hid the Elusive card.
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


func _first_opponent_board_card(st, foe: int) -> int:
	for col in range(3):
		for id: int in st.zone_cards(col, foe):
			return int(id)
	return -1


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
	_ctl.start_offline(_human_deck(), _bot_deck(), SEED)
	await _wait_play_phase()


func _human_deck() -> Array:
	var deck: Array = []
	for i in 10:
		deck.append(ELUSIVE_CARD)
	for i in 2:
		deck.append(PLAIN_CARD)
	return deck


## Cheap units the bot can afford and play from its first turn, so an opponent card is
## on the board by the time the control assertions run. Chip carries no keywords and no
## ability, so it cannot stun or buff anything and stays a clean control.
func _bot_deck() -> Array:
	var deck: Array = []
	for i in 12:
		deck.append(PLAIN_CARD)
	return deck


func _wait_play_phase() -> void:
	for i in 4000:
		await process_frame
		if _ctl.is_play_phase() and not _pres.is_busy():
			return
	_fail("harness", "never reached an idle play phase")


## Waits for the bot to finish its turn and for OUR next play phase to open. The bot
## ends its own turn, so this returns on its own; the bound is the only other exit.
func _next_play_phase() -> void:
	for i in 6000:
		await process_frame
		if _ctl.is_play_phase() and not _pres.is_busy():
			return
	_fail("harness", "never reached the next play phase")


func _idle() -> void:
	for i in 2000:
		await process_frame
		if not _pres.is_busy():
			return


## The presenter going idle does NOT mean the board has stopped moving: the swap tween
## runs outside the presenter's queue. Wait for the node to stop before querying physics.
## Bounded: three stable frames, at most 600.
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


## Both keys are always present: a card missing from the opening hand must come back as
## an empty list, not as a key error that aborts the run before it can report anything.
func _hand_ids_by_card_id(st, me: int) -> Dictionary:
	var out := {ELUSIVE_CARD: [], PLAIN_CARD: []}
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