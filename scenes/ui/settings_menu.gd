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
	
	# Load current settings
	_load_settings()
	_populate_controls_list()
	
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
	
	config.save(SETTINGS_PATH)


func _apply_settings() -> void:
	# Apply audio settings
	_apply_audio_bus("Master", master_slider.value)
	_apply_audio_bus("Music", music_slider.value)
	_apply_audio_bus("SFX", sfx_slider.value)
	_apply_audio_bus("UI", ui_slider.value)
	
	# Apply graphics settings
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	)


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
