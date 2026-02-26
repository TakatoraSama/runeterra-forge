extends Node

# ── Constants ───────────────────────────────────────────────────────────────────

var SWAP_DURATION = 1  # seconds for the tween animation of each swap


# ── Overview ───────────────────────────────────────────────────────────────────

## SwapLaneManager – owns all Elusive swap-lane logic.
## AutoLoad singleton: accessible from any script via SwapLaneManager.<method>.
##
## During PLAY phase, Elusive board cards can be dragged to a different lane.
## Their pending swap is stored here. At SWAP_LANE phase (between PLAY and RESOLVE),
## execute_swaps() animates the moves: instant snap-to-origin, then
## tween-to-destination in flip-first order (one at a time).


# ── Data ─────────────────────────────────────────────────────────────────────

## Pending swaps for the current round. Cleared after execute_swaps().
var pending_swaps: Array = []

## Permanent swap history (append-only, never cleared).
## Entry format: {card_id, owner_player_id, swapped_by_player_id,
##                cause_card_id, from_zone, to_zone, turn_number}
var swap_history: Array = []


# ── Scene-tree helpers ────────────────────────────────────────────────────────

func _get_card_manager() -> Node:
	return get_node_or_null("/root/Main/CardManager")


func _get_board() -> Node:
	return get_node_or_null("/root/Main/Board")


# ── Query API ─────────────────────────────────────────────────────────────────

func has_pending_swap(card) -> bool:
	"""Return true if this card already has a swap registered this round."""
	for entry in pending_swaps:
		if entry["card"] == card:
			return true
	return false


func get_swap_count_for_card(card_id: String, player_id: int) -> int:
	"""Count completed swaps for a specific card owner (usable for level-up conditions)."""
	var count := 0
	for entry in swap_history:
		if entry["card_id"] == card_id and entry["owner_player_id"] == player_id:
			count += 1
	return count


# ── Registration ──────────────────────────────────────────────────────────────

func register_swap(card, from_zone: Vector2i, from_slot,
		to_zone: Vector2i, to_slot, swapped_by_player_id: int) -> void:
	"""Record a pending swap initiated during PLAY phase.
	The card has already been moved to to_slot visually; this entry stores
	the origin so execute_swaps() can animate the full return-then-move."""
	var game_manager = get_node_or_null("/root/Main/GameManager")
	var current_turn := 0
	if game_manager and "turn_number" in game_manager:
		current_turn = game_manager.turn_number

	pending_swaps.append({
		"card": card,
		"swapped_by_player_id": swapped_by_player_id,
		"cause_card_id": card.card_id,
		"from_zone": from_zone,
		"from_slot": from_slot,
		"to_zone": to_zone,
		"to_slot": to_slot,
		"turn_number": current_turn
	})
	print("SwapLane registered: %s from zone %s → zone %s (by player %d, turn %d)" % [
		card.card_id, str(from_zone), str(to_zone), swapped_by_player_id, current_turn])


# ── Execution (called from GameManager._swap_lane_phase) ──────────────────────

func execute_swaps() -> void:
	"""Coroutine – animates all pending swaps.
	Step 1: instantly snap every swapping card back to its origin (no tween).
	Step 2: sequentially tween each card to its destination (flip-first order).
	If the destination slot is occupied at step 2, the swap is cancelled."""
	if pending_swaps.is_empty():
		return

	var board = _get_board()
	var card_manager = _get_card_manager()
	if not board or not card_manager:
		pending_swaps.clear()
		return

	var sorted_swaps := _sort_swaps_by_flip_first(pending_swaps, card_manager.flip_first_player_id)

	# ── Step 1: snap all cards instantly back to their origin zones ────────
	for entry in sorted_swaps:
		var card = entry["card"]
		if not is_instance_valid(card):
			continue

		var from_zone: Vector2i = entry["from_zone"]
		var to_zone: Vector2i = entry["to_zone"]

		# Undo the temporary destination placement — clear whichever slot the card
		# currently occupies (may differ from stored to_slot after reposition).
		board.remove_card_from_zone(to_zone, card)
		var current_dest_slot = card.card_slot_is_in
		if current_dest_slot:
			current_dest_slot.card_in_slot = false

		# Re-anchor at origin — find first free slot (origin zone may have been
		# repositioned since the drag, so stored from_slot could be occupied).
		board.add_card_to_zone(from_zone, card)
		var snap_slot = null
		for s in board.slots_by_zone.get(from_zone, []):
			if not s.card_in_slot:
				snap_slot = s
				break
		if snap_slot:
			snap_slot.card_in_slot = true
			card.card_slot_is_in = snap_slot
			card.position = snap_slot.position

	# ── Step 2: animate each card to its destination, one at a time ───────
	for entry in sorted_swaps:
		var card = entry["card"]
		if not is_instance_valid(card):
			continue

		var from_zone: Vector2i = entry["from_zone"]
		var to_zone: Vector2i = entry["to_zone"]
		var to_slot = entry["to_slot"]

		# Destination occupied → cancel this swap, card stays at origin
		if to_slot.card_in_slot:
			print("SwapLane cancelled (slot occupied): %s stays in zone %s" % [
				card.card_id, str(from_zone)])
			continue

		# Move tracking: origin → destination (use card's actual current slot from step 1)
		var actual_from_slot = card.card_slot_is_in
		board.remove_card_from_zone(from_zone, card)
		if actual_from_slot:
			actual_from_slot.card_in_slot = false

		board.add_card_to_zone(to_zone, card)
		to_slot.card_in_slot = true
		card.card_slot_is_in = to_slot

		# Animate to destination — elevate z_index so card renders above others
		card.z_index = 10
		var tween = card.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(card, "position", to_slot.position, SWAP_DURATION)
		await tween.finished
		card.z_index = 0  # Restore to CARD_BOARD_Z_INDEX

		# Fire swap-arrive ability only for locally-owned cards.
		# Both clients run execute_swaps(), but abilities must only resolve
		# on the owning player's client to avoid double-recall RPCs.
		if card.owner_player_id == card_manager.current_player_id:
			await AbilityResolver.execute_swap_arrive_ability(card, to_zone)

		# Record in permanent history
		swap_history.append({
			"card_id": card.card_id,
			"owner_player_id": card.owner_player_id,
			"swapped_by_player_id": entry["swapped_by_player_id"],
			"cause_card_id": entry["cause_card_id"],
			"from_zone": from_zone,
			"to_zone": to_zone,
			"turn_number": entry["turn_number"]
		})
		print("SwapLane executed: %s zone %s → zone %s (total swaps: %d)" % [
			card.card_id, str(from_zone), str(to_zone), swap_history.size()])

	pending_swaps.clear()


# ── Sort helpers ──────────────────────────────────────────────────────────────

func _sort_swaps_by_flip_first(swaps: Array, flip_first_id: int) -> Array:
	"""Return swaps reordered so the flip-first player's swaps come first."""
	if flip_first_id < 0:
		return swaps
	var first: Array = []
	var second: Array = []
	for entry in swaps:
		if entry["swapped_by_player_id"] == flip_first_id:
			first.append(entry)
		else:
			second.append(entry)
	var result: Array = []
	result.append_array(first)
	result.append_array(second)
	return result
