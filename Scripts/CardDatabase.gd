class_name CardDatabase

const CARDS = {
	# Champions - Azir Line
	"Azir1": {
		"Name": "Azir",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Azir1.webp",
		"Level": 1,
		"Cost": 6,
		"Power": 5,
		"Keyword": [],
		"Skill": "{Game Start}: Summon a [Buried Sun Disc] at mid lane.",
		"LevelUp": "You've summoned {ally_threshold}+ allies or landmarks.",
		"LevelUpTo": "Azir2",
		"AbilityType": "summon_sun_disc",
		"BalanceValues": {"ally_threshold": 6},
		"PreviewTooltip": ["Azir1", "Azir2", "Azir3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Azir2": {
		"Name": "Azir",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Azir2.webp",
		"Level": 2,
		"Cost": 6,
		"Power": 6,
		"Keyword": [],
		"Skill": "{Aura}: Your other Ascended allies in play have +{aura_power} Power.",
		"LevelUp": "You've {restored the Sun Disc}.",
		"LevelUpTo": "Azir3",
		"AbilityType": "aura_ascended_buff",
		"BalanceValues": {"aura_power": 2},
		"PreviewTooltip": ["Azir1", "Azir2", "Azir3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Azir3": {
		"Name": "Azir",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Azir3.webp",
		"Level": 3,
		"Cost": 6,
		"Power": 8,
		"Keyword": ["Barrier"],
		"Skill": "{Aura}: Your other Ascended allies in play have +{aura_power} Power and their {Game End} skill activate twice.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "aura_ascended_buff",
		"BalanceValues": {"aura_power": 2},
		"PreviewTooltip": ["Azir1", "Azir2", "Azir3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	
	# Champions - Renekton Line
	"Renekton1": {
		"Name": "Renekton",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Renekton1.webp",
		"Level": 1,
		"Cost": 3,
		"Power": 4,
		"Keyword": ["Challenger"],
		"Skill": "{Round Start}: Grant me +{win_power} Power if you're winning here.",
		"LevelUp": "I've increased my Power by {power_threshold}+.",
		"LevelUpTo": "Renekton2",
		"AbilityType": "conditional_buff",
		"BalanceValues": {"win_power": 2, "power_threshold": 4},
		"PreviewTooltip": ["Renekton1", "Renekton2", "Renekton3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Renekton2": {
		"Name": "Renekton",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Renekton2.webp",
		"Level": 2,
		"Cost": 3,
		"Power": 5,
		"Keyword": ["Challenger"],
		"Skill": "{Round Start}: Grant me +{win_power} Power if you're winning here.",
		"LevelUp": "You've {restored the Sun Disc}.",
		"LevelUpTo": "Renekton3",
		"AbilityType": "conditional_buff",
		"BalanceValues": {"win_power": 3},
		"PreviewTooltip": ["Renekton1", "Renekton2", "Renekton3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Renekton3": {
		"Name": "Renekton",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Renekton3.webp",
		"Level": 3,
		"Cost": 3,
		"Power": 10,
		"Keyword": ["Challenger"],
		"Skill": "{Round Start}: Grant me +{win_power} Power if you're winning here. [br] {Game End}: Grant an enemy here -{enemy_debuff} Power",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "conditional_buff",
		"BalanceValues": {"win_power": 3, "enemy_debuff": 3},
		"PreviewTooltip": ["Renekton1", "Renekton2", "Renekton3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	
	# Champions - Nasus Line
	"Nasus1": {
		"Name": "Nasus",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Nasus1.webp",
		"Level": 1,
		"Cost": 2,
		"Power": 2,
		"Keyword": [],
		"Skill": "{Round End}: Kills the weakest ally here and grant me +{kill_power} Power.",
		"LevelUp": "You've killed {kill_threshold}+ units.",
		"LevelUpTo": "Nasus2",
		"AbilityType": "kill_ally_buff",
		"BalanceValues": {"kill_power": 2, "kill_threshold": 2},
		"PreviewTooltip": ["Nasus1", "Nasus2", "Nasus3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Nasus2": {
		"Name": "Nasus",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Nasus2.webp",
		"Level": 2,
		"Cost": 2,
		"Power": 3,
		"Keyword": ["Fearsome"],
		"Skill": "{Round End}: Kills the weakest ally here and grant me +{kill_power} Power.",
		"LevelUp": "You've {restored the Sun Disc}.",
		"LevelUpTo": "Nasus3",
		"AbilityType": "kill_ally_buff",
		"BalanceValues": {"kill_power": 3},
		"PreviewTooltip": ["Nasus1", "Nasus2", "Nasus3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Nasus3": {
		"Name": "Nasus",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Nasus3.webp",
		"Level": 3,
		"Cost": 2,
		"Power": 10,
		"Keyword": ["Fearsome"],
		"Skill": "{Round End}: Kills the weakest ally here and grant me +{kill_power} Power. [br] {Game End}: Kill an enemy here that has less power than me.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "kill_ally_buff",
		"BalanceValues": {"kill_power": 3},
		"PreviewTooltip": ["Nasus1", "Nasus2", "Nasus3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	
	# Champions - Xerath Line
	"Xerath1": {
		"Name": "Xerath",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Xerath1.webp",
		"Level": 1,
		"Cost": 4,
		"Power": 3,
		"Keyword": [],
		"Skill": "{Play}: Drain {drain_power} Power from other units here.",
		"LevelUp": "I've seen {ally_threshold}+ allies in play with increased power.",
		"LevelUpTo": "Xerath2",
		"AbilityType": "drain_power",
		"BalanceValues": {"drain_power": 2, "ally_threshold": 4},
		"PreviewTooltip": ["Xerath1", "Xerath2", "Xerath3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Xerath2": {
		"Name": "Xerath",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Xerath2.webp",
		"Level": 2,
		"Cost": 4,
		"Power": 4,
		"Keyword": [],
		"Skill": "{Aura}: Back-row enemies here have -{aura_debuff} Power.",
		"LevelUp": "You've {restored the Sun Disc}.",
		"LevelUpTo": "Xerath3",
		"AbilityType": "aura_debuff",
		"BalanceValues": {"aura_debuff": 1},
		"PreviewTooltip": ["Xerath1", "Xerath2", "Xerath3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	"Xerath3": {
		"Name": "Xerath",
		"Region": ["Shurima"],
		"Type": "Champion",
		"SubType": "Ascended",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Xerath3.webp",
		"Level": 3,
		"Cost": 4,
		"Power": 7,
		"Keyword": ["Barrier"],
		"Skill": "{Aura}: Back-row enemies have -{aura_debuff} Power. [br] {Game End}: Grant me the Power of front-row enemies here.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "aura_debuff",
		"BalanceValues": {"aura_debuff": 1},
		"PreviewTooltip": ["Xerath1", "Xerath2", "Xerath3", "BuriedSunDisc", "RestoredSunDisc"]
	},
	
	# Champions - Tryndamere Line
	"Tryndamere1": {
		"Name": "Tryndamere",
		"Region": ["Freljord"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Tryndamere1.webp",
		"Level": 1,
		"Cost": 2,
		"Power": 3,
		"Keyword": [],
		"Skill": "",
		"LevelUp": "If I would die, I Level Up instead.",
		"LevelUpTo": "Tryndamere2",
		"AbilityType": "levelup_on_death",
		"PreviewTooltip": ["Tryndamere1", "Tryndamere2"]
	},
	"Tryndamere2": {
		"Name": "Tryndamere",
		"Region": ["Freljord"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Tryndamere2.webp",
		"Level": 2,
		"Cost": 2,
		"Power": 4,
		"Keyword": ["Fearsome", "Tough"],
		"Skill": "If I would die, grant me +{survive_power} Power instead.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "survive_death",
		"BalanceValues": {"survive_power": 2},
		"PreviewTooltip": ["Tryndamere1", "Tryndamere2"]
	},
	
	# Champions - Trundle Line
	"Trundle1": {
		"Name": "Trundle",
		"Region": ["Freljord"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Trundle1.webp",
		"Level": 1,
		"Cost": 3,
		"Power": 3,
		"Keyword": [],
		"Skill": "{Play}: Create an [Ice Pillar] in hand.",
		"LevelUp": "You've played an [Ice Pillar].",
		"LevelUpTo": "Trundle2",
		"AbilityType": "create_card",
		"PreviewTooltip": ["Trundle1", "Trundle2", "IcePillar"]
	},
	"Trundle2": {
		"Name": "Trundle",
		"Region": ["Freljord"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Trundle2.webp",
		"Level": 2,
		"Cost": 3,
		"Power": 4,
		"Keyword": ["Regeneration"],
		"Skill": "{Game End}: Grant me +{behold_power} Power for each {mana_threshold}+ cost unit you behold.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "conditional_buff",
		"BalanceValues": {"behold_power": 2, "mana_threshold": 5},
		"PreviewTooltip": ["Trundle1", "Trundle2", "IcePillar"]
	},

	# Champions - Ahri line
	"Ahri1": {
		"Name": "Ahri",
		"Region": ["Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Ahri1.webp",
		"Level": 1,
		"Cost": 1,
		"Power": 2,
		"Keyword": ["Elusive"],
		"Skill": "Each round, when I {swap lane}, {recall} the weakest ally here.",
		"LevelUp": "I've recalled {recall_threshold}+ allies.",
		"LevelUpTo": "Ahri2",
		"AbilityType": "swap_arrive_recall",
		"BalanceValues": {"recall_threshold": 3},
		"PreviewTooltip": ["Ahri1", "Ahri2"]
	},
	"Ahri2": {
		"Name": "Ahri",
		"Region": ["Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Ahri2.webp",
		"Level": 2,
		"Cost": 1,
		"Power": 3,
		"Keyword": ["Elusive"],
		"Skill": "Each round, when I {swap lane}, {recall} the weakest ally here and reduce its cost by {recall_cost_reduction}.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "swap_arrive_recall",
		"BalanceValues": {"recall_cost_reduction": 1},
		"PreviewTooltip": ["Ahri1", "Ahri2"]
	},

	# Champions - Kennen line
	"Kennen1": {
		"Name": "Kennen",
		"Region": ["Bandle City","Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Kennen1.webp",
		"Level": 1,
		"Cost": 1,
		"Power": 1,
		"Keyword": [],
		"Skill": "{Play}: {Stun} an enemy here.",
		"LevelUp": "You've sumomoned the same ally {summon_threshold}+ times.",
		"LevelUpTo": "Kennen2",
		"AbilityType": "",
		"BalanceValues": {"summon_threshold": 3},
		"PreviewTooltip": ["Kennen1", "Kennen2"]
	},
	"Kennen2": {
		"Name": "Kennen",
		"Region": ["Bandle City","Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Kennen2.webp",
		"Level": 2,
		"Cost": 1,
		"Power": 2,
		"Keyword": [],
		"Skill": "{Play}: {Stun} an enemy here and grant it -{power_decrease} Power.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "",
		"BalanceValues": {"power_decrease": 1},
		"PreviewTooltip": ["Kennen1", "Kennen2"]
	},

	# Champions - Irelia line
	"Irelia1": {
		"Name": "Irelia",
		"Region": ["Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Irelia1.webp",
		"Level": 1,
		"Cost": 2,
		"Power": 2,
		"Keyword": [],
		"Skill": "When I {swap lane}, summon a [Blade] at the original lane.",
		"LevelUp": "You've summoned {ally_threshold}+ allies.",
		"LevelUpTo": "Irelia2",
		"AbilityType": "",
		"BalanceValues": {"ally_threshold": 6},
		"PreviewTooltip": ["Irelia1", "Irelia2", "Blade"]
	},
	"Irelia2": {
		"Name": "Irelia",
		"Region": ["Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Irelia2.webp",
		"Level": 2,
		"Cost": 2,
		"Power": 3,
		"Keyword": [],
		"Skill": "When I {swap lane}, summon a [Blade] at the original lane. [br] Aura: 1 cost allies have +1 Power.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "",
		"BalanceValues": {"ally_threshold": 6},
		"PreviewTooltip": ["Irelia1", "Irelia2", "Blade"]
	},

	# Champions - Sion line
	"Sion1": {
		"Name": "Sion",
		"Region": ["Noxus"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Sion1.webp",
		"Level": 1,
		"Cost": 6,
		"Power": 8,
		"Keyword": [],
		"Skill": "When I'm discarded, grant another ally in hand +2 Power.",
		"LevelUp": "You've discarded or summoned {power_threshold}+ Power.",
		"LevelUpTo": "Sion2",
		"AbilityType": "",
		"BalanceValues": {"power_threshold": 32},
		"PreviewTooltip": ["Sion1", "Sion2"]
	},
	"Sion2": {
		"Name": "Sion",
		"Region": ["Noxus"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Sion2.webp",
		"Level": 2,
		"Cost": 6,
		"Power": 9,
		"Keyword": [],
		"Skill": "I have +{power_increase} Power for each card you've discarded this game. [br]",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "",
		"BalanceValues": {"power_increase": 1},
		"PreviewTooltip": ["Sion1", "Sion2"]
	},
	
	# Landmarks
	"BuriedSunDisc": {
		"Name": "Buried Sun Disc",
		"Region": ["Shurima"],
		"Type": "Landmark",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/BuriedSunDisc.webp",
		"Cost": 0,
		"Keyword": [],
		"Skill": "Once you have {ascended_threshold}+ level 2 Ascended allies in play, {restore the Sun Disc}.",
		"LevelUpTo": "RestoredSunDisc",
		"AbilityType": "transform_landmark",
		"BalanceValues": {"ascended_threshold": 2},
		"PreviewTooltip": ["BuriedSunDisc", "RestoredSunDisc"]
	},
	"RestoredSunDisc": {
		"Name": "Restored Sun Disc",
		"Region": ["Shurima"],
		"Type": "Landmark",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/RestoredSunDisc.webp",
		"Cost": 0,
		"Keyword": [],
		"Skill": "Draw {draw_count} for each Ascended ally that is not beheld. [br] For the rest of the game, your level 2 Ascended allies are level 3.",
		"LevelUpTo": null,
		"AbilityType": "ascend_champions",
		"BalanceValues": {"draw_count": 1},
		"PreviewTooltip": ["BuriedSunDisc", "RestoredSunDisc"]
	},
	
	# Followers
	"IcePillar": {
		"Name": "Ice Pillar",
		"Region": ["Freljord"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/IcePillar.webp",
		"Cost": 5,
		"Power": 5,
		"Keyword": ["Regeneration"],
		"Skill": "{Play}: Next turn, you get +{mana_bonus} mana.",
		"AbilityType": "mana_ramp",
		"BalanceValues": {"mana_bonus": 5},
		"PreviewTooltip": ["Trundle1", "Trundle2", "IcePillar"]
	},
	"Chip": {
		"Name": "Chip",
		"Region": ["Targon"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Chip.webp",
		"Cost": 1,
		"Power": 1,
		"Keyword": [],
		"Skill": '"Snow on my feat! Rain on my head!"',
		"AbilityType": "none",
		"BalanceValues": {},
		"PreviewTooltip": ["Chip"]
	},
	"Blade": {
		"Name": "Blade",
		"Region": ["Ionia"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Blade.webp",
		"Cost": 1,
		"Power": 1,
		"Keyword": [],
		"Skill": "{Aura}: Other allied [Blades] have +{aura_power} Power.",
		"AbilityType": "none",
		"BalanceValues": {"aura_power": 1},
		"PreviewTooltip": ["Irelia1", "Irelia2", "Blade"]
	},
}


static func populate_card_visuals(card: Node, card_data: Dictionary, source_card: Node = null) -> void:
	"""Populate all visual text and sprite nodes on a card from card_data.
	Single source of truth for card display — replaces duplicated setup blocks
	that previously appeared in Deck.gd, CardManager.gd, and Card.gd."""
	var name_label = card.get_node_or_null("CardFront/TextContainer/CardName")
	if name_label:
		name_label.text = str(card_data.get("Name", ""))

	var cost_label = card.get_node_or_null("CardFront/Cost")
	if cost_label:
		cost_label.text = str(card_data.get("Cost", 0))

	apply_power_visual(card, card_data, source_card)

	var skill_label = card.get_node_or_null("CardFront/TextContainer/Skill")
	var skill_text: String = str(card_data.get("Skill", ""))
	if skill_label && skill_text != "":
		skill_label.visible = true
		skill_label.text = format_card_text(skill_text, card_data.get("BalanceValues", {}))
	else:
		skill_label.visible = false

	var level_up_raw = card_data.get("LevelUp", null)
	var level_up_text: String = str(level_up_raw) if level_up_raw != null else ""
	var has_level_up := level_up_raw != null and level_up_text != ""
	var lv_label = card.get_node_or_null("CardFront/TextContainer/LevelUp")
	var lv_sep = card.get_node_or_null("CardFront/TextContainer/LevelSeperator")
	if lv_label:
		lv_label.text = format_card_text(level_up_text, card_data.get("BalanceValues", {})) if has_level_up else ""
		lv_label.visible = has_level_up
	if lv_sep:
		lv_sep.visible = has_level_up

	var sprite_path: String = str(card_data.get("Sprite", ""))
	if sprite_path != "":
		var sprite_node = card.get_node_or_null("CardFront/CardSpriteParent/CardSprite")
		if sprite_node:
			sprite_node.texture = ResourceLoader.load(sprite_path)

	var sub_type: String = str(card_data.get("SubType", ""))
	var has_sub_type := sub_type != ""
	var sub_label = card.get_node_or_null("CardFront/SubType")
	var sub_bg = card.get_node_or_null("CardFront/CardSubType")
	if sub_label:
		if has_sub_type:
			sub_label.text = sub_type.to_upper()
		sub_label.visible = has_sub_type
	if sub_bg:
		sub_bg.visible = has_sub_type

	var region: Array = card_data.get("Region", [])
	var region_sprite_node_1 = card.get_node_or_null("CardFront/TextContainer/RegionContainer/Region1")
	var region_sprite_node_2 = card.get_node_or_null("CardFront/TextContainer/RegionContainer/Region2")
	
	region_sprite_node_1.texture = ResourceLoader.load("res://Assets/RegionSprites/" + (region[0].replace(" ", "")) + ".webp")
	if region.size() > 1 and region_sprite_node_2:
		region_sprite_node_2.texture = ResourceLoader.load("res://Assets/RegionSprites/" + (region[1].replace(" ", "")) + ".webp")
	else:
		region_sprite_node_2.visible = false

	var keywords: Array = card_data.get("Keyword", [])
	var keyword_container = card.get_node_or_null("CardFront/TextContainer/KeywordContainer")
	var keyword_item_scene = preload("res://Scenes/KeywordItem.tscn")

	if keyword_container:
		for child in keyword_container.get_children():
			child.queue_free()
	if keywords.size() > 0:
		keyword_container.visible = true
		for keyword in keywords:
			var item = keyword_item_scene.instantiate()
			var keyword_sprite_path = "res://Assets/KeywordSprites/" + str(keyword) + ".webp"
			item.get_node("KeywordSprite").texture = ResourceLoader.load(keyword_sprite_path)
			keyword_container.add_child(item)
	else:
		keyword_container.visible = false


static func format_card_text(text: String, balance_values: Dictionary = {}) -> String:
	"""Replace {..} with gold (substituting balance_values if key matches) and [..] with blue,
	while preserving real BBCode tags (e.g. [br])."""
	var result := ""
	var i := 0

	while i < text.length():
		var c := text[i]

		if c == "[":
			var close_idx := text.find("]", i + 1)
			if close_idx != -1:
				var content := text.substr(i + 1, close_idx - i - 1)
				if _is_bbcode_tag(content):
					result += text.substr(i, close_idx - i + 1)
				else:
					result += "[color=#54a5ff]" + content + "[/color]"
				i = close_idx + 1
				continue

		if c == "{":
			var close_idx := text.find("}", i + 1)
			if close_idx != -1:
				var content := text.substr(i + 1, close_idx - i - 1)
				if balance_values.has(content):
					result += str(balance_values[content])
				else:
					result += "[color=#ffca4b]" + content + "[/color]"
				i = close_idx + 1
				continue

		result += c
		i += 1

	return result


static func _is_bbcode_tag(content: String) -> bool:
	var tag := content.strip_edges()
	if tag == "":
		return false

	if tag.begins_with("/"):
		tag = tag.substr(1)

	var eq_idx := tag.find("=")
	if eq_idx != -1:
		tag = tag.substr(0, eq_idx)

	tag = tag.to_lower()
	var known_tags := {
		"b": true,
		"i": true,
		"u": true,
		"s": true,
		"code": true,
		"p": true,
		"center": true,
		"left": true,
		"right": true,
		"fill": true,
		"indent": true,
		"url": true,
		"img": true,
		"font": true,
		"font_size": true,
		"color": true,
		"bgcolor": true,
		"outline_size": true,
		"outline_color": true,
		"table": true,
		"cell": true,
		"ul": true,
		"ol": true,
		"li": true,
		"hint": true,
		"dropcap": true,
		"opentype_features": true,
		"lang": true,
		"br": true,
		"lb": true,
		"rb": true
	}

	return known_tags.has(tag)


static func get_card_id_by_name(card_name: String, prefer_collectible: bool = false) -> String:
	"""Find the first card ID matching the given name.
	If prefer_collectible is true, prioritise Collectible entries."""
	var fallback := ""
	for id in CARDS:
		if CARDS[id].get("Name", "") == card_name:
			if prefer_collectible and CARDS[id].get("Collectible", false):
				return id
			if fallback == "":
				fallback = id
	return fallback


static func apply_power_visual(card_node: Node, card_data: Dictionary, source_card: Node = null) -> void:
	"""Apply power text/icon UI rules.
	Landmark cards hide both the Power label and the CardPower sprite."""
	if card_node == null:
		return

	var power_label = card_node.get_node_or_null("CardFront/Power")
	var power_sprite = card_node.get_node_or_null("CardFront/CardPower")
	var is_landmark := str(card_data.get("Type", "")) == "Landmark"
	var should_show_power := (not is_landmark) and card_data.has("Power")

	if power_label:
		power_label.visible = should_show_power
		if should_show_power:
			if source_card and source_card.has_method("get_power_display_text_for_base"):
				power_label.text = source_card.get_power_display_text_for_base(int(card_data.get("Power", 0)))
			else:
				power_label.text = str(card_data.get("Power", 0))
		else:
			power_label.text = ""

	if power_sprite:
		power_sprite.visible = should_show_power
