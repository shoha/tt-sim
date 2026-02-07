extends VBoxContainer
class_name AssetBrowser

## A tabbed browser for all asset packs.
## Each tab contains assets from one pack with its own search filter.

signal asset_selected(pack_id: String, asset_id: String, variant_id: String)

const AssetPackTabScene = preload("res://scenes/states/playing/asset_pack_tab.tscn")

@onready var tab_container: TabContainer = $TabContainer

var _tabs: Dictionary = {}  # pack_id -> AssetPackTab


func _ready() -> void:
	# Wait for AssetPackManager to be ready
	if AssetPackManager.get_packs().size() > 0:
		_create_tabs()
	else:
		AssetPackManager.packs_loaded.connect(_on_packs_loaded, CONNECT_ONE_SHOT)


func _on_packs_loaded() -> void:
	_create_tabs()


func _create_tabs() -> void:
	# Disconnect before clearing to avoid stale connections
	if tab_container.tab_changed.is_connected(_on_tab_changed):
		tab_container.tab_changed.disconnect(_on_tab_changed)

	# Clear existing tabs
	for child in tab_container.get_children():
		child.queue_free()
	_tabs.clear()
	
	# Create a tab for each pack
	for pack in AssetPackManager.get_packs():
		var tab = AssetPackTabScene.instantiate() as AssetPackTab
		tab.name = pack.display_name
		tab_container.add_child(tab)
		tab.setup(pack.pack_id)
		tab.asset_selected.connect(_on_asset_selected)
		_tabs[pack.pack_id] = tab
	
	# Refresh the first tab
	if tab_container.get_child_count() > 0:
		_refresh_current_tab()
	
	# Connect to tab changes
	tab_container.tab_changed.connect(_on_tab_changed)


func _on_tab_changed(_tab_index: int) -> void:
	_refresh_current_tab()


func _refresh_current_tab() -> void:
	var current_tab = tab_container.get_current_tab_control()
	if current_tab and current_tab is AssetPackTab:
		current_tab.refresh()


func _on_asset_selected(pack_id: String, asset_id: String, variant_id: String) -> void:
	asset_selected.emit(pack_id, asset_id, variant_id)


## Clear all search filters
func clear_filters() -> void:
	for tab in _tabs.values():
		tab.clear_filter()


## Focus the search field in the current tab
func focus_current_search() -> void:
	var current_tab = tab_container.get_current_tab_control()
	if current_tab and current_tab is AssetPackTab:
		current_tab.focus_search()


## Get the number of loaded packs
func get_pack_count() -> int:
	return _tabs.size()
