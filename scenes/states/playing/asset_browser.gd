class_name AssetBrowser
extends VBoxContainer

## A tabbed browser for all asset packs.
## Each tab contains assets from one pack with its own search filter.

signal asset_selected(pack_id: String, asset_id: String, variant_id: String)
signal asset_drag_started(pack_id: String, asset_id: String, variant_id: String, icon: Texture2D)

const AssetPackTabScene = preload("res://scenes/states/playing/asset_pack_tab.tscn")

var _tabs: Dictionary = {}  # pack_id -> AssetPackTab

@onready var tab_container: TabContainer = $TabContainer


func _ready() -> void:
	# Wait for AssetManager to be ready
	if AssetManager.get_packs().size() > 0:
		_create_tabs()
	else:
		AssetManager.packs_loaded.connect(_on_packs_loaded, CONNECT_ONE_SHOT)


func _on_packs_loaded() -> void:
	_create_tabs()


func _create_tabs() -> void:
	# Disconnect before clearing to avoid stale connections
	if tab_container.tab_changed.is_connected(_on_tab_changed):
		tab_container.tab_changed.disconnect(_on_tab_changed)

	# Remove existing tabs immediately (not queue_free) to avoid dual-children
	# issues where old and new tabs coexist in the TabContainer
	var old_children = tab_container.get_children()
	for child in old_children:
		tab_container.remove_child(child)
		child.queue_free()
	_tabs.clear()

	# Create a tab for each pack
	var packs = AssetManager.get_packs()
	print("AssetBrowser: _create_tabs() — creating %d tabs" % packs.size())
	for pack in packs:
		var tab = AssetPackTabScene.instantiate() as AssetPackTab
		tab.name = pack.display_name
		tab_container.add_child(tab)
		tab.setup(pack.pack_id)
		tab.asset_selected.connect(_on_asset_selected)
		tab.asset_drag_started.connect(_on_asset_drag_started)
		_tabs[pack.pack_id] = tab

	# Refresh the first tab
	if tab_container.get_child_count() > 0:
		_refresh_current_tab()

	# Connect to tab changes
	tab_container.tab_changed.connect(_on_tab_changed)


## Add a tab for a newly-completed pack download, or refresh it if a tab for
## this pack_id already exists. Unlike _create_tabs(), this touches only the
## one affected tab instead of tearing down and rebuilding every tab (which
## would reset the user's tab selection/search filter and block the main
## thread once per existing tab via AssetPackTab._exit_tree()'s thread join).
func _add_or_refresh_tab(pack_id: String) -> void:
	if _tabs.has(pack_id):
		_tabs[pack_id].refresh()
		return

	var pack = AssetManager.get_pack(pack_id)
	if pack == null:
		push_warning("AssetBrowser: _add_or_refresh_tab called for unknown pack_id: " + pack_id)
		return

	var tab = AssetPackTabScene.instantiate() as AssetPackTab
	tab.name = pack.display_name
	tab_container.add_child(tab)
	tab.setup(pack.pack_id)
	tab.asset_selected.connect(_on_asset_selected)
	tab.asset_drag_started.connect(_on_asset_drag_started)
	_tabs[pack_id] = tab

	# _create_tabs() may not have run yet (e.g. this pack finished downloading
	# before the initial catalog loaded), so make sure tab_changed is wired up.
	if not tab_container.tab_changed.is_connected(_on_tab_changed):
		tab_container.tab_changed.connect(_on_tab_changed)


func _on_tab_changed(_tab_index: int) -> void:
	_refresh_current_tab()
	TabUtils.animate_tab_change(tab_container, self)


func _refresh_current_tab() -> void:
	var current_tab = tab_container.get_current_tab_control()
	if current_tab and current_tab is AssetPackTab:
		current_tab.refresh()


func _on_asset_selected(pack_id: String, asset_id: String, variant_id: String) -> void:
	print("AssetBrowser: relaying asset_selected %s/%s/%s" % [pack_id, asset_id, variant_id])
	asset_selected.emit(pack_id, asset_id, variant_id)


func _on_asset_drag_started(
	pack_id: String, asset_id: String, variant_id: String, icon: Texture2D
) -> void:
	asset_drag_started.emit(pack_id, asset_id, variant_id, icon)


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
