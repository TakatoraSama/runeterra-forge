## The concrete MatchAbilities of M3: every card ability in the pure-data engine.
##
## This class owns no card logic at all — it binds `state`/`ops` and delegates each
## hook to the module that implements it:
##   PlayAbilities   {Play}, {Game Start}, swap-arrive, level-up, discard, last breath,
##                   draw passive, death prevention.
##   PhaseAbilities  {Round Start}, {Round End} and the three {Game End} passes.
##   MatchAuras      the passive aura modifiers.
##   MatchLevelUps   every level-up condition, for both owners.
##
## `after_change()` is the one piece of behaviour that lives here: the rules call it
## after each resolved card / phase batch, and it must settle the board — auras are
## recomputed and level-ups are checked until nothing changes (max 5 iterations, so a
## pathological card cannot spin forever).
##
## Install it on a match with `MatchCardAbilities.install(rules)` BEFORE start_match(),
## so the {Game Start} abilities are seen.
class_name MatchCardAbilities extends MatchAbilities

## after_change() settles the board; this bounds the settle loop.
const MAX_SETTLE_ITERATIONS := 5


## Creates the dispatcher, binds it to `rules` and returns it, so a caller can keep
## the reference and drive the modules themselves.
static func install(rules: MatchRules) -> MatchCardAbilities:
	var hooks := MatchCardAbilities.new()
	rules.set_abilities(hooks)
	return hooks


# ----------------------------
# Card flow
# ----------------------------

func on_game_start(card_id: String, owner: int) -> void:
	PlayAbilities.on_game_start(self, card_id, owner)


func on_card_drawn(id: int) -> void:
	PlayAbilities.on_card_drawn(self, id)


func on_play(id: int) -> void:
	PlayAbilities.on_play(self, id)


func on_swap_arrive(id: int, from_col: int, to_col: int) -> void:
	PlayAbilities.on_swap_arrive(self, id, from_col, to_col)


func on_discard(id: int) -> void:
	PlayAbilities.on_discard(self, id)


func on_last_breath(id: int) -> void:
	PlayAbilities.on_last_breath(self, id)


func on_level_up(id: int) -> void:
	PlayAbilities.on_level_up(self, id)
	after_change()


func prevents_death(id: int) -> bool:
	return PlayAbilities.prevents_death(self, id)


func on_death_prevented(id: int) -> void:
	PlayAbilities.on_death_prevented(self, id)


# ----------------------------
# Phases
# ----------------------------

func on_round_start(id: int) -> bool:
	return PhaseAbilities.on_round_start(self, id)


func on_round_end(id: int) -> bool:
	return PhaseAbilities.on_round_end(self, id)


func on_game_end_phase() -> void:
	PhaseAbilities.on_game_end_phase(self)


# ----------------------------
# Settling
# ----------------------------

func on_deep(player: int) -> void:
	after_change()


## Recomputes the auras and re-checks the level-ups until the board is stable, at
## most MAX_SETTLE_ITERATIONS times. Auras run first: a buff can be what pushes a
## champion over its level-up threshold, and a level-up can change which auras apply.
func after_change() -> void:
	for _i in MAX_SETTLE_ITERATIONS:
		MatchAuras.recalculate(self)
		if not MatchLevelUps.check_all(self):
			break