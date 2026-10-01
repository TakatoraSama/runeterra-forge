class_name MatchState extends RefCounted
## Pure-data state of a whole match: cards, players, board zones, trackers and the RNG.
## No Node, no scene tree, no autoloads. Player ids are absolute (0 = host, 1 = guest);
## there is no local/remote perspective anywhere in here.
##
## Zones are keyed by Vector2i(col, owner) and are always COMPACT: a card's `slot` equals its
## index in its zone list, and removing a card shifts the later cards down
## (like BoardGeneration.reposition_cards_in_zone). All 8 zones (3 columns x 2 owners plus
## one spell zone per owner) are pre-created so a missing zone can never be told apart from
## an empty one in the serialized form.

const COLUMNS := 3
const SLOTS_PER_ZONE := 4
const SPELL_COL := -1
const SPELL_SLOTS := 4
enum GamePhase { GAME_START, TURN_LOOP, GAME_END }  # same values as GameManager
enum RoundPhase { NONE, ROUND_START, PLAY, SWAP_LANE, RESOLVE, ROUND_END }  # same values as GameManager

## Tracker keys that hold integers. Mirrors the keys of CardManager's tracker arrays plus
## "instance_id"; used to int()-cast the numbers JSON turned into floats on load.
const TRACKER_INT_KEYS: Array[String] = [
	"instance_id",
	"owner_player_id",
	"killer_player_id",
	"creator_player_id",
	"recaller_player_id",
	"turn",
	"created_at_turn",
	"discarded_at_turn",
	"stunned_on_turn",
	"zone_key",
]

var cards: Dictionary = {}  # instance_id (int) -> CardState
var next_instance_id: int = 1
var players: Array[PlayerState] = []  # always 2, created in _init()
var turn: int = 0
var game_phase: int = GamePhase.GAME_START
var round_phase: int = RoundPhase.NONE
var flip_first: int = -1  # absolute player id with priority, -1 = unset
var lane_ids: Array[String] = []
var lane_revealed: Array[bool] = [false, false, false]
var noxkraya_col: int = -1
var zones: Dictionary = {}  # Vector2i(col, owner) -> Array[int] of instance ids, COMPACT, index == slot
var play_order: Array[int] = []  # append-only: every card that ever entered the board
var played_this_turn: Array[int] = []
var killed: Array[Dictionary] = []  # trackers: same keys as CardManager's arrays + "instance_id";
var summoned: Array[Dictionary] = []  #   all player ids absolute
var created: Array[Dictionary] = []
var recalled: Array[Dictionary] = []
var discarded: Array[Dictionary] = []
var drawn: Array[Dictionary] = []
var stuns: Array[Dictionary] = []  # {"instance_id": int, "stunned_on_turn": int}
var pending_swaps: Array[Dictionary] = []
var swap_history: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	players = [PlayerState.new(), PlayerState.new()]
	_ensure_zones()


## Creates a new card instance, assigns it the next instance id and registers it.
func new_card(card_id: String, owner: int, location: int) -> CardState:
	var c := CardState.new()
	c.instance_id = next_instance_id
	next_instance_id += 1
	c.card_id = card_id
	c.owner = owner
	c.location = location
	cards[c.instance_id] = c
	return c


## Returns the card with that instance id, or null when unknown.
func card(id: int) -> CardState:
	var c: CardState = cards.get(id, null)
	return c


## Returns a COPY of the instance ids in a zone ([] when the zone does not exist).
func zone_cards(col: int, owner: int) -> Array[int]:
	var result: Array[int] = []
	var list: Array = zones.get(Vector2i(col, owner), [])
	for id in list:
		result.append(int(id))
	return result


## Returns true when a zone still has room (the spell zone holds SPELL_SLOTS cards).
## A column outside 0..COLUMNS-1 that is not SPELL_COL has no zone, so it reports false.
func zone_has_space(col: int, owner: int) -> bool:
	if not _is_valid_col(col):
		return false
	var limit: int = SPELL_SLOTS if col == SPELL_COL else SLOTS_PER_ZONE
	return zone_cards(col, owner).size() < limit


## Places a card in a zone. slot -1 appends, otherwise the card is inserted at min(slot, size)
## and the cards behind it shift back.
## Guards, all of which return false and change nothing:
##   - unknown instance id;
##   - a column outside 0..COLUMNS-1 that is not SPELL_COL (push_error);
##   - a zone owned by another player than the card (push_error);
##   - a full target zone the card does not already sit in.
## Re-slotting a card inside its own (full) zone works: it is taken out first, which frees the
## slot it needs. A card that is on the board in a different zone is removed from there first.
func place_card(id: int, col: int, owner: int, slot: int = -1) -> bool:
	var c := card(id)
	if c == null:
		return false
	if not _is_valid_col(col):
		push_error("MatchState.place_card: %d is not a lane column nor the spell column" % col)
		return false
	if owner != c.owner:
		push_error("MatchState.place_card: instance %d belongs to player %d, not to player %d" % [
			id, c.owner, owner])
		return false
	var key := Vector2i(col, owner)
	# Already in this very zone? Its own slot is the one to free, so skip the space check.
	var already_here: bool = zones[key].find(id) >= 0
	if not already_here and not zone_has_space(col, owner):
		return false
	if already_here \
			or c.location == CardState.Location.BOARD \
			or c.location == CardState.Location.SPELL_ZONE:
		remove_from_zone(id)
	var list: Array = zones[key]
	var pos: int = list.size() if slot < 0 else mini(maxi(slot, 0), list.size())
	list.insert(pos, id)
	c.col = col
	c.location = CardState.Location.SPELL_ZONE if col == SPELL_COL else CardState.Location.BOARD
	_reindex_zone(key)
	return true


## Takes a card out of its zone, compacts the zone (later cards shift down) and clears
## its col/slot. The card's location is left untouched; a card that is not on the board
## is a no-op.
func remove_from_zone(id: int) -> void:
	var c := card(id)
	if c == null:
		return
	var key := Vector2i(c.col, c.owner)
	var list: Array = zones.get(key, [])
	var idx := list.find(id)
	if idx >= 0:
		list.remove_at(idx)
		_reindex_zone(key)
	c.col = -1
	c.slot = -1


## Puts a card in a player's hand at index 0 (newest first) and marks it as in hand.
func add_to_hand(owner: int, id: int) -> void:
	if owner < 0 or owner >= players.size():
		return
	var c := card(id)
	if c == null:
		return
	c.owner = owner
	players[owner].hand.insert(0, id)
	c.location = CardState.Location.HAND
	c.col = -1
	c.slot = -1


## Takes a card out of a player's hand. Does nothing when the card is not in it.
func remove_from_hand(owner: int, id: int) -> void:
	if owner < 0 or owner >= players.size():
		return
	var hand: Array[int] = players[owner].hand
	var idx := hand.find(id)
	if idx >= 0:
		hand.remove_at(idx)


## Moves the top card of a deck (index 0) into that player's hand; returns its instance id
## or -1 when the deck is empty.
func draw_top(owner: int) -> int:
	if owner < 0 or owner >= players.size():
		return -1
	if players[owner].deck.is_empty():
		return -1
	var id: int = players[owner].deck.pop_front()
	add_to_hand(owner, id)
	return id


## Returns the other player (0 -> 1, 1 -> 0).
func opponent(p: int) -> int:
	return 1 - p


## Returns a JSON-safe, stable Dictionary of the whole match.
## Card keys are strings, zone keys are "col:owner" and the rng is stored as strings because
## its 64-bit seed/state would lose precision as JSON floats above 2^53.
func to_dict() -> Dictionary:
	var cards_out: Dictionary = {}
	for id in cards:
		var c: CardState = cards[id]
		cards_out[str(int(id))] = c.to_dict()
	var players_out: Array = []
	for p in players:
		players_out.append(p.to_dict())
	var zones_out: Dictionary = {}
	for key in zones:
		var k: Vector2i = key
		var ids: Array = []
		var list: Array = zones[k]
		for id in list:
			ids.append(int(id))
		zones_out["%d:%d" % [k.x, k.y]] = ids
	return {
		"cards": cards_out,
		"next_instance_id": next_instance_id,
		"players": players_out,
		"turn": turn,
		"game_phase": game_phase,
		"round_phase": round_phase,
		"flip_first": flip_first,
		"lane_ids": _array_to_plain(lane_ids),
		"lane_revealed": _array_to_plain(lane_revealed),
		"noxkraya_col": noxkraya_col,
		"zones": zones_out,
		"play_order": _array_to_plain(play_order),
		"played_this_turn": _array_to_plain(played_this_turn),
		"killed": _trackers_to_plain(killed),
		"summoned": _trackers_to_plain(summoned),
		"created": _trackers_to_plain(created),
		"recalled": _trackers_to_plain(recalled),
		"discarded": _trackers_to_plain(discarded),
		"drawn": _trackers_to_plain(drawn),
		"stuns": _trackers_to_plain(stuns),
		"pending_swaps": _trackers_to_plain(pending_swaps),
		"swap_history": _trackers_to_plain(swap_history),
		"rng": {"seed": str(rng.seed), "state": str(rng.state)},
	}


## Rebuilds a full MatchState from to_dict() output, including the rng (seed first, then state).
static func from_dict(d: Dictionary) -> MatchState:
	var s := MatchState.new()
	s.next_instance_id = int(d.get("next_instance_id", 1))
	s.turn = int(d.get("turn", 0))
	s.game_phase = int(d.get("game_phase", GamePhase.GAME_START))
	s.round_phase = int(d.get("round_phase", RoundPhase.NONE))
	s.flip_first = int(d.get("flip_first", -1))
	s.noxkraya_col = int(d.get("noxkraya_col", -1))

	var lane_ids_out: Array[String] = []
	var raw_lane_ids: Array = d.get("lane_ids", [])
	for lane_id in raw_lane_ids:
		lane_ids_out.append(str(lane_id))
	s.lane_ids = lane_ids_out

	var revealed: Array[bool] = [false, false, false]
	var raw_revealed: Array = d.get("lane_revealed", [])
	for i in mini(raw_revealed.size(), COLUMNS):
		revealed[i] = bool(raw_revealed[i])
	s.lane_revealed = revealed

	var raw_players: Array = d.get("players", [])
	s.players.clear()
	for i in mini(raw_players.size(), 2):
		s.players.append(PlayerState.from_dict(raw_players[i]))
	while s.players.size() < 2:
		s.players.append(PlayerState.new())

	var cards_dict: Dictionary = d.get("cards", {})
	for key in cards_dict:
		var entry: Dictionary = cards_dict[key]
		var c := CardState.from_dict(entry)
		s.cards[int(key)] = c

	var zones_dict: Dictionary = d.get("zones", {})
	for key in zones_dict:
		var parts := str(key).split(":")
		if parts.size() != 2:
			continue
		var ids: Array[int] = []
		var raw_ids: Array = zones_dict[key]
		for id in raw_ids:
			ids.append(int(id))
		s.zones[Vector2i(int(parts[0]), int(parts[1]))] = ids
	s._ensure_zones()

	s.play_order = _to_int_array(d.get("play_order", []))
	s.played_this_turn = _to_int_array(d.get("played_this_turn", []))
	s.killed = _to_tracker_array(d.get("killed", []))
	s.summoned = _to_tracker_array(d.get("summoned", []))
	s.created = _to_tracker_array(d.get("created", []))
	s.recalled = _to_tracker_array(d.get("recalled", []))
	s.discarded = _to_tracker_array(d.get("discarded", []))
	s.drawn = _to_tracker_array(d.get("drawn", []))
	s.stuns = _to_tracker_array(d.get("stuns", []))
	s.pending_swaps = _to_tracker_array(d.get("pending_swaps", []))
	s.swap_history = _to_tracker_array(d.get("swap_history", []))

	# The rng seed and state are 64-bit; they are stored as Strings to survive JSON.
	# The seed must be set before the state or the state is overwritten.
	var rng_dict: Dictionary = d.get("rng", {})
	if rng_dict.has("seed"):
		s.rng.seed = _as_int(rng_dict["seed"])
	if rng_dict.has("state"):
		s.rng.state = _as_int(rng_dict["state"])
	return s


## Returns a stable hash of the serialized state, for desync detection.
func checksum() -> int:
	return hash(JSON.stringify(to_dict(), "", true))


## Creates every zone that does not exist yet (3 columns x 2 owners + 1 spell zone per owner).
func _ensure_zones() -> void:
	for p in players.size():
		for col in COLUMNS:
			var key := Vector2i(col, p)
			if not zones.has(key):
				var empty: Array[int] = []
				zones[key] = empty
		var spell_key := Vector2i(SPELL_COL, p)
		if not zones.has(spell_key):
			var empty_spell: Array[int] = []
			zones[spell_key] = empty_spell


## Returns true when col is a lane column (0..COLUMNS-1) or the spell column.
func _is_valid_col(col: int) -> bool:
	return col == SPELL_COL or (col >= 0 and col < COLUMNS)


## Re-syncs col/slot of every card in a zone so that card.slot == its index in the zone.
func _reindex_zone(key: Vector2i) -> void:
	var list: Array = zones.get(key, [])
	for i in list.size():
		var c := card(int(list[i]))
		if c == null:
			continue
		c.col = key.x
		c.slot = i


## Copies a (possibly typed) array into a plain Array of the same values.
func _array_to_plain(src: Array) -> Array:
	var out: Array = []
	for v in src:
		out.append(v)
	return out


## Copies tracker dictionaries, stripping anything JSON cannot represent (e.g. Vector2i).
func _trackers_to_plain(src: Array[Dictionary]) -> Array:
	var out: Array = []
	for entry in src:
		var copy: Dictionary = {}
		for k in entry:
			copy[k] = _json_safe(entry[k])
		out.append(copy)
	return out


## Converts a value into something JSON.stringify can write: Vector2i becomes [x, y],
## everything else is passed through unchanged.
func _json_safe(v: Variant) -> Variant:
	if v is Vector2i:
		return [v.x, v.y]
	return v


## Reads a value that may be an int, a JSON float or a String of digits back into an int.
static func _as_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	var text := str(v)
	if text.contains("."):
		return int(float(text))
	return int(text)


## Rebuilds an Array[int] from a serialized array.
static func _to_int_array(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if not (raw is Array):
		return out
	for v in (raw as Array):
		out.append(int(v))
	return out


## Rebuilds an Array[Dictionary] from serialized tracker entries. JSON turns every number
## into a float, so the known numeric keys (see TRACKER_INT_KEYS) and any nested numbers are
## converted back to ints; this keeps to_dict() byte-identical across a JSON round trip.
static func _to_tracker_array(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out
	for v in (raw as Array):
		var entry: Dictionary = v as Dictionary
		var copy: Dictionary = {}
		for k in entry:
			copy[k] = _restore_value(entry[k])
		for k in TRACKER_INT_KEYS:
			if copy.has(k) and (copy[k] is int or copy[k] is float):
				copy[k] = int(copy[k])
		out.append(copy)
	return out


## Restores a JSON value to its natural GDScript type: numbers to int, arrays/dictionaries
## recursively, everything else unchanged.
static func _restore_value(v: Variant) -> Variant:
	if v is int or v is float:
		return int(v)
	if v is Array:
		var out: Array = []
		for item in v:
			out.append(_restore_value(item))
		return out
	if v is Dictionary:
		var out_dict: Dictionary = {}
		for k in v:
			out_dict[k] = _restore_value(v[k])
		return out_dict
	return v
