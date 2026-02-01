extends ItemList

## Emitted when an asset is selected from the list
## Uses the new pack-based system
signal asset_selected(pack_id: String, asset_id: String, variant_id: String)

## Legacy signal for backward compatibility
## DEPRECATED: Use asset_selected instead
signal pokemon_selected(pokemon_number: String, is_shiny: bool)

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

func _items_thread_function() -> void:
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

func populate_items(filter: String = "") -> void:
	call_deferred("clear")
	_current_items = []

	# Iterate through all packs and their assets
	for pack in AssetPackManager.get_packs():
		for asset in pack.get_all_assets():
			var display_name = asset.display_name
			
			if filter == "" or filter.to_lower() in display_name.to_lower():
				# Get the default variant for icon
				var icon_path = pack.get_icon_path(asset.asset_id, "default")
				
				_current_items.append({
					"pack_id": pack.pack_id,
					"asset_id": asset.asset_id,
					"variant_id": "default",
					"name": display_name,
					"icon": icon_path,
					"has_variants": asset.has_variants(),
					"variants": asset.get_variant_ids()
				})

	for item in _current_items:
		var icon = load(item.icon) if ResourceLoader.exists(item.icon) else null
		call_deferred("add_item", item.name, icon)

func _on_pokemon_filter_text_changed(new_text: String) -> void:
	_current_filter = new_text
	items_sem.post()

func _on_item_activated(index: int) -> void:
	var selected_item = _current_items[index]
	
	# Emit the new signal
	asset_selected.emit(
		selected_item.pack_id,
		selected_item.asset_id,
		selected_item.variant_id
	)
	
	# Also emit legacy signal for backward compatibility if it's a Pokemon
	if selected_item.pack_id == "pokemon":
		var is_shiny = selected_item.variant_id == "shiny"
		pokemon_selected.emit(selected_item.asset_id, is_shiny)


## Get variant options for the selected item
## Returns array of variant IDs, or empty if no variants
func get_selected_variants(index: int) -> Array[String]:
	if index < 0 or index >= _current_items.size():
		return []
	var item = _current_items[index]
	return item.variants if item.has("variants") else []


## Select a specific variant for spawning
func select_variant(index: int, variant_id: String) -> void:
	if index < 0 or index >= _current_items.size():
		return
	_current_items[index].variant_id = variant_id


func _exit_tree() -> void:
	# Set exit condition to true.
	exit_mutex.lock()
	exit_items_thread = true # Protect with Mutex.
	exit_mutex.unlock()

	# Unblock by posting.
	items_sem.post()

	# Wait until it exits.
	items_thread.wait_to_finish()
