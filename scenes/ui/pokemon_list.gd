extends ItemList

var exit_mutex: Mutex
var items_mutex: Mutex
var items_sem: Semaphore
var items_thread: Thread
var exit_items_thread := false

var _current_items: Array
var _current_filter: String

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	exit_mutex = Mutex.new()
	items_mutex = Mutex.new()
	items_sem = Semaphore.new()
	items_thread = Thread.new()

	exit_items_thread = false
	
	items_thread.start(_items_thread_function)
	items_sem.post()
	
func _items_thread_function():
	while true:
		items_sem.wait()
		
		exit_mutex.lock()
		var should_exit = exit_items_thread
		exit_mutex.unlock()
		
		if should_exit:
			break
		
		items_mutex.lock()
		populate_items(_current_filter)
		items_mutex.unlock()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func populate_items(filter: String = "") -> void:
	call_deferred("clear")
	_current_items = []
	
	for pokemon_number in PokemonAutoload.available_pokemon:
		var pokemon = PokemonAutoload.available_pokemon[pokemon_number]
		var pokemon_name = pokemon.name

		if filter == "" or filter.to_lower() in pokemon.name.to_lower():
			var scene_path = PokemonAutoload.path_to_scene(pokemon_number, false)
			var icon_path = PokemonAutoload.path_to_icon(pokemon_number, false)
			_current_items.append({"name": pokemon_name, "icon": icon_path, "scene": scene_path})
	
	for item in _current_items:
		call_deferred("add_item", item.name, load(item.icon))

func _on_pokemon_filter_text_changed(new_text: String) -> void:
	_current_filter = new_text
	items_sem.post()

func _on_item_activated(index: int) -> void:
	var selected_item = _current_items[index]
	var pokemon_scene: PackedScene = load(selected_item.scene)
	EventBus.pokemon_added.emit(pokemon_scene)
	
func _exit_tree():
	# Set exit condition to true.
	exit_mutex.lock()
	exit_items_thread = true # Protect with Mutex.
	exit_mutex.unlock()

	# Unblock by posting.
	items_sem.post()

	# Wait until it exits.
	items_thread.wait_to_finish()
