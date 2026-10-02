extends SceneTree
## Scene regression: an Elusive lane swap lays the board out the way the original game did.
##
## Three things were wrong, and this drives the REAL drop (mouse warp -> InputManager ->
## CardManager) so all three are covered:
##
##   1. The card was not board size after the drop. CardManager._start_drag_engine scales
##      a swap-dragged card to HAND size (0.2) and nothing scaled it back to board size
##      (0.15) on release.
##   2. The vacated slot did not free up during PLAY. The swap was only a position
##      preview, so the model AND Board.cards_by_zone still had the card in its origin
##      lane: a unit played into that lane landed after it instead of into its slot.
##   3. The card was pulled back. _on_card_swapped snapped it to its origin slot and then
##      tweened it across, so a card the player had just dropped in the new lane visibly
##      visited the old one first.
##
## The fix is a display layout (_display_ids) the Board is laid out from, while the model
## stays the engine's truth. Both scenarios run a real offline match through
## Scenes/Main.tscn with the real MatchController, MatchPresenter, CardManager,
## InputManager and BoardGeneration.
##
## Deck: four Ahri1 (cost 1, printed Elusive) + eight Chip (cost 1). Seed 5 deals
## Ahri1, Chip, Chip, Chip, which is exactly what scenario B needs to fill a lane.
##
## Scenario A (the user's own report): Ahri in Left slot 2, dragged to Middle; Left
##   compacts; a unit played into Left takes her old slot.
## Scenario B: a FULL lane with the Elusive last, swapped out, then a fifth card played
##   into the lane it just left. That fifth play is the engine room rule and is expected to
##   be REFUSED with zone_full until Scripts/Match implements it.

const SEED := 5
const SEED_C := 11
const LANE_LEFT := 0
const LANE_MIDDLE := 1
const LANE_RIGHT := 2
const BIG_MANA := 9
const LOCAL_ROW := 1
const ELUSIVE_CARD := "Ahri1"
const BOARD_SCALE := 0.15

# CardState.Location, spelled out because a SceneTree script must not reference a
# class_name at parse time: that compiles Card.gd before the autoloads exist.
const LOC_HAND := 1

var _failures := 0
var _main: Node
var _ctl: Node
var _pres: Node
var _cm: Node
var _im: Node
var _board: Node
var _mi: GDScript
var _booted_ok := false
var _subject := -1

# Pull-back watch: the node whose position is sampled every frame, and the origin-lane slot
# positions it must never be seen at.
var _watched: Node = null
var _forbidden: Array[Vector2] = []
var _sampled := 0
var _pullbacks := 0


func _initialize() -> void:
	_mi = load("res://Scripts/Match/MatchIntents.gd")
	await _scenario_a()
	_teardown()
	await _scenario_b()
	_teardown()
	await _scenario_c()
	_teardown()
	_finish()


# ---------------------------- Scenario A: the user's case ----------------------------

## Ahri in Left slot 2 -> drag her to Middle -> Left compacts -> a unit played into Left
## takes her old slot -> nothing ever snaps her back.
##
## Timeline, and why it is shaped this way: the opening hand is four cards, so turn one
## spends all of them (Left = X, Y, Ahri; Middle = Z), and turn two draws exactly one.
## Ahri's {swap} ability recalls the weakest RESOLVED ally of the lane she ARRIVES in, so
## at SWAP_LANE it takes Z out of Middle — which is why Left is untouched and why the
## "plays into her old slot" check is still meaningful one turn later.
func _scenario_a() -> void:
	print("[CASE] A: swap out of Left slot 2 into Middle")
	await _boot(SEED, _deck())
	if not _booted():
		return
	var st = _ctl.state
	var ahri := _hand_pick(ELUSIVE_CARD)
	if ahri < 0:
		_fail("A.deck", "no %s in the opening hand" % ELUSIVE_CARD)
		return
	_subject = ahri

	# --- turn 1: Left = [X, Y, Ahri] (Ahri last, so her slot really frees),
	#              Middle = [Z], so the destination is not empty.
	await _play_into(LANE_LEFT)
	await _play_into(LANE_LEFT)
	await _play(ahri, LANE_LEFT)
	await _play_into(LANE_MIDDLE)
	await _end_turn()
	await _next_play_phase()

	var node = _pres.node_for(ahri)
	if node == null:
		_fail("A.setup", "%s has no node" % ELUSIVE_CARD)
		return
	var lane0: Array = _lane_slots(LANE_LEFT)
	var lane1: Array = _lane_slots(LANE_MIDDLE)
	_expect(node.card_slot_is_in == lane0[2], "%s sits in Left slot 2 before the swap (got %s)" % [ELUSIVE_CARD, str(node.card_slot_is_in)])
	_expect(st.card(ahri).col == LANE_LEFT and st.card(ahri).slot == 2, "%s engine is (col0, slot2), got (col%d, slot%d)" % [ELUSIVE_CARD, st.card(ahri).col, st.card(ahri).slot])

	var ahri_old_slot = node.card_slot_is_in
	var behind_left: Array = []
	for card in _lane_cards(LANE_LEFT):
		if card != node:
			behind_left.append(card)
	_expect(behind_left.size() == 2, "Left holds 2 cards besides Ahri (got %d)" % behind_left.size())
	var power_left_before := _lane_power(LANE_LEFT)
	var power_middle_before := _lane_power(LANE_MIDDLE)
	var ahri_power := _card_power(ahri)

	# --- the drop, through the real input path -------------------------------
	if not await _real_drop(node, LANE_MIDDLE, "A", ELUSIVE_CARD, lane0):
		return

	# --- 1. board size, and the card is in the destination lane --------------
	_expect(is_equal_approx(node.scale.x, BOARD_SCALE) and is_equal_approx(node.scale.y, BOARD_SCALE), "%s is board size %s after the drop (got %s)" % [ELUSIVE_CARD, str(BOARD_SCALE), str(node.scale.x)])
	_expect(node in _lane_cards(LANE_MIDDLE), "%s is in Board.cards_by_zone[%d,%d] after the drop" % [ELUSIVE_CARD, LANE_MIDDLE, LOCAL_ROW])
	_expect(node.card_slot_is_in != null and node.card_slot_is_in in lane1, "%s has a Middle slot after the drop" % ELUSIVE_CARD)
	_expect(node not in _lane_cards(LANE_LEFT), "%s left Board.cards_by_zone[%d,%d]" % [ELUSIVE_CARD, LANE_LEFT, LOCAL_ROW])

	# --- 2. the origin compacted and the vacated slot is free ---------------
	_expect(not bool(ahri_old_slot.card_in_slot), "%s's vacated Left slot is free (card_in_slot=%s)" % [ELUSIVE_CARD, str(ahri_old_slot.card_in_slot)])
	var left_now: Array = _lane_cards(LANE_LEFT)
	_expect(left_now.size() == 2, "Left compacts to 2 cards (got %d)" % left_now.size())
	for i in left_now.size():
		_expect(left_now[i].card_slot_is_in == lane0[i], "Left card %d is compacted onto slot %d" % [i, i])
	for card in behind_left:
		_expect(card in left_now, "the card behind %s survived the compaction" % ELUSIVE_CARD)

	# --- power labels follow the DISPLAY, not the model --------------------
	_expect(_lane_power(LANE_LEFT) == power_left_before - ahri_power, "Left's power label drops %s's power at the drop (%d -> %d)" % [ELUSIVE_CARD, power_left_before, _lane_power(LANE_LEFT)])
	_expect(_lane_power(LANE_MIDDLE) == power_middle_before + ahri_power, "Middle's power label gains %s's power at the drop (%d -> %d)" % [ELUSIVE_CARD, power_middle_before, _lane_power(LANE_MIDDLE)])

	# --- the user's case: a new unit into Left takes Ahri's old slot -------
	var into_left := await _play_into(LANE_LEFT)
	if into_left >= 0:
		var u = _pres.node_for(into_left)
		_expect(u != null and u.card_slot_is_in == ahri_old_slot, "a unit played into Left takes %s's old slot" % ELUSIVE_CARD)
		_assert_no_overlap(LANE_LEFT, "Left after a later play")
	else:
		_fail("A.play", "no card in hand to play into Left after the drop")

	# --- 3. no pull-back, through SWAP_LANE into the next PLAY phase ---------
	await _end_turn()
	await _next_play_phase()
	_stop_watch()
	_expect(_pullbacks == 0, "%s never sat on a Left slot position after the drop (samples=%d, pull-backs=%d)" % [ELUSIVE_CARD, _sampled, _pullbacks])

	_expect(st.card(ahri).col == LANE_MIDDLE, "%s engine col is %d after SWAP_LANE (got %d)" % [ELUSIVE_CARD, LANE_MIDDLE, st.card(ahri).col])
	_expect(node in _lane_cards(LANE_MIDDLE), "%s is still in Board.cards_by_zone[%d,%d] on the next turn" % [ELUSIVE_CARD, LANE_MIDDLE, LOCAL_ROW])
	_expect(node.card_slot_is_in != null and node.card_slot_is_in in lane1, "%s has a Middle slot on the next turn" % ELUSIVE_CARD)
	_expect(is_equal_approx(node.scale.x, BOARD_SCALE), "%s is still board size on the next turn (got %s)" % [ELUSIVE_CARD, str(node.scale.x)])

	# --- a unit into the destination does not land on top of Ahri ----------
	var into_middle := await _play_into(LANE_MIDDLE)
	if into_middle >= 0:
		var v = _pres.node_for(into_middle)
		_expect(v != null and v.card_slot_is_in != node.card_slot_is_in, "a unit played into Middle does not overlap %s" % ELUSIVE_CARD)
		_assert_no_overlap(LANE_MIDDLE, "Middle after a later play")
	else:
		_fail("A.play", "no card in hand to play into Middle on the next turn")


# ---------------------------- Scenario B: the full-lane overflow ----------------------------

## Right lane holds four cards with the Elusive LAST. She is swapped out, which frees the
## lane, and a fifth card is played into it during the same PLAY phase. That fifth play is
## the engine room rule: it is REFUSED with zone_full until Scripts/Match implements it.
func _scenario_b() -> void:
	print("[CASE] B: full lane, swap the Elusive out, play a fifth card into it")
	await _boot(SEED, _deck())
	if not _booted():
		return
	var st = _ctl.state
	var ahri := _hand_pick(ELUSIVE_CARD)
	if ahri < 0:
		_fail("B.deck", "no %s in the opening hand" % ELUSIVE_CARD)
		return
	_subject = ahri

	await _play_into(LANE_RIGHT)
	await _play_into(LANE_RIGHT)
	await _play_into(LANE_RIGHT)
	await _play(ahri, LANE_RIGHT)
	await _end_turn()
	await _next_play_phase()

	var node = _pres.node_for(ahri)
	if node == null:
		_fail("B.setup", "%s has no node" % ELUSIVE_CARD)
		return
	var lane2: Array = _lane_slots(LANE_RIGHT)
	_expect(_lane_cards(LANE_RIGHT).size() == 4, "Right lane is full with 4 cards (got %d)" % _lane_cards(LANE_RIGHT).size())
	_expect(node.card_slot_is_in == lane2[3], "%s is the last card of the full Right lane" % ELUSIVE_CARD)
	var ahri_old_slot = node.card_slot_is_in

	# --- the swap out ---------------------------------------------------------
	if not await _real_drop(node, LANE_LEFT, "B", ELUSIVE_CARD, []):
		return
	_expect(node in _lane_cards(LANE_LEFT), "%s moved to Board.cards_by_zone[%d,%d]" % [ELUSIVE_CARD, LANE_LEFT, LOCAL_ROW])
	_expect(_lane_cards(LANE_RIGHT).size() == 3, "Right shows 3 cards once %s is queued out (got %d)" % [ELUSIVE_CARD, _lane_cards(LANE_RIGHT).size()])
	_expect(not bool(ahri_old_slot.card_in_slot), "the vacated Right slot is free (card_in_slot=%s)" % str(ahri_old_slot.card_in_slot))

	# --- the fifth card, same PLAY phase. Needs the engine room rule. ---------
	var fifth := _hand_pick_filler()
	if fifth < 0:
		_fail("B.play", "no card left in hand for the overflow play")
		return
	_expect(_ctl.submit_local(_mi.play_card(fifth, LANE_RIGHT, -1)), "a fifth card into the lane %s is leaving is ACCEPTED" % ELUSIVE_CARD)
	await _idle()
	var v = _pres.node_for(fifth)
	_expect(v != null, "the overflow card has a node")
	if v != null:
		_expect(v.card_slot_is_in != null, "the overflow card has a slot")
		_expect(st.card(fifth).col == LANE_RIGHT, "the overflow card's engine col is %d (got %d)" % [LANE_RIGHT, st.card(fifth).col])
	_assert_no_overlap(LANE_RIGHT, "Right with the overflow card")

	# --- after SWAP_LANE: engine == model == Board, nothing overlapping ------
	await _end_turn()
	await _next_play_phase()
	var right_now: Array = _lane_cards(LANE_RIGHT)
	_expect(right_now.size() == 4, "Right settles at 4 cards after SWAP_LANE (got %d)" % right_now.size())
	_assert_no_overlap(LANE_RIGHT, "Right after SWAP_LANE")
	_expect(node in _lane_cards(LANE_LEFT), "%s settled in Left" % ELUSIVE_CARD)
	for card in right_now:
		var id: int = _pres.instance_of(card)
		_expect(st.card(id).col == LANE_RIGHT, "settled Right card #%d engine col is %d" % [id, LANE_RIGHT])
		_expect(card.card_slot_is_in != null, "settled Right card #%d has a slot" % id)


# ---------------------------- Scenario C: two swaps in one turn ----------------------------

## Two own swaps queued in one turn, which is what turns the mid-SWAP_LANE re-lay into a
## visible pull-back.
##
## The engine walks the swap queue in order, and each step emits card_swapped and THEN the
## arriving card's {swap} ability. Ahri's recalls the weakest RESOLVED ally of the lane she
## ARRIVES in, and that recall re-lays lane 1 — the origin lane of the SECOND swap, which
## has not been executed yet. If the pending queue was emptied at the SWAP_LANE phase
## change, that re-lay finds the second card still registered in the model and puts it back
## on a lane-1 slot until its own card_swapped arrives.
##
## So: Zed (Elusive, power 2) sits in lane 1 behind a Chip (power 1); Ahri arrives into
## lane 1 and recalls the Chip; lane 1 is re-laid while Zed is still queued out. Zed must
## never be seen on a lane-1 slot position from his drop through SWAP_LANE.
func _scenario_c() -> void:
	print("[CASE] C: two swaps queued in one turn, a lane re-laid mid-SWAP_LANE")
	await _boot(SEED_C, _deck_c())
	if not _booted():
		return
	var st = _ctl.state
	var ahri := _hand_pick(ELUSIVE_CARD)
	var zed := _hand_pick("Zed1")
	if ahri < 0 or zed < 0:
		_fail("C.deck", "opening hand lacks Ahri1 and Zed1")
		return
	_subject = ahri

	# --- turn 1: Ahri in Left, Zed in Middle behind a weaker Chip -------------
	await _play(ahri, LANE_LEFT)
	await _play(zed, LANE_MIDDLE)
	var chip := await _play_into(LANE_MIDDLE)
	if chip < 0:
		_fail("C.setup", "no card left for the Chip in Middle")
		return
	await _end_turn()
	await _next_play_phase()

	var zed_node = _pres.node_for(zed)
	if zed_node == null:
		_fail("C.setup", "Zed1 has no node")
		return
	var lane1: Array = _lane_slots(LANE_MIDDLE)
	_expect(st.card(zed).is_resolved, "Zed1 is resolved")
	_expect(st.card(zed).col == LANE_MIDDLE, "Zed1 starts in Middle (got col %d)" % st.card(zed).col)
	_expect(zed_node.card_slot_is_in != null and zed_node.card_slot_is_in in lane1, "Zed1 sits in a Middle slot")

	# --- turn 2: queue BOTH swaps, through the real drop ---------------------
	if not await _real_drop(ahri_node_of(ahri), LANE_MIDDLE, "C", ELUSIVE_CARD, []):
		return
	_expect(st.card(ahri).col == LANE_LEFT, "Ahri1 is still in the model at Left until SWAP_LANE (got %d)" % st.card(ahri).col)
	if not await _real_drop(zed_node, LANE_RIGHT, "C", "Zed1", lane1):
		return
	_expect(zed_node in _lane_cards(LANE_RIGHT), "Zed1 is displayed in Right the moment his swap is queued")
	_expect(zed_node not in _lane_cards(LANE_MIDDLE), "Zed1 has left Board.cards_by_zone[%d,%d]" % [LANE_MIDDLE, LOCAL_ROW])

	# --- SWAP_LANE: Ahri arrives, recalls the Chip, lane 1 is re-laid --------
	await _end_turn()
	await _next_play_phase()
	_stop_watch()
	_expect(st.card(chip).location == LOC_HAND, "Ahri1's {swap} recalled the Chip out of Middle (location %d)" % st.card(chip).location)
	_expect(_pullbacks == 0, "Zed1 was never put back on a Middle slot by the mid-SWAP_LANE re-lay (samples=%d, pull-backs=%d)" % [_sampled, _pullbacks])

	_expect(st.card(zed).col == LANE_RIGHT, "Zed1 engine col is %d after SWAP_LANE (got %d)" % [LANE_RIGHT, st.card(zed).col])
	_expect(zed_node in _lane_cards(LANE_RIGHT), "Zed1 is registered in Board.cards_by_zone[%d,%d]" % [LANE_RIGHT, LOCAL_ROW])
	_expect(zed_node.card_slot_is_in != null and zed_node.card_slot_is_in in _lane_slots(LANE_RIGHT), "Zed1 has a Right slot")
	_expect(st.card(ahri).col == LANE_MIDDLE, "Ahri1 engine col is %d after SWAP_LANE (got %d)" % [LANE_MIDDLE, st.card(ahri).col])
	_assert_no_overlap(LANE_RIGHT, "Right after two swaps")


func ahri_node_of(id: int):
	return _pres.node_for(id)


# ---------------------------- assertions ----------------------------

## Every card in the lane must sit on its own slot, and on one of that lane's own slots.
## Two cards sharing a slot is the overlap a wrong layout produces.
func _assert_no_overlap(col: int, when: String) -> void:
	var slots: Array = _lane_slots(col)
	var seen := {}
	for card in _lane_cards(col):
		var slot = card.card_slot_is_in
		_expect(slot != null, "%s: a card in lane %d has a slot" % [when, col])
		if slot == null:
			continue
		_expect(slot in slots, "%s: a lane %d card is on one of that lane's own slots" % [when, col])
		_expect(not seen.has(slot.get_instance_id()), "%s: two cards share one slot in lane %d" % [when, col])
		seen[slot.get_instance_id()] = true


## The whole drop, through the real input path: a real left click picks the card up, the
## mouse moves to the destination lane's first free slot, and the drop is released.
##
## `watch_slots` are the origin-lane slots whose positions the card must never sit on once
## the drop starts; pass [] when there is nothing to watch.
##
## Two frames pass between moving the mouse and releasing, so CardManager._process has
## already moved the dragged card under the cursor. Releasing while it still sat on its
## origin slot would make the no-pull-back sampling meaningless.
func _real_drop(node: Node, dest_col: int, case_id: String, card_id: String, watch_slots: Array) -> bool:
	await _mouse_on(node)
	_im.raycast_at_cursor()
	if _cm.card_being_dragged != node:
		_fail("%s.drop" % case_id, "a real left click did not pick up %s" % card_id)
		_reset_drag()
		return false
	_expect(bool(_cm.get("_is_swap_drag")), "%s: a real left click starts %s's swap drag" % [case_id, card_id])
	var dest_slot = _first_free_slot(dest_col)
	if dest_slot == null:
		_fail("%s.drop" % case_id, "lane %d has no free slot to drop on" % dest_col)
		_reset_drag()
		return false
	await _mouse_on_slot(dest_slot)
	await _tick()
	await _tick()
	# Sampling starts HERE: before the release the card is legitimately still under the
	# cursor in the origin lane, and that is not a pull-back.
	_start_watch(node, watch_slots)
	_cm.finish_drag()
	await _next_frame()
	await _idle()
	return true


func _reset_drag() -> void:
	if _cm == null:
		return
	_cm.card_being_dragged = null
	_cm.set("_is_swap_drag", false)


func _start_watch(node: Node, forbidden_slots: Array) -> void:
	_watched = node
	_forbidden.clear()
	for slot in forbidden_slots:
		if slot is Node and is_instance_valid(slot):
			_forbidden.append((slot as Node).position)
	_sampled = 0
	_pullbacks = 0


func _stop_watch() -> void:
	_watched = null
	_forbidden.clear()


## One frame, recorded. Every wait loop in this script goes through this, so the sampling
## is continuous from the drop to the next PLAY phase without a second coroutine.
func _tick() -> void:
	await process_frame
	if _watched == null or not is_instance_valid(_watched):
		return
	_sampled += 1
	var here: Vector2 = _watched.position
	for spot in _forbidden:
		if here.is_equal_approx(spot):
			_pullbacks += 1
			if _pullbacks == 1:
				print("[FAIL-PULLBACK] %s sat on an origin-lane slot position %s at sample %d" % [_watched.name, str(spot), _sampled])
			return


# ---------------------------- harness ----------------------------

func _boot(seed_value: int, deck: Array) -> void:
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
	_booted_ok = _ctl != null and _pres != null
	if _booted_ok:
		_main.get_node("LobbyUI").get_node("Panel").visible = false
		_cm = _main.get_node("CardManager")
		_im = _main.get_node("InputManager")
		_board = _main.get_node("Board")
	if not _booted_ok:
		_fail("harness", "Main.tscn did not come up: a script it depends on does not compile")
		return
	_ctl.start_offline(deck, _bot_deck(), seed_value)
	for i in 4000:
		await _tick()
		if _ctl.is_play_phase() and not _pres.is_busy():
			return
	_fail("harness", "never reached an idle play phase")


func _booted() -> bool:
	if _booted_ok and _ctl != null:
		return true
	_fail("harness", "the match never booted, so the scenario could not run")
	return false


func _teardown() -> void:
	if _main != null and is_instance_valid(_main):
		root.remove_child(_main)
		_main.queue_free()
	_main = null
	_ctl = null
	_pres = null
	_cm = null
	_im = null
	_board = null
	_booted_ok = false
	_subject = -1
	await process_frame


func _deck() -> Array:
	var deck: Array = []
	for i in 4:
		deck.append(ELUSIVE_CARD)
	for i in 8:
		deck.append("Chip")
	return deck


## Scenario C needs a SECOND Elusive to queue two swaps in one turn, so it gets its own
## deck. Seed 11 deals Ahri1, Zed1, Chip, Zed1 against this list.
func _deck_c() -> Array:
	var deck: Array = []
	for i in 3:
		deck.append(ELUSIVE_CARD)
	for i in 3:
		deck.append("Zed1")
	for i in 6:
		deck.append("Chip")
	return deck


func _bot_deck() -> Array:
	var deck: Array = []
	for i in 12:
		deck.append("Chip")
	return deck


func _next_frame() -> void:
	await _tick()


func _next_play_phase() -> void:
	# The presenter going idle does not mean the bot has finished its turn; wait for the
	# play phase to actually reopen.
	for i in 6000:
		await _tick()
		if _ctl.is_play_phase() and not _pres.is_busy():
			return
	_fail("harness", "never reached the next play phase")


func _idle() -> void:
	for i in 2000:
		await _tick()
		if not _pres.is_busy():
			return


func _end_turn() -> void:
	_expect(_ctl.submit_local(_mi.end_turn()), "end turn accepted")
	await _idle()


## Plays a specific instance id into `col` and waits for the view to catch up.
func _play(id: int, col: int) -> void:
	_mana()
	_expect(_ctl.submit_local(_mi.play_card(id, col, -1)), "play #%d into lane %d accepted" % [id, col])
	await _idle()


## Plays any plain unit from hand into `col`; returns the instance id, or -1 when the
## hand has nothing left. Every card in this deck costs 1, so BIG_MANA always covers it.
func _play_into(col: int) -> int:
	var id := _hand_pick_filler()
	if id < 0:
		return -1
	_mana()
	_expect(_ctl.submit_local(_mi.play_card(id, col, -1)), "play #%d into lane %d accepted" % [id, col])
	await _idle()
	return id


func _mana() -> void:
	var me: int = _ctl.local_player
	_ctl.state.players[me].current_mana = BIG_MANA


## The first hand card with `card_id`, or -1.
func _hand_pick(card_id: String) -> int:
	var me: int = _ctl.local_player
	for id: int in _ctl.state.players[me].hand:
		if str(_ctl.state.card(id).card_id) == card_id:
			return int(id)
	return -1


## Any hand card that is a plain unit, other than the card under test. A Spell or Landmark
## cannot be played into a lane at all, so those are skipped too; a second Ahri1 is a
## perfectly good filler.
func _hand_pick_filler() -> int:
	var me: int = _ctl.local_player
	for id: int in _ctl.state.players[me].hand:
		if id == _subject:
			continue
		var kind := str(_ctl.state.card(id).data().get("Type", ""))
		if kind == "Spell" or kind == "Landmark":
			continue
		return int(id)
	return -1


func _lane_slots(col: int) -> Array:
	return _board.slots_by_zone.get(Vector2i(col, LOCAL_ROW), [])


func _lane_cards(col: int) -> Array:
	return _board.cards_by_zone.get(Vector2i(col, LOCAL_ROW), [])


func _first_free_slot(col: int):
	for slot in _lane_slots(col):
		if is_instance_valid(slot) and not bool(slot.card_in_slot):
			return slot
	return null


## The engine's power for the card, used only to predict what the lane label must become.
func _card_power(id: int) -> int:
	var node = _pres.node_for(id)
	if node == null:
		return 0
	var label = node.get_node_or_null("CardFront/Power")
	if label == null or not bool(label.visible):
		return 0
	return int(_ctl.state.card(id).get_current_power())


func _lane_power(col: int) -> int:
	var label = _board.power_labels_by_zone.get(Vector2i(col, LOCAL_ROW), null)
	if label == null:
		return -1
	return int(str(label.text).strip_edges())


func _mouse_on(node: Node) -> void:
	await _mouse_to(node.get_global_transform_with_canvas().origin)


func _mouse_on_slot(slot: Node) -> void:
	await _mouse_to(slot.get_global_transform_with_canvas().origin)


## Headless runs in a tiny window, so a world position is not a screen position. The
## viewport's final transform bridges the two.
func _mouse_to(world_origin: Vector2) -> void:
	var screen: Vector2 = _main.get_viewport().get_final_transform() * world_origin
	_main.get_viewport().warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	await process_frame
	await physics_frame


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