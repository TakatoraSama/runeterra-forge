## Match events for the pure-data rules engine.
##
## Every event is a plain Dictionary of primitives (int, String, StringName, bool,
## Array, Dictionary) with a "type" key holding one of the constants below. They carry
## no Objects or Nodes, so they can be serialized with JSON.stringify() and sent over
## the network as-is, and both peers can replay a match from the resulting log.
## This class is static only: it holds no state.
class_name MatchEvents

# --- Turn / phase flow ---
const TURN_STARTED := &"turn_started"				# {turn}
const PHASE_CHANGED := &"phase_changed"			# {game_phase, round_phase, turn}
const MANA_CHANGED := &"mana_changed"				# {player, current, max}
const TURN_ENDED := &"turn_ended"				# {player} - that player ended their turn (public)
const PLAY_OPENED := &"play_opened"				# {turn} - PLAY is open for `turn` (session layer only)
const SESSION_ENDED := &"session_ended"			# {reason: String}
const PRIORITY_CHANGED := &"priority_changed"		# {player}
const LANE_ASSIGNED := &"lane_assigned"			# {lane_ids: Array}
const LANE_REVEALED := &"lane_revealed"			# {col, lane_id}
const LANE_EFFECT := &"lane_effect"				# {col, lane_id, effect: String}

# --- Card flow ---
const CARD_DRAWN := &"card_drawn"					# {player, instance_id, card_id}
const CARD_CREATED_IN_HAND := &"card_created_in_hand"	# {player, instance_id, card_id, creator_instance_id}
const CARD_PLAYED := &"card_played"				# {player, instance_id, card_id, col, slot}
const PLAY_UNDONE := &"play_undone"				# {player, instance_ids: Array, hand_after: Array of instance ids}
const INTENT_REJECTED := &"intent_rejected"		# {player, intent_type, reason, instance_id (-1 = the intent names no card)}
const SWAP_STARTED := &"swap_started"				# {player, instance_id, from_col, to_col}
const CARD_SWAPPED := &"card_swapped"				# {player, instance_id, from_col, to_col, slot}
const CARD_REVEALED := &"card_revealed"			# {player, instance_id, card_id, col, slot}
const POWER_CHANGED := &"power_changed"			# {instance_id, delta, new_power}
const COST_CHANGED := &"cost_changed"				# {instance_id, delta, new_cost}
const KEYWORD_ADDED := &"keyword_added"			# {instance_id, keyword}
const KEYWORD_REMOVED := &"keyword_removed"		# {instance_id, keyword}
const CARD_KILLED := &"card_killed"				# {instance_id, killer_player, killer_instance_id}
const DEATH_PREVENTED := &"death_prevented"		# {instance_id}
const CARD_DISCARDED := &"card_discarded"		# {player, instance_id, card_id}
const CARD_RECALLED := &"card_recalled"			# {player, instance_id}
const CARD_SUMMONED := &"card_summoned"			# {player, instance_id, card_id, col, slot}
const CARD_LEVELED_UP := &"card_leveled_up"		# {instance_id, old_card_id, new_card_id}
const DEEP_CHANGED := &"deep_changed"				# {player, is_deep}
const SUN_DISC_RESTORED := &"sun_disc_restored"	# {player}
const GAME_ENDED := &"game_ended"				# {winner (-1 = tie), lane_powers: [[p0c0, p0c1, p0c2], [p1c0, p1c1, p1c2]]}

const SPELL_RESOLVED := &"spell_resolved"			# {player, instance_id}
const CARD_SHUFFLED_INTO_DECK := &"card_shuffled_into_deck"	# {player, instance_id, card_id}
const RESOLVE_STARTED := &"resolve_started"			# {plays: Array} - {player, instance_id, col, slot} per card, no card_id


static func turn_started(turn: int) -> Dictionary:
	"""Round start: the turn counter advanced to `turn`."""
	return {"type": TURN_STARTED, "turn": turn}


static func phase_changed(game_phase: int, round_phase: int, turn: int) -> Dictionary:
	"""One of the GamePhase / RoundPhase values changed."""
	return {"type": PHASE_CHANGED, "game_phase": game_phase, "round_phase": round_phase, "turn": turn}


static func mana_changed(player: int, current: int, max: int) -> Dictionary:
	"""A player's mana pool changed."""
	return {"type": MANA_CHANGED, "player": player, "current": current, "max": max}


static func priority_changed(player: int) -> Dictionary:
	"""Turn priority moved to `player`."""
	return {"type": PRIORITY_CHANGED, "player": player}



static func turn_ended(player: int) -> Dictionary:
	"""`player` ended their turn. Public to both viewers: each side needs it to
	grey out its own End Turn button while the round waits for the other player.
	Emitted by MatchRules._end_turn before _resolve_round, never by the presenter."""
	return {"type": TURN_ENDED, "player": player}


static func lane_assigned(lane_ids: Array) -> Dictionary:
	"""The three lanes were assigned (still hidden from the players)."""
	return {"type": LANE_ASSIGNED, "lane_ids": lane_ids}


static func lane_revealed(col: int, lane_id: String) -> Dictionary:
	"""The lane in column `col` was revealed as `lane_id`."""
	return {"type": LANE_REVEALED, "col": col, "lane_id": lane_id}


static func lane_effect(col: int, lane_id: String, effect: String) -> Dictionary:
	"""A lane's passive effect was announced."""
	return {"type": LANE_EFFECT, "col": col, "lane_id": lane_id, "effect": effect}


static func card_drawn(player: int, instance_id: int, card_id: String) -> Dictionary:
	"""`player` drew the card `instance_id` (card_id `card_id`) from their deck."""
	return {"type": CARD_DRAWN, "player": player, "instance_id": instance_id, "card_id": card_id}


static func card_created_in_hand(player: int, instance_id: int, card_id: String, creator_instance_id: int) -> Dictionary:
	"""An effect created card `instance_id` directly into `player`'s hand."""
	return {
		"type": CARD_CREATED_IN_HAND,
		"player": player,
		"instance_id": instance_id,
		"card_id": card_id,
		"creator_instance_id": creator_instance_id,
	}


static func card_played(player: int, instance_id: int, card_id: String, col: int, slot: int) -> Dictionary:
	"""`player` moved card `instance_id` onto the board (column `col`, slot `slot`)."""
	return {
		"type": CARD_PLAYED,
		"player": player,
		"instance_id": instance_id,
		"card_id": card_id,
		"col": col,
		"slot": slot,
	}


static func play_undone(player: int, instance_ids: Array, hand_after: Array = []) -> Dictionary:
	"""`player` undid the listed plays, pulling them back to hand. `hand_after` is that
	player's hand order once every card is back, so a presenter can re-lay the hand
	without guessing which slot each card returned to."""
	return {"type": PLAY_UNDONE, "player": player, "instance_ids": instance_ids, "hand_after": hand_after}


static func intent_rejected(player: int, intent_type: String, reason: String, instance_id: int = -1) -> Dictionary:
	"""An intent from `player` was refused because of `reason`. `instance_id` is the card
	the intent was about, or -1 for intents that name none (end_turn, undo), so a
	presenter can send that card home instead of only showing the reason.
	PLANNED, deliberately NOT done here because it changes behaviour: this event will
	gain a "private_to" key equal to `player` so a refusal reaches the sender alone.
	redact_for() already drops any event whose private_to is not the viewer, so the
	change is only made at the emission sites (M5a Group A)."""
	return {
		"type": INTENT_REJECTED,
		"player": player,
		"intent_type": intent_type,
		"reason": reason,
		"instance_id": instance_id,
	}


static func swap_started(player: int, instance_id: int, from_col: int, to_col: int) -> Dictionary:
	"""`player` started dragging card `instance_id` from `from_col` to `to_col` (SWAP_LANE)."""
	return {
		"type": SWAP_STARTED,
		"player": player,
		"instance_id": instance_id,
		"from_col": from_col,
		"to_col": to_col,
	}


static func card_swapped(player: int, instance_id: int, from_col: int, to_col: int, slot: int) -> Dictionary:
	"""Card `instance_id` was moved from `from_col` to `to_col` and landed in `slot`."""
	return {
		"type": CARD_SWAPPED,
		"player": player,
		"instance_id": instance_id,
		"from_col": from_col,
		"to_col": to_col,
		"slot": slot,
	}


static func card_revealed(player: int, instance_id: int, card_id: String, col: int, slot: int, power: int = -1, cost: int = -1, keywords: Array = []) -> Dictionary:
	"""A previously hidden card became public at resolve time.
	`power`, `cost` and `keywords` carry the card's FINAL values, so a viewer shows the
	real numbers instead of reconstructing them from modifiers it never saw. They are
	OPTIONAL and OMITTED from the dict at their sentinels (-1 / -1 / []): every existing
	caller keeps producing the exact same event, so a consumer must read them with a
	default (event.get("power", -1)) and must not assume the key is present."""
	var event: Dictionary = {
		"type": CARD_REVEALED,
		"player": player,
		"instance_id": instance_id,
		"card_id": card_id,
		"col": col,
		"slot": slot,
	}
	if power >= 0:
		event["power"] = power
	if cost >= 0:
		event["cost"] = cost
	if not keywords.is_empty():
		event["keywords"] = keywords
	return event


static func power_changed(instance_id: int, delta: int, new_power: int) -> Dictionary:
	"""A card's power changed by `delta` and is now `new_power`."""
	return {"type": POWER_CHANGED, "instance_id": instance_id, "delta": delta, "new_power": new_power}


static func cost_changed(instance_id: int, delta: int, new_cost: int) -> Dictionary:
	"""A card's cost changed by `delta` and is now `new_cost`."""
	return {"type": COST_CHANGED, "instance_id": instance_id, "delta": delta, "new_cost": new_cost}


static func keyword_added(instance_id: int, keyword: String) -> Dictionary:
	"""A runtime keyword was granted to a card."""
	return {"type": KEYWORD_ADDED, "instance_id": instance_id, "keyword": keyword}


static func keyword_removed(instance_id: int, keyword: String) -> Dictionary:
	"""A runtime keyword was taken away from a card."""
	return {"type": KEYWORD_REMOVED, "instance_id": instance_id, "keyword": keyword}


static func card_killed(instance_id: int, killer_player: int, killer_instance_id: int) -> Dictionary:
	"""Card `instance_id` died; -1 killer fields mean the zone / no source."""
	return {
		"type": CARD_KILLED,
		"instance_id": instance_id,
		"killer_player": killer_player,
		"killer_instance_id": killer_instance_id,
	}


static func death_prevented(instance_id: int) -> Dictionary:
	"""Card `instance_id` would have died but an effect saved it."""
	return {"type": DEATH_PREVENTED, "instance_id": instance_id}


static func card_discarded(player: int, instance_id: int, card_id: String) -> Dictionary:
	"""`player` discarded the card `instance_id` from their hand."""
	return {"type": CARD_DISCARDED, "player": player, "instance_id": instance_id, "card_id": card_id}


static func card_recalled(player: int, instance_id: int) -> Dictionary:
	"""`player`'s card `instance_id` returned to their hand."""
	return {"type": CARD_RECALLED, "player": player, "instance_id": instance_id}


static func card_summoned(player: int, instance_id: int, card_id: String, col: int, slot: int, power: int = -1, cost: int = -1, keywords: Array = []) -> Dictionary:
	"""An effect summoned card `instance_id` straight onto the board.
	`power`, `cost` and `keywords` carry the summoned card's FINAL values and are
	omitted from the dict unless given, exactly as in card_revealed()."""
	var event: Dictionary = {
		"type": CARD_SUMMONED,
		"player": player,
		"instance_id": instance_id,
		"card_id": card_id,
		"col": col,
		"slot": slot,
	}
	if power >= 0:
		event["power"] = power
	if cost >= 0:
		event["cost"] = cost
	if not keywords.is_empty():
		event["keywords"] = keywords
	return event


static func card_leveled_up(instance_id: int, old_card_id: String, new_card_id: String, silent: bool = false) -> Dictionary:
	"""A champion card swapped its card_id when levelling up. `silent` marks the
	secondary copies that only followed the champion's level-up."""
	return {
		"type": CARD_LEVELED_UP,
		"instance_id": instance_id,
		"old_card_id": old_card_id,
		"new_card_id": new_card_id,
		"silent": silent,
	}


static func deep_changed(player: int, is_deep: bool) -> Dictionary:
	"""`player` went into (or came out of) Deep."""
	return {"type": DEEP_CHANGED, "player": player, "is_deep": is_deep}


static func sun_disc_restored(player: int) -> Dictionary:
	"""`player`'s Sun Disc came back into play."""
	return {"type": SUN_DISC_RESTORED, "player": player}


static func game_ended(winner: int, lane_powers: Array) -> Dictionary:
	"""The match is over. `winner` is -1 for a tie. `lane_powers` is [[p0c0, p0c1, p0c2], [p1c0, p1c1, p1c2]]."""
	return {"type": GAME_ENDED, "winner": winner, "lane_powers": lane_powers}


static func spell_resolved(player: int, instance_id: int) -> Dictionary:
	"""`player`'s spell `instance_id` finished resolving and left the board."""
	return {"type": SPELL_RESOLVED, "player": player, "instance_id": instance_id}


static func card_shuffled_into_deck(player: int, instance_id: int, card_id: String) -> Dictionary:
	"""`player` shuffled card `instance_id` (card_id `card_id`) from hand back into their deck."""
	return {
		"type": CARD_SHUFFLED_INTO_DECK,
		"player": player,
		"instance_id": instance_id,
		"card_id": card_id,
	}


static func resolve_started(plays: Array) -> Dictionary:
	"""The resolve phase began. `plays` lists the cards going down this round as
	{player, instance_id, col, slot}, with no card_id: everyone sees the board, the
	card identities stay secret until they are revealed one by one."""
	return {"type": RESOLVE_STARTED, "plays": plays}


static func play_opened(turn: int) -> Dictionary:
	"""PLAY is open for turn `turn` and both players may act. The rules engine
	emits nothing for the turn of the player who did not end it, and a session may
	hold a submit back until every viewer has acked the previous batch, so the
	opening of a PLAY phase is announced by the SESSION layer (MatchHost), never
	by MatchRules and never for the first turn of a match.
	This is the gate the presenter's is_play_phase() waits for."""
	return {"type": PLAY_OPENED, "turn": turn}


static func session_ended(reason: String) -> Dictionary:
	"""The session is over for a reason the rules do not own: a peer disconnected,
	the opponent left, the join handshake was refused. `reason` is a REASON_TEXT
	key of MatchPresenter ("not_ready", "opponent_left", "disconnected", ...).
	Informational only: GAME_ENDED remains the match result."""
	return {"type": SESSION_ENDED, "reason": reason}


static func redact_for(event: Dictionary, viewer: int) -> Variant:
	"""Return what `viewer` is allowed to see of `event`, or null if nothing is sent.
	`event` is never mutated: the result is always a deep copy.
	An event tagged "private_to" (a card that is still in a hand or a deck) goes
	to its owner alone; everything else follows the opponent-visibility rules,
	where opponent plays stay secret until RESOLVE and hidden hand contents keep
	their identity but lose `card_id`."""
	if event.has("private_to") and int(event["private_to"]) != viewer:
		return null
	var copy: Dictionary = event.duplicate(true)
	var owner_id: Variant = copy.get("player", null)
	var is_opponent: bool = not (owner_id is int and owner_id == viewer)
	match copy.get("type", &""):
		CARD_PLAYED, PLAY_UNDONE, SWAP_STARTED:
			if is_opponent:
				return null
		CARD_DRAWN, CARD_CREATED_IN_HAND, CARD_SHUFFLED_INTO_DECK:
			if is_opponent:
				copy.erase("card_id")
	return copy
