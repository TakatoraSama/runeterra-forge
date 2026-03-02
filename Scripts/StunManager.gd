extends Node

## StunManager – tracks runtime Stun state per card.
## AutoLoad singleton: accessible from any script via StunManager.<method>.
##
## Stun is a negative runtime keyword that:
##   - Blocks the stunned card's own Elusive self-swap
##   - Blocks the card's Round Start ability
##   - Blocks the card's Round End ability
## Expiry rule: removed at the START of _proceed_to_resolve() if stunned_on_turn < current_turn.


# ── Data ─────────────────────────────────────────────────────────────────────

## Active stun entries for the current game.
## Entry format: { "card": Node, "stunned_on_turn": int }
var _stun_entries: Array = []


# ── Public API ────────────────────────────────────────────────────────────────

func apply_stun(card: Node, current_turn: int) -> void:
	"""Apply Stun to a card. Silently ignores duplicate application (Stun is non-stackable)."""
	if not is_instance_valid(card):
		return
	if has_stun(card):
		print("StunManager: %s is already stunned, skipping duplicate." % card.card_id)
		return
	_stun_entries.append({ "card": card, "stunned_on_turn": current_turn })
	card.add_runtime_keyword("Stun")
	print("StunManager: stunned %s on turn %d (total stunned: %d)" % [
		card.card_id, current_turn, _stun_entries.size()])


func has_stun(card: Node) -> bool:
	"""Return true if this card is currently stunned."""
	for entry in _stun_entries:
		if is_instance_valid(entry["card"]) and entry["card"] == card:
			return true
	return false


func on_resolve_start(current_turn: int) -> void:
	"""Called at the beginning of _proceed_to_resolve().
	Expires all stuns applied on a previous turn (stunned_on_turn < current_turn).
	Also purges entries whose card node is no longer valid (killed / recalled cards)."""
	var expired: Array = []
	for entry in _stun_entries:
		if not is_instance_valid(entry["card"]) or entry["stunned_on_turn"] < current_turn:
			expired.append(entry)
	for entry in expired:
		_stun_entries.erase(entry)
		if is_instance_valid(entry["card"]):
			entry["card"].remove_runtime_keyword("Stun")
			print("StunManager: Stun expired on %s (was stunned turn %d, now turn %d)" % [
				entry["card"].card_id, entry["stunned_on_turn"], current_turn])
	if expired.size() > 0:
		print("StunManager: expired %d stun(s) at resolve start of turn %d." % [
			expired.size(), current_turn])


func reset() -> void:
	"""Clear all stun state. Call this when starting a new game."""
	_stun_entries.clear()
	print("StunManager: reset — all stun entries cleared.")
