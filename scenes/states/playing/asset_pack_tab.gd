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

	# Collect asset info in background thread (no node access needed)
	var items_to_add: Array = []
	for asset in pack.get_all_assets():
		var display_name = asset.display_name

		# Apply filter
		if _filter == "" or _filter.to_lower() in display_name.to_lower():
			items_to_add.append(
				{
					"pack_id": _pack_id,
					"asset_id": asset.asset_id,
					"variant_id": "default",
					"name": display_name,
					"has_variants": asset.has_variants(),
					"variants": asset.get_variant_ids()
				}
			)

	_items = items_to_add

	if _items.is_empty():
		call_deferred("_show_empty_state")
	else:
		# Add items to list on main thread
		for item in _items:
			call_deferred("_add_item_to_list", item)


func _clear_list() -> void:
	item_list.clear()


func _add_item_to_list(item: Dictionary) -> void:
	# Add item without icon to avoid bulk icon downloads for remote asset packs
	item_list.add_item(item.name)


func _show_empty_state() -> void:
	var msg = 'No results for "%s"' % _filter if _filter != "" else "No assets in this pack"
	item_list.add_item(msg)
	item_list.set_item_disabled(0, true)
	item_list.set_item_selectable(0, false)


func _on_filter_changed(new_text: String) -> void:
	_filter = new_text
	_needs_populate = true
	_items_sem.post()


func _on_item_activated(index: int) -> void:
	print(
		(
			"AssetPackTab: item_activated index=%d, _items.size()=%d, pack=%s"
			% [index, _items.size(), _pack_id]
		)
	)
	if index < 0 or index >= _items.size():
		push_warning("AssetPackTab: index %d out of range (items=%d)" % [index, _items.size()])
		return

	var selected = _items[index]
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


func _exit_tree() -> void:
	_exit_mutex.lock()
	_exit_thread = true
	_exit_mutex.unlock()

	_items_sem.post()
	_items_thread.wait_to_finish()
