class_name KeywordDatabase

const KEYWORDS = {
	"Fearsome": {
		"Description": "{Play} skill from enemy units with less than 3 Power cannot target this unit.",
		"Sprite": "res://Assets/KeywordSprites/Fearsome.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Barrier": {
		"Description": "Negates the next {Kill} effect from the enemy. Remove this keyword at the next round end.",
		"Sprite": "res://Assets/KeywordSprites/Barrier.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Regeneration": {
		"Description": "{Round End}: Cleanses the permanent negative Power debuff.",
		"Sprite": "res://Assets/KeywordSprites/Regeneration.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Tough": {
		"Description": "Reduces the number of negative Power debuffs received from all sources by 1.",
		"Sprite": "res://Assets/KeywordSprites/Tough.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Challenger": {
		"Description": "While this keyword is active, +2 Power if enemy plays a card here. Inactivate this keyword at round end.",
		"Sprite": "res://Assets/KeywordSprites/Challenger.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Lifesteal": {
		"Description": "When this unit decreases other cards' Power, grant this Power that much.",
		"Sprite": "res://Assets/KeywordSprites/Lifesteal.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Augment": {
		"Description": "When you play a created card, grant me +1 Power.",
		"Sprite": "res://Assets/KeywordSprites/Augmented.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Elusive": {
		"Description": "Each round, You can {swap lane} me.",
		"Sprite": "res://Assets/KeywordSprites/Elusive.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Evolve": {
		"Description": "I have +2 once you've had units with 4+ other unique positive keywords in play this game.",
		"Sprite": "res://Assets/KeywordSprites/Evolve.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Spirit": {
		"Description": "This unit has +1 Power. This keyword can stack.",
		"Sprite": "res://Assets/KeywordSprites/Spirit.webp",
		"Stackable": true,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Impact": {
		"Description": "This lane has +1 Power. This keyword can stack.",
		"Sprite": "res://Assets/KeywordSprites/Impact.webp",
		"Stackable": true,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Stun": {
		"Description": "Stunned units cannot activate their Round End, Round Start, Elusive effects. Remove this keyword at play next resolve phase.",
		"Sprite": "res://Assets/KeywordSprites/Stun.webp",
		"Stackable": false,
		"Generatable": false,
		"Transferable": false,
		"Positive": false
	},
	"Deep": {
		"Description": "You are Deep when you're running out of deck. When that happens, grant units with the Deep keyword +3 Power.",
		"Sprite": "res://Assets/KeywordSprites/Deep.webp",
		"Stackable": false,
		"Generatable": false,
		"Transferable": true,
		"Positive": true
	},
	"Scout": {
		"Description": "This unit's {Play}, {Round Start}, and {Round End} effects activate twice.",
		"Sprite": "res://Assets/KeywordSprites/Scout.webp",
		"Stackable": false,
		"Generatable": true,
		"Transferable": true,
		"Positive": true
	},
	"Ephemeral": {
		"Description": "This unit dies once it activates its skill.",
		"Sprite": "res://Assets/KeywordSprites/Ephemeral.webp",
		"Stackable": false,
		"Generatable": false,
		"Transferable": false,
		"Positive": false
	},
}
