## Champion level-up condition checks and Sun Disc logic for the pure-data rules engine.
##
## Ports every check in `Scripts/LevelUpManager.gd`: the champion line-ups
## (Azir, Irelia, Trundle, Xerath, Nasus, Ahri, Kennen, Rumble, Sion, Draven,
## Nautilus, Janna), the power-threshold check (Renekton) and the Sun Disc
## transform / restore. M3 runs all of them from one entry point, `check_all()`,
## because the engine has a single "something changed, re-evaluate" moment
## (`MatchAbilities.after_change`) instead of the old code's several call sites
## (after resolve, after abilities, after draw, after Deep, after every aura recalc).
##
## Deliberate differences from the old code:
##   - owner gating removed (`owner_player_id != cm.current_player_id` / `!= 1`):
##     every check now runs for BOTH owners; the host simulates the whole match;
##   - every level-up is an instant `ops.level_up()` (no animation lock / await);
##   - trackers are matched on INSTANCE ids where the old code compared card nodes or
##     card ids (see the Ahri note below).
##   - a summon only counts once it is REVEALED: a card played from hand gets its
##     `summoned` entry written face-down at play time and flipped by the reveal, so
##     Azir, Irelia, Kennen and Trundle never level off a card the opponent has not
##     seen yet (Sion already skipped unresolved entries, like the old code);
##   - Azir and Irelia exclude only their OWN instance, not every entry with their
##     card_id: a second copy the owner summoned is an ally, as it is for every other
##     champion (the old code compared card ids and skipped them all).
##
## No Node, no scene tree, no signals, no autoloads.
class_name MatchLevelUps


## Runs every level-up condition for both players. Returns true when at least one card
## levelled up (or the Sun Disc transformed), so the caller's
## "auras -> level-ups -> auras" loop knows whether it has to run again.
static func check_all(ctx: MatchAbilities) -> bool:
	var changed: bool = false
	if _check_azir_levelup(ctx):
		changed = true
	if _check_irelia_levelup(ctx):
		changed = true
	if _check_trundle_levelup(ctx):
		changed = true
	if _check_xerath_levelup(ctx):
		changed = true
	if _check_nasus_levelup(ctx):
		changed = true
	if _check_ahri_levelup(ctx):
		changed = true
	if _check_kennen_levelup(ctx):
		changed = true
	if _check_rumble_levelup(ctx):
		changed = true
	if _check_sion_levelup(ctx):
		changed = true
	if _check_draven_levelup(ctx):
		changed = true
	if _check_nautilus_levelup_all(ctx):
		changed = true
	if _check_janna_levelup(ctx):
		changed = true
	if _check_level_ups_by_power(ctx):
		changed = true
	if _check_sun_disc_transform(ctx):
		changed = true
	return changed


# ─── Individual level-up checks ──────────────────────────────────────────────────

## Azir lv1 → lv2: ally_threshold+ summoned allies or landmarks of the owner
## (Azir's own instance excluded; unrevealed summons not counted).
## Port of `_check_azir_levelup`.
static func _check_azir_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Azir" or ops.card_level(id) != 1:
			continue
		var ally_threshold: int = ops.bv(id, "ally_threshold", 6)
		var count: int = _count_summoned(state, card.owner, id, true)
		if count < ally_threshold:
			continue
		if _level_up_and_check_disc(ctx, id):
			changed = true
	return changed


## Irelia lv1 → lv2: ally_threshold+ summoned Champions/Followers (no landmarks).
## Irelia's own instance is excluded; unrevealed summons are not counted.
## Port of `_check_irelia_levelup`.
static func _check_irelia_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Irelia" or ops.card_level(id) != 1:
			continue
		var ally_threshold: int = ops.bv(id, "ally_threshold", 6)
		var count: int = _count_summoned(state, card.owner, id, false)
		if count < ally_threshold:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Counts the owner's REVEALED `summoned` entries, skipping the champion's own INSTANCE
## (a second copy of the same champion counts as an ally). Champions and Followers
## always count; Landmarks only for Azir (Irelia excludes them).
## Port of the two counting loops inside `_check_azir_levelup` / `_check_irelia_levelup`.
static func _count_summoned(state: MatchState, owner_id: int, self_instance_id: int, include_landmarks: bool) -> int:
	var count: int = 0
	for entry: Dictionary in state.summoned:
		if int(entry.get("owner_player_id", -1)) != owner_id:
			continue
		if int(entry.get("instance_id", -1)) == self_instance_id:
			continue  # Skip the champion herself
		if not bool(entry.get("is_resolved", false)):
			continue  # Still face-down in the resolve queue
		var summoned_card_id: String = str(entry.get("card_id", ""))
		var card_type: String = str(CardDatabase.CARDS.get(summoned_card_id, {}).get("Type", ""))
		if card_type == "Champion" or card_type == "Follower":
			count += 1
		elif include_landmarks and card_type == "Landmark":
			count += 1
	return count


## Trundle lv1 → lv2 for BOTH owners: the owner played an Ice Pillar from hand AND it
## has been revealed (an unrevealed one is still face-down and does not count).
## Port of `_check_trundle_levelup` (the owner argument is gone, the gating removed).
static func _check_trundle_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for owner_id in 2:
		var ice_pillar_played: bool = false
		for entry: Dictionary in state.summoned:
			if str(entry.get("card_id", "")) != "IcePillar":
				continue
			if int(entry.get("owner_player_id", -1)) != owner_id:
				continue
			if not bool(entry.get("was_played_from_hand", false)):
				continue
			if not bool(entry.get("is_resolved", false)):
				continue
			ice_pillar_played = true
			break
		if not ice_pillar_played:
			continue
		for id in _on_board_ids(ctx):
			var card := state.card(id)
			if card.owner != owner_id:
				continue
			if ops.card_name(id) != "Trundle":
				continue
			if str(card.data().get("AbilityType", "")) != "create_card":
				continue
			if _level_up_to_data(ctx, id, "LevelUpTo"):
				changed = true
	return changed


## Xerath lv1 → lv2: ally_threshold+ allied resolved Champions/Followers have a
## positive total power modifier. Port of `_check_xerath_levelup`.
static func _check_xerath_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Xerath":
			continue
		if str(card.data().get("AbilityType", "")) != "drain_power":
			continue
		var ally_threshold: int = ops.bv(id, "ally_threshold", 4)
		var buffed_count: int = 0
		for ally_id in ops.board_ids(card.owner):
			var ally := state.card(ally_id)
			if ally == null or not ally.is_resolved:
				continue
			var c_type: String = str(ally.data().get("Type", ""))
			if c_type != "Champion" and c_type != "Follower":
				continue
			if ally.power_modifier + ally.aura_power_modifier > 0:
				buffed_count += 1
		if buffed_count < ally_threshold:
			continue
		if _level_up_and_check_disc(ctx, id):
			changed = true
	return changed


## Nasus lv1 → lv2: the owner has killed kill_threshold+ units.
## Port of `_check_nasus_levelup` (owner gating removed).
static func _check_nasus_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Nasus" or ops.card_level(id) != 1:
			continue
		var kill_threshold: int = ops.bv(id, "kill_threshold", 2)
		var owner_kill_count: int = 0
		for entry: Dictionary in state.killed:
			if int(entry.get("killer_player_id", -1)) == card.owner:
				owner_kill_count += 1
		if owner_kill_count < kill_threshold:
			continue
		if _level_up_and_check_disc(ctx, id):
			changed = true
	return changed


## Ahri lv1 → lv2: Ahri has recalled recall_threshold+ allies.
## Port of `_check_ahri_levelup`. DEVIATION: the old code compared the recalled
## tracker's `recaller_card_id` with Ahri's CURRENT card_id, so once Ahri levelled up
## no later recall could ever count towards the next threshold. Here the recall must
## name THIS Ahri INSTANCE (`recaller_instance_id`), which survives a level-up.
static func _check_ahri_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Ahri" or ops.card_level(id) != 1:
			continue
		var recall_threshold: int = ops.bv(id, "recall_threshold", 3)
		var recall_count: int = 0
		for entry: Dictionary in state.recalled:
			if int(entry.get("recaller_player_id", -1)) != card.owner:
				continue
			if int(entry.get("recaller_instance_id", -1)) != id:
				continue
			recall_count += 1
		if recall_count < recall_threshold:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Kennen lv1 → lv2: the owner summoned the same ally summon_threshold+ times. A copy
## still face-down in the resolve queue does not count yet.
## Port of `_check_kennen_levelup`.
static func _check_kennen_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Kennen" or ops.card_level(id) != 1:
			continue
		var summon_threshold: int = ops.bv(id, "summon_threshold", 3)
		var id_counts: Dictionary = {}
		for entry: Dictionary in state.summoned:
			if int(entry.get("owner_player_id", -1)) != card.owner:
				continue
			if not bool(entry.get("is_resolved", false)):
				continue
			var sid: String = str(entry.get("card_id", ""))
			id_counts[sid] = int(id_counts.get(sid, 0)) + 1
		var qualifying: bool = false
		for sid: String in id_counts:
			if int(id_counts[sid]) >= summon_threshold:
				qualifying = true
				break
		if not qualifying:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Rumble lv1 → lv2: the owner discarded discard_threshold+ times.
## Port of `_check_rumble_levelup` (owner gating removed).
static func _check_rumble_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Rumble" or ops.card_level(id) != 1:
			continue
		var discard_threshold: int = ops.bv(id, "discard_threshold", 4)
		var owner_discard_count: int = 0
		for entry: Dictionary in state.discarded:
			if int(entry.get("owner_player_id", -1)) == card.owner:
				owner_discard_count += 1
		if owner_discard_count < discard_threshold:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Sion lv1 → lv2: the owner has discarded or summoned power_threshold+ total base Power.
## Port of `_check_sion_levelup` (owner gating removed). Unresolved summons (still
## face-down in the resolve queue) do not count, like the old code.
static func _check_sion_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Sion" or ops.card_level(id) != 1:
			continue
		var power_threshold: int = ops.bv(id, "power_threshold", 32)
		var total_power: int = 0
		for entry: Dictionary in state.discarded:
			if int(entry.get("owner_player_id", -1)) != card.owner:
				continue
			total_power += _base_power_of(str(entry.get("card_id", "")))
		for entry: Dictionary in state.summoned:
			if int(entry.get("owner_player_id", -1)) != card.owner:
				continue
			if not bool(entry.get("is_resolved", false)):
				continue
			total_power += _base_power_of(str(entry.get("card_id", "")))
		if total_power < power_threshold:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Draven lv1 → lv2: he has seen axe_threshold+ Spinning Axes played while on the board.
## Port of `_check_draven_levelup` (owner gating removed). The count lives on the card
## (`CardState.axe_play_count`, bumped by the Spinning Axe play ability).
static func _check_draven_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Draven" or ops.card_level(id) != 1:
			continue
		var axe_threshold: int = ops.bv(id, "axe_threshold", 2)
		if card.axe_play_count < axe_threshold:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Nautilus lv1 → lv2 for both players. Port of `_check_nautilus_levelup_all`.
static func _check_nautilus_levelup_all(ctx: MatchAbilities) -> bool:
	var changed: bool = false
	for player_id in 2:
		if _check_nautilus_levelup(ctx, player_id):
			changed = true
	return changed


## Nautilus lv1 → lv2 once the owning player is Deep (their deck ran out).
## Port of `_check_nautilus_levelup` (owner gating removed).
static func _check_nautilus_levelup(ctx: MatchAbilities, player_id: int) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	if not state.players[player_id].is_deep:
		return false
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if card.owner != player_id:
			continue
		if ops.card_name(id) != "Nautilus" or ops.card_level(id) != 1:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Janna lv1 → lv2 after drawing draw_threshold+ cards cumulatively.
## Port of `_check_janna_levelup` (owner gating removed).
static func _check_janna_levelup(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := state.card(id)
		if ops.card_name(id) != "Janna" or ops.card_level(id) != 1:
			continue
		var draw_threshold: int = ops.bv(id, "draw_threshold", 12)
		var count: int = 0
		for entry: Dictionary in state.drawn:
			if int(entry.get("owner_player_id", -1)) == card.owner:
				count += 1
		if count < draw_threshold:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			changed = true
	return changed


## Power-threshold level-ups (Renekton lv1: "I've increased my Power by
## power_threshold+"). The old code ran `check_level_up_by_power` on every resolved
## on-board card after every aura recalculation; here `check_all` runs it once over the
## whole board. Only the PERMANENT modifier counts, exactly like the old check (which
## compared `card.power_modifier`, not the aura part).
static func _check_level_ups_by_power(ctx: MatchAbilities) -> bool:
	var changed: bool = false
	for id in _board_ids(ctx):
		var card := ctx.state.card(id)
		if card == null:
			continue
		var balance: Dictionary = card.data().get("BalanceValues", {})
		if not balance.has("power_threshold"):
			continue
		if card.power_modifier < int(balance.get("power_threshold", 0)):
			continue
		if _level_up_and_check_disc(ctx, id):
			changed = true
	return changed


# ─── Sun Disc helpers ────────────────────────────────────────────────────────────

## True when `owner_id` has a Restored Sun Disc on the board.
## Port of `_is_sun_disc_restored`.
static func _is_sun_disc_restored(ctx: MatchAbilities, owner_id: int) -> bool:
	var ops: MatchOps = ctx.ops
	for id in _on_board_ids(ctx):
		if ctx.state.card(id).owner != owner_id:
			continue
		if ops.card_name(id) == "Restored Sun Disc":
			return true
	return false


## If the Sun Disc is already restored and `card_id` just became lv2 Ascended, push it
## straight to lv3. Port of `_check_ascended_sun_disc_upgrade`.
static func _check_ascended_sun_disc_upgrade(ctx: MatchAbilities, card_id: int) -> bool:
	var card := ctx.state.card(card_id)
	if card == null:
		return false
	var card_data := card.data()
	if str(card_data.get("Type", "")) != "Champion":
		return false
	if str(card_data.get("SubType", "")) != "Ascended":
		return false
	if int(card_data.get("Level", 1)) != 2:
		return false
	if not _is_sun_disc_restored(ctx, card.owner):
		return false
	return _level_up_to_data(ctx, card_id, "LevelUpTo")


## Levels `card_id` up to its `LevelUpTo` and then applies the Sun Disc upgrade rule.
## This is the old "_perform_level_up() + _check_ascended_sun_disc_upgrade()" sequence
## that the Ascended champions (Azir, Xerath, Nasus, Renekton) each used.
static func _level_up_and_check_disc(ctx: MatchAbilities, card_id: int) -> bool:
	if not _level_up_to_data(ctx, card_id, "LevelUpTo"):
		return false
	_check_ascended_sun_disc_upgrade(ctx, card_id)
	return true


## Buried Sun Disc → Restored Sun Disc when the owner has ascended_threshold+ allied
## Ascended Champions at lv2 on the board. Port of `_check_sun_disc_transform`.
static func _check_sun_disc_transform(ctx: MatchAbilities) -> bool:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var changed: bool = false
	for id in _on_board_ids(ctx):
		var card := state.card(id)
		if str(card.data().get("AbilityType", "")) != "transform_landmark":
			continue
		if ops.card_name(id) != "Buried Sun Disc":
			continue
		var owner_id: int = card.owner
		var ascended_lv2_count: int = 0
		for ally_id in ops.board_ids(owner_id):
			var ally := state.card(ally_id)
			if ally == null or not ally.is_resolved:
				continue
			var ally_data := ally.data()
			if str(ally_data.get("Type", "")) != "Champion":
				continue
			if str(ally_data.get("SubType", "")) != "Ascended":
				continue
			if int(ally_data.get("Level", 1)) == 2:
				ascended_lv2_count += 1
		var ascended_threshold: int = ops.bv(id, "ascended_threshold", 2)
		if ascended_lv2_count < ascended_threshold:
			continue
		if _level_up_to_data(ctx, id, "LevelUpTo"):
			_on_sun_disc_restored(ctx, owner_id)
			changed = true
	return changed


## Side effects of the Sun Disc transform: draw every Ascended card that is not
## beheld, then immediately level every allied lv2 Ascended champion to lv3.
## Port of `_on_sun_disc_restored`. The old code only drew for the local player
## (`owner_id == cm.current_player_id`); the host now does it for both owners.
static func _on_sun_disc_restored(ctx: MatchAbilities, owner_id: int) -> void:
	var state: MatchState = ctx.state
	var ops: MatchOps = ctx.ops
	var beheld_names: Dictionary = {}
	for beheld_id in ops.beheld(owner_id):
		var beheld := state.card(beheld_id)
		if beheld == null:
			continue
		if str(beheld.data().get("SubType", "")) != "Ascended":
			continue
		var beheld_name: String = str(beheld.data().get("Name", ""))
		if not beheld_name.is_empty():
			beheld_names[beheld_name] = true

	# Deck order decides which copy is drawn first; one copy per champion NAME.
	for deck_id in state.players[owner_id].deck.duplicate():
		var deck_card := state.card(deck_id)
		if deck_card == null:
			continue
		if str(deck_card.data().get("SubType", "")) != "Ascended":
			continue
		var deck_name: String = str(deck_card.data().get("Name", ""))
		if beheld_names.has(deck_name):
			continue
		beheld_names[deck_name] = true  # no duplicate draws of the same champion
		ops.draw_specific(owner_id, deck_card.card_id)

	# Level every allied lv2 Ascended champion to lv3. Snapshot the ids first:
	# level_up changes card_id in place.
	for id in _on_board_ids(ctx):
		var ally := state.card(id)
		if ally.owner != owner_id:
			continue
		var ally_data := ally.data()
		if str(ally_data.get("Type", "")) != "Champion":
			continue
		if str(ally_data.get("SubType", "")) != "Ascended":
			continue
		if int(ally_data.get("Level", 1)) != 2:
			continue
		_level_up_to_data(ctx, id, "LevelUpTo")


# ─── Internals ───────────────────────────────────────────────────────────────────

## Every on-board, resolved card as instance ids, in play order (a snapshot, so the
## caller may level cards up while iterating it).
static func _board_ids(ctx: MatchAbilities) -> Array[int]:
	var ops: MatchOps = ctx.ops
	var ids: Array[int] = []
	for id in ctx.state.play_order:
		var card := ctx.state.card(id)
		if card == null or not card.is_resolved or not ops.is_on_board(id):
			continue
		ids.append(id)
	return ids


## Every card anywhere on the board, resolved or not, as instance ids in play order
## (a snapshot, so the caller may level cards up while iterating it). Trundle, the
## Sun Disc transform and the restore used this list in the old code: those three
## checks only asked whether a card was on the board, never whether it was revealed.
static func _on_board_ids(ctx: MatchAbilities) -> Array[int]:
	var ops: MatchOps = ctx.ops
	var ids: Array[int] = []
	for id in ctx.state.play_order:
		var card := ctx.state.card(id)
		if card == null or not ops.is_on_board(id):
			continue
		ids.append(id)
	return ids


## The shared tail of every check: read `key` off the card data, bail on an empty or
## unknown target id, and `ops.level_up()` to it. True when the card levelled up.
static func _level_up_to_data(ctx: MatchAbilities, card_id: int, key: String) -> bool:
	var card := ctx.state.card(card_id)
	if card == null:
		return false
	var level_up_to := str(card.data().get(key, ""))
	if level_up_to.is_empty() or not CardDatabase.CARDS.has(level_up_to):
		return false
	ctx.ops.level_up(card_id, level_up_to)
	return true


## A card's base Power (0 when it has none, like `CardDatabase` entries without Power).
static func _base_power_of(card_id: String) -> int:
	var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if not card_data.has("Power"):
		return 0
	return int(card_data.get("Power", 0))