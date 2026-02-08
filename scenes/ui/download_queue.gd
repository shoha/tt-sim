extends CanvasLayer
class_name DownloadQueue

## UI widget showing active asset downloads.
##
## Displays a compact icon in the bottom-left corner when downloads are in progress.
## Clicking the icon expands a detailed panel showing download progress.

const MAX_VISIBLE_ITEMS := 3
const HIDE_DELAY := 2.0  # Seconds to wait before hiding after all downloads complete
const PULSE_SPEED := 3.0  # Pulse animation speed

# Theme colors (matching dark_theme.gd)
const COLOR_ACCENT := Color("#db924b")
const COLOR_SURFACE2 := Color("#3e2b3c")
const COLOR_SURFACE3 := Color("#50374d")
const COLOR_TEXT_ON_ACCENT := Color("#2c1f2b")

@onready var icon_button: Button = %IconButton
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var title_label: Label = %TitleLabel
@onready var items_container: VBoxContainer = %ItemsContainer
@onready var queue_label: Label = %QueueLabel

var _download_items: Dictionary = {}  # key -> {container, label, progress_bar}
var _hide_timer: Timer
var _is_icon_visible: bool = false
var _is_panel_expanded: bool = false
var _tween: Tween
var _pulse_time: float = 0.0
var _badge_container: PanelContainer
var _badge_label: Label


func _ready() -> void:
	# Start hidden
	icon_button.visible = false
	detail_panel.visible = false
	detail_panel.modulate.a = 0.0

	# Connect button
	icon_button.pressed.connect(_on_icon_pressed)

	# Create badge as child of button
	_create_badge()

	# Create hide timer
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_on_hide_timer_timeout)
	add_child(_hide_timer)

	# Connect to download signals
	_connect_signals()

	# No need to process when icon is hidden
	set_process(false)


func _create_badge() -> void:
	_badge_container = PanelContainer.new()
	_badge_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge_container.offset_left = -14
	_badge_container.offset_right = 4
	_badge_container.offset_top = -6
	_badge_container.offset_bottom = 10
	_badge_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style with theme accent color
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_ACCENT
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	_badge_container.add_theme_stylebox_override("panel", style)

	icon_button.add_child(_badge_container)

	_badge_label = Label.new()
	_badge_label.text = "0"
	_badge_label.add_theme_font_size_override("font_size", 11)
	_badge_label.add_theme_color_override("font_color", COLOR_TEXT_ON_ACCENT)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_container.add_child(_badge_label)


func _connect_signals() -> void:
	AssetDownloader.download_completed.connect(_on_download_completed)
	AssetDownloader.download_failed.connect(_on_download_failed)
	AssetDownloader.download_progress.connect(_on_download_progress)

	AssetStreamer.asset_received.connect(_on_p2p_completed)
	AssetStreamer.asset_failed.connect(_on_p2p_failed)
	AssetStreamer.transfer_progress.connect(_on_p2p_progress)


func _process(delta: float) -> void:
	_update_queue_count()

	# Pulse animation for icon button when not expanded
	if _is_icon_visible and not _is_panel_expanded:
		_pulse_time += delta * PULSE_SPEED
		var pulse = 0.85 + 0.15 * sin(_pulse_time)
		icon_button.modulate = Color(pulse, pulse, pulse, 1.0)


func _add_or_update_item(
	pack_id: String, asset_id: String, variant_id: String, progress: float, source: String = "HTTP"
) -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]

	if not _is_icon_visible:
		_show_icon()

	_hide_timer.stop()

	if _download_items.has(key):
		var item = _download_items[key]
		item.progress_bar.value = progress * 100.0
	else:
		var container = HBoxContainer.new()
		container.add_theme_constant_override("separation", 8)
		container.alignment = BoxContainer.ALIGNMENT_CENTER

		# Source indicator (Caption style)
		var source_label = Label.new()
		source_label.theme_type_variation = "Caption"
		source_label.text = "[%s]" % source
		source_label.custom_minimum_size = Vector2(40, 0)
		source_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		container.add_child(source_label)

		# Asset name (Body style)
		var display_name = AssetPackManager.get_asset_display_name(pack_id, asset_id)
		var label = Label.new()
		label.theme_type_variation = "Body"
		label.text = display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.clip_text = true
		label.custom_minimum_size = Vector2(120, 0)
		container.add_child(label)

		# Progress bar
		var progress_bar = ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(80, 16)
		progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress_bar.value = progress * 100.0
		progress_bar.show_percentage = false
		container.add_child(progress_bar)

		items_container.add_child(container)

		_download_items[key] = {
			"container": container, "label": label, "progress_bar": progress_bar, "source": source
		}

		# Animate in
		container.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(container, "modulate:a", 1.0, 0.15)

		_limit_visible_items()

	_update_badge()


func _remove_item(pack_id: String, asset_id: String, variant_id: String, success: bool) -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]

	if not _download_items.has(key):
		return

	var item = _download_items[key]
	var container = item.container

	if success:
		item.progress_bar.value = 100.0
		item.progress_bar.modulate = Color(0.5, 0.8, 0.5)
		AudioManager.play_success()
	else:
		item.progress_bar.modulate = Color(0.8, 0.4, 0.4)
		AudioManager.play_error()

	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_property(container, "modulate:a", 0.0, 0.2)
	tween.tween_callback(
		func():
			container.queue_free()
			_download_items.erase(key)
			_update_badge()
			_check_hide_icon()
	)


func _limit_visible_items() -> void:
	var items = items_container.get_children()
	for i in range(items.size()):
		items[i].visible = i < MAX_VISIBLE_ITEMS


func _update_badge() -> void:
	var count = _download_items.size()
	_badge_label.text = str(count)
	_badge_container.visible = count > 0


func _update_queue_count() -> void:
	var http_queued = 0
	var p2p_queued = 0

	http_queued = AssetDownloader.get_queued_download_count()

	p2p_queued = AssetStreamer.get_queued_request_count()

	var total_queued = http_queued + p2p_queued
	var total_active = _download_items.size()

	if total_queued > 0:
		queue_label.text = "+ %d more in queue" % total_queued
		queue_label.visible = true
	else:
		queue_label.visible = false

	if total_active > 0:
		title_label.text = "Downloading Assets (%d)" % total_active
	else:
		title_label.text = "Downloading Assets"


func _check_hide_icon() -> void:
	if _download_items.is_empty():
		_hide_timer.start(HIDE_DELAY)


func _show_icon() -> void:
	_is_icon_visible = true
	_pulse_time = 0.0
	icon_button.visible = true
	icon_button.modulate.a = 0.0
	set_process(true)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(icon_button, "modulate:a", 1.0, 0.2)


func _hide_icon() -> void:
	if _is_panel_expanded:
		_collapse_panel()

	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(icon_button, "modulate:a", 0.0, 0.15)
	tween.tween_callback(
		func():
			icon_button.visible = false
			_is_icon_visible = false
			set_process(false)
	)


func _expand_panel() -> void:
	_is_panel_expanded = true
	detail_panel.visible = true
	detail_panel.modulate.a = 0.0
	detail_panel.pivot_offset = detail_panel.size / 2
	detail_panel.scale = Vector2(0.9, 0.9)
	icon_button.modulate = Color.WHITE

	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property(detail_panel, "modulate:a", 1.0, 0.15)
	_tween.tween_property(detail_panel, "scale", Vector2.ONE, 0.2)

	AudioManager.play_open()


func _collapse_panel() -> void:
	if _tween:
		_tween.kill()

	detail_panel.pivot_offset = detail_panel.size / 2

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(detail_panel, "modulate:a", 0.0, 0.1)
	_tween.tween_property(detail_panel, "scale", Vector2(0.95, 0.95), 0.1)
	_tween.chain().tween_callback(
		func():
			detail_panel.visible = false
			_is_panel_expanded = false
	)

	AudioManager.play_close()


func _on_icon_pressed() -> void:
	if _is_panel_expanded:
		_collapse_panel()
	else:
		_expand_panel()


func _on_hide_timer_timeout() -> void:
	if _download_items.is_empty():
		_hide_icon()


# HTTP Download callbacks
func _on_download_completed(
	pack_id: String, asset_id: String, variant_id: String, _local_path: String
) -> void:
	_remove_item(pack_id, asset_id, variant_id, true)


func _on_download_failed(
	pack_id: String, asset_id: String, variant_id: String, _error: String
) -> void:
	_remove_item(pack_id, asset_id, variant_id, false)


func _on_download_progress(
	pack_id: String, asset_id: String, variant_id: String, progress: float
) -> void:
	_add_or_update_item(pack_id, asset_id, variant_id, progress, "HTTP")


# P2P callbacks
func _on_p2p_completed(
	pack_id: String, asset_id: String, variant_id: String, _local_path: String
) -> void:
	_remove_item(pack_id, asset_id, variant_id, true)


func _on_p2p_failed(pack_id: String, asset_id: String, variant_id: String, _error: String) -> void:
	_remove_item(pack_id, asset_id, variant_id, false)


func _on_p2p_progress(
	pack_id: String, asset_id: String, variant_id: String, progress: float
) -> void:
	_add_or_update_item(pack_id, asset_id, variant_id, progress, "P2P")
