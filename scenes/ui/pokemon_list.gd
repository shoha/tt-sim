extends ItemList

signal pokemon_added(pokemon: PackedScene)

var _current_items: Array

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	populate_items()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func populate_items(filter: String = "") -> void:
	clear()
	_current_items = []
	
	for pokemon_name in PokemonAutoload.available_pokemon:
		if filter == "" or filter.to_lower() in pokemon_name.to_lower():
			var pokemon = PokemonAutoload.available_pokemon[pokemon_name]
			_current_items.append({"name": pokemon_name, "icon": pokemon.icon, "scene": pokemon.scene})
			_current_items.append({"name": pokemon_name, "icon": pokemon.shiny_icon, "scene": pokemon.shiny_scene})
	
	for item in _current_items:
		add_item(item.name, load(item.icon))

func _on_pokemon_filter_text_changed(new_text: String) -> void:
	populate_items(new_text)

func _on_item_activated(index: int) -> void:
	var selected_item = _current_items[index]
	var pokemon_scene: PackedScene = load(selected_item.scene)
	pokemon_added.emit(pokemon_scene)
	
