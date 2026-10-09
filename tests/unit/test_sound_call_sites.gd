extends GutTest

## Sounds mark what the player did, not code putting controls in step: Settings opens and
## resets without a burst of ticks, a toggle ticks on a click but not when code sets it,
## token_hover chirps only for a token the player can drag and once per 150 ms sweep,
## finished download variants are silent (the pack's toast speaks once), and the volume
## sliders follow a squared taper. Checked on AudioManager.sound_requested, which reports
## every play() call before coalescing could hide one.

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const DOWNLOAD_QUEUE_SCENE := preload("res://scenes/ui/download_queue.tscn")
const PACK_ID := "_test_sound_call_sites_pack"
## SettingsMenu tweens its sliders home over 0.3 s on Reset.
const RESET_TWEEN_S := 0.3

var _requested: Array[StringName] = []


func before_each() -> void:
	_requested.clear()
	AudioManager.sound_requested.connect(_on_sound_requested)


func after_each() -> void:
	AudioManager.sound_requested.disconnect(_on_sound_requested)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _on_sound_requested(sound: StringName) -> void:
	_requested.append(sound)


func _count(sound: StringName) -> int:
	return _requested.count(sound)


# --- settings ------------------------------------------------------------------


func _open_settings() -> SettingsMenu:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	return menu


func _checks(menu: SettingsMenu) -> Array[CheckButton]:
	return [
		menu.fullscreen_check,
		menu.vsync_check,
		menu.lofi_check,
		menu.occlusion_fade_check,
		menu.ssao_check,
		menu.ssr_check,
		menu.sdfgi_check,
		menu.p2p_enabled_check,
		menu.prereleases_check,
	]


func _sliders(menu: SettingsMenu) -> Array[HSlider]:
	return [
		menu.master_slider,
		menu.sfx_slider,
		menu.ui_slider,
		menu.cell_tint_opacity_slider,
		menu.line_thickness_slider,
		menu.fade_distance_slider,
		menu.foliage_density_slider,
	]


func test_opening_settings_requests_no_tick() -> void:
	_open_settings()
	await wait_process_frames(2)
	assert_eq(_count(&"tick"), 0)


func test_showing_saved_values_is_silent_and_emits_no_signals() -> void:
	var menu := _open_settings()
	for check in _checks(menu):
		check.set_pressed_no_signal(false)
	for slider in _sliders(menu):
		slider.set_value_no_signal(slider.min_value)
	var config := ConfigFile.new()
	config.set_value("audio", "master", 40.0)
	config.set_value("audio", "sfx", 30.0)
	config.set_value("audio", "ui", 20.0)
	config.set_value("graphics", "fullscreen", true)
	config.set_value("graphics", "vsync", true)
	config.set_value("graphics", "lofi_enabled", true)
	config.set_value("network", "p2p_enabled", true)
	config.set_value("grid_visuals", "line_thickness", 3.0)
	for check in _checks(menu):
		watch_signals(check)
	for slider in _sliders(menu):
		watch_signals(slider)

	menu._show_saved_values(config)

	assert_eq(_count(&"tick"), 0)
	for check in _checks(menu):
		assert_signal_not_emitted(check, "toggled", str(check.name))
	for slider in _sliders(menu):
		assert_signal_not_emitted(slider, "value_changed", str(slider.name))
	assert_true(menu.fullscreen_check.button_pressed, "the saved values are shown")
	assert_eq(menu.master_slider.value, 40.0)
	assert_eq(menu.line_thickness_slider.value, 3.0)


func test_reset_is_silent_until_the_sliders_land_then_a_drag_ticks() -> void:
	var menu := _open_settings()
	await wait_process_frames(2)
	for check in _checks(menu):
		check.set_pressed_no_signal(not check.button_pressed)
	for slider in _sliders(menu):
		slider.set_value_no_signal(slider.min_value)
	_requested.clear()

	# _show_defaults is Reset without the two preferences that save to disk at once.
	menu._show_defaults()
	await wait_seconds(RESET_TWEEN_S + 0.1)

	assert_eq(_count(&"tick"), 0, "Reset's click is the whole sound of the gesture")
	assert_eq(menu.master_slider.value, 100.0, "the sliders tweened home")
	assert_eq(menu.master_label.text, "100%", "and their handlers ran")
	assert_false(menu._resetting)
	menu.cell_tint_opacity_slider.value = 50.0
	assert_eq(_count(&"tick"), 1, "a slider the user moves ticks again")


func test_the_music_row_is_hidden_until_there_is_music() -> void:
	var menu := _open_settings()
	assert_false(SettingsMenu.SHOW_MUSIC_VOLUME)
	assert_false(menu.music_slider.get_parent().visible)
	assert_true(menu.master_slider.get_parent().visible)


# --- toggles -------------------------------------------------------------------


func test_a_toggle_set_from_code_is_silent_and_a_click_ticks() -> void:
	var check := CheckButton.new()
	add_child_autofree(check)
	check.button_pressed = true
	check.button_pressed = false
	assert_eq(_count(&"tick"), 0, "code set the toggle")
	assert_eq(_count(&"click"), 0)
	# A click flips the state, then emits pressed.
	check.button_pressed = true
	check.pressed.emit()
	assert_eq(_count(&"tick"), 1)
	assert_eq(_count(&"click"), 0, "a toggle ticks instead of clicking")


# --- token hover ---------------------------------------------------------------


func _hover_controller(dragging_allowed: bool) -> BoardTokenController:
	var draggable: DraggableToken = autofree(DraggableToken.new())
	draggable.dragging_allowed = dragging_allowed
	var controller: BoardTokenController = autofree(BoardTokenController.new())
	controller.draggable_token = draggable
	return controller


func test_hover_chirps_only_for_a_token_the_player_can_drag() -> void:
	_hover_controller(false)._on_mouse_entered()
	assert_eq(_count(&"token_hover"), 0, "no CONTROL permission, or another peer's drag lock")
	_hover_controller(true)._on_mouse_entered()
	assert_eq(_count(&"token_hover"), 1)
	var bare: BoardTokenController = autofree(BoardTokenController.new())
	assert_false(bare.wants_hover_sound(), "nothing to drag")


func test_a_sweep_across_six_tokens_chirps_once_per_cooldown() -> void:
	var entry := AudioManager.sound_entry(&"token_hover")
	assert_almost_eq(float(entry["cooldown_s"]), 0.15, 0.0001)
	var queue := SoundRequestQueue.new({&"token_hover": entry})
	var heard := 0
	for i in range(6):
		var now_s := i * 0.04
		queue.request(&"token_hover", now_s)
		heard += queue.flush(now_s).size()
	assert_eq(heard, 2, "at 0 ms and 160 ms, not six times")


# --- downloads -----------------------------------------------------------------


func test_finished_variants_are_silent_and_a_pack_chimes_once() -> void:
	var queue: DownloadQueue = DOWNLOAD_QUEUE_SCENE.instantiate()
	add_child_autofree(queue)
	for i in range(5):
		queue._on_p2p_progress(PACK_ID, "asset", "v%d" % i, 0.5)
	_requested.clear()

	for i in range(4):
		queue._on_p2p_completed(PACK_ID, "asset", "v%d" % i, "")
	queue._on_p2p_failed(PACK_ID, "asset", "v4", "test failure")
	assert_eq(_requested, [] as Array[StringName], "no sound per variant")

	queue._add_or_update_pack_item(PACK_ID, 1, 2)
	_requested.clear()
	queue._remove_pack_item(PACK_ID, true)
	assert_eq(_count(&"success"), 1, "the toast's own chime, once")


# --- bus volumes ---------------------------------------------------------------


func test_volume_sliders_use_a_squared_taper() -> void:
	assert_almost_eq(AudioManager.slider_to_db(1.0), 0.0, 0.001)
	assert_almost_eq(AudioManager.slider_to_db(0.5), -12.04, 0.01)
	assert_almost_eq(AudioManager.slider_to_db(0.1), -40.0, 0.01)
	assert_eq(AudioManager.slider_to_db(0.0), -INF)
	assert_almost_eq(AudioManager.db_to_slider(AudioManager.slider_to_db(0.3)), 0.3, 0.0001)
