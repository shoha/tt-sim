extends CanvasLayer
class_name SettingsMenu

## Settings menu with Audio, Graphics, and Controls tabs.
##
## Integrates with UIManager for proper overlay handling.
## Settings are saved to user://settings.cfg

signal closed

const SETTINGS_PATH := "user://settings.cfg"

# Audio controls
@onready var master_slider: HSlider = %MasterVolumeSlider
@onready var master_label: Label = %MasterVolumeLabel
@onready var music_slider: HSlider = %MusicVolumeSlider
@onready var music_label: Label = %MusicVolumeLabel
@onready var sfx_slider: HSlider = %SFXVolumeSlider
@onready var sfx_label: Label = %SFXVolumeLabel
@onready var ui_slider: HSlider = %UIVolumeSlider
@onready var ui_label: Label = %UIVolumeLabel

# Graphics controls
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var vsync_check: CheckButton = %VSyncCheck

# Controls display
@onready var controls_list: VBoxContainer = %ControlsList

# Network controls
@onready var p2p_enabled_check: CheckButton = %P2PEnabledCheck
@onready var clear_cache_button: Button = %ClearCacheButton
@onready var cache_info_label: Label = %CacheInfo

# Update controls
@onready var version_label: Label = %VersionLabel
@onready var prereleases_check: CheckButton = %PrereleasesCheck
@onready var check_updates_button: Button = %CheckUpdatesButton
@onready var update_status_label: Label = %UpdateStatus

# Buttons
@onready var close_button: Button = %CloseButton
@onready var reset_button: Button = %ResetButton
@onready var apply_button: Button = %ApplyButton

var _tween: Tween


func _ready() -> void:
	# Connect UI signals
	close_button.pressed.connect(_on_close_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	apply_button.pressed.connect(_on_apply_pressed)
	
	# Audio sliders
	master_slider.value_changed.connect(_on_master_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	ui_slider.value_changed.connect(_on_ui_volume_changed)
	
	# Graphics
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	
	# Network
	p2p_enabled_check.toggled.connect(_on_p2p_toggled)
	clear_cache_button.pressed.connect(_on_clear_cache_pressed)
	
	# Updates
	prereleases_check.toggled.connect(_on_prereleases_toggled)
	check_updates_button.pressed.connect(_on_check_updates_pressed)
	UpdateManager.update_check_complete.connect(_on_update_check_complete)
	UpdateManager.update_check_failed.connect(_on_update_check_failed)
	UpdateManager.update_available.connect(_on_update_available)
	
	# Load current settings
	_load_settings()
	_populate_controls_list()
	_update_cache_info()
	_update_version_info()
	
	# Register as overlay (cast to Control for type compatibility)
	UIManager.register_overlay($ColorRect as Control)
	
	# Animate in
	_set_alpha(0.0)
	_animate_in()


func _set_alpha(alpha: float) -> void:
	$ColorRect.modulate.a = alpha
	$CenterContainer.modulate.a = alpha


func _populate_controls_list() -> void:
	# Clear existing
	for child in controls_list.get_children():
		child.queue_free()
	
	# Add control hints
	var controls = [
		["Left Click + Drag", "Move token"],
		["Right Click", "Open context menu"],
		["Scroll Wheel", "Zoom camera"],
		["Middle Click + Drag", "Pan camera"],
		["ESC", "Pause / Close menu"],
	]
	
	for control in controls:
		var hbox = HBoxContainer.new()
		
		var key_label = Label.new()
		key_label.text = control[0]
		key_label.theme_type_variation = "Body"
		key_label.custom_minimum_size = Vector2(180, 0)
		hbox.add_child(key_label)
		
		var action_label = Label.new()
		action_label.text = control[1]
		action_label.theme_type_variation = "Caption"
		hbox.add_child(action_label)
		
		controls_list.add_child(hbox)


func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	
	if err == OK:
		master_slider.value = config.get_value("audio", "master", 100.0)
		music_slider.value = config.get_value("audio", "music", 100.0)
		sfx_slider.value = config.get_value("audio", "sfx", 100.0)
		ui_slider.value = config.get_value("audio", "ui", 100.0)
		fullscreen_check.button_pressed = config.get_value("graphics", "fullscreen", false)
		vsync_check.button_pressed = config.get_value("graphics", "vsync", true)
		p2p_enabled_check.button_pressed = config.get_value("network", "p2p_enabled", true)
		prereleases_check.button_pressed = config.get_value("updates", "check_prereleases", false)
	
	# Update labels
	_update_volume_label(master_label, master_slider.value)
	_update_volume_label(music_label, music_slider.value)
	_update_volume_label(sfx_label, sfx_slider.value)
	_update_volume_label(ui_label, ui_slider.value)


func _save_settings() -> void:
	var config = ConfigFile.new()
	
	config.set_value("audio", "master", master_slider.value)
	config.set_value("audio", "music", music_slider.value)
	config.set_value("audio", "sfx", sfx_slider.value)
	config.set_value("audio", "ui", ui_slider.value)
	config.set_value("graphics", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("graphics", "vsync", vsync_check.button_pressed)
	config.set_value("network", "p2p_enabled", p2p_enabled_check.button_pressed)
	config.set_value("updates", "check_prereleases", prereleases_check.button_pressed)
	
	config.save(SETTINGS_PATH)


func _apply_settings() -> void:
	# Apply audio settings
	_apply_audio_bus("Master", master_slider.value)
	_apply_audio_bus("Music", music_slider.value)
	_apply_audio_bus("SFX", sfx_slider.value)
	_apply_audio_bus("UI", ui_slider.value)
	
	# Apply graphics settings - only change mode if different to avoid macOS toggle issue
	var current_mode := DisplayServer.window_get_mode()
	var is_currently_fullscreen := current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	
	if fullscreen_check.button_pressed and not is_currently_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen_check.button_pressed and is_currently_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	)
	
	# Apply network settings
	_apply_network_settings()


func _apply_network_settings() -> void:
	if has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		streamer.set_enabled(p2p_enabled_check.button_pressed)


func _apply_audio_bus(bus_name: String, volume_percent: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var db = linear_to_db(volume_percent / 100.0)
		AudioServer.set_bus_volume_db(bus_idx, db)


func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(value)


func _on_master_volume_changed(value: float) -> void:
	_update_volume_label(master_label, value)


func _on_music_volume_changed(value: float) -> void:
	_update_volume_label(music_label, value)


func _on_sfx_volume_changed(value: float) -> void:
	_update_volume_label(sfx_label, value)


func _on_ui_volume_changed(value: float) -> void:
	_update_volume_label(ui_label, value)


func _on_fullscreen_toggled(_pressed: bool) -> void:
	pass


func _on_vsync_toggled(_pressed: bool) -> void:
	pass


func _on_close_pressed() -> void:
	animate_out()


func _on_reset_pressed() -> void:
	master_slider.value = 100.0
	music_slider.value = 100.0
	sfx_slider.value = 100.0
	ui_slider.value = 100.0
	fullscreen_check.button_pressed = false
	vsync_check.button_pressed = true
	p2p_enabled_check.button_pressed = true
	prereleases_check.button_pressed = false


func _on_p2p_toggled(_pressed: bool) -> void:
	pass


func _on_clear_cache_pressed() -> void:
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		downloader.clear_all_caches()
		_update_cache_info()
		
		if UIManager.has_method("show_toast"):
			UIManager.show_toast("Asset cache cleared", 1) # SUCCESS type


func _update_cache_info() -> void:
	var cache_size = _get_cache_size()
	var size_text = _format_size(cache_size)
	cache_info_label.text = "Cache size: %s\nClearing will force re-download of assets." % size_text


func _get_cache_size() -> int:
	var cache_dir = "user://asset_cache/"
	if not DirAccess.dir_exists_absolute(cache_dir):
		return 0
	return _get_dir_size(cache_dir)


func _get_dir_size(path: String) -> int:
	var total_size = 0
	var dir = DirAccess.open(path)
	if not dir:
		return 0
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = path + "/" + file_name
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				total_size += _get_dir_size(full_path)
		else:
			var file = FileAccess.open(full_path, FileAccess.READ)
			if file:
				total_size += file.get_length()
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()
	
	return total_size


func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.1f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))


func _on_apply_pressed() -> void:
	_apply_settings()
	_save_settings()
	
	if UIManager.has_method("show_toast"):
		UIManager.show_toast("Settings saved", 0) # INFO type


func _animate_in() -> void:
	if _tween:
		_tween.kill()
	
	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.9, 0.9)
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property($ColorRect, "modulate:a", 1.0, 0.2)
	_tween.tween_property($CenterContainer, "modulate:a", 1.0, 0.2)
	_tween.tween_property(panel, "scale", Vector2.ONE, 0.2)


func animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	
	if _tween:
		_tween.kill()
	
	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property($ColorRect, "modulate:a", 0.0, 0.15)
	_tween.tween_property($CenterContainer, "modulate:a", 0.0, 0.15)
	_tween.tween_property(panel, "scale", Vector2(0.95, 0.95), 0.15)
	
	await _tween.finished
	closed.emit()
	queue_free()


func _update_version_info() -> void:
	version_label.text = "v" + UpdateManager.get_current_version()


func _on_prereleases_toggled(pressed: bool) -> void:
	UpdateManager.set_prerelease_enabled(pressed)


func _on_check_updates_pressed() -> void:
	check_updates_button.disabled = true
	update_status_label.text = "Checking for updates..."
	UpdateManager.check_for_updates()


func _on_update_check_complete(has_update: bool) -> void:
	check_updates_button.disabled = false
	if not has_update:
		update_status_label.text = "You're up to date!"


func _on_update_check_failed(error: String) -> void:
	check_updates_button.disabled = false
	update_status_label.text = "Check failed: " + error


func _on_update_available(release_info: Dictionary) -> void:
	check_updates_button.disabled = false
	var version = release_info.get("version", "?")
	update_status_label.text = "Update available: v" + version
	
	# Show the update dialog
	var dialog_scene = preload("res://scenes/ui/update_dialog.tscn")
	var dialog = dialog_scene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(release_info)
