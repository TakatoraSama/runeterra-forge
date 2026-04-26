extends NinePatchRect

const MARGIN_H := 12.0
const MARGIN_V := 8.0

func _ready() -> void:
	# NinePatchRect is not a container, so it won't auto-size to children.
	# Report the HBoxContainer's minimum size + margins as our own so the
	# parent KeywordContainer allocates the correct width for this badge.
	custom_minimum_size = $HBoxContainer.get_minimum_size() + Vector2(MARGIN_H * 2, MARGIN_V * 2)
