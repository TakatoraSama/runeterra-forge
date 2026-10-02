extends SceneTree
## Scene regression: a card RECALLED to your own hand can be played again.
##
## Bug: the LOCAL branch of MatchPresenter._on_card_recalled had the same flaw
## _on_play_undone had — it called _remove_from_zone_model(id) and nothing else. The
## node went back to the hand but stayed registered in Board.cards_by_zone with its
## slot marked occupied, and Card.card_slot_is_in was left pointing at that slot, so
## CardManager._start_drag_engine treated the returned card as a board card and
## can_start_swap refused it: no drag started.
##
## Recall card: NavoriConspirator, "{Play}: Recall other allies here"
## (AbilityType recall_allies_same_lane). It is chosen over SolitaryMonk
## (recall_cost_allies) because it needs no target and no cost-bracket condition: any
## other resolved unit in the lane it lands in is recalled, so a single plain Chip in
## that lane satisfies it. Its {Play} ability fires during RESOLVE, so the sequence is
## play Chip -> end turn -> next play phase -> play Navori Conspirator -> end turn.
##
## Deck: eight Chip plus four NavoriConspirator. Seed 5 deals Chip + Navori
## Conspirator + Chip + Navori Conspirator, so both cards are in hand on turn one.

const SEED := 5
const DECK_CHIPS := 8
const DECK_NAVORI := 4
const LANE := 0
const BIG_MANA := 9
const LOCAL_ROW := 1
const UNIT_CARD := "Chip"
const RECALL_CARD := "NavoriConspirator"

const LOC_HAND := 1
const LOC_BOARD := 2

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
	if by_id[UNIT_CARD].size() < 1 or by_id[RECALL_CARD].size() < 1:
		_fail("deck", "opening hand lacks %s and %s: %s" % [UNIT_CARD, RECALL_CARD, str(by_id)])
		_finish()
		return
	var ally: int = by_id[UNIT_CARD][0]

	# --- turn 1: play the ally into the lane and let it resolve -----------------
	st.players[me].current_mana = BIG_MANA
	_expect(_ctl.submit_local(_mi.play_card(ally, LANE, -1)), "play %s accepted" % UNIT_CARD)
	await _idle()
	var ally_node = _pres.node_for(ally)
	_expect(ally_node != null, "%s #%d has a node" % [UNIT_CARD, ally])
	var old_slot = ally_node.card_slot_is_in if ally_node != null else null
	_expect(_ctl.submit_local(_mi.end_turn()), "end turn 1 accepted")
	await _next_play_phase()
	_expect(st.card(ally).is_resolved, "#%d is resolved after turn 1" % ally)
	_expect(st.card(ally).col == LANE, "#%d stayed in lane %d (got %d)" % [ally, LANE, st.card(ally).col])

	# --- turn 2: play the recall card in the same lane, let it resolve ---------
	var navori: Array = _hand_ids_by_card_id(st, me)[RECALL_CARD]
	if navori.size() < 1:
		_fail("deck", "no %s in hand on turn 2" % RECALL_CARD)
		_finish()
		return
	var recaller: int = navori[0]
	st.players[me].current_mana = BIG_MANA
	_expect(_ctl.submit_local(_mi.play_card(recaller, LANE, -1)), "play %s accepted" % RECALL_CARD)
	await _idle()
	_expect(_ctl.submit_local(_mi.end_turn()), "end turn 2 accepted")
	await _next_play_phase()

	# --- the recall has happened ------------------------------------------------
	_expect(st.card(ally).location == LOC_HAND, "recalled #%d is back in hand (got location %d)" % [ally, st.card(ally).location])
	await _assert_back_in_hand(ally, old_slot)

	# --- and it can be played once more ----------------------------------------
	st.players[me].current_mana = BIG_MANA
	_expect(_ctl.submit_local(_mi.play_card(ally, LANE, -1)), "replay #%d accepted" % ally)
	await _idle()
	var node = _pres.node_for(ally)
	_expect(node != null, "replayed #%d has a node" % ally)
	if node != null:
		var slot = node.card_slot_is_in
		_expect(slot != null, "replayed #%d has a fresh slot" % ally)
		_expect(st.card(ally).col == LANE, "replayed #%d engine col is %d (got %d)" % [ally, LANE, st.card(ally).col])
		var zone: Array = _board.cards_by_zone.get(Vector2i(LANE, LOCAL_ROW), [])
		_expect(node in zone, "replayed #%d is in Board zone (%d,%d)" % [ally, LANE, LOCAL_ROW])

	_finish()


# --- assertions ------------------------------------------------------------------

## The recalled card must look exactly like an undone one: engine says hand, slot
## freed, node in no board zone, card_slot_is_in cleared, a live click area that a
## point query hits, and a drag that starts as a HAND drag.
func _assert_back_in_hand(id: int, old_slot: Variant) -> void:
	var node = _pres.node_for(id)
	_expect(node != null, "#%d still has its node after the recall" % id)
	if node == null:
		return
	var card = _ctl.state.card(id)
	_expect(card.location == LOC_HAND, "#%d engine location is HAND (got %d)" % [id, card.location])

	if old_slot != null:
		# old_slot need not end up FREE: Navori Conspirator landed in the SAME lane, and
		# the zone rebuild handed it the very slot the recalled card vacated. What has to
		# hold is that this lane's slots and its registered cards agree with each other.
		_assert_zone_consistent(LANE, "after the recall")
		var found = _board.get_next_available_slot_for_position(old_slot.global_position)
		_expect(found != null, "#%d's old position still resolves to a drop slot" % id)
		if found != null:
			_expect(_board.get_zone_for_slot(found) == _board.get_zone_for_slot(old_slot), "#%d's drop lookup stays in its own zone" % id)
	var in_zone := false
	for key: Vector2i in _board.cards_by_zone:
		if node in _board.cards_by_zone[key]:
			in_zone = true
	_expect(not in_zone, "#%d is in no Board.cards_by_zone after the recall" % id)
	_expect(node.card_slot_is_in == null, "#%d has card_slot_is_in cleared (got %s)" % [id, str(node.card_slot_is_in)])

	var collider = node.get_node_or_null("Area2D/CollisionShape2D")
	_expect(collider != null, "#%d has a CollisionShape2D" % id)
	if collider != null:
		_expect(not collider.disabled, "#%d collider is enabled after the recall" % id)

	await _settle(node)
	var hit: bool = await _click_hits(node)
	_expect(hit, "#%d is among the mask==1 hits at its own position" % id)

	_reset_drag()
	_cm.start_drag(node)
	_expect(_cm.card_being_dragged == node, "#%d start_drag began a drag" % id)
	_expect(not bool(_cm.get("_is_swap_drag")), "#%d start_drag is a HAND drag (is_swap=%s)" % [id, str(_cm.get("_is_swap_drag"))])
	_reset_drag()

	# The same thing again, the way the PLAYER does it: put the real mouse on the card
	# and let InputManager.raycast_at_cursor() pick it. raycast_at_cursor accepts only a
	# collision_mask == 1 hit, so this is what proves the recalled card is clickable again.
	var clicked: Dictionary = await _left_click_via_input(node)
	_expect(clicked["dragged"] == node, "#%d a real left click on it starts ITS drag (got %s)" % [id, str(clicked["dragged"])])
	_expect(not bool(clicked["is_swap"]), "#%d a real left click on it is a HAND drag (is_swap=%s)" % [id, str(clicked["is_swap"])])


## The lane's slot flags and its registered card nodes must describe the same set:
## every occupied slot holds a card registered in this zone, and every card registered
## in this zone sits in one of this zone's slots. A card that left for the hand while
## staying registered in Board.cards_by_zone breaks the first half — which is exactly
## what the unfixed presenter leaves behind.
func _assert_zone_consistent(col: int, when: String) -> void:
	var zone_key := Vector2i(col, LOCAL_ROW)
	var registered: Array = _board.cards_by_zone.get(zone_key, [])
	var slots: Array = _board.slots_by_zone.get(zone_key, [])
	for slot in slots:
		if not slot.card_in_slot:
			continue
		var holder = null
		for card in registered:
			if card.card_slot_is_in == slot:
				holder = card
		_expect(holder != null, "zone (%d,%d) %s: an occupied slot has a registered holder" % [col, LOCAL_ROW, when])
	for card in registered:
		_expect(card.card_slot_is_in != null and card.card_slot_is_in in slots, "zone (%d,%d) %s: a registered card sits in one of this zone's slots" % [col, LOCAL_ROW, when])


## The exact left-click path the player uses: warp the real mouse onto the card and let
## InputManager.raycast_at_cursor() decide, rather than calling CardManager.start_drag
## directly. raycast_at_cursor accepts only a collision_mask == 1 hit and hand cards
## overlap, so this is what proves the card is reachable by a click at all.
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
	_ctl.start_offline(_deck(), _bot_deck(), SEED)
	await _wait_play_phase()


func _deck() -> Array:
	var deck: Array = []
	for i in DECK_CHIPS:
		deck.append(UNIT_CARD)
	for i in DECK_NAVORI:
		deck.append(RECALL_CARD)
	return deck


func _bot_deck() -> Array:
	var deck: Array = []
	for i in 6:
		deck.append(UNIT_CARD)
	for i in 4:
		deck.append(RECALL_CARD)
	return deck


func _wait_play_phase() -> void:
	for i in 4000:
		await process_frame
		if _ctl.is_play_phase() and not _pres.is_busy():
			return
	_fail("harness", "never reached an idle play phase")


## Waits for the bot to finish its turn and for OUR next play phase to open. The bot
## ends its own turn, so this returns on its own; the bound is the only exit besides
## success.
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


## The presenter going idle does NOT mean the hand has stopped moving: the recall
## scale tween and update_hand_position run outside the presenter's queue. Wait for the
## node to actually stop moving before querying physics. Bounded: three stable frames.
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
	var out := {UNIT_CARD: [], RECALL_CARD: []}
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