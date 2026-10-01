## {Round Start}, {Round End} and {Game End} card abilities for the pure-data engine.
##
## Ported from `Scripts/AbilityResolver.gd` (`execute_round_start_ability`,
## `execute_round_end_ability`, `execute_game_end_ability`,
## `execute_game_end_hand_ability` and their handlers) plus the three passes of
## `Scripts/CardManager.gd::trigger_game_end_abilities`.
##
## Static only, no Node, no scene tree, no autoload, no await, no global RNG: every
## change goes through `ctx.ops` and every random pick through `ctx.state.rng`.
## Owner gating is gone (the host runs every effect), animations and timers are
## dropped, and the owner-relative lane comparison uses absolute player ids.
class_name PhaseAbilities

const ROUND_START_MARKER := "{Round Start}"
const ROUND_END_MARKER := "{Round End}"
const GAME_END_MARKER := "{Game End}"


# ----------------------------
# Round Start
# ----------------------------

## Fires the {Round Start} ability of card `id`. The gate is EXACT: the Skill text
## must CONTAIN "{Round Start}" (old `execute_round_start_ability`). Returns true
## when the gate passed, like the old function did.
static func on_round_start(ctx: MatchAbilities, id: int) -> bool:
	var card := ctx.state.card(id)
	if card == null:
		return false
	var data: Dictionary = card.data()
	if data.is_empty():
		return false
	if not str(data.get("Skill", "")).contains(ROUND_START_MARKER):
		return false
	match str(data.get("AbilityType", "none")):
		"conditional_buff":
			_round_start_conditional_buff(ctx, id)
		"create_card_if_not_in_hand", "create_multiple_cards", "janna_draw_cost_reduce":
			PlayAbilities.run_play_type(ctx, id, str(data.get("AbilityType", "")))
		_:
			pass
	return true


## Renekton {Round Start}: +win_power Power when this lane is won.
## (old `_ability_conditional_buff`.) The power-threshold level-up that used to be
## called here is left to MatchLevelUps through the rules' `after_change()`.
static func _round_start_conditional_buff(ctx: MatchAbilities, id: int) -> void:
	if not ctx.ops.is_on_board(id):
		return
	var card := ctx.state.card(id)
	var col: int = card.col
	var owner: int = card.owner
	# "winning here" = own resolved lane power > enemy resolved lane power.
	if ctx.ops.lane_power(col, owner) <= ctx.ops.lane_power(col, 1 - owner):
		return
	ctx.ops.change_power(id, ctx.ops.bv(id, "win_power", 2))


# ----------------------------
# Round End
# ----------------------------

## Fires the {Round End} ability of card `id`. The gate is EXACT: the Skill text
## must BEGIN WITH "{Round End}" (old `execute_round_end_ability`).
static func on_round_end(ctx: MatchAbilities, id: int) -> bool:
	var card := ctx.state.card(id)
	if card == null:
		return false
	var data: Dictionary = card.data()
	if data.is_empty():
		return false
	if not str(data.get("Skill", "")).begins_with(ROUND_END_MARKER):
		return false
	match str(data.get("AbilityType", "none")):
		"kill_ally_buff":
			_round_end_kill_ally_buff(ctx, id)
		"megatusk_deep_buff_lane":
			_round_end_megatusk_deep_buff_lane(ctx, id)
		"terror_debuff_lane_enemies":
			_round_end_terror_debuff_lane_enemies(ctx, id)
		_:
			pass
	return true


## Nasus {Round End}: kill the weakest other ally in this lane AND grant self
## +kill_power Power. (old `_ability_kill_ally_buff`.) The buff is the keyword "and"
## of the card text: it applies even when the death was prevented, but NOT when
## there is no other unit here at all — the old code returned early in that case.
static func _round_end_kill_ally_buff(ctx: MatchAbilities, id: int) -> void:
	if not ctx.ops.is_on_board(id):
		return
	var card := ctx.state.card(id)
	var owner: int = card.owner
	var col: int = card.col

	# Weakest other Champion/Follower in the zone; strict "<" keeps the FIRST one on ties.
	var weakest: int = -1
	var weakest_power: int = 0
	for other: int in ctx.state.zone_cards(col, owner):
		if other == id or not ctx.ops.is_unit(other):
			continue
		var power: int = ctx.state.card(other).get_current_power()
		if weakest < 0 or power < weakest_power:
			weakest = other
			weakest_power = power
	if weakest < 0:
		return

	ctx.ops.kill(weakest, owner, id)
	ctx.ops.change_power(id, ctx.ops.bv(id, "kill_power", 2))


## Megatusk {Round End}: while its owner is Deep, every resolved allied
## Champion/Follower in this lane (Megatusk included) gains +power_bonus Power.
static func _round_end_megatusk_deep_buff_lane(ctx: MatchAbilities, id: int) -> void:
	if not ctx.ops.is_on_board(id):
		return
	var card := ctx.state.card(id)
	if not ctx.state.players[card.owner].is_deep:
		return
	var bonus: int = ctx.ops.bv(id, "power_bonus", 1)
	for ally: int in ctx.state.zone_cards(card.col, card.owner):
		var ally_card := ctx.state.card(ally)
		if ally_card == null or not ally_card.is_resolved or not ctx.ops.is_unit(ally):
			continue
		ctx.ops.change_power(ally, bonus)


## Terror of the Tides {Round End}: every resolved enemy Champion/Follower in this
## lane loses -power_reduction Power.
static func _round_end_terror_debuff_lane_enemies(ctx: MatchAbilities, id: int) -> void:
	if not ctx.ops.is_on_board(id):
		return
	var card := ctx.state.card(id)
	var amount: int = ctx.ops.bv(id, "power_reduction", 1)
	for enemy: int in ctx.state.zone_cards(card.col, 1 - card.owner):
		var enemy_card := ctx.state.card(enemy)
		if enemy_card == null or not enemy_card.is_resolved or not ctx.ops.is_unit(enemy):
			continue
		ctx.ops.change_power(enemy, -amount)


# ----------------------------
# Game End
# ----------------------------

## The three {Game End} passes of CardManager.trigger_game_end_abilities:
##   1. every on-board card in play order, flip-first first, gate "{Game End}" in Skill;
##   2. every resolved on-board Azir at Level 3 re-fires its owner's Ascended allies once;
##   3. hand cards with a {Game End} summon (Sion) per player, flip-first first.
static func on_game_end_phase(ctx: MatchAbilities) -> void:
	# Snapshot once, like the old code, and re-check "still on board" on every pass.
	var board_ids: Array[int] = _sorted_by_flip_first(ctx, ctx.state.play_order)
	_game_end_pass_one(ctx, board_ids)
	_game_end_pass_two(ctx, board_ids)
	_game_end_pass_three(ctx)


## Pass 1: every on-board card with "{Game End}" in its Skill fires exactly once.
static func _game_end_pass_one(ctx: MatchAbilities, board_ids: Array[int]) -> void:
	var fired: Dictionary = {}
	for id: int in board_ids:
		# A card may have been killed by an earlier ability this phase.
		if not ctx.ops.is_on_board(id):
			continue
		if fired.has(id):
			continue
		fired[id] = true
		var card := ctx.state.card(id)
		var data: Dictionary = card.data()
		if data.is_empty() or not str(data.get("Skill", "")).contains(GAME_END_MARKER):
			continue
		_run_game_end_ability(ctx, id, data)
		ctx.after_change()


## The {Game End} dispatch of one on-board card (old `execute_game_end_ability`).
## `conditional_buff` covers two different champions, so it branches on the Name.
static func _run_game_end_ability(ctx: MatchAbilities, id: int, data: Dictionary) -> void:
	match str(data.get("AbilityType", "none")):
		"conditional_buff":
			match str(data.get("Name", "")):
				"Trundle":
					_game_end_trundle_buff(ctx, id)
				"Renekton":
					_game_end_renekton_debuff(ctx, id)
				_:
					pass
		"aura_debuff":
			_game_end_xerath_buff(ctx, id)
		"kill_ally_buff":
			_game_end_nasus_kill(ctx, id)
		_:
			pass


## Pass 2: a resolved on-board Azir at Level 3 makes each of its owner's other
## resolved on-board Ascended cards with "{Game End}" fire one more time. Each card
## gets that bonus fire at most once across all Azirs.
static func _game_end_pass_two(ctx: MatchAbilities, board_ids: Array[int]) -> void:
	var double_fired: Dictionary = {}
	for azir: int in board_ids:
		if not ctx.ops.is_on_board(azir):
			continue
		var azir_card := ctx.state.card(azir)
		if not azir_card.is_resolved:
			continue
		var azir_data: Dictionary = azir_card.data()
		if str(azir_data.get("Name", "")) != "Azir" or ctx.ops.card_level(azir) != 3:
			continue
		for id: int in board_ids:
			if id == azir or not ctx.ops.is_on_board(id):
				continue
			var card := ctx.state.card(id)
			if card.owner != azir_card.owner or not card.is_resolved:
				continue
			if double_fired.has(id):
				continue
			var data: Dictionary = card.data()
			if data.is_empty():
				continue
			if str(data.get("SubType", "")).to_lower() != "ascended":
				continue
			if not str(data.get("Skill", "")).contains(GAME_END_MARKER):
				continue
			double_fired[id] = true
			_run_game_end_ability(ctx, id, data)
			ctx.after_change()


## Pass 3: the Sion {Game End} hand summon, for both players in flip-first order.
static func _game_end_pass_three(ctx: MatchAbilities) -> void:
	for player: int in _players_in_order(ctx):
		var snapshot: Array[int] = ctx.state.players[player].hand.duplicate()
		for id: int in snapshot:
			var card := ctx.state.card(id)
			if card == null or card.location != CardState.Location.HAND:
				continue
			var data: Dictionary = card.data()
			if data.is_empty() or not str(data.get("Skill", "")).contains(GAME_END_MARKER):
				continue
			var ability_type: String = str(data.get("AbilityType", "none"))
			var hand_ability_type: String = str(data.get("HandAbilityType", ""))
			var effective: String = hand_ability_type if hand_ability_type != "" else ability_type
			if effective != "game_end_summon_from_hand":
				continue
			_game_end_sion_summon(ctx, id, player)
			ctx.after_change()


## Trundle lv2 {Game End}: +behold_power Power for every OTHER Champion/Follower the
## owner beholds whose BASE Cost is mana_threshold or more (old
## `_game_end_trundle_buff`: hand + board, itself excluded).
static func _game_end_trundle_buff(ctx: MatchAbilities, id: int) -> void:
	var owner: int = ctx.state.card(id).owner
	var threshold: int = ctx.ops.bv(id, "mana_threshold", 5)
	var count: int = 0
	for beheld: int in ctx.ops.beheld(owner):
		if beheld == id or not ctx.ops.is_unit(beheld):
			continue
		var data: Dictionary = ctx.state.card(beheld).data()
		if int(data.get("Cost", 0)) >= threshold:
			count += 1
	if count <= 0:
		return
	ctx.ops.change_power(id, ctx.ops.bv(id, "behold_power", 2) * count)


## Renekton lv3 {Game End}: a random resolved enemy Champion/Follower in this lane
## loses enemy_debuff Power (old `_game_end_renekton_debuff`).
static func _game_end_renekton_debuff(ctx: MatchAbilities, id: int) -> void:
	if not ctx.ops.is_on_board(id):
		return
	var card := ctx.state.card(id)
	var targets: Array = []
	for enemy: int in ctx.state.zone_cards(card.col, 1 - card.owner):
		var enemy_card := ctx.state.card(enemy)
		if enemy_card == null or not enemy_card.is_resolved or not ctx.ops.is_unit(enemy):
			continue
		targets.append(enemy)
	if targets.is_empty():
		return
	var target: int = ctx.ops.pick_random(targets)
	if target < 0:
		return
	ctx.ops.change_power(target, -ctx.ops.bv(id, "enemy_debuff", 3))


## Xerath lv3 {Game End}: gain the Power of every front-row enemy Champion/Follower
## in this lane (old `_game_end_xerath_buff`: slot index 0 or 1, enemies keep theirs).
static func _game_end_xerath_buff(ctx: MatchAbilities, id: int) -> void:
	if not ctx.ops.is_on_board(id):
		return
	var card := ctx.state.card(id)
	var gained: int = 0
	var enemies: Array[int] = ctx.state.zone_cards(card.col, 1 - card.owner)
	for slot: int in enemies.size():
		if slot > 1:
			break  # back row
		var enemy := ctx.state.card(enemies[slot])
		if enemy == null or not ctx.ops.is_unit(enemies[slot]):
			continue
		gained += enemy.get_current_power()
	if gained > 0:
		ctx.ops.change_power(id, gained)


## Nasus lv3 {Game End}: kill a random resolved enemy Champion/Follower in this lane
## with STRICTLY less Power than Nasus (old `_ability_nasus_game_end_kill`).
static func _game_end_nasus_kill(ctx: MatchAbilities, id: int) -> void:
	if not ctx.ops.is_on_board(id):
		return
	var card := ctx.state.card(id)
	var my_power: int = card.get_current_power()
	var targets: Array = []
	for enemy: int in ctx.state.zone_cards(card.col, 1 - card.owner):
		var enemy_card := ctx.state.card(enemy)
		if enemy_card == null or not enemy_card.is_resolved or not ctx.ops.is_unit(enemy):
			continue
		if enemy_card.get_current_power() < my_power:
			targets.append(enemy)
	if targets.is_empty():
		return
	var target: int = ctx.ops.pick_random(targets)
	if target < 0:
		return
	ctx.ops.kill(target, card.owner, id)


## Sion lv2 / Sion Returned {Game End}: from hand, summon to the lane with the
## highest own power where the owner is LOSING; else the lowest own power lane;
## else column 0. A full zone means the card simply stays in hand
## (old `_ability_game_end_sion_summon`).
static func _game_end_sion_summon(ctx: MatchAbilities, id: int, owner: int) -> void:
	var best_col: int = -1
	var best_power: int = -1
	for col in MatchState.COLUMNS:
		var ally_power: int = ctx.ops.lane_power(col, owner)
		var enemy_power: int = ctx.ops.lane_power(col, 1 - owner)
		if ally_power < enemy_power and ally_power > best_power:
			best_col = col
			best_power = ally_power
	if best_col < 0:
		# Not losing anywhere: take the lane with the lowest own power.
		var lowest_power: int = 0
		for col in MatchState.COLUMNS:
			var ally_power: int = ctx.ops.lane_power(col, owner)
			if best_col < 0 or ally_power < lowest_power:
				best_col = col
				lowest_power = ally_power
	if best_col < 0:
		best_col = 0
	ctx.ops.put_into_play(id, best_col)


# ----------------------------
# Internals
# ----------------------------

## Reorders instance ids so the flip-first player's come first, keeping their
## relative order (MatchRules._sort_by_flip_first).
static func _sorted_by_flip_first(ctx: MatchAbilities, ids: Array) -> Array[int]:
	var first: Array[int] = []
	var second: Array[int] = []
	for raw: Variant in ids:
		var id: int = int(raw)
		var card := ctx.state.card(id)
		if card != null and card.owner == ctx.state.flip_first:
			first.append(id)
		else:
			second.append(id)
	return first + second


## The two players in flip-first order ([0, 1] until priority is known).
static func _players_in_order(ctx: MatchAbilities) -> Array[int]:
	if ctx.state.flip_first < 0 or ctx.state.flip_first > 1:
		return [0, 1]
	return [ctx.state.flip_first, 1 - ctx.state.flip_first]