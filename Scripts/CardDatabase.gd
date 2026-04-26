class_name CardDatabase

const CARD_SCENE = preload("res://Scenes/Card.tscn")
const CARD_SPELL_SCENE = preload("res://Scenes/CardSpell.tscn")
const CARD_LANDMARK_SCENE = preload("res://Scenes/CardLandmark.tscn")

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
		"Keyword": ["Regeneration"],
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
		"Skill": "Each round, when I {swap} lane, {recall} the weakest ally here.",
		"LevelUp": "I've {recalled} {recall_threshold}+ allies.",
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
		"Skill": "Each round, when I {swap} lane, {recall} the weakest ally here and reduce its cost by {recall_cost_reduction}.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "swap_arrive_recall",
		"BalanceValues": {"recall_cost_reduction": 1},
		"PreviewTooltip": ["Ahri1", "Ahri2"]
	},

	# Champions - Kennen line
	"Kennen1": {
		"Name": "Kennen",
		"Region": ["Bandle City", "Ionia"],
		"Type": "Champion",
		"SubType": "Yordle",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Kennen1.webp",
		"Level": 1,
		"Cost": 1,
		"Power": 1,
		"Keyword": [],
		"Skill": "{Play}: :Stun:{Stun} an enemy here.",
		"LevelUp": "You've sumomoned the same ally {summon_threshold}+ times.",
		"LevelUpTo": "Kennen2",
		"AbilityType": "stun_enemy",
		"BalanceValues": {"summon_threshold": 3},
		"PreviewTooltip": ["Kennen1", "Kennen2"]
	},
	"Kennen2": {
		"Name": "Kennen",
		"Region": ["Bandle City", "Ionia"],
		"Type": "Champion",
		"SubType": "Yordle",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Kennen2.webp",
		"Level": 2,
		"Cost": 1,
		"Power": 2,
		"Keyword": [],
		"Skill": "{Play}: :Stun:{Stun} an enemy here and grant it -{power_decrease} Power.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "stun_enemy",
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
		"Cost": 3,
		"Power": 1,
		"Keyword": ["Elusive"],
		"Skill": "When I {swap} lane, summon a [Blade] at the original lane.",
		"LevelUp": "You've summoned {ally_threshold}+ allies.",
		"LevelUpTo": "Irelia2",
		"AbilityType": "swap_arrive_summon_blade",
		"BalanceValues": {"ally_threshold": 7},
		"PreviewTooltip": ["Irelia1", "Irelia2", "Blade"]
	},
	"Irelia2": {
		"Name": "Irelia",
		"Region": ["Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Irelia2.webp",
		"Level": 2,
		"Cost": 3,
		"Power": 2,
		"Keyword": ["Elusive"],
		"Skill": "When I {swap} lane, summon a [Blade] at the original lane. [br] {Aura}: 1 cost allies have +{power_increase} Power.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "swap_arrive_summon_blade",
		"BalanceValues": {"power_increase": 1},
		"PreviewTooltip": ["Irelia1", "Irelia2", "Blade"]
	},

	# Champions - Rumble
	"Rumble1": {
		"Name": "Rumble",
		"Region": ["Bandle City", "Noxus"],
		"Type": "Champion",
		"SubType": "Yordle",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Rumble1.webp",
		"Level": 1,
		"Cost": 4,
		"Power": 3,
		"Keyword": [],
		"Skill": "{Play}: Discard a 2 or less, 3-4, and 5+ cost card to grant me +2 Power for each card discarded.",
		"LevelUp": "You've discarded {discard_threshold}+ times.",
		"LevelUpTo": "Rumble2",
		"AbilityType": "discard_by_cost_bracket",
		"BalanceValues": {"discard_threshold": 4},
		"PreviewTooltip": ["Rumble1", "Rumble2"]
	},
	"Rumble2": {
		"Name": "Rumble",
		"Region": ["Bandle City", "Noxus"],
		"Type": "Champion",
		"SubType": "Yordle",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Rumble2.webp",
		"Level": 2,
		"Cost": 4,
		"Power": 4,
		"Keyword": [],
		"Skill": "When I level up, for each of your discarded cards, create a random card with a cost equal to the discarded card's cost, reduce its cost by 1 and grant it :Augment:{Augment}.",
		"LevelUp": "",
		"LevelUpTo": "Rumble2",
		"AbilityType": "level_up_create_from_discards",
		"BalanceValues": {},
		"PreviewTooltip": ["Rumble1", "Rumble2"]
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
		"Skill": "When I'm discarded, grant another ally in hand +{power_buff} Power and create a copy of me in your hand.",
		"LevelUp": "You've discarded or summoned {power_threshold}+ Power.",
		"LevelUpTo": "Sion2",
		"AbilityType": "on_discard_buff_create",
		"BalanceValues": {"power_buff": 2, "power_threshold": 32},
		"PreviewTooltip": ["Sion1", "Sion2", "SionReturned"]
	},
	"Sion2": {
		"Name": "Sion",
		"Region": ["Noxus"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Sion2.webp",
		"Level": 2,
		"Cost": 6,
		"Power": 10,
		"Keyword": [],
		"Skill": "{Last Breath}: Create [Sion Returned] in your hand. [br] {Game End}: If I'm in your hand, summon me to the highest power lane where you're losing.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "last_breath_create",
		"HandAbilityType": "game_end_summon_from_hand",
		"BalanceValues": {},
		"PreviewTooltip": ["Sion1", "Sion2", "SionReturned"]
	},
	"SionReturned": {
		"Name": "Sion Returned",
		"Region": ["Noxus"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/SionReturned.webp",
		"Level": 1,
		"Cost": 6,
		"Power": 10,
		"Keyword": [],
		"Skill": "{Game End}: If I'm in your hand, summon me to the highest power lane where you're losing.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "game_end_summon_from_hand",
		"BalanceValues": {},
		"PreviewTooltip": ["Sion1", "Sion2", "SionReturned"]
	},

	# Champions - Nautilus line
	"Nautilus1": {
		"Name": "Nautilus",
		"Region": ["Bilgewater"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Nautilus1.webp",
		"Level": 1,
		"Cost": 5,
		"Power": 0,
		"Keyword": ["Fearsome", "Tough"],
		"Skill": "",
		"LevelUp": "When you are :Deep:{Deep}. When I level up, create 3 random {created_cost}+ cost sea monsters in your hand.",
		"LevelUpTo": "Nautilus2",
		"AbilityType": "",
		"BalanceValues": {"created_cost": 3},
		"PreviewTooltip": ["Nautilus1", "Nautilus2"]
	},
	"Nautilus2": {
		"Name": "Nautilus",
		"Region": ["Bilgewater"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Nautilus2.webp",
		"Level": 2,
		"Cost": 5,
		"Power": 13,
		"Keyword": ["Fearsome", "Tough"],
		"Skill": "{Aura}: Sea Monsters allies cost {cost_reduction} less.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "",
		"BalanceValues": {"cost_reduction": 3},
		"PreviewTooltip": ["Nautilus1", "Nautilus2"]
	},

	# Champions - Janna line
	"Janna1": {
		"Name": "Janna",
		"Region": ["Piltover Zaun"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Janna1.webp",
		"Level": 1,
		"Cost": 1,
		"Power": 2,
		"Keyword": [],
		"Skill": "{Play}: {Updraft} {updraft_threshold} to draw that much at the next {Round Start}.",
		"LevelUp": "You've drawn {draw_threshold}+ cards.",
		"LevelUpTo": "Janna2",
		"AbilityType": "",
		"BalanceValues": {"updraft_threshold": 2, "draw_threshold": 12},
		"PreviewTooltip": ["Janna1", "Janna2"]
	},
	"Janna2": {
		"Name": "Janna",
		"Region": ["Piltover Zaun"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Janna2.webp",
		"Level": 2,
		"Cost": 1,
		"Power": 3,
		"Keyword": ["Elusive"],
		"Skill": "{Play} or {Round Start}: Draw {draw_threshold}. [br] When you draw a card, reduce its cost by {cost_reduction}.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"updraft_threshold": 2, "draw_threshold": 1, "cost_reduction": 1},
		"PreviewTooltip": ["Janna1", "Janna2"]
	},

	# Champion - Mordekaiser line
	"Mordekaiser1": {
		"Name": "Mordekaiser",
		"Region": ["Noxus", "Shadow Isles"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Mordekaiser1.webp",
		"Level": 1,
		"Cost": 5,
		"Power": 8,
		"Keyword": ["Challenger"],
		"Skill": "{Play}: Kill 2 allies here. [br] When another ally dies, revive it.",
		"LevelUp": "{killed_threshold}+ allies have died. Allies with 5+ Power count twice.",
		"LevelUpTo": "Mordekaiser2",
		"AbilityType": "",
		"BalanceValues": {"killed_threshold": 8},
		"PreviewTooltip": ["Mordekaiser1", "Mordekaiser2"]
	},
	"Mordekaiser2": {
		"Name": "Mordekaiser",
		"Region": ["Noxus", "Shadow Isles"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Mordekaiser2.webp",
		"Level": 2,
		"Cost": 5,
		"Power": 9,
		"Keyword": ["Challenger"],
		"Skill": "When another ally dies, revive it. [br] {Round End}: Kill other units here, remaining only me and the weakest enemy.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"revive_buff": 2},
		"PreviewTooltip": ["Mordekaiser1", "Mordekaiser2"]
	},

	# Champion - Viktor line
	"Viktor1": {
		"Name": "Viktor",
		"Region": ["Piltover Zaun"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Viktor1.webp",
		"Level": 1,
		"Cost": 2,
		"Power": 3,
		"Keyword": ["Augment"],
		"Skill": "{Play} or {Round Start}: Create a [Hex Core Upgrade] in your hand if you don't have one.",
		"LevelUp": "You've played {card_threshold}+ created cards.",
		"LevelUpTo": "Viktor2",
		"AbilityType": "",
		"BalanceValues": {"card_threshold": 4},
		"PreviewTooltip": ["Viktor1", "Viktor2", "HexCoreUpgrade"]
	},
	"Viktor2": {
		"Name": "Viktor",
		"Region": ["Piltover Zaun"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Viktor2.webp",
		"Level": 2,
		"Cost": 2,
		"Power": 4,
		"Keyword": ["Augment"],
		"Skill": "{Play} or {Round Start}: Create a [Hex Core Upgrade] in your hand if you don't have one. [br] {Aura}: Created cards cost {cost_decrease} less.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "",
		"BalanceValues": {"cost_decrease": 1},
		"PreviewTooltip": ["Viktor1", "Viktor2", "HexCoreUpgrade"]
	},
	"HexCoreUpgrade": {
		"Name": "Hex Core Upgrade",
		"Region": ["Piltover Zaun"],
		"Type": "Spell",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/HexCoreUpgrade.webp",
		"Cost": 0,
		"Keyword": ["Slow"],
		"Skill": "Grant [Viktor] a random keyword.",
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Viktor1", "Viktor2", "HexCoreUpgrade"]
	},

	# Champion - Draven line
	"Draven1": {
		"Name": "Draven",
		"Region": ["Noxus"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Draven1.webp",
		"Level": 1,
		"Cost": 3,
		"Power": 3,
		"Keyword": [],
		"Skill": "{Play} or {Round Start}: Create a [Spinning Axe] in your hand if you don't have one.",
		"LevelUp": "I've seen you play {axe_threshold}+ [Spinning Axes].",
		"LevelUpTo": "Draven2",
		"AbilityType": "create_card_if_not_in_hand",
		"BalanceValues": {"axe_threshold": 2},
		"PreviewTooltip": ["Draven1", "Draven2", "SpinningAxe"]
	},
	"Draven2": {
		"Name": "Draven",
		"Region": ["Noxus"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Draven2.webp",
		"Level": 2,
		"Cost": 3,
		"Power": 4,
		"Keyword": [],
		"Skill": "{Play} or {Round Start}: Create 2 [Spinning Axes] in your hand.",
		"LevelUp": "",
		"LevelUpTo": "",
		"AbilityType": "create_multiple_cards",
		"BalanceValues": {"create_count": 2, "create_card_id": "SpinningAxe"},
		"PreviewTooltip": ["Draven1", "Draven2", "SpinningAxe"]
	},
	"SpinningAxe": {
		"Name": "Spinning Axe",
		"Region": ["Noxus"],
		"Type": "Spell",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/SpinningAxe.webp",
		"Cost": 0,
		"Keyword": ["Fast"],
		"Skill": "Discard your leftmost card to grant [Draven] +{power_bonus} Power.",
		"AbilityType": "spinning_axe_discard",
		"BalanceValues": {"power_bonus": 1},
		"PreviewTooltip": ["Draven1", "Draven2", "SpinningAxe"]
	},

	# Champions - Lucian line
	"Lucian1": {
		"Name": "Lucian",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Lucian1.webp",
		"Level": 1,
		"Cost": 1,
		"Power": 2,
		"Keyword": [],
		"Skill": "",
		"LevelUp": "I've seen {die_threshold}+ allies or an allied [Senna] die.",
		"LevelUpTo": "Lucian2",
		"AbilityType": "",
		"BalanceValues": {"die_threshold": 3},
		"PreviewTooltip": ["Lucian1", "Lucian2"]
	},
	"Lucian2": {
		"Name": "Lucian",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Lucian2.webp",
		"Level": 2,
		"Cost": 1,
		"Power": 3,
		"Keyword": [],
		"Skill": "The first time each round I see another ally die, {Rally} another ally here.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Lucian1", "Lucian2"]
	},

	# Champions - Garen line
	"Garen1": {
		"Name": "Garen",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "Elite",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Garen1.webp",
		"Level": 1,
		"Cost": 5,
		"Power": 5,
		"Keyword": ["Regeneration"],
		"Skill": "{Play}: Grant front-row allies +{play_buff} Power.",
		"LevelUp": "You've activated {Play} effects {levelup_threshold}+ times.",
		"LevelUpTo": "Garen2",
		"AbilityType": "",
		"BalanceValues": {"play_buff": 1, "levelup_threshold": 5},
		"PreviewTooltip": ["Garen1", "Garen2"]
	},
	"Garen2": {
		"Name": "Garen",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "Elite",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Garen2.webp",
		"Level": 2,
		"Cost": 5,
		"Power": 6,
		"Keyword": ["Regeneration"],
		"Skill": "{Play}: Grant allies +{play_buff} Power. [br] {Round Start}: {Rally} ALL allies.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"play_buff": 1},
		"PreviewTooltip": ["Garen1", "Garen2"]
	},

	# Champions - Quinn line
	"Quinn1": {
		"Name": "Quinn",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Quinn1.webp",
		"Level": 1,
		"Cost": 4,
		"Power": 5,
		"Keyword": ["Scout"],
		"Skill": "{Play}: {Spawn} [Valor] 1 at another location and grant it :Challenger:{Challenger}.",
		"LevelUp": "You've activated {Play} effects {levelup_threshold}+ times.",
		"LevelUpTo": "Quinn2",
		"AbilityType": "",
		"BalanceValues": {"levelup_threshold": 4},
		"PreviewTooltip": ["Quinn1", "Quinn2", "Valor"]
	},
	"Quinn2": {
		"Name": "Quinn",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Quinn2.webp",
		"Level": 2,
		"Cost": 4,
		"Power": 6,
		"Keyword": ["Scout"],
		"Skill": "{Play} or {Round Start}: {Spawn} [Valor] 1 at another location and grant it :Challenger:{Challenger}.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Quinn1", "Quinn2", "Valor"]
	},
	"Valor": {
		"Name": "Valor",
		"Region": ["Demacia"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Valor.webp",
		"Cost": 1,
		"Power": 1,
		"Keyword": [],
		"Skill": "",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Quinn1", "Quinn2", "Valor"]
	},

	# Champion - Hecarim line
	"Hecarim1": {
		"Name": "Hecarim",
		"Region": ["Shadow Isles"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Hecarim1.webp",
		"Level": 1,
		"Cost": 6,
		"Power": 6,
		"Keyword": ["Overwhelm"],
		"Skill": "{Play}: Summon a [Spectral Rider] to each other location.",
		"LevelUp": "You've summoned {summon_threshold}+ :Ephemeral:{Ephemeral} units.",
		"LevelUpTo": "Hecarim2",
		"AbilityType": "",
		"BalanceValues": {"summon_threshold": 6},
		"PreviewTooltip": ["Hecarim1", "Hecarim2", "SpectralRider"]
	},
	"Hecarim2": {
		"Name": "Hecarim",
		"Region": ["Shadow Isles"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Hecarim2.webp",
		"Level": 2,
		"Cost": 6,
		"Power": 7,
		"Keyword": ["Overwhelm"],
		"Skill": "{Play}: Summon a [Spectral Rider] to each other location. [br] When I level up, grant :Ephemeral:{Ephemeral} units {everywhere} +{buff_power} Power.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"buff_power": 3},
		"PreviewTooltip": ["Hecarim1", "Hecarim2", "SpectralRider"]
	},
	"SpectralRider": {
		"Name": "Spectral Rider",
		"Region": ["Shadow Isles"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/SpectralRider.webp",
		"Cost": 2,
		"Power": 2,
		"Keyword": ["Ephemeral"],
		"Skill": "{Round Start}: Grant the strongest allied [Hecarim] my Power.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Hecarim1", "Hecarim2", "SpectralRider"]
	},

	# Champion - Zed line
	"Zed1": {
		"Name": "Zed",
		"Region": ["Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Zed1.webp",
		"Level": 1,
		"Cost": 2,
		"Power": 2,
		"Keyword": ["Elusive"],
		"Skill": "When I {swap} lane, summon a [Living Shadow] at the original lane and I {strike} an enemy there.",
		"LevelUp": "I've seen myself or [Living Shadow] strike {strike_threshold}+ times.",
		"LevelUpTo": "Zed2",
		"AbilityType": "",
		"BalanceValues": {"strike_threshold": 3},
		"PreviewTooltip": ["Zed1", "Zed2", "LivingShadow"]
	},
	"Zed2": {
		"Name": "Zed",
		"Region": ["Ionia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Zed2.webp",
		"Level": 2,
		"Cost": 2,
		"Power": 3,
		"Keyword": ["Elusive"],
		"Skill": "When I {swap} lane, summon a [Living Shadow] with my Power at the original lane and I {strike} an enemy there.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Zed1", "Zed2", "LivingShadow"]
	},
	"LivingShadow": {
		"Name": "Living Shadow",
		"Region": ["Ionia"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/LivingShadow.webp",
		"Cost": 2,
		"Power": 2,
		"Keyword": ["Ephemeral"],
		"Skill": "{Round End}: I strike the weakest enemy here if you're winning here.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Zed1", "Zed2", "LivingShadow"]
	},

	# Champions - Ryze line
	"Ryze1": {
		"Name": "Ryze",
		"Region": ["Runeterra"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Ryze1.webp",
		"Level": 1,
		"Cost": 3,
		"Power": 3,
		"Keyword": [],
		"Skill": "{Game Start}: Shuffle the World Runes into your deck.",
		"LevelUp": "You've played {worldrunes_threshold}+ different World Runes.",
		"LevelUpTo": "Ryze2",
		"AbilityType": "",
		"BalanceValues": {"worldrunes_threshold": 3},
		"PreviewTooltip": ["Ryze1", "Ryze2", "ShardofViolence", "ShardofBetrayal", "ShardofReverence", "ShardofHope", "ShardofMadness"]
	},
	"Ryze2": {
		"Name": "Ryze",
		"Region": ["Runeterra"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Ryze2.webp",
		"Level": 2,
		"Cost": 3,
		"Power": 4,
		"Keyword": [],
		"Skill": "{Round End}: If you have 5 different World Runes in play, you win the game.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Ryze1", "Ryze2", "ShardofViolence", "ShardofBetrayal", "ShardofReverence", "ShardofHope", "ShardofMadness"]
	},
	"ShardofViolence": {
		"Name": "Shard of Violence",
		"Region": ["Runeterra"],
		"Type": "Landmark",
		"SubType": "World Rune",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/ShardofViolence.webp",
		"Cost": 1,
		"Keyword": ["Landmark"],
		"Skill": "{Play}: Draw {draw_count}. [br] When I'm {Played}, if I'm unique, activate your other World Runes.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"draw_count": 1},
		"PreviewTooltip": ["Ryze1", "Ryze2", "ShardofViolence", "ShardofBetrayal", "ShardofReverence", "ShardofHope", "ShardofMadness"]
	},
	"ShardofBetrayal": {
		"Name": "Shard of Betrayal",
		"Region": ["Runeterra"],
		"Type": "Landmark",
		"SubType": "World Rune",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/ShardofBetrayal.webp",
		"Cost": 1,
		"Keyword": ["Landmark"],
		"Skill": "{Play}: Grant the strongest enemy -{power_reduction} Power. [br] When I'm {Played}, if I'm unique, activate your other World Runes.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"power_reduction": 1},
		"PreviewTooltip": ["Ryze1", "Ryze2", "ShardofViolence", "ShardofBetrayal", "ShardofReverence", "ShardofHope", "ShardofMadness"]
	},
	"ShardofReverence": {
		"Name": "Shard of Reverence",
		"Region": ["Runeterra"],
		"Type": "Landmark",
		"SubType": "World Rune",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/ShardofReverence.webp",
		"Cost": 1,
		"Keyword": ["Landmark"],
		"Skill": "{Play}: Next turn, you get +{mana_bonus} mana. [br] When I'm {Played}, if I'm unique, activate your other World Runes.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"mana_bonus": 1},
		"PreviewTooltip": ["Ryze1", "Ryze2", "ShardofViolence", "ShardofBetrayal", "ShardofReverence", "ShardofHope", "ShardofMadness"]
	},
	"ShardofHope": {
		"Name": "Shard of Hope",
		"Region": ["Runeterra"],
		"Type": "Landmark",
		"SubType": "World Rune",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/ShardofHope.webp",
		"Cost": 1,
		"Keyword": ["Landmark"],
		"Skill": "{Play}: Grant the weakest ally +{power_bonus} Power. [br] When I'm {Played}, if I'm unique, activate your other World Runes.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"power_bonus": 1},
		"PreviewTooltip": ["Ryze1", "Ryze2", "ShardofViolence", "ShardofBetrayal", "ShardofReverence", "ShardofHope", "ShardofMadness"]
	},
	"ShardofMadness": {
		"Name": "Shard of Madness",
		"Region": ["Runeterra"],
		"Type": "Landmark",
		"SubType": "World Rune",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/ShardofMadness.webp",
		"Cost": 1,
		"Keyword": ["Landmark"],
		"Skill": "{Play}: :Stun:{Stun} the strongest enemy. [br] When I'm {Played}, if I'm unique, activate your other World Runes.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"power_bonus": 1},
		"PreviewTooltip": ["Ryze1", "Ryze2", "ShardofViolence", "ShardofBetrayal", "ShardofReverence", "ShardofHope", "ShardofMadness"]
	},

	# Champion - Galio line
	"Galio1": {
		"Name": "Galio",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/Galio1.webp",
		"Level": 1,
		"Cost": 14,
		"Power": 10,
		"Keyword": [],
		"Skill": "I cost 1 less for each mana you've spent this game. [br] {Round End}: If I'm in your hand, pay my cost to summon me to the losing lane.",
		"LevelUp": "You've spent {mana_threshold}+ mana.",
		"LevelUpTo": "Galio2",
		"AbilityType": "",
		"BalanceValues": {"mana_threshold": 14},
		"PreviewTooltip": ["Galio1", "Galio2"]
	},
	"Galio2": {
		"Name": "Galio",
		"Region": ["Demacia"],
		"Type": "Champion",
		"SubType": "",
		"Collectible": false,
		"Sprite": "res://Assets/CardSprites/Galio2.webp",
		"Level": 2,
		"Cost": 0,
		"Power": 10,
		"Keyword": [],
		"Skill": "{Round End}: If I'm in your hand, summon me to the losing lane. [br] When another ally activates {Play} effect, {Rally} it.",
		"LevelUp": "",
		"LevelUpTo": null,
		"AbilityType": "",
		"BalanceValues": {"mana_threshold": 14},
		"PreviewTooltip": ["Galio1", "Galio2"]
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
		"Keyword": ["Landmark"],
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
		"Keyword": ["Landmark"],
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
		"Keyword": [],
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
		"Power": 0,
		"Keyword": [],
		"Skill": "{Aura}: Other allied [Blades] have +{aura_power} Power.",
		"AbilityType": "aura_blade_buff",
		"BalanceValues": {"aura_power": 1},
		"PreviewTooltip": ["Irelia1", "Irelia2", "Blade"]
	},
	"NavoriConspirator": {
		"Name": "Navori Conspirator",
		"Region": ["Ionia"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 2,
		"Power": 4,
		"Keyword": [],
		"Skill": "{Play}: {Recall} other allies here.",
		"AbilityType": "recall_allies_same_lane",
		"BalanceValues": {"aura_power": 1},
		"PreviewTooltip": ["NavoriConspirator"]
	},
	"SolitaryMonk": {
		"Name": "Solitary Monk",
		"Region": ["Ionia"],
		"Type": "Follower",
		"SubType": "",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 2,
		"Power": 4,
		"Keyword": [],
		"Skill": "{Play}: {Recall} {recall_cost} cost allies.",
		"AbilityType": "recall_cost_allies",
		"BalanceValues": {"recall_cost": 1},
		"PreviewTooltip": ["SolitaryMonk"]
	},
	"SeaScarab": {
		"Name": "Sea Scarab",
		"Region": ["Shadow Isles"],
		"Type": "Follower",
		"SubType": "Sea Monster",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 2,
		"Power": 2,
		"Keyword": ["Deep"],
		"Skill": "",
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["SeaScarab"]
	},
	"Megatusk": {
		"Name": "Megatusk",
		"Region": ["Bilgewater"],
		"Type": "Follower",
		"SubType": "Sea Monster",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 3,
		"Power": 3,
		"Keyword": ["Deep"],
		"Skill": "",
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["Megatusk"]
	},
	"TheBeastBelow": {
		"Name": "The Beast Below",
		"Region": ["Bilgewater"],
		"Type": "Follower",
		"SubType": "Sea Monster",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 4,
		"Power": 4,
		"Keyword": ["Deep"],
		"Skill": "",
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["TheBeastBelow"]
	},
	"AbyssalEye": {
		"Name": "Abyssal Eye",
		"Region": ["Bilgewater"],
		"Type": "Follower",
		"SubType": "Sea Monster",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 5,
		"Power": 5,
		"Keyword": ["Deep"],
		"Skill": "",
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["AbyssalEye"]
	},
	"DevourerOfTheDepths": {
		"Name": "Devourer of the Depths",
		"Region": ["Bilgewater"],
		"Type": "Follower",
		"SubType": "Sea Monster",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 6,
		"Power": 6,
		"Keyword": ["Deep"],
		"Skill": "",
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["DevourerOfTheDepths"]
	},
	"TerrorOfTheTides": {
		"Name": "Terror of the Tides",
		"Region": ["Bilgewater"],
		"Type": "Follower",
		"SubType": "Sea Monster",
		"Collectible": true,
		"Sprite": "res://Assets/CardSprites/DummySprite.webp",
		"Cost": 7,
		"Power": 7,
		"Keyword": ["Deep"],
		"Skill": "",
		"AbilityType": "",
		"BalanceValues": {},
		"PreviewTooltip": ["TerrorOfTheTides"]
	},

	# Spells

}


static func populate_card_visuals(card: Node, card_data: Dictionary, source_card: Node = null) -> void:
	"""Populate all visual text and sprite nodes on a card from card_data.
	Type-aware: handles Unit (Champion/Follower), Spell, and Landmark card scenes."""
	var card_type := str(card_data.get("Type", ""))
	var is_spell := card_type == "Spell"
	var is_landmark := card_type == "Landmark"

	var name_label = card.get_node_or_null("CardFront/TextContainer/CardName")
	if name_label:
		name_label.text = str(card_data.get("Name", ""))
		var available_width := 530.0
		var name_font: Font = name_label.get_theme_font("normal_font")
		var font_size := 64
		var min_font_size := 36
		if name_font:
			while font_size > min_font_size:
				if name_font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= available_width:
					break
				font_size -= 2
		name_label.add_theme_font_size_override("normal_font_size", font_size)

	var cost_label = card.get_node_or_null("CardFront/Cost")
	if cost_label:
		cost_label.text = str(card_data.get("Cost", 0))

	if not is_spell and not is_landmark:
		apply_power_visual(card, card_data, source_card)

	var skill_label = card.get_node_or_null("CardFront/TextContainer/Skill")
	var skill_text: String = str(card_data.get("Skill", ""))
	if skill_label && skill_text != "":
		skill_label.visible = true
		skill_label.text = format_card_text(skill_text, card_data.get("BalanceValues", {}))
	else:
		skill_label.visible = false

	if not is_spell and not is_landmark:
		_apply_level_up_visual(card, card_data)

	var sprite_path: String = str(card_data.get("Sprite", ""))
	if sprite_path != "":
		var sprite_node: Node = null
		if is_spell:
			sprite_node = card.get_node_or_null("CardFront/CardSpellSpriteParent/CardSpellSprite")
		else:
			sprite_node = card.get_node_or_null("CardFront/CardSpriteParent/CardSprite")
		if sprite_node:
			sprite_node.texture = ResourceLoader.load(sprite_path)

	if not is_spell and not is_landmark:
		_apply_subtype_visual(card, card_data)

	_apply_region_visual(card, card_data, is_spell)

	_apply_keyword_visual(card, card_data)


static func _apply_level_up_visual(card: Node, card_data: Dictionary) -> void:
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


static func _apply_subtype_visual(card: Node, card_data: Dictionary) -> void:
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


static func _apply_region_visual(card: Node, card_data: Dictionary, is_spell: bool) -> void:
	var region: Array = card_data.get("Region", [])
	var region_container_path := "CardFront/TextContainer/RegionContainer" if not is_spell else "CardFront/RegionContainer"
	var region_sprite_node_1 = card.get_node_or_null(region_container_path + "/Region1")
	var region_sprite_node_2 = card.get_node_or_null(region_container_path + "/Region2")

	if region.size() > 0 and region_sprite_node_1:
		region_sprite_node_1.texture = ResourceLoader.load("res://Assets/RegionSprites/" + (region[0].replace(" ", "")) + ".webp")
		region_sprite_node_1.visible = true
	if region.size() > 1 and region_sprite_node_2:
		region_sprite_node_2.texture = ResourceLoader.load("res://Assets/RegionSprites/" + (region[1].replace(" ", "")) + ".webp")
		region_sprite_node_2.visible = true
	elif region_sprite_node_2:
		region_sprite_node_2.visible = false


static func _apply_keyword_visual(card: Node, card_data: Dictionary) -> void:
	var keywords: Array = card_data.get("Keyword", [])
	var keyword_container = card.get_node_or_null("CardFront/TextContainer/KeywordContainer")
	var keyword_item_scene = preload("res://Scenes/KeywordItem.tscn")

	if keyword_container:
		for child in keyword_container.get_children():
			child.queue_free()
	if keywords.size() == 0:
		keyword_container.visible = false
		return
	keyword_container.visible = true
	var show_name := keywords.size() < 3
	for keyword in keywords:
		var item = keyword_item_scene.instantiate()
		var keyword_sprite_path = "res://Assets/KeywordSprites/" + str(keyword) + ".webp"
		item.get_node("HBoxContainer/SpriteMargin/KeywordSprite").texture = ResourceLoader.load(keyword_sprite_path)
		if show_name:
			item.get_node("HBoxContainer/KeywordName").text = keyword
		else:
			item.get_node("HBoxContainer/KeywordName").visible = false
		keyword_container.add_child(item)


static func format_card_text(text: String, balance_values: Dictionary = {}) -> String:
	"""Mirrors the web frontend formatCardText:
	- {key} → substitute balance value, or render gold
	- [CardName] → render blue
	- [br] → line break
	- :Keyword: → keyword icon + name
	- :Keyword:{Vocab} → keyword icon + vocab value
	- -{Vocab} → minus + vocab value (nowrap)"""
	var result := ""
	var i := 0

	while i < text.length():
		var c := text[i]

		if c == "[":
			var close_idx := text.find("]", i + 1)
			if close_idx != -1:
				var content := text.substr(i + 1, close_idx - i - 1)
				if content == "br":
					result += "[br]"
				elif _is_bbcode_tag(content):
					result += text.substr(i, close_idx - i + 1)
				else:
					result += "[color=#54a5ff]" + content + "[/color]"
				i = close_idx + 1
				continue

		if c == ":":
			var close_idx := text.find(":", i + 1)
			if close_idx != -1 and close_idx > i + 1:
				var content := text.substr(i + 1, close_idx - i - 1)
				if content.is_valid_identifier() or content.is_valid_int():
					var img_bbcode := '[img=32x32]res://Assets/KeywordSprites/' + content + '.webp[/img]'
					var next_pos := close_idx + 1
					if next_pos < text.length() and text[next_pos] == "{":
						var vocab_close := text.find("}", next_pos + 1)
						if vocab_close != -1:
							var vocab_content := text.substr(next_pos + 1, vocab_close - next_pos - 1)
							var vocab_val: String
							if balance_values.has(vocab_content):
								vocab_val = str(balance_values[vocab_content])
							else:
								vocab_val = "[color=#ffca4b]" + vocab_content + "[/color]"
							result += img_bbcode + vocab_val
							i = vocab_close + 1
							continue
					result += img_bbcode + content
					i = close_idx + 1
					continue

		if c == "-" and i + 1 < text.length() and text[i + 1] == "{":
			var close_brace := text.find("}", i + 2)
			if close_brace != -1:
				var content := text.substr(i + 2, close_brace - i - 2)
				if result.ends_with(" "):
					result = result.substr(0, result.length() - 1) + " "
				var vocab_val: String
				if balance_values.has(content):
					vocab_val = str(balance_values[content])
				else:
					vocab_val = "[color=#ffca4b]" + content + "[/color]"
				result += "-" + vocab_val
				i = close_brace + 1
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


static func get_collectible_cards() -> Array:
	"""Returns all Collectible=true cards as an Array of dicts (with 'id' injected),
	sorted Champions first, then by Cost ascending, then Name alphabetically."""
	var result: Array = []
	for card_id in CARDS:
		var data: Dictionary = CARDS[card_id]
		if data.get("Collectible", false):
			var entry := data.duplicate()
			entry["id"] = card_id
			result.append(entry)
	result.sort_custom(func(a, b):
		var a_champ := 1 if a.get("Type", "") != "Champion" else 0
		var b_champ := 1 if b.get("Type", "") != "Champion" else 0
		if a_champ != b_champ:
			return a_champ < b_champ
		if a.get("Cost", 0) != b.get("Cost", 0):
			return a.get("Cost", 0) < b.get("Cost", 0)
		return a.get("Name", "") < b.get("Name", ""))
	return result


static func get_related_cards(card_id: String) -> Array:
	"""Returns card data dicts (with 'id') for every entry in the card's PreviewTooltip list."""
	var data: Dictionary = CARDS.get(card_id, {})
	var tooltip_ids: Array = data.get("PreviewTooltip", [])
	var result: Array = []
	for tid in tooltip_ids:
		var td: Dictionary = CARDS.get(str(tid), {})
		if not td.is_empty():
			var entry := td.duplicate()
			entry["id"] = str(tid)
			result.append(entry)
	return result

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


static func get_card_scene(card_data: Dictionary) -> PackedScene:
	var card_type := str(card_data.get("Type", ""))
	match card_type:
		"Spell":
			return CARD_SPELL_SCENE
		"Landmark":
			return CARD_LANDMARK_SCENE
		_:
			return CARD_SCENE


static func get_card_script(card_data: Dictionary) -> Script:
	var card_type := str(card_data.get("Type", ""))
	match card_type:
		"Spell":
			return preload("res://Scripts/CardSpell.gd")
		"Landmark":
			return preload("res://Scripts/CardLandmark.gd")
		_:
			return preload("res://Scripts/Card.gd")


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
