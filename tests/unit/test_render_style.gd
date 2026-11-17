extends GutTest

## RenderStyle (painter/render_style.gd, docs/systems/painter.md): the preset-to-mood table covers
## every environment preset, the Settings choice overrides the map's look, a Classic-only preset
## always draws Classic, and the level's `look` field survives the level codec and a late-join
## snapshot.

const CLASSIC_ONLY: Array[String] = [
	"indoor_neutral",
	"dungeon_dark",
	"dungeon_crypt",
	"cave",
	"tavern",
	"underwater",
	"hell",
	"ethereal",
	"none",
	"bright_editor",
]

var _saved_choice: int = RenderStyle.DEFAULT_CHOICE


func before_each() -> void:
	_saved_choice = RenderStyle.choice


func after_each() -> void:
	RenderStyle.choice = _saved_choice
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._current_level_dict.clear()


func test_every_preset_is_in_the_mood_table() -> void:
	var presets: Array = EnvironmentPresets.PRESETS.keys()
	assert_eq(presets.size(), 18, "the 18 presets the table was written for")
	for preset: String in presets:
		assert_true(RenderStyle.MOOD_FOR_PRESET.has(preset), "%s is in the table" % preset)
	for preset: String in RenderStyle.MOOD_FOR_PRESET:
		assert_true(preset == "" or presets.has(preset), "%s is a real preset" % preset)


func test_the_table_names_only_sheet_moods_and_the_indoor_presets_are_classic_only() -> void:
	for preset: String in RenderStyle.MOOD_FOR_PRESET:
		var mood := RenderStyle.mood_for_preset(preset)
		if CLASSIC_ONLY.has(preset):
			assert_eq(mood, "", "%s is Classic only" % preset)
		else:
			assert_true(PainterSheet.MOODS.has(mood), "%s paints as a sheet mood (%s)" % [preset, mood])


func test_the_settings_choice_overrides_the_maps_look() -> void:
	var painted := {"style": RenderStyle.PAINTED, "sheet": "", "mood": ""}
	var classic := {"style": RenderStyle.CLASSIC, "sheet": "", "mood": ""}
	var c := RenderStyle.resolve(painted, "outdoor_day", RenderStyle.CHOICE_CLASSIC)
	assert_eq(c["style"], RenderStyle.CLASSIC, "Classic in Settings wins over a painted map")
	var p := RenderStyle.resolve(classic, "outdoor_day", RenderStyle.CHOICE_PAINTED)
	assert_eq(p["style"], RenderStyle.PAINTED, "Painted in Settings wins over a classic map")
	assert_eq(p["mood"], "summer")
	assert_eq(p["sheet"], RenderStyle.DEFAULT_SHEET)
	var m := RenderStyle.resolve(painted, "outdoor_sunset", RenderStyle.CHOICE_MAP)
	assert_eq(m["style"], RenderStyle.PAINTED, "Map's choice follows the map")
	assert_eq(m["mood"], "dusk", "an unset mood comes from the preset")
	var unset := RenderStyle.resolve({}, "outdoor_day", RenderStyle.CHOICE_MAP)
	assert_eq(unset["style"], RenderStyle.CLASSIC, "a map with no look is Classic")


func test_the_default_choice_is_painted_and_draws_every_outdoor_map_painted() -> void:
	assert_eq(RenderStyle.DEFAULT_CHOICE, RenderStyle.CHOICE_PAINTED)
	assert_eq(RenderStyle.stored(ConfigFile.new()), RenderStyle.CHOICE_PAINTED, "no file")
	var classic_look := {"style": RenderStyle.CLASSIC}
	var drawn := RenderStyle.resolve(classic_look, "arctic", RenderStyle.DEFAULT_CHOICE)
	assert_eq(drawn["style"], RenderStyle.PAINTED)
	assert_eq(drawn["mood"], "winter")
	var indoor := RenderStyle.resolve({}, "tavern", RenderStyle.DEFAULT_CHOICE)
	assert_eq(indoor["style"], RenderStyle.CLASSIC, "a preset no mood paints is still Classic")


func test_a_file_that_never_stored_the_look_is_painted() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "shadow_quality", 2)
	assert_eq(RenderStyle.stored(config), RenderStyle.CHOICE_PAINTED, "other rows, no look")


func test_an_unversioned_classic_is_the_old_default_and_reads_as_painted() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", RenderStyle.KEY, RenderStyle.CHOICE_CLASSIC)
	assert_eq(RenderStyle.stored(config), RenderStyle.CHOICE_PAINTED, "pre-flip look=0")
	config.set_value("graphics", RenderStyle.KEY, RenderStyle.CHOICE_MAP)
	assert_eq(RenderStyle.stored(config), RenderStyle.CHOICE_MAP, "an old Map's choice was chosen")


func test_a_classic_saved_by_the_settings_menu_stays_classic() -> void:
	var config := ConfigFile.new()
	RenderStyle.store(config, RenderStyle.CHOICE_CLASSIC)
	assert_eq(config.get_value("graphics", RenderStyle.KEY_VERSION), RenderStyle.VERSION)
	assert_eq(RenderStyle.stored(config), RenderStyle.CHOICE_CLASSIC)
	var path := "user://test_render_style_classic.cfg"
	assert_eq(config.save(path), OK)
	var back := ConfigFile.new()
	assert_eq(back.load(path), OK)
	assert_eq(RenderStyle.stored(back), RenderStyle.CHOICE_CLASSIC, "survives a file round trip")
	SettingsGpuOptions.apply_startup(back)
	assert_eq(RenderStyle.choice, RenderStyle.CHOICE_CLASSIC)
	assert_eq(RenderStyle.resolve({}, "outdoor_day")["style"], RenderStyle.CLASSIC)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_new_map_carries_the_painted_look_and_follows_it_under_maps_choice() -> void:
	var level := AuthoringController.new_level()
	assert_eq(level.look.get("style"), RenderStyle.PAINTED)
	var drawn := RenderStyle.resolve(level.look, "outdoor_day", RenderStyle.CHOICE_MAP)
	assert_eq(drawn["style"], RenderStyle.PAINTED)
	var back := LevelData.from_dict(level.to_dict())
	assert_eq(back.look, level.look, "it survives the level codec")


func test_a_quality_pick_leaves_the_look_at_its_default() -> void:
	for preset in QualityPreset.CHOICES:
		assert_false(QualityPreset.rows_for(preset).has(RenderStyle.KEY), "no preset sets the look")
	var config := ConfigFile.new()
	var bench := {"gpu_ms": 9.0, "adapter_type": RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU}
	QualityAuto.record(config, QualityPreset.LOWEST, bench)
	assert_true(config.has_section("graphics"), "the weak-GPU pick wrote its rows")
	assert_false(config.has_section_key("graphics", RenderStyle.KEY), "and not the look")
	assert_eq(RenderStyle.stored(config), RenderStyle.CHOICE_PAINTED, "Classic stays a choice")


func test_a_classic_only_preset_falls_back_and_a_looks_mood_wins() -> void:
	var look := {"style": RenderStyle.PAINTED, "sheet": "core", "mood": "winter"}
	var dungeon := RenderStyle.resolve(look, "dungeon_dark", RenderStyle.CHOICE_PAINTED)
	assert_eq(dungeon["style"], RenderStyle.CLASSIC, "no mood paints a dungeon yet")
	assert_eq(dungeon["mood"], "")
	var forest := RenderStyle.resolve(look, "forest", RenderStyle.CHOICE_PAINTED)
	assert_eq(forest["mood"], "winter", "the look's own mood beats the preset's")


func test_a_stored_choice_is_sanitized() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", RenderStyle.KEY, 7)
	assert_eq(RenderStyle.stored(config), RenderStyle.DEFAULT_CHOICE)
	config.set_value("graphics", RenderStyle.KEY, RenderStyle.CHOICE_MAP)
	assert_eq(RenderStyle.stored(config), RenderStyle.CHOICE_MAP)
	assert_eq(RenderStyle.sanitize_look({"style": "neon"})["style"], RenderStyle.CLASSIC)
	assert_eq(RenderStyle.sanitize_look("painted"), {})


func test_the_settings_look_row_offers_saves_and_applies_the_choice() -> void:
	var menu: SettingsMenu = (load("res://scenes/ui/settings_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	var row := menu.get_node("%LookOption") as OptionButton
	assert_eq(row.item_count, RenderStyle.CHOICES.size())
	assert_false(row.tooltip_text.is_empty(), "the row explains itself")
	SettingsGpuOptions.show_defaults(menu)
	assert_eq(row.get_selected_id(), RenderStyle.CHOICE_PAINTED, "Painted by default")
	var painted_text := row.get_item_text(row.get_item_index(RenderStyle.CHOICE_PAINTED))
	assert_string_contains(painted_text, "default")
	assert_string_contains(row.tooltip_text, "default")
	row.select(row.get_item_index(RenderStyle.CHOICE_CLASSIC))
	var path := "user://test_render_style_settings.cfg"
	menu._save_settings(path)
	var config := ConfigFile.new()
	assert_eq(config.load(path), OK)
	assert_eq(config.get_value("graphics", RenderStyle.KEY), RenderStyle.CHOICE_CLASSIC)
	SettingsGpuOptions.show_defaults(menu)
	SettingsGpuOptions.show_saved(menu, config)
	assert_eq(row.get_selected_id(), RenderStyle.CHOICE_CLASSIC, "a saved Classic is kept")
	SettingsGpuOptions.apply(menu, null)
	assert_eq(RenderStyle.choice, RenderStyle.CHOICE_CLASSIC)
	SettingsGpuOptions.apply_startup(ConfigFile.new())
	assert_eq(RenderStyle.choice, RenderStyle.CHOICE_PAINTED, "a fresh install starts Painted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_look_field_survives_the_level_codec() -> void:
	var level := LevelData.new()
	assert_eq(level.look, {}, "a new level is Classic")
	level.look = {"style": RenderStyle.PAINTED, "sheet": "core", "mood": "dusk"}
	var back := LevelData.from_dict(level.to_dict())
	assert_eq(back.look, level.look)
	assert_eq(level.duplicate_level().look, level.look, "a copied level keeps its look")
	assert_eq(LevelData.from_dict({}).look, {}, "an old level dict reads as Classic")


func test_a_late_joiner_snapshot_carries_the_look() -> void:
	var level := LevelData.new()
	level.level_folder = "_painter-a1_snapshot"
	level.environment_preset = "outdoor_sunset"
	level.look = {"style": RenderStyle.PAINTED, "sheet": "", "mood": ""}
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._current_level_dict = level.to_dict()
	NetworkManager.update_level_snapshot(
		func(level_dict: Dictionary) -> Dictionary:
			return LevelVisualState.patch_level_dict(level_dict, {"sun_settings": {"mode": "on"}})
	)
	var joined := LevelData.from_dict(NetworkManager._current_level_dict)
	assert_eq(joined.look, level.look, "the late joiner draws the map's look")
	assert_eq(RenderStyle.resolve(joined.look, joined.environment_preset, 2)["mood"], "dusk")
