extends GutTest

## UiMotion, the one place UI motion is decided (docs/UI_TASTE.md M1-M6 and the 2026-11-15
## section): the duration bands, no overshoot on functional controls, the stagger cap, and
## Reduce motion (the saved key, and what the helpers and the panel base do under it).

const TEMP_PATH := "user://test_ui_motion.cfg"
const PANEL_FILES := [
	"res://scenes/ui/animated_canvas_layer_panel.gd",
	"res://scenes/ui/animated_visibility_container.gd",
	"res://scenes/ui/download_queue.gd",
	"res://scenes/ui/primitives/icon_button.gd",
	"res://scenes/ui/primitives/tile_row.gd",
	"res://scenes/states/playing/token_context_menu.gd",
	"res://scenes/states/playing/asset_browser_container.gd",
	"res://scenes/level_editor/level_editor.gd",
	"res://scenes/states/authoring/authoring_welcome.gd",
]


func before_each() -> void:
	UiPreferences.settings_path = TEMP_PATH
	UiMotion.user_reduce = false


func after_each() -> void:
	UiMotion.user_reduce = false
	UiPreferences.settings_path = Paths.SETTINGS_PATH
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_feedback_durations_are_90_to_120_ms() -> void:
	for seconds: float in [UiMotion.FEEDBACK_IN_S, UiMotion.FEEDBACK_OUT_S, UiMotion.PRESS_S]:
		assert_between(seconds, 0.09, 0.12, "feedback %.3f" % seconds)


func test_panels_and_menus_are_160_to_240_ms_and_leave_no_slower_than_they_arrive() -> void:
	for seconds: float in [UiMotion.PANEL_IN_S, UiMotion.PANEL_OUT_S, UiMotion.STATE_S]:
		assert_between(seconds, 0.16, 0.24, "panel %.3f" % seconds)
	assert_true(UiMotion.PANEL_OUT_S <= UiMotion.PANEL_IN_S, "an exit is not slower than its entrance")
	assert_true(UiMotion.FEEDBACK_OUT_S <= UiMotion.FEEDBACK_IN_S)
	assert_between(UiMotion.ENTRANCE_S, 0.16, 0.24)
	assert_lte(UiMotion.LARGE_MAX_S, 0.4, "nothing is longer than 400 ms")
	for seconds: float in [UiMotion.SOFT_IN_S, UiMotion.SOFT_OUT_S]:
		assert_lte(seconds, UiMotion.LARGE_MAX_S)


func test_constants_are_aliases_of_the_tokens() -> void:
	assert_eq(Constants.ANIM_HOVER_IN, UiMotion.FEEDBACK_IN_S)
	assert_eq(Constants.ANIM_HOVER_OUT, UiMotion.FEEDBACK_OUT_S)
	assert_eq(Constants.ANIM_PRESS, UiMotion.PRESS_S)
	assert_eq(Constants.ANIM_FADE_IN_DURATION, UiMotion.PANEL_IN_S)
	assert_eq(Constants.ANIM_FADE_OUT_DURATION, UiMotion.PANEL_OUT_S)
	assert_eq(Constants.ANIM_ENTRANCE, UiMotion.ENTRANCE_S)
	assert_eq(Constants.ANIM_ENTRANCE_STAGGER, UiMotion.STAGGER_S)


func test_arrivals_and_exits_have_no_overshoot() -> void:
	for trans: int in [UiMotion.ARRIVE_TRANS, UiMotion.EXIT_TRANS]:
		assert_false(
			[Tween.TRANS_BACK, Tween.TRANS_ELASTIC, Tween.TRANS_BOUNCE, Tween.TRANS_SPRING].has(trans)
		)
	assert_eq(UiMotion.CELEBRATE_TRANS, Tween.TRANS_BACK, "the one overshoot is named")


func test_no_panel_or_control_source_uses_an_overshoot_curve() -> void:
	for path: String in PANEL_FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("TRANS_BACK"), "%s: no TRANS_BACK" % path)
		assert_false(text.contains("TRANS_ELASTIC"), "%s: no TRANS_ELASTIC" % path)
		assert_false(text.contains("TRANS_BOUNCE"), "%s: no TRANS_BOUNCE" % path)


func test_stagger_is_20_to_30_ms_and_the_whole_entrance_is_capped() -> void:
	assert_between(UiMotion.STAGGER_S, 0.02, 0.03)
	for count: int in [2, 3, 5, 8, 20]:
		var step := UiMotion.stagger_step(count)
		assert_lte(step, UiMotion.STAGGER_S + 0.0001, "%d rows" % count)
		var total := UiMotion.ENTRANCE_S + step * float(count - 1)
		var note := "%d rows finish in time: %.3f" % [count, total]
		assert_lte(total, UiMotion.STAGGER_CAP_S + 0.0001, note)
	var short_step := UiMotion.stagger_step(3)
	assert_almost_eq(short_step, UiMotion.STAGGER_S, 0.0001, "a short list takes the full step")
	assert_eq(UiMotion.stagger_step(1), 0.0, "one row has nothing to stagger against")


func test_reduce_motion_defaults_off_and_round_trips() -> void:
	assert_false(UiPreferences.load_reduce_motion(), "off when nothing is saved")
	var config := ConfigFile.new()
	config.set_value("audio", "master", 0.5)
	config.save(TEMP_PATH)
	UiPreferences.save_reduce_motion(true)
	assert_true(UiPreferences.load_reduce_motion())
	assert_true(UiMotion.user_reduce, "saving applies it at once")
	var reread := ConfigFile.new()
	reread.load(TEMP_PATH)
	assert_eq(reread.get_value("audio", "master", -1.0), 0.5, "other sections kept")
	assert_true(reread.get_value(UiPreferences.SECTION, UiPreferences.KEY_REDUCE_MOTION, false))
	UiPreferences.save_reduce_motion(false)
	assert_false(UiPreferences.load_reduce_motion())
	assert_false(UiMotion.user_reduce)


func test_reduced_helpers_keep_fades_and_drop_travel() -> void:
	assert_eq(UiMotion.fade_s(0.3), 0.3)
	assert_eq(UiMotion.travel(12.0, 0.0), 12.0)
	UiMotion.user_reduce = true
	assert_true(UiMotion.reduced())
	assert_eq(UiMotion.fade_s(0.3), UiMotion.FADE_ONLY_S, "a long fade is cut short")
	assert_eq(UiMotion.fade_s(0.05), 0.05, "a shorter one is left")
	assert_eq(UiMotion.travel(12.0, 0.0), 0.0)
	assert_eq(UiMotion.travel(Vector2(0.9, 0.9), Vector2.ONE), Vector2.ONE)
	assert_eq(UiMotion.stagger_step(8), 0.0, "nothing staggers")


func test_reduced_scale_feedback_stays_at_rest_with_no_tween() -> void:
	var button := Button.new()
	add_child_autofree(button)
	UiMotion.user_reduce = true
	var tween := UiMotion.scale_to(button, null, Vector2(1.06, 1.06), 0.12, UiMotion.ARRIVE_TRANS)
	assert_null(tween)
	assert_eq(button.offset_transform_scale, Vector2.ONE)
	UiMotion.user_reduce = false
	tween = UiMotion.scale_to(button, null, Vector2(1.06, 1.06), 0.12, UiMotion.ARRIVE_TRANS)
	assert_not_null(tween, "full motion still tweens")
	tween.kill()


func test_reduced_stagger_fades_rows_together_with_no_lift() -> void:
	UiMotion.user_reduce = true
	var holder := VBoxContainer.new()
	add_child_autofree(holder)
	var rows: Array[Control] = []
	for i in 4:
		var row := Label.new()
		holder.add_child(row)
		rows.append(row)
	UiMotion.stagger_in(rows, holder)
	for row in rows:
		assert_eq(row.modulate.a, 0.0, "hidden before the first frame")
	await wait_seconds(UiMotion.FADE_ONLY_S + 0.2)
	for row in rows:
		assert_almost_eq(row.modulate.a, 1.0, 0.01)
		assert_eq(row.offset_transform_position, Vector2.ZERO, "no lift under Reduce motion")


func test_full_motion_stagger_lifts_with_the_offset_transform_not_position() -> void:
	var holder := VBoxContainer.new()
	add_child_autofree(holder)
	var rows: Array[Control] = []
	for i in 3:
		var row := Label.new()
		holder.add_child(row)
		rows.append(row)
	UiMotion.stagger_in(rows, holder)
	await wait_frames(4)
	assert_gt(rows[2].offset_transform_position.y, 0.0, "the last row has not arrived yet")
	for row in rows:
		assert_eq(row.position.x, 0.0)
	await wait_seconds(UiMotion.STAGGER_CAP_S + 0.2)
	for row in rows:
		assert_almost_eq(row.modulate.a, 1.0, 0.01)
		assert_almost_eq(row.offset_transform_position.y, 0.0, 0.01)


func test_reduced_panel_enters_with_no_scale() -> void:
	UiMotion.user_reduce = true
	var panel := AnimatedCanvasLayerPanel.new()
	var backdrop := ColorRect.new()
	backdrop.name = "ColorRect"
	panel.add_child(backdrop)
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	panel.add_child(center)
	var sheet := PanelContainer.new()
	sheet.name = "PanelContainer"
	center.add_child(sheet)
	panel.play_sounds = false
	add_child_autofree(panel)
	assert_eq(sheet.scale, Vector2.ONE, "no scale-in under Reduce motion")
	await wait_seconds(UiMotion.FADE_ONLY_S + 0.15)
	assert_almost_eq(center.modulate.a, 1.0, 0.01, "the fade still arrives")


func test_full_motion_panel_starts_slightly_small_and_never_overshoots() -> void:
	var panel := AnimatedCanvasLayerPanel.new()
	var backdrop := ColorRect.new()
	backdrop.name = "ColorRect"
	panel.add_child(backdrop)
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	panel.add_child(center)
	var sheet := PanelContainer.new()
	sheet.name = "PanelContainer"
	center.add_child(sheet)
	panel.play_sounds = false
	add_child_autofree(panel)
	assert_almost_eq(sheet.scale.x, UiMotion.PANEL_SCALE_FROM, 0.001)
	var peak := 0.0
	for i in 30:
		await wait_frames(1)
		peak = maxf(peak, sheet.scale.x)
	assert_lte(peak, 1.0 + 0.0001, "ease out settles at 1.0 and does not pass it")
