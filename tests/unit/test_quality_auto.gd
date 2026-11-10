extends GutTest

## Graphics quality presets and the first-run pick (card autoquality, 2026-11-10): QualityPreset's
## rows and matching, QualityAuto's decision table (a pure function of the measured frame and the
## adapter type, with its hysteresis), the once-per-install rule and record, QualityBench's pure
## parts and its headless end, the pick's flag, and the Settings row.

const TMP_SETTINGS := "user://test_quality_auto_settings.cfg"
const MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const PICK := preload("res://utils/quality/quality_pick.gd")
const DISCRETE := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
const INTEGRATED := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU

var _saved_cascades: int
var _saved_scale: int


func before_each() -> void:
	_saved_cascades = ShadowCascades.current
	_saved_scale = RenderScale.current


func after_each() -> void:
	ShadowCascades.current = _saved_cascades
	RenderScale.current = _saved_scale
	RenderingServer.directional_soft_shadow_filter_set_quality(SettingsMenu.DEFAULT_SHADOW_QUALITY)
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))


func test_high_is_exactly_the_rows_defaults() -> void:
	assert_eq(QualityPreset.DEFAULT, QualityPreset.HIGH)
	var none := QualityPreset.saved_rows(ConfigFile.new())
	assert_eq(QualityPreset.matching(none), QualityPreset.HIGH, "no settings file reads as High")
	assert_eq(none.shadow_quality, SettingsMenu.DEFAULT_SHADOW_QUALITY)
	assert_eq(none.shadow_cascades, ShadowCascades.DEFAULT)
	assert_eq(none.render_scale, RenderScale.DEFAULT)
	assert_eq(none.ssao_enabled, Constants.RENDERING_TOGGLES_DEFAULTS["ssao_enabled"])


func test_each_preset_matches_itself_and_a_changed_row_is_custom() -> void:
	for preset in QualityPreset.CHOICES:
		assert_eq(QualityPreset.matching(QualityPreset.rows_for(preset)), preset)
	var rows := QualityPreset.rows_for(QualityPreset.LOW)
	rows.render_scale = 85
	assert_eq(QualityPreset.matching(rows), QualityPreset.CUSTOM)
	assert_eq(QualityPreset.sanitize(9), QualityPreset.DEFAULT)


func test_lower_presets_only_lower_costs() -> void:
	var high := QualityPreset.rows_for(QualityPreset.HIGH)
	var low := QualityPreset.rows_for(QualityPreset.LOW)
	var lowest := QualityPreset.rows_for(QualityPreset.LOWEST)
	assert_false(low.ssao_enabled, "Low drops the occlusion")
	assert_true(low.shadow_quality <= high.shadow_quality)
	assert_eq(low.render_scale, RenderScale.FULL, "Low keeps the full render")
	assert_eq(lowest.render_scale, 75, "Lowest draws at 75 %")
	lowest.render_scale = RenderScale.FULL
	assert_eq(QualityPreset.matching(lowest), QualityPreset.LOW, "Lowest is Low at 75 %")


func test_write_then_saved_rows_round_trip() -> void:
	for preset in QualityPreset.CHOICES:
		var config := ConfigFile.new()
		QualityPreset.write(config, preset)
		assert_eq(QualityPreset.matching(QualityPreset.saved_rows(config)), preset)


func test_decide_reads_the_table() -> void:
	# The minspec2 estimates of the decision view (filled 200 ft home, defaults).
	assert_eq(QualityAuto.decide(4.8, DISCRETE), QualityPreset.HIGH, "RTX 3080")
	assert_eq(QualityAuto.decide(10.3, DISCRETE), QualityPreset.HIGH, "about 1.7x a 1060")
	assert_eq(QualityAuto.decide(17.5, DISCRETE), QualityPreset.LOW, "GTX 1060")
	assert_eq(QualityAuto.decide(42.0, INTEGRATED), QualityPreset.LOWEST, "Iris Xe")
	assert_eq(QualityAuto.decide(400.0, DISCRETE), QualityPreset.LOWEST, "the floor")


func test_decide_boundaries() -> void:
	var high_limit := QualityAuto.TARGET_MS * QualityAuto.DEFAULT_SHARE
	var low_limit := QualityAuto.TARGET_MS / QualityAuto.LOW_RATIO
	assert_eq(QualityAuto.decide(high_limit, DISCRETE), QualityPreset.HIGH)
	assert_eq(QualityAuto.decide(high_limit + 0.01, DISCRETE), QualityPreset.LOW)
	assert_eq(QualityAuto.decide(low_limit, DISCRETE), QualityPreset.LOW)
	assert_eq(QualityAuto.decide(low_limit + 0.01, DISCRETE), QualityPreset.LOWEST)


func test_measurement_wins_over_the_adapter_type() -> void:
	assert_eq(QualityAuto.decide(4.8, INTEGRATED), QualityPreset.HIGH, "a fast iGPU is fast")
	assert_eq(QualityAuto.decide(42.0, DISCRETE), QualityPreset.LOWEST, "a slow dGPU is slow")


func test_no_measurement_falls_back_on_the_adapter_type() -> void:
	for bad in [0.0, -1.0, NAN, INF]:
		assert_eq(QualityAuto.decide(bad, DISCRETE), QualityPreset.HIGH)
		assert_eq(QualityAuto.decide(bad, INTEGRATED), QualityPreset.LOW)
		assert_eq(QualityAuto.decide(bad, RenderingDevice.DEVICE_TYPE_CPU), QualityPreset.LOWEST)
	assert_eq(QualityAuto.fallback_for(RenderingDevice.DEVICE_TYPE_OTHER), QualityPreset.HIGH)
	assert_eq(QualityAuto.fallback_for(RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU), QualityPreset.LOWEST)


func test_a_rerun_leans_toward_the_preset_in_use() -> void:
	var high_limit := QualityAuto.TARGET_MS * QualityAuto.DEFAULT_SHARE
	var near := high_limit * 1.05
	assert_eq(QualityAuto.decide(near, DISCRETE), QualityPreset.LOW, "first run: just over")
	assert_eq(QualityAuto.decide(near, DISCRETE, QualityPreset.HIGH), QualityPreset.HIGH)
	var under := high_limit * 0.95
	assert_eq(QualityAuto.decide(under, DISCRETE), QualityPreset.HIGH, "first run: just under")
	assert_eq(QualityAuto.decide(under, DISCRETE, QualityPreset.LOW), QualityPreset.LOW)
	var low_limit := QualityAuto.TARGET_MS / QualityAuto.LOW_RATIO
	assert_eq(QualityAuto.decide(low_limit * 1.05, DISCRETE, QualityPreset.LOW), QualityPreset.LOW)
	assert_eq(
		QualityAuto.decide(low_limit * 0.95, DISCRETE, QualityPreset.LOWEST), QualityPreset.LOWEST
	)
	assert_eq(QualityAuto.decide(4.8, DISCRETE, QualityPreset.LOWEST), QualityPreset.HIGH)


func test_pending_only_once_and_never_over_saved_rows() -> void:
	var config := ConfigFile.new()
	assert_true(QualityAuto.pending(config), "a first run")
	config.set_value("graphics", "vsync", true)
	assert_false(QualityAuto.pending(config), "a player who saved any graphics row")
	var done := ConfigFile.new()
	done.set_value(QualityAuto.SECTION, QualityAuto.KEY_DONE, true)
	assert_false(QualityAuto.pending(done), "already picked")
	var audio_only := ConfigFile.new()
	audio_only.set_value("audio", "master", 80.0)
	assert_true(QualityAuto.pending(audio_only), "other sections do not count")


func test_a_high_pick_leaves_a_fresh_file_without_graphics_rows() -> void:
	var config := ConfigFile.new()
	QualityAuto.record(config, QualityPreset.HIGH, {"gpu_ms": 2.5, "adapter_type": DISCRETE})
	assert_false(config.has_section("graphics"), "same as no settings file")
	assert_eq(QualityAuto.recorded_preset(config), QualityPreset.HIGH)
	assert_false(QualityAuto.pending(config))
	assert_eq(config.get_value(QualityAuto.SECTION, QualityAuto.KEY_RULE), QualityAuto.RULE)


func test_a_low_pick_writes_its_rows() -> void:
	var config := ConfigFile.new()
	QualityAuto.record(config, QualityPreset.LOW, {"gpu_ms": 9.0, "adapter_type": DISCRETE})
	assert_eq(QualityPreset.matching(QualityPreset.saved_rows(config)), QualityPreset.LOW)
	assert_eq(QualityAuto.recorded_preset(config), QualityPreset.LOW)
	assert_eq(QualityAuto.recorded_preset(ConfigFile.new()), QualityPreset.CUSTOM)


func test_a_high_rerun_over_saved_rows_writes_high_back() -> void:
	var config := ConfigFile.new()
	QualityPreset.write(config, QualityPreset.LOWEST)
	QualityAuto.record(config, QualityPreset.HIGH, {"gpu_ms": 2.5, "adapter_type": DISCRETE})
	assert_eq(QualityPreset.matching(QualityPreset.saved_rows(config)), QualityPreset.HIGH)


func test_apply_rows_sets_what_later_maps_read() -> void:
	QualityPreset.apply_rows(QualityPreset.rows_for(QualityPreset.LOWEST), null, ConfigFile.new())
	assert_eq(ShadowCascades.current, QualityPreset.rows_for(QualityPreset.LOWEST).shadow_cascades)
	assert_eq(RenderScale.current, 75)
	QualityPreset.apply_rows(QualityPreset.rows_for(QualityPreset.HIGH), null, ConfigFile.new())
	assert_eq(ShadowCascades.current, ShadowCascades.DEFAULT)
	assert_eq(RenderScale.current, RenderScale.DEFAULT)


func test_the_flag_is_shipped_on_and_off_loads_nothing() -> void:
	assert_eq(OnDemand.QUALITY_FLAG, QualityAuto.FLAG_SETTING)
	assert_true(QualityAuto.applies_automatically(), "shipped on (board perf-look-quality-low: ship)")
	var saved: Variant = ProjectSettings.get_setting(QualityAuto.FLAG_SETTING)
	ProjectSettings.set_setting(QualityAuto.FLAG_SETTING, false)
	var parent := Node.new()
	add_child_autofree(parent)
	assert_false(QualityAuto.applies_automatically())
	assert_null(OnDemand.quality_pick(parent))
	assert_eq(parent.get_child_count(), 0)
	ProjectSettings.set_setting(QualityAuto.FLAG_SETTING, saved)


func test_bench_pure_parts() -> void:
	assert_eq(QualityBench.median(PackedFloat32Array([3.0, 1.0, 2.0])), 2.0)
	assert_eq(QualityBench.median(PackedFloat32Array([4.0, 1.0, 2.0, 3.0])), 2.5)
	assert_eq(QualityBench.median(PackedFloat32Array()), 0.0)
	var args := PackedStringArray(["--x", QualityBench.SCALE_ARG + "2"])
	assert_eq(QualityBench.scale_from_args(args, 1.0), 2.0)
	assert_eq(QualityBench.scale_from_args(PackedStringArray(), 1.0), 1.0)
	var falling := PackedFloat32Array()
	for i in 30:
		falling.append(6.0 - i * 0.1)
	assert_false(QualityBench.settled(falling), "times still falling: the clocks are rising")
	var flat := PackedFloat32Array()
	flat.resize(30)
	flat.fill(2.0)
	assert_true(QualityBench.settled(flat))
	assert_false(QualityBench.settled(flat.slice(0, 10)), "too few frames to tell")
	assert_eq(QualityBench.extra_load(14.0, 3.0), 4, "a paced 14 ms frame, 3 ms of GPU")
	assert_eq(QualityBench.extra_load(14.0, 7.0), 1, "a slower GPU fills it with one more")
	assert_eq(QualityBench.extra_load(14.0, 10.0), 0, "a GPU that fills the frame needs none")
	assert_eq(QualityBench.extra_load(3.0, 2.5), 0, "an unpaced frame needs none")
	assert_eq(QualityBench.extra_load(14.0, 0.5), QualityBench.LOAD_MAX)
	assert_eq(QualityBench.extra_load(14.0, 0.0), 0)
	var garbage := PackedStringArray([QualityBench.SCALE_ARG + "x"])
	assert_eq(QualityBench.scale_from_args(garbage, 1.5), 1.5, "unreadable: the fallback")


func test_bench_headless_reports_no_measurement() -> void:
	var bench := QualityBench.new()
	var got: Array[Dictionary] = []
	bench.measured.connect(func(result: Dictionary) -> void: got.append(result))
	add_child(bench)
	await wait_physics_frames(3)
	assert_eq(got.size(), 1, "measured once")
	assert_false(got[0].ok)
	assert_eq(got[0].gpu_ms, 0.0)
	assert_false(is_instance_valid(bench), "it freed itself")


func test_the_pick_writes_nothing_headless() -> void:
	var pick: Node = PICK.new()
	pick.settings_path = TMP_SETTINGS
	add_child(pick)
	await wait_physics_frames(3)
	assert_false(is_instance_valid(pick), "it freed itself")
	assert_false(FileAccess.file_exists(TMP_SETTINGS), "no settings file written")


func test_settings_row_selects_shows_and_marks_custom() -> void:
	var menu: SettingsMenu = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	var option: OptionButton = menu.get_node("%QualityOption")
	for preset in QualityPreset.CHOICES:
		assert_true(option.get_item_index(preset) >= 0, "preset %d offered" % preset)
	assert_false(option.tooltip_text.is_empty())
	menu._show_defaults()
	assert_eq(option.get_selected_id(), QualityPreset.HIGH, "defaults read as High")
	option.select(option.get_item_index(QualityPreset.LOWEST))
	option.item_selected.emit(option.selected)
	assert_eq(menu.render_scale_option.get_selected_id(), 75)
	assert_false(menu.ssao_check.button_pressed)
	menu._save_settings(TMP_SETTINGS)
	var config := ConfigFile.new()
	assert_eq(config.load(TMP_SETTINGS), OK)
	assert_eq(QualityPreset.matching(QualityPreset.saved_rows(config)), QualityPreset.LOWEST)
	menu.ssao_check.button_pressed = true
	assert_eq(option.get_selected_id(), QualityPreset.CUSTOM, "a changed row reads Custom")
	var note_row: Control = menu.get_node("%QualityNoteRow")
	assert_false(note_row.visible, "no pick recorded, no note")
