## Aura recalculation for the pure-data rules engine.
##
## Ports `Scripts/AuraSystem.recalculate_auras` (the current version, including
## `_is_back_row` for Xerath lv2 / lv3). The old system owned two modifiers that are reset
## and re-applied from scratch on every board change — `Card.aura_power_modifier` and
## `Card.aura_cost_modifier` — and they exist here as `CardState.aura_power_modifier` /
## `CardState.aura_cost_modifier`. Nothing else writes them, so a full reset + re-apply
## is always correct and idempotent.
##
## Deliberate differences from the old code:
##   - owner gating removed (`owner_id != cm.current_player_id`): the host runs every
##     aura, so the Nautilus lv2 hand discount applies to BOTH players' hands;
##   - the label refresh steps (Step 3 / 3b) are presentation (M4): instead this emits
##     one `power_changed` / `cost_changed` event per card whose TOTAL changed, and a
##     recalculation that changes nothing emits nothing at all;
##   - "same side" is decided by the zone owner instead of the zone row. The engine keys
##     zones as Vector2i(col, owner), so row == owner and the two are the same test.
##
## No Node, no scene tree, no signals, no autoloads.
class_name MatchAuras


## Resets every aura modifier and re-applies every active aura source, then emits one
## event per card whose displayed power or cost actually changed. Returns nothing;
## `MatchLevelUps.check_all` is what the caller loops on.
static func recalculate(ctx: MatchAbilities) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops

	# --- Step 1: snapshot the totals we are about to change, then reset -------------
	var old_power: Dictionary = {}   # instance_id -> power before the reset
	var old_cost: Dictionary = {}    # instance_id -> cost before the reset
	var board_ids: Array[int] = []
	for id in state.play_order:
		var card := state.card(id)
		if card == null or not ops.is_on_board(id):
			continue
		board_ids.append(id)
		old_power[id] = card.get_current_power()
		card.aura_power_modifier = 0
	var hand_ids: Array[int] = []
	for p in 2:
		for hand_id in state.players[p].hand:
			var hand_card := state.card(hand_id)
			if hand_card == null:
				continue
			hand_ids.append(hand_id)
			old_cost[hand_id] = hand_card.get_current_cost()
			hand_card.aura_cost_modifier = 0

	# --- Step 2: re-apply every active aura source, in the old dispatch order ------
	for id in state.play_order:
		var card := state.card(id)
		if card == null or not card.is_resolved or not ops.is_on_board(id):
			continue
		var card_name: String = ops.card_name(id)
		var level: int = ops.card_level(id)
		var ability_type: String = str(card.data().get("AbilityType", ""))
		if card_name == "Xerath" and level == 2:
			_apply_aura_xerath_lv2(ctx, id)
		elif card_name == "Xerath" and level == 3:
			_apply_aura_xerath_lv3(ctx, id)
		elif card_name == "Azir" and level >= 2:
			_apply_aura_azir(ctx, id)
		elif ability_type == "aura_ascended_buff":
			# Fallback for any future non-Azir ascended-aura card
			_apply_aura_azir(ctx, id)
		elif card_name == "Irelia" and level == 2:
			_apply_aura_irelia_lv2(ctx, id)
		elif ability_type == "aura_blade_buff":
			_apply_aura_blade(ctx, id)
		elif card_name == "Nautilus" and level == 2:
			_apply_aura_nautilus_lv2(ctx, id)

	# The Deep aura is global (not per-source), so it runs after the source loop.
	_apply_aura_deep(ctx)

	# --- Step 3: publish only real changes ----------------------------------------
	for id in board_ids:
		var card := state.card(id)
		if card == null:
			continue
		var new_power: int = card.get_current_power()
		if new_power == int(old_power[id]):
			continue
		# Through the card, so an aura cannot announce the new power of an opponent's
		# face-down card (MatchOps.emit_card_event applies the hidden-card rule).
		ops.emit_card_event(MatchEvents.power_changed(id, new_power - int(old_power[id]), new_power), id)
	for id in hand_ids:
		var card := state.card(id)
		if card == null:
			continue
		var new_cost: int = card.get_current_cost()
		if new_cost == int(old_cost[id]):
			continue
		var event := MatchEvents.cost_changed(id, new_cost - int(old_cost[id]), new_cost)
		ops.emit_card_event(event, id)


# ─── Individual aura implementations ─────────────────────────────────────────────

## Azir lv2/lv3 aura: other allied Ascended Champions/Followers in play gain
## +aura_power Power (all allied lanes, not just Azir's lane). Never itself.
static func _apply_aura_azir(ctx: MatchAbilities, azir_id: int) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var azir := state.card(azir_id)
	if azir == null:
		return
	var aura_amount: int = ops.bv(azir_id, "aura_power", 2)
	var owner_id: int = azir.owner

	for ally_id in ops.board_ids(owner_id):
		if ally_id == azir_id:
			continue
		var ally := state.card(ally_id)
		if ally == null or ally.owner != owner_id or not ally.is_resolved:
			continue
		var ally_data := ally.data()
		if str(ally_data.get("SubType", "")).to_lower() != "ascended":
			continue
		if not _is_unit(ally_data):
			continue
		ally.aura_power_modifier += aura_amount


## Xerath lv2 aura: back-row enemy Champions/Followers in THIS lane have
## -aura_debuff Power.
static func _apply_aura_xerath_lv2(ctx: MatchAbilities, xerath_id: int) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var xerath := state.card(xerath_id)
	if xerath == null:
		return
	var aura_debuff: int = ops.bv(xerath_id, "aura_debuff", 1)
	var enemy_row: int = state.opponent(xerath.owner)

	for enemy_id in state.zone_cards(xerath.col, enemy_row):
		var enemy := state.card(enemy_id)
		if enemy == null or not enemy.is_resolved:
			continue
		if not _is_unit(enemy.data()):
			continue
		if not _is_back_row(enemy):
			continue
		enemy.aura_power_modifier -= aura_debuff


## Xerath lv3 aura: back-row enemy Champions/Followers in EVERY lane have
## -aura_debuff Power.
static func _apply_aura_xerath_lv3(ctx: MatchAbilities, xerath_id: int) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var xerath := state.card(xerath_id)
	if xerath == null:
		return
	var aura_debuff: int = ops.bv(xerath_id, "aura_debuff", 1)
	var enemy_row: int = state.opponent(xerath.owner)

	for col in MatchState.COLUMNS:
		for enemy_id in state.zone_cards(col, enemy_row):
			var enemy := state.card(enemy_id)
			if enemy == null or not enemy.is_resolved:
				continue
			if not _is_unit(enemy.data()):
				continue
			if _is_back_row(enemy):
				enemy.aura_power_modifier -= aura_debuff


## Irelia lv2 aura: allied Champions/Followers whose BASE cost is 1 gain
## +power_increase Power. Iterates every on-board card of the owner, like the old code.
static func _apply_aura_irelia_lv2(ctx: MatchAbilities, irelia_id: int) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var irelia := state.card(irelia_id)
	if irelia == null:
		return
	var aura_amount: int = ops.bv(irelia_id, "power_increase", 1)
	var owner_id: int = irelia.owner

	for ally_id in ops.board_ids(owner_id):
		var ally := state.card(ally_id)
		if ally == null or ally.owner != owner_id or not ally.is_resolved:
			continue
		var ally_data := ally.data()
		if not _is_unit(ally_data):
			continue
		if int(ally_data.get("Cost", -1)) != 1:
			continue
		ally.aura_power_modifier += aura_amount


## Blade aura: all OTHER allied Blades gain +aura_power Power.
static func _apply_aura_blade(ctx: MatchAbilities, blade_id: int) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var blade := state.card(blade_id)
	if blade == null:
		return
	var aura_amount: int = ops.bv(blade_id, "aura_power", 1)
	var ally_row: int = blade.owner

	for ally_id in ops.board_ids(ally_row):
		if ally_id == blade_id:
			continue
		var ally := state.card(ally_id)
		if ally == null or not ally.is_resolved or ally.owner != ally_row:
			continue
		if ally.card_id != "Blade":
			continue
		ally.aura_power_modifier += aura_amount


## Nautilus lv2 aura: Sea Monster cards in the owner's HAND cost {cost_reduction}
## less. The old code only ever touched the local player's hand; here both players'
## hands are discounted, because the host simulates the whole match.
static func _apply_aura_nautilus_lv2(ctx: MatchAbilities, nautilus_id: int) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var nautilus := state.card(nautilus_id)
	if nautilus == null:
		return
	var cost_reduction: int = ops.bv(nautilus_id, "cost_reduction", 3)
	var owner_id: int = nautilus.owner

	for hand_id in state.players[owner_id].hand:
		var hand_card := state.card(hand_id)
		if hand_card == null or hand_card.owner != owner_id:
			continue
		if str(hand_card.data().get("SubType", "")) == "Sea Monster":
			hand_card.aura_cost_modifier -= cost_reduction


## Deep aura: every resolved on-board unit with the 'Deep' keyword owned by a Deep
## player gains +3 aura Power. Deep is permanent once triggered (the deck ran out).
static func _apply_aura_deep(ctx: MatchAbilities) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops

	for id in ops.board_ids(0) + ops.board_ids(1):
		var card := state.card(id)
		if card == null or not card.is_resolved:
			continue
		if card.owner < 0 or card.owner >= state.players.size():
			continue
		if not state.players[card.owner].is_deep:
			continue
		if card.data().get("Keyword", []).has("Deep"):
			card.aura_power_modifier += 3


# ─── Internals ───────────────────────────────────────────────────────────────────

## "Back row" is slot index 2 or 3 inside its own zone (0-1 are the front row).
## The single definition both Xerath auras share (old `_is_back_row`).
static func _is_back_row(card: CardState) -> bool:
	return card.slot >= 2


## True for the two card types every aura targets (Champion / Follower).
static func _is_unit(card_data: Dictionary) -> bool:
	var card_type: String = str(card_data.get("Type", ""))
	return card_type == "Champion" or card_type == "Follower"