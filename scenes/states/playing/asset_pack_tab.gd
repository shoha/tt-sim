extends MarginContainer
class_name AssetPackTab

## A tab displaying assets from a single pack with search filtering.

signal asset_selected(pack_id: String, asset_id: String, variant_id: String)
signal asset_drag_started(pack_id: String, asset_id: String, variant_id: String, icon: Texture2D)

var _drag_pressed_index: int = -1
var _drag_press_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD_PX: float = 8.0

var _pack_id: String = ""
var _items: Array = []
var _filter: String = ""
var _icon_cache: Dictionary = {}  # asset_id -> ImageTexture

var _exit_mutex: Mutex
var _items_mutex: Mutex
var _items_sem: Semaphore
var _items_thread: Thread
var _exit_thread := false
var _needs_populate := false

# Thread-safe snapshots: written on main thread under _items_mutex, read by worker
var _current_filter: String = ""
var _pack_snapshot: Array = []

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
	item_list.gui_input.connect(_on_item_list_gui_input)


## Initialize this tab for a specific pack
func setup(pack_id: String) -> void:
	_pack_id = pack_id
	_needs_populate = true
	_request_populate()


## Refresh the items (call when tab becomes visible)
func refresh() -> void:
	if _pack_id != "":
		_needs_populate = true
		_request_populate()


## Snapshot pack data on the main thread and wake the worker.
## All AssetManager access happens here (main thread only).
func _request_populate() -> void:
	_items_mutex.lock()
	_current_filter = _filter
	var pack = AssetManager.get_pack(_pack_id)
	if pack:
		_pack_snapshot = []
		for asset in pack.get_all_assets():
			(
				_pack_snapshot
				. append(
					{
						"asset_id": asset.asset_id,
						"display_name": asset.display_name,
						"has_variants": asset.has_variants(),
						"variant_ids": asset.get_variant_ids(),
						"icon_path": pack.get_icon_path(asset.asset_id, "default"),
					}
				)
			)
	else:
		_pack_snapshot = []
	_items_mutex.unlock()
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
		# _populate_items() returns with the mutex locked; unlock here
		_items_mutex.unlock()


## Build filtered items from snapshot data. Called with _items_mutex locked;
## returns with it locked (but unlocks in the middle for the filtering work).
func _populate_items() -> void:
	call_deferred("_clear_list")

	# Copy snapshot data under mutex (already locked by caller)
	var filter := _current_filter
	var snapshot := _pack_snapshot.duplicate()
	var pack_id := _pack_id
	_items.clear()
	_items_mutex.unlock()

	# Filter and build items list without any lock held
	var items_to_add: Array = []
	for entry in snapshot:
		var display_name: String = entry.display_name
		if filter == "" or filter.to_lower() in display_name.to_lower():
			(
				items_to_add
				. append(
					{
						"pack_id": pack_id,
						"asset_id": entry.asset_id,
						"variant_id": "default",
						"name": display_name,
						"has_variants": entry.has_variants,
						"variants": entry.variant_ids,
						"icon_path": entry.icon_path,
					}
				)
			)

	# Re-lock to write results
	_items_mutex.lock()
	_items = items_to_add

	if _items.is_empty():
		call_deferred("_show_empty_state", filter)
	else:
		for item in _items:
			call_deferred("_add_item_to_list", item)


func _clear_list() -> void:
	if not is_instance_valid(self):
		return
	item_list.clear()


func _add_item_to_list(item: Dictionary) -> void:
	if not is_instance_valid(self):
		return
	var index := item_list.add_item(item.name)
	var icon_path: String = item.get("icon_path", "")
	if icon_path == "":
		return
	var cache_key: String = item.asset_id
	if _icon_cache.has(cache_key):
		item_list.set_item_icon(index, _icon_cache[cache_key])
		return
	if not FileAccess.file_exists(icon_path):
		return
	ResourceLoader.load_threaded_request(icon_path, "Image")
	_poll_icon_load.call_deferred(icon_path, cache_key, index)


## Poll for threaded icon load completion. Retries next frame if still loading.
func _poll_icon_load(path: String, cache_key: String, index: int) -> void:
	if not is_instance_valid(self):
		return
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_poll_icon_load.call_deferred(path, cache_key, index)
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return
	var image: Image = ResourceLoader.load_threaded_get(path)
	if not image or not is_instance_valid(self):
		return
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = texture
	if index < item_list.item_count:
		item_list.set_item_icon(index, texture)


func _show_empty_state(filter_text: String = "") -> void:
	if not is_instance_valid(self):
		return
	var msg = 'No results for "%s"' % filter_text if filter_text != "" else "No assets in this pack"
	item_list.add_item(msg)
	item_list.set_item_disabled(0, true)
	item_list.set_item_selectable(0, false)


func _on_filter_changed(new_text: String) -> void:
	_filter = new_text
	_needs_populate = true
	_request_populate()


func _on_item_activated(index: int) -> void:
	_items_mutex.lock()
	var items_copy := _items.duplicate()
	_items_mutex.unlock()

	print(
		(
			"AssetPackTab: item_activated index=%d, _items.size()=%d, pack=%s"
			% [index, items_copy.size(), _pack_id]
		)
	)
	if index < 0 or index >= items_copy.size():
		push_warning("AssetPackTab: index %d out of range (items=%d)" % [index, items_copy.size()])
		return

	var selected = items_copy[index]
	print(
		(
			"AssetPackTab: emitting asset_selected %s/%s/%s"
			% [selected.pack_id, selected.asset_id, selected.variant_id]
		)
	)
	asset_selected.emit(selected.pack_id, selected.asset_id, selected.variant_id)


## Clear the search filter
func clear_filter() -> void:
	search_filter.clear()
	_filter = ""


## Focus the search field
func focus_search() -> void:
	search_filter.grab_focus()


func _on_item_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var idx := item_list.get_item_at_position(event.position, true)
			if idx >= 0:
				_drag_pressed_index = idx
				_drag_press_pos = event.position
			else:
				_drag_pressed_index = -1
		else:
			_drag_pressed_index = -1

	if event is InputEventMouseMotion and _drag_pressed_index >= 0:
		if event.position.distance_to(_drag_press_pos) >= DRAG_THRESHOLD_PX:
			_start_drag(_drag_pressed_index)
			_drag_pressed_index = -1


func _start_drag(index: int) -> void:
	_items_mutex.lock()
	var items_copy := _items.duplicate()
	_items_mutex.unlock()

	if index < 0 or index >= items_copy.size():
		return

	var selected: Dictionary = items_copy[index]
	var icon: Texture2D = _icon_cache.get(selected.asset_id, null)
	asset_drag_started.emit(selected.pack_id, selected.asset_id, selected.variant_id, icon)


func _exit_tree() -> void:
	_exit_mutex.lock()
	_exit_thread = true
	_exit_mutex.unlock()

	_items_sem.post()
	_items_thread.wait_to_finish()
