extends MarginContainer
class_name AssetPackTab

## A tab displaying assets from a single pack with search filtering.

signal asset_selected(pack_id: String, asset_id: String, variant_id: String)

var _pack_id: String = ""
var _items: Array = []
var _filter: String = ""

var _exit_mutex: Mutex
var _items_mutex: Mutex
var _items_sem: Semaphore
var _items_thread: Thread
var _exit_thread := false
var _needs_populate := false

@onready var search_filter: LineEdit = $Content/Header/SearchFilter
@onready var item_list: ItemList = $Content/ItemList


func _ready() -> void:
	_exit_mutex = Mutex.new()
	_items_mutex = Mutex.new()
	_items_sem = Semaphore.new()
	_items_thread = Thread.new()
	
	_exit_thread = false
	_items_thread.start(_items_thread_function)
	
	# Connect signals
	search_filter.text_changed.connect(_on_filter_changed)
	item_list.item_activated.connect(_on_item_activated)


## Initialize this tab for a specific pack
func setup(pack_id: String) -> void:
	_pack_id = pack_id
	_needs_populate = true
	_items_sem.post()


## Refresh the items (call when tab becomes visible)
func refresh() -> void:
	if _pack_id != "":
		_needs_populate = true
		_items_sem.post()


func _items_thread_function() -> void:
	while true:
		_items_sem.wait()
		
		_exit_mutex.lock()
		var should_exit = _exit_thread
		_exit_mutex.unlock()
		
		if should_exit:
			break
		
		_items_mutex.lock()
		_populate_items()
		_items_mutex.unlock()


func _populate_items() -> void:
	call_deferred("_clear_list")
	_items.clear()
	
	var pack = AssetPackManager.get_pack(_pack_id)
	if not pack:
		return
	
	for asset in pack.get_all_assets():
		var display_name = asset.display_name
		
		# Apply filter
		if _filter == "" or _filter.to_lower() in display_name.to_lower():
			var icon_path = pack.get_icon_path(asset.asset_id, "default")
			
			# Load icon on background thread
			var icon: Texture2D = null
			if ResourceLoader.exists(icon_path):
				icon = load(icon_path)
			
			_items.append({
				"pack_id": _pack_id,
				"asset_id": asset.asset_id,
				"variant_id": "default",
				"name": display_name,
				"icon": icon,  # Store loaded texture, not path
				"has_variants": asset.has_variants(),
				"variants": asset.get_variant_ids()
			})
	
	# Add items to list on main thread (icons already loaded)
	for item in _items:
		call_deferred("_add_item_to_list", item)


func _clear_list() -> void:
	item_list.clear()


func _add_item_to_list(item: Dictionary) -> void:
	# Icon is already loaded from background thread
	item_list.add_item(item.name, item.icon)


func _on_filter_changed(new_text: String) -> void:
	_filter = new_text
	_needs_populate = true
	_items_sem.post()


func _on_item_activated(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	
	var selected = _items[index]
	asset_selected.emit(selected.pack_id, selected.asset_id, selected.variant_id)


## Clear the search filter
func clear_filter() -> void:
	search_filter.clear()
	_filter = ""


## Focus the search field
func focus_search() -> void:
	search_filter.grab_focus()


func _exit_tree() -> void:
	_exit_mutex.lock()
	_exit_thread = true
	_exit_mutex.unlock()
	
	_items_sem.post()
	_items_thread.wait_to_finish()
