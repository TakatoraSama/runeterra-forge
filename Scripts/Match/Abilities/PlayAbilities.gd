## {Play}, {Game Start}, swap-arrive, level-up, on-discard, Last Breath and the
## draw-passive of the old `Scripts/AbilityResolver.gd`, ported to the pure-data engine.
##
## Everything runs through the `ctx.ops` primitives, every effect applies to BOTH players
## (the host executes all of them, so the old "only runs on the owner's client" gates are
## gone) and every random choice comes from the match rng through `ops.pick_random`.
##
## `ctx` is the MatchAbilities dispatcher: `ctx.state` is the MatchState, `ctx.ops` its
## MatchOps. MatchCardAbilities (agent D) forwards every hook here; PhaseAbilities calls
## `run_play_type` for the {Round Start} abilities that share a Play implementation.
class_name PlayAbilities extends RefCounted

const SPINNING_AXE := "SpinningAxe"
const DRAVEN_NAME := "Draven"
const BLADE := "Blade"
const SION1 := "Sion1"
const SION_RETURNED := "SionReturned"
const BURIED_SUN_DISC := "BuriedSunDisc"
const SUN_DISC_COL := 1  # column B, the mid lane


# ----------------------------
# Hooks
# ----------------------------

## Fires the {Play} ability of the card that just resolved, then records the Spinning
## Axe play for every Draven of the same owner (old CardManager.resolve_played_cards).
static func on_play(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or card.card_id.is_empty():
		return
	if card.data().is_empty():
		return
	run_play_type(ctx, id, str(card.data().get("AbilityType", "none")))
	if card.card_id == SPINNING_AXE:
		_count_axe_play(ctx, card.owner)


## Runs one Play implementation by its AbilityType. PhaseAbilities reuses this for the
## {Round Start} abilities that share a Play handler.
static func run_play_type(ctx: MatchAbilities, id: int, ability_type: String) -> void:
	match ability_type:
		"summon_copy":
			_summon_copy(ctx, id)
		"buff_allies":
			pass  # placeholder in the old code: it only logged
		"damage_enemies":
			pass  # placeholder in the old code: it only logged
		"create_card":
			_create_card(ctx, id)
		"mana_ramp":
			_mana_ramp(ctx, id)
		"drain_power":
			_drain_power(ctx, id)
		"stun_enemy":
			_stun_enemy(ctx, id)
		"recall_allies_same_lane":
			_recall_allies_same_lane(ctx, id)
		"recall_cost_allies":
			_recall_cost_allies(ctx, id)
		"discard_by_cost_bracket":
			_discard_by_cost_bracket(ctx, id)
		"create_card_if_not_in_hand":
			_create_card_if_not_in_hand(ctx, id)
		"spinning_axe_discard":
			_spinning_axe_discard(ctx, id)
		"create_multiple_cards":
			_create_multiple_cards(ctx, id)
		"janna_updraft_draw":
			_janna_updraft_draw(ctx, id)
		"janna_draw_cost_reduce":
			_janna_draw_cost_reduce(ctx, id)
		"sea_scarab_draw_discard":
			_sea_scarab_draw_discard(ctx, id)
		"abyssal_eye_draw":
			_abyssal_eye_draw(ctx, id)
		"devourer_deep_kill_enemy":
			_devourer_deep_kill_enemy(ctx, id)
		_:
			pass  # no Play ability or an unhandled type


## {Game Start} abilities (only Azir's Sun Disc exists).
static func on_game_start(ctx: MatchAbilities, card_id: String, owner: int) -> void:
	var data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	match str(data.get("AbilityType", "none")):
		"summon_sun_disc":
			_summon_sun_disc(ctx, card_id, owner)
		_:
			pass


## {swap} lane abilities, dispatched on the card's AbilityType.
static func on_swap_arrive(ctx: MatchAbilities, id: int, from_col: int, to_col: int) -> void:
	var card := ctx.state.card(id)
	if card == null or card.card_id.is_empty():
		return
	var data: Dictionary = card.data()
	if data.is_empty():
		return
	match str(data.get("AbilityType", "none")):
		"swap_arrive_recall":
			_swap_arrive_recall(ctx, id, to_col)
		"swap_arrive_summon_blade":
			_swap_arrive_summon_blade(ctx, id, from_col)
		_:
			pass


## {When I level up} abilities. The card already carries its NEW card_id, so the
## dispatch uses the new entry's AbilityType (old execute_level_up_ability).
static func on_level_up(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or card.card_id.is_empty():
		return
	var data: Dictionary = card.data()
	if data.is_empty():
		return
	match str(data.get("AbilityType", "none")):
		"level_up_create_from_discards":
			_level_up_create_from_discards(ctx, id)
		"nautilus_levelup_create_sea_monsters":
			_nautilus_levelup_create_sea_monsters(ctx, id)
		_:
			pass


## Sion1 {When I'm discarded}: the card has already left the hand.
static func on_discard(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or card.card_id.is_empty():
		return
	var data: Dictionary = card.data()
	if data.is_empty():
		return
	if str(data.get("AbilityType", "none")) != "on_discard_buff_create":
		return
	var owner: int = card.owner
	var hand: Array[int] = ctx.state.players[owner].hand
	if not hand.is_empty():
		var target: int = ctx.ops.pick_random(hand)
		if target >= 0:
			ctx.ops.change_power(target, ctx.ops.bv(id, "power_buff", 2))
	ctx.ops.create_in_hand(SION1, owner, id)


## Sion2 {Last Breath}: the card is already GONE, its card_id is still readable.
static func on_last_breath(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or card.card_id.is_empty():
		return
	var data: Dictionary = card.data()
	if data.is_empty():
		return
	if str(data.get("AbilityType", "none")) != "last_breath_create":
		return
	ctx.ops.create_in_hand(SION_RETURNED, card.owner, id)


## Janna lv2 passive: every card its owner draws is discounted, and the level-up checks
## run right away so Janna lv1's draw count is never delayed.
static func on_card_drawn(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var reduction: int = _janna_draw_cost_reduction(ctx, card.owner)
	if reduction > 0:
		ctx.ops.change_cost(id, -reduction)
	MatchLevelUps.check_all(ctx)


## Card.gd's can_prevent_death: only these two AbilityTypes save a card from dying.
static func prevents_death(ctx: MatchAbilities, id: int) -> bool:
	var card := ctx.state.card(id)
	if card == null or card.card_id.is_empty():
		return false
	var ability_type: String = str(card.data().get("AbilityType", "none"))
	return ability_type == "levelup_on_death" or ability_type == "survive_death"


## Card.gd's on_death_prevented: level up instead, or survive with +survive_power.
static func on_death_prevented(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or card.card_id.is_empty():
		return
	var data: Dictionary = card.data()
	if data.is_empty():
		return
	match str(data.get("AbilityType", "none")):
		"levelup_on_death":
			var new_id: String = str(data.get("LevelUpTo", ""))
			if not new_id.is_empty():
				ctx.ops.level_up(id, new_id)
		"survive_death":
			ctx.ops.change_power(id, ctx.ops.bv(id, "survive_power", 2))
		_:
			pass


# ----------------------------
# Play implementations
# ----------------------------

## Summons a copy of the card into the next free slot of its own zone (old
## _ability_summon_copy). No card uses this type yet; it is ported for parity.
static func _summon_copy(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or not ctx.ops.is_on_board(id):
		return
	ctx.ops.summon(card.card_id, card.owner, card.col, id)


## Trundle lv1 {Play}: create the [CardName] written in the Skill text in hand.
## The old code passed no creator for this one ability (every other create_* did).
static func _create_card(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var target_id: String = _bracketed_card_id(ctx, id)
	if target_id.is_empty():
		return
	ctx.ops.create_in_hand(target_id, card.owner, -1)


## Ice Pillar {Play}: bonus mana next turn.
static func _mana_ramp(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	ctx.ops.queue_temp_mana(card.owner, ctx.ops.bv(id, "mana_bonus", 5))


## Xerath lv1 {Play}: drain drain_power from every other Champion/Follower in this lane
## (both sides) and gain exactly the amount that was actually drained.
static func _drain_power(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or not ctx.ops.is_on_board(id):
		return
	var drain_amount: int = ctx.ops.bv(id, "drain_power", 2)
	var total_drained: int = 0
	var lane_cards: Array[int] = _lane_units(ctx, card.col, card.owner, true)
	lane_cards.append_array(_lane_units(ctx, card.col, 1 - card.owner, true))
	for target in lane_cards:
		if target == id:
			continue
		var target_card := ctx.state.card(target)
		if target_card == null:
			continue
		var power_before: int = target_card.get_current_power()
		ctx.ops.change_power(target, -drain_amount)
		total_drained += power_before - target_card.get_current_power()
	if total_drained > 0:
		ctx.ops.change_power(id, total_drained)


## Kennen {Play}: stun a random enemy Champion/Follower in this lane; lv2 also takes
## power_decrease Power off the target.
static func _stun_enemy(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or not ctx.ops.is_on_board(id):
		return
	var valid: Array[int] = _lane_units(ctx, card.col, 1 - card.owner, true)
	if valid.is_empty():
		return
	var target: int = ctx.ops.pick_random(valid)
	if target < 0:
		return
	ctx.ops.stun(target)
	var power_decrease: int = ctx.ops.bv(id, "power_decrease", 0)
	if power_decrease > 0:
		ctx.ops.change_power(target, -power_decrease)


## Navori Conspirator {Play}: recall every other allied resolved unit in this lane.
static func _recall_allies_same_lane(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or not ctx.ops.is_on_board(id):
		return
	var targets: Array[int] = _lane_units(ctx, card.col, card.owner, true)
	for target in targets:
		if target == id:
			continue
		ctx.ops.recall(target, card.owner, id)


## Solitary Monk {Play}: recall every allied resolved unit in ANY lane whose BASE cost
## equals recall_cost.
static func _recall_cost_allies(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var recall_cost: int = ctx.ops.bv(id, "recall_cost", 1)
	for col in MatchState.COLUMNS:
		for target in _lane_units(ctx, col, card.owner, true):
			if target == id:
				continue
			var target_card := ctx.state.card(target)
			if target_card == null:
				continue
			if int(target_card.data().get("Cost", 0)) != recall_cost:
				continue
			ctx.ops.recall(target, card.owner, id)


## Rumble {Play}: discard one card per cost bracket (<=2, 3-4, 5+) and gain +2 Power
## for each card actually discarded. The level-up that follows is MatchLevelUps' job.
static func _discard_by_cost_bracket(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var hand: Array[int] = ctx.state.players[card.owner].hand
	var brackets: Array[Array] = [[], [], []]
	for hand_id in hand:
		var hand_card := ctx.state.card(hand_id)
		if hand_card == null:
			continue
		var cost: int = hand_card.get_current_cost()
		if cost <= 2:
			brackets[0].append(hand_id)
		elif cost <= 4:
			brackets[1].append(hand_id)
		else:
			brackets[2].append(hand_id)
	var discard_count: int = 0
	for bracket in brackets:
		var picks: Array = bracket
		if picks.is_empty():
			continue
		var pick: int = ctx.ops.pick_random(picks)
		if pick < 0:
			continue
		ctx.ops.discard(pick, id)
		discard_count += 1
	if discard_count > 0:
		ctx.ops.change_power(id, 2 * discard_count)


## Draven lv1 {Play}/{Round Start}: create the [CardName] in the Skill text, but only
## when the owner does not already hold one.
static func _create_card_if_not_in_hand(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var target_id: String = _bracketed_card_id(ctx, id)
	if target_id.is_empty():
		return
	for hand_id in ctx.state.players[card.owner].hand:
		var hand_card := ctx.state.card(hand_id)
		if hand_card != null and hand_card.card_id == target_id:
			return
	ctx.ops.create_in_hand(target_id, card.owner, id)


## Spinning Axe: discard the newest (leftmost) hand card and grant the owner's first
## resolved, on-board Draven +power_bonus Power.
static func _spinning_axe_discard(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var hand: Array[int] = ctx.state.players[card.owner].hand
	if hand.is_empty():
		return
	for board_id in ctx.ops.board_ids(card.owner, true):
		if ctx.ops.card_name(board_id) == DRAVEN_NAME:
			ctx.ops.change_power(board_id, ctx.ops.bv(id, "power_bonus", 1))
			break
	ctx.ops.discard(hand[0], id)


## Draven lv2 {Play}/{Round Start}: create create_count copies of create_card_id.
static func _create_multiple_cards(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var create_count: int = ctx.ops.bv(id, "create_count", 1)
	var create_card_id: String = str(card.data().get("BalanceValues", {}).get("create_card_id", ""))
	if create_card_id.is_empty():
		return
	for i in create_count:
		ctx.ops.create_in_hand(create_card_id, card.owner, id)


## Janna lv1 {Play}: Updraft the updraft_threshold oldest hand cards (they sit at the END
## of the hand) — each costs 1 less and goes back into the deck — then draw that many.
static func _janna_updraft_draw(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var owner: int = card.owner
	var threshold: int = ctx.ops.bv(id, "updraft_threshold", 2)
	var hand: Array[int] = ctx.state.players[owner].hand
	var take: int = mini(threshold, hand.size())
	if take <= 0:
		return
	var updrafted: Array[int] = []
	for i in range(hand.size() - take, hand.size()):
		updrafted.append(hand[i])
	for updraft_id in updrafted:
		ctx.ops.change_cost(updraft_id, -1)
	for updraft_id in updrafted:
		ctx.ops.shuffle_into_deck(owner, updraft_id)
	for i in take:
		ctx.ops.draw(owner)


## Janna lv2 {Play}/{Round Start}: draw draw_threshold. The discount comes from the
## passive, which runs on every ops.draw().
static func _janna_draw_cost_reduce(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var draw_threshold: int = ctx.ops.bv(id, "draw_threshold", 1)
	for i in draw_threshold:
		ctx.ops.draw(card.owner)


## Sea Scarab {Play}: draw a random non-champion card straight from the deck and
## discard it again.
static func _sea_scarab_draw_discard(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var owner: int = card.owner
	var non_champions: Array[int] = []
	for deck_id in ctx.state.players[owner].deck:
		var deck_card := ctx.state.card(int(deck_id))
		if deck_card == null:
			continue
		if str(deck_card.data().get("Type", "")) == "Champion":
			continue
		non_champions.append(int(deck_id))
	if non_champions.is_empty():
		return
	var picked: int = ctx.ops.pick_random(non_champions)
	if picked < 0:
		return
	var picked_id: String = ctx.state.card(picked).card_id
	var drawn_id: int = ctx.ops.draw_specific(owner, picked_id)
	if drawn_id < 0:
		return
	ctx.ops.discard(drawn_id, id)


## Abyssal Eye {Play}: draw draw_count cards.
static func _abyssal_eye_draw(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var draw_count: int = ctx.ops.bv(id, "draw_count", 1)
	for i in draw_count:
		ctx.ops.draw(card.owner)


## Devourer of the Depths {Play}: while the owner is Deep, kill a random enemy
## Champion/Follower in this lane that has strictly less Power than the Devourer.
static func _devourer_deep_kill_enemy(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null or not ctx.ops.is_on_board(id):
		return
	var owner: int = card.owner
	if not ctx.state.players[owner].is_deep:
		return
	var my_power: int = card.get_current_power()
	var valid: Array[int] = []
	for enemy in _lane_units(ctx, card.col, 1 - owner, true):
		var enemy_card := ctx.state.card(enemy)
		if enemy_card == null:
			continue
		if enemy_card.get_current_power() < my_power:
			valid.append(enemy)
	if valid.is_empty():
		return
	var target: int = ctx.ops.pick_random(valid)
	if target >= 0:
		ctx.ops.kill(target, owner, id)


# ----------------------------
# Level-up implementations
# ----------------------------

## Rumble lv2 {When I level up}: for each card this player discarded, create a random
## collectible card of the same base cost, at 1 cost less and with the Augment keyword.
static func _level_up_create_from_discards(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var owner: int = card.owner
	var owner_discards: Array[Dictionary] = []
	for entry in ctx.state.discarded:
		if int(entry.get("owner_player_id", -1)) == owner:
			owner_discards.append(entry)
	if owner_discards.is_empty():
		return
	var pool_cache: Dictionary = {}
	for entry in owner_discards:
		var src_data: Dictionary = CardDatabase.CARDS.get(str(entry.get("card_id", "")), {})
		var base_cost: int = int(src_data.get("Cost", 0))
		if not pool_cache.has(base_cost):
			var pool: Array[String] = []
			for card_id: String in CardDatabase.CARDS:
				var cd: Dictionary = CardDatabase.CARDS[card_id]
				if bool(cd.get("Collectible", false)) and int(cd.get("Cost", -1)) == base_cost:
					pool.append(card_id)
			pool_cache[base_cost] = pool
		var candidates: Array = pool_cache[base_cost]
		if candidates.is_empty():
			continue
		var picked_id: String = _pick_card_id(ctx, candidates)
		if picked_id.is_empty():
			continue
		var new_id: int = ctx.ops.create_in_hand(picked_id, owner, id)
		if new_id < 0:
			continue
		ctx.ops.change_cost(new_id, -1)
		ctx.ops.add_keyword(new_id, "Augment")


## Nautilus lv2 {When I level up}: create created_count distinct Sea Monsters with a base
## cost of at least created_cost.
static func _nautilus_levelup_create_sea_monsters(ctx: MatchAbilities, id: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var owner: int = card.owner
	var created_cost: int = ctx.ops.bv(id, "created_cost", 3)
	var created_count: int = ctx.ops.bv(id, "created_count", 3)
	var pool: Array[String] = []
	for card_id: String in CardDatabase.CARDS:
		var cd: Dictionary = CardDatabase.CARDS[card_id]
		if str(cd.get("SubType", "")) != "Sea Monster":
			continue
		if int(cd.get("Cost", 0)) < created_cost:
			continue
		pool.append(card_id)
	if pool.is_empty():
		return
	_shuffle(ctx.state.rng, pool)
	for i in mini(created_count, pool.size()):
		ctx.ops.create_in_hand(pool[i], owner, id)


# ----------------------------
# Game Start / swap-arrive
# ----------------------------

## Azir {Game Start}: a Buried Sun Disc in the mid lane on the owner's side.
static func _summon_sun_disc(ctx: MatchAbilities, card_id: String, owner: int) -> void:
	ctx.ops.summon(BURIED_SUN_DISC, owner, SUN_DISC_COL, _deck_instance_of(ctx, card_id, owner))


## Ahri {swap} lane: recall the weakest resolved ally at the destination (ties go to the
## lexicographically smaller card_id); lv2 also reduces the recalled card's cost.
static func _swap_arrive_recall(ctx: MatchAbilities, id: int, to_col: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	var owner: int = card.owner
	var weakest: int = -1
	var weakest_power: int = 0
	var weakest_card_id: String = ""
	for ally in _lane_units(ctx, to_col, owner, true):
		if ally == id:
			continue
		var ally_card := ctx.state.card(ally)
		if ally_card == null:
			continue
		var power: int = ally_card.get_current_power()
		if weakest < 0 or power < weakest_power \
				or (power == weakest_power and ally_card.card_id < weakest_card_id):
			weakest = ally
			weakest_power = power
			weakest_card_id = ally_card.card_id
	if weakest < 0:
		return
	ctx.ops.recall(weakest, owner, id)
	var cost_reduction: int = ctx.ops.bv(id, "recall_cost_reduction", 0)
	if cost_reduction > 0:
		ctx.ops.change_cost(weakest, -cost_reduction)


## Irelia {swap} lane: summon a Blade in the lane she came from.
static func _swap_arrive_summon_blade(ctx: MatchAbilities, id: int, from_col: int) -> void:
	var card := ctx.state.card(id)
	if card == null:
		return
	ctx.ops.summon(BLADE, card.owner, from_col, id)


# ----------------------------
# Internals
# ----------------------------

## Every resolved Champion/Follower in (col, owner) that may still be picked as a
## target: face-down cards are filtered out here because ops.pick_random does not.
static func _lane_units(ctx: MatchAbilities, col: int, owner: int, resolved_only: bool) -> Array[int]:
	var out: Array[int] = []
	if col < 0:
		return out
	for unit_id in ctx.ops.zone_ids(col, owner):
		var card := ctx.state.card(unit_id)
		if card == null:
			continue
		if resolved_only and not card.is_resolved:
			continue
		if not ctx.ops.is_unit(unit_id):
			continue
		out.append(unit_id)
	return out


## One card id out of `pool`, drawn from the match rng. ops.pick_random only handles
## instance ids, so the CardDatabase pools the level-up abilities build are picked here.
static func _pick_card_id(ctx: MatchAbilities, pool: Array) -> String:
	if pool.is_empty():
		return ""
	return str(pool[ctx.state.rng.randi() % pool.size()])


## Parses the first "[CardName]" out of the card's Skill text and resolves it to a card
## id ("" when the text has no bracket or no card carries that name).
static func _bracketed_card_id(ctx: MatchAbilities, id: int) -> String:
	var card := ctx.state.card(id)
	if card == null:
		return ""
	var skill_text: String = str(card.data().get("Skill", ""))
	var bracket_start: int = skill_text.find("[")
	var bracket_end: int = skill_text.find("]")
	if bracket_start == -1 or bracket_end == -1 or bracket_end <= bracket_start:
		return ""
	var target_name: String = skill_text.substr(bracket_start + 1, bracket_end - bracket_start - 1)
	return CardDatabase.get_card_id_by_name(target_name)


## Total discount the owner's resolved, on-board Janna lv2 cards give to every card it
## draws; it stacks (old get_janna_draw_cost_reduction).
static func _janna_draw_cost_reduction(ctx: MatchAbilities, owner: int) -> int:
	var reduction: int = 0
	for board_id in ctx.ops.board_ids(owner, true):
		if str(ctx.state.card(board_id).data().get("AbilityType", "")) != "janna_draw_cost_reduce":
			continue
		reduction += ctx.ops.bv(board_id, "cost_reduction", 1)
	return reduction


## CardManager.resolve_played_cards: every resolved, on-board Draven of the owner counts
## one more Spinning Axe play.
static func _count_axe_play(ctx: MatchAbilities, owner: int) -> void:
	for board_id in ctx.ops.board_ids(owner, true):
		var card := ctx.state.card(board_id)
		if card == null or ctx.ops.card_name(board_id) != DRAVEN_NAME:
			continue
		card.axe_play_count += 1


## The instance of `card_id` still sitting in `owner`'s deck, or -1 (used as the creator
## of a {Game Start} summon, which happens before any card left the deck).
static func _deck_instance_of(ctx: MatchAbilities, card_id: String, owner: int) -> int:
	for deck_id in ctx.state.players[owner].deck:
		var card := ctx.state.card(int(deck_id))
		if card != null and card.card_id == card_id:
			return card.instance_id
	return -1


## In-place Fisher-Yates over `list`, drawn from the match rng.
static func _shuffle(rng: RandomNumberGenerator, list: Array[String]) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = list[i]
		list[i] = list[j]
		list[j] = tmp