extends ItemList



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	populate_items()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func populate_items(filter: String = "") -> void:
	clear()
	
	for pokemon_name in PokemonAutoload.available_pokemon:
		if filter == "" or filter.to_lower() in pokemon_name.to_lower():
			var pokemon = PokemonAutoload.available_pokemon[pokemon_name]
			add_icon_item(load(pokemon.icon))
			add_icon_item(load(pokemon.shiny_icon))

func _on_pokemon_filter_text_changed(new_text: String) -> void:
	populate_items(new_text)


func _on_item_activated(index: int) -> void:
	print(index)
