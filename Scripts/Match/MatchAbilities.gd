## Ability hooks for the pure-data rules engine.
##
## The base class is a complete no-op: M2 has the round loop but no card abilities,
## so every hook simply does nothing (the `on_round_*` hooks report "nothing fired").
##   on_discard       — after ops.discard() took a card out of a hand
##   on_last_breath   — after a real ops.kill(); the card is already GONE
##   on_level_up      — after ops.level_up() changed the primary card
##   on_deep          — after ops.set_deep() flipped is_deep
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


func on_discard(id: int) -> void:
	"""Card `id` just left a hand through ops.discard(); it is GONE already."""
	pass


func on_last_breath(id: int) -> void:
	"""Card `id` was really killed by ops.kill(); the card is GONE already."""
	pass


func on_level_up(id: int) -> void:
	"""Card `id` just levelled up through ops.level_up() (primary card only;
	silent copies of the same champion do NOT fire this)."""
	pass


func on_deep(player: int) -> void:
	"""`player` just went Deep (their deck ran out) through ops.set_deep()."""
	pass


func prevents_death(id: int) -> bool:
	"""Returns true when card `id` survives the kill that is about to happen."""
	return false


func on_death_prevented(id: int) -> void:
	"""Card `id` was about to die but an ability saved it (still on board)."""
	pass
