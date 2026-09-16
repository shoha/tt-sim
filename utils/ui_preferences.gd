class_name UiPreferences
extends RefCounted

## Per-user UI preferences persisted in the settings file's [ui] section,
## following the project's convention that each system reads and writes its
## own section (see docs/CONVENTIONS.md, Settings Persistence). Tests point
## settings_path at a temporary file.

const SECTION := "ui"
const KEY_SHOW_VALUES := "show_values"

static var settings_path: String = Paths.SETTINGS_PATH


static func load_show_values() -> bool:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("UiPreferences: failed to load settings: %d" % err)
	return bool(config.get_value(SECTION, KEY_SHOW_VALUES, false))


static func save_show_values(on: bool) -> void:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("UiPreferences: failed to load settings for save: %d" % err)
	config.set_value(SECTION, KEY_SHOW_VALUES, on)
	config.save(settings_path)
