## Ability hooks for the pure-data rules engine.
##
## The base class is a complete no-op: M2 has the round loop but no card abilities,
## so every hook simply does nothing (the `on_round_*` hooks report "nothing fired").
## M3 subclasses this, binds it with bind() and implements the cards themselves.
##
## Rules/Ops call the hooks at exactly these moments:
##   on_game_start    — start_match, once per distinct "{Game Start}" card id per player
##   on_card_drawn    — right after every ops.draw() that put a card in a hand
##   on_play          — RESOLVE, right after a card is revealed
##   on_round_start   — ROUND_START, per on-board card in play_order (flip first, not stunned)
##   on_round_end     — ROUND_END, same order and skip rules
##   on_swap_arrive   — SWAP_LANE, right after a card landed in its destination column
##   on_game_end_phase— once at GAME_END, before the winner is decided
##   after_change     — after each resolved card / ability batch (auras, level-ups)
##
## No Node, no scene tree, no signals, no autoloads: hooks mutate the match only
## through the `ops` primitives.
class_name MatchAbilities extends RefCounted

var state: MatchState
var ops: MatchOps


func bind(p_state: MatchState, p_ops: MatchOps) -> void:
	"""Attach to a match. Called by MatchRules._init() and set_abilities()."""
	state = p_state
	ops = p_ops


func on_game_start(card_id: String, owner: int) -> void:
	"""A "{Game Start}" card `card_id` in `owner`'s deck is about to fire."""
	pass


func on_card_drawn(id: int) -> void:
	"""Card `id` was just added to a hand by ops.draw()."""
	pass


func on_play(id: int) -> void:
	"""Card `id` was just revealed during RESOLVE; its {Play} ability fires now."""
	pass


func on_round_start(id: int) -> bool:
	"""Card `id`'s {Round Start} ability. Returns true when something fired."""
	return false


func on_round_end(id: int) -> bool:
	"""Card `id`'s {Round End} ability. Returns true when something fired."""
	return false


func on_swap_arrive(id: int, from_col: int, to_col: int) -> void:
	"""Card `id` just moved from column `from_col` to `to_col` at SWAP_LANE."""
	pass


func on_game_end_phase() -> void:
	"""Called once at GAME_END; M3 runs the {Game End} passes inside."""
	pass


func after_change() -> void:
	"""Called after each resolved card / ability batch (M3: auras, level-ups)."""
	pass
