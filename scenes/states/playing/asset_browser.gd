extends VBoxContainer
class_name AssetBrowser

## A tabbed browser for all asset packs.
## Each tab contains assets from one pack with its own search filter.

signal asset_selected(pack_id: String, asset_id: String, variant_id: String)

const AssetPackTabScene = preload("res://scenes/states/playing/asset_pack_tab.tscn")

@onready var tab_container: TabContainer = $TabContainer
@onready var url_edit: LineEdit = $AddPackRow/UrlEdit
@onready var download_button: Button = $AddPackRow/DownloadButton
@onready var progress_label: Label = $AddPackRow/ProgressLabel

var _tabs: Dictionary = {}  # pack_id -> AssetPackTab
var _downloading_pack_id: String = ""


func _ready() -> void:
	# Wait for AssetPackManager to be ready
	if AssetPackManager.get_packs().size() > 0:
		_create_tabs()
	else:
		AssetPackManager.packs_loaded.connect(_on_packs_loaded, CONNECT_ONE_SHOT)
	
	# Pack download from URL
	if download_button:
		download_button.pressed.connect(_on_download_pack_pressed)
	if not AssetPackManager.pack_download_progress.is_connected(_on_pack_download_progress):
		AssetPackManager.pack_download_progress.connect(_on_pack_download_progress)
	if not AssetPackManager.pack_download_completed.is_connected(_on_pack_download_completed):
		AssetPackManager.pack_download_completed.connect(_on_pack_download_completed)
	if not AssetPackManager.pack_download_failed.is_connected(_on_pack_download_failed):
		AssetPackManager.pack_download_failed.connect(_on_pack_download_failed)


func _on_packs_loaded() -> void:
	_create_tabs()


func _on_download_pack_pressed() -> void:
	var url = url_edit.text.strip_edges()
	if url.is_empty():
		progress_label.text = "Enter a manifest URL"
		progress_label.visible = true
		return
	
	progress_label.text = "Fetching manifest..."
	progress_label.visible = true
	download_button.disabled = true
	
	if AssetPackManager.download_asset_pack_from_url(url):
		_downloading_pack_id = ""  # Will be set when we get progress
	else:
		progress_label.text = "Failed to start download"
		download_button.disabled = false


func _on_pack_download_progress(pack_id: String, downloaded: int, total: int) -> void:
	_downloading_pack_id = pack_id
	progress_label.text = "Downloading %s: %d / %d" % [pack_id, downloaded, total]
	progress_label.visible = true


func _on_pack_download_completed(pack_id: String) -> void:
	if pack_id == _downloading_pack_id or _downloading_pack_id == "":
		progress_label.text = "Download complete!"
		progress_label.visible = true
		download_button.disabled = false
		_downloading_pack_id = ""
		# Refresh tabs to show new pack
		_create_tabs()
		# Clear success message after a delay
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if progress_label.text == "Download complete!":
				progress_label.visible = false
		)


func _on_pack_download_failed(pack_id: String, error: String) -> void:
	if pack_id == _downloading_pack_id or _downloading_pack_id == "":
		progress_label.text = "Download failed: %s" % error
		progress_label.visible = true
		download_button.disabled = false
		_downloading_pack_id = ""


func _create_tabs() -> void:
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
