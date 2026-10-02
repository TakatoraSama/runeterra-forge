extends Node2D

# View-only deck stack. The Match engine owns the deck; the presenter drives the
# visible count through set_view_count(). The deck ids live in MatchDecks
# (DEFAULT_DECK_IDS / sanitize). DEFAULT_DECK below is kept as plain data: it is
# the table Tests/test_match_decks.gd pins MatchDecks.DEFAULT_DECK_IDS against.

## Fallback deck ids, in deck order. Copied into MatchDecks.DEFAULT_DECK_IDS.
const DEFAULT_DECK := [
	{"id": "Azir1", "cost_mod": 0},
	{"id": "Renekton1", "cost_mod": 0},
	{"id": "Nasus1", "cost_mod": 0},
	{"id": "Xerath1", "cost_mod": 0},
	{"id": "Tryndamere1", "cost_mod": 0},
	{"id": "Ahri1", "cost_mod": 0},
	{"id": "Kennen1", "cost_mod": 0},
	{"id": "NavoriConspirator", "cost_mod": 0},
	{"id": "Janna1", "cost_mod": 0},
	{"id": "Draven1", "cost_mod": 0},
	{"id": "Rumble1", "cost_mod": 0},
	{"id": "Sion1", "cost_mod": 0},
]

func set_view_count(n: int) -> void:
	"""View-only deck count update (used by the presenter in engine mode).
	At 0 the whole stack is hidden."""
	$RichTextLabel.text = str(n)
	var hide := n <= 0
	var collider := $Area2D/CollisionShape2D
	collider.disabled = hide
	$Sprite2D.visible = not hide
	$RichTextLabel.visible = not hide

