extends CanvasLayer
class_name DownloadQueue

## UI widget showing active asset downloads.
##
## Displays in the bottom-left corner when downloads are in progress.
## Shows current download, progress bar, and queue count.

const MAX_VISIBLE_ITEMS := 3
const HIDE_DELAY := 2.0 # Seconds to wait before hiding after all downloads complete

@onready var panel: PanelContainer = $MarginContainer/PanelContainer
@onready var title_label: Label = $MarginContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var items_container: VBoxContainer = $MarginContainer/PanelContainer/MarginContainer/VBoxContainer/ItemsContainer
@onready var queue_label: Label = $MarginContainer/PanelContainer/MarginContainer/VBoxContainer/QueueLabel

var _download_items: Dictionary = {} # key -> {container, label, progress_bar}
var _hide_timer: Timer
var _is_visible: bool = false
var _tween: Tween


func _ready() -> void:
	# Start hidden
	panel.modulate.a = 0.0
	panel.visible = false
	
	# Create hide timer
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_on_hide_timer_timeout)
	add_child(_hide_timer)
	
	# Connect to download signals
	_connect_signals()


func _connect_signals() -> void:
	# Connect to AssetDownloader
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		downloader.download_completed.connect(_on_download_completed)
		downloader.download_failed.connect(_on_download_failed)
		downloader.download_progress.connect(_on_download_progress)
	
	# Connect to AssetStreamer (P2P)
	if has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		streamer.asset_received.connect(_on_p2p_completed)
		streamer.asset_failed.connect(_on_p2p_failed)
		streamer.transfer_progress.connect(_on_p2p_progress)


func _process(_delta: float) -> void:
	_update_queue_count()


## Add or update a download item
func _add_or_update_item(pack_id: String, asset_id: String, variant_id: String, progress: float, source: String = "HTTP") -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]
	
	# Show panel if hidden
	if not _is_visible:
		_show_panel()
	
	# Cancel hide timer
	_hide_timer.stop()
	
	if _download_items.has(key):
		# Update existing
		var item = _download_items[key]
		item.progress_bar.value = progress * 100.0
	else:
		# Create new item
		var container = HBoxContainer.new()
		container.add_theme_constant_override("separation", 8)
		
		# Source indicator
		var source_label = Label.new()
		source_label.text = "[%s]" % source
		source_label.add_theme_font_size_override("font_size", 10)
		source_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		source_label.custom_minimum_size = Vector2(40, 0)
		container.add_child(source_label)
		
		# Asset name
		var display_name = AssetPackManager.get_asset_display_name(pack_id, asset_id)
		var label = Label.new()
		label.text = display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.custom_minimum_size = Vector2(120, 0)
		container.add_child(label)
		
		# Progress bar
		var progress_bar = ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(80, 16)
		progress_bar.value = progress * 100.0
		progress_bar.show_percentage = false
		container.add_child(progress_bar)
		
		items_container.add_child(container)
		
		_download_items[key] = {
			"container": container,
			"label": label,
			"progress_bar": progress_bar,
			"source": source
		}
		
		# Animate in
		container.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(container, "modulate:a", 1.0, 0.15)
		
		# Limit visible items
		_limit_visible_items()


## Remove a download item
func _remove_item(pack_id: String, asset_id: String, variant_id: String, success: bool) -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]
	
	if not _download_items.has(key):
		return
	
	var item = _download_items[key]
	var container = item.container
	
	# Flash color based on success/failure
	if success:
		item.progress_bar.value = 100.0
		item.progress_bar.modulate = Color(0.5, 0.8, 0.5)
	else:
		item.progress_bar.modulate = Color(0.8, 0.4, 0.4)
	
	# Animate out after brief delay
	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_property(container, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func():
		container.queue_free()
		_download_items.erase(key)
		_check_hide_panel()
	)


## Limit visible items to MAX_VISIBLE_ITEMS
func _limit_visible_items() -> void:
	var items = items_container.get_children()
	for i in range(items.size()):
		items[i].visible = i < MAX_VISIBLE_ITEMS


## Update queue count label
func _update_queue_count() -> void:
	var http_queued = 0
	var p2p_queued = 0
	
	if has_node("/root/AssetDownloader"):
		http_queued = get_node("/root/AssetDownloader").get_queued_download_count()
	
	if has_node("/root/AssetStreamer"):
		p2p_queued = get_node("/root/AssetStreamer").get_queued_request_count()
	
	var total_queued = http_queued + p2p_queued
	var total_active = _download_items.size()
	
	if total_queued > 0:
		queue_label.text = "+ %d more in queue" % total_queued
		queue_label.visible = true
	else:
		queue_label.visible = false
	
	# Update title
	if total_active > 0:
		title_label.text = "Downloading Assets (%d)" % total_active
	else:
		title_label.text = "Downloading Assets"


## Check if we should hide the panel
func _check_hide_panel() -> void:
	if _download_items.is_empty():
		_hide_timer.start(HIDE_DELAY)


## Show the panel with animation
func _show_panel() -> void:
	_is_visible = true
	panel.visible = true
	
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(panel, "modulate:a", 1.0, 0.2)


## Hide the panel with animation
func _hide_panel() -> void:
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(panel, "modulate:a", 0.0, 0.15)
	_tween.tween_callback(func():
		panel.visible = false
		_is_visible = false
	)


func _on_hide_timer_timeout() -> void:
	if _download_items.is_empty():
		_hide_panel()


# HTTP Download callbacks
func _on_download_completed(pack_id: String, asset_id: String, variant_id: String, _local_path: String) -> void:
	_remove_item(pack_id, asset_id, variant_id, true)


func _on_download_failed(pack_id: String, asset_id: String, variant_id: String, _error: String) -> void:
	_remove_item(pack_id, asset_id, variant_id, false)


func _on_download_progress(pack_id: String, asset_id: String, variant_id: String, progress: float) -> void:
	_add_or_update_item(pack_id, asset_id, variant_id, progress, "HTTP")


# P2P callbacks
func _on_p2p_completed(pack_id: String, asset_id: String, variant_id: String, _local_path: String) -> void:
	_remove_item(pack_id, asset_id, variant_id, true)


func _on_p2p_failed(pack_id: String, asset_id: String, variant_id: String, _error: String) -> void:
	_remove_item(pack_id, asset_id, variant_id, false)


func _on_p2p_progress(pack_id: String, asset_id: String, variant_id: String, progress: float) -> void:
	_add_or_update_item(pack_id, asset_id, variant_id, progress, "P2P")
