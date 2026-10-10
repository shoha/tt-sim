class_name UiPreferences
extends RefCounted

## Per-user UI preferences persisted in the settings file's [ui] section,
## following the project's convention that each system reads and writes its
## own section (see docs/CONVENTIONS.md, Settings Persistence). Tests point
## settings_path at a temporary file.

const SECTION := "ui"
const KEY_SHOW_VALUES := "show_values"
## The Interface size choice: InterfaceSize.AUTO (0) or a percent from InterfaceSize.CHOICES.
const KEY_INTERFACE_SIZE := "interface_size"

static var settings_path: String = Paths.SETTINGS_PATH


static func load_show_values() -> bool:
	return bool(_load().get_value(SECTION, KEY_SHOW_VALUES, false))


static func save_show_values(on: bool) -> void:
	_save(KEY_SHOW_VALUES, on)


## The saved Interface size choice; Auto when none is saved or the value is not a choice.
static func load_interface_size() -> int:
	return InterfaceSize.sanitize(
		int(_load().get_value(SECTION, KEY_INTERFACE_SIZE, InterfaceSize.AUTO))
	)


static func save_interface_size(choice: int) -> void:
	_save(KEY_INTERFACE_SIZE, InterfaceSize.sanitize(choice))


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("UiPreferences: failed to load settings: %d" % err)
	return config


## Write one key of the [ui] section, keeping everything else in the file.
static func _save(key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("UiPreferences: failed to load settings for save: %d" % err)
	config.set_value(SECTION, key, value)
	var save_err := config.save(settings_path)
	if save_err != OK:
		push_warning("UiPreferences: failed to save settings: %d" % save_err)
