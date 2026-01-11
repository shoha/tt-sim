extends Node

@export var available_pokemon: Dictionary = {
	"bulbasaur": {
		"scene": "res://scenes/pokemon/1_bulbasaur.tscn",
		"shiny_scene": "res://scenes/pokemon/1_bulbasaur_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/1_bulbasaur.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/1_bulbasaur_shiny.png"
	},
	"ivysaur": {
		"scene": "res://scenes/pokemon/2_ivysaur.tscn",
		"shiny_scene": "res://scenes/pokemon/2_ivysaur_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/2_ivysaur.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/2_ivysaur_shiny.png"
	},
	"venusaur": {
		"scene": "res://scenes/pokemon/3_venusaur.tscn",
		"shiny_scene": "res://scenes/pokemon/3_venusaur_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/3_venusaur.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/3_venusaur_shiny.png"
	},
	"charmander": {
		"scene": "res://scenes/pokemon/4_charmander.tscn",
		"shiny_scene": "res://scenes/pokemon/4_charmander_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/4_charmander.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/4_charmander_shiny.png"
	},
	"charmeleon": {
		"scene": "res://scenes/pokemon/5_charmeleon.tscn",
		"shiny_scene": "res://scenes/pokemon/5_charmeleon_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/5_charmeleon.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/5_charmeleon_shiny.png"
	},
	"charizard": {
		"scene": "res://scenes/pokemon/6_charizard.tscn",
		"shiny_scene": "res://scenes/pokemon/6_charizard_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/6_charizard.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/6_charizard_shiny.png"
	},
	"squirtle": {
		"scene": "res://scenes/pokemon/7_squirtle.tscn",
		"shiny_scene": "res://scenes/pokemon/7_squirtle.tscn",
		"icon": "res://assets/icons/pokemon/ZA/7_squirtle.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/7_squirtle_shiny.png"
	},
	"wartortle": {
		"scene": "res://scenes/pokemon/8_wartortle.tscn",
		"shiny_scene": "res://scenes/pokemon/8_wartortle_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/8_wartortle.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/8_wartortle_shiny.png"
	},
	"blastoise": {
		"scene": "res://scenes/pokemon/9_blastoise.tscn",
		"shiny_scene": "res://scenes/pokemon/9_blastoise_shiny.tscn",
		"icon": "res://assets/icons/pokemon/ZA/9_blastoise.png",
		"shiny_icon": "res://assets/icons/pokemon/ZA/9_blastoise_shiny.png"
	}
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
