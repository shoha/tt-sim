class_name SettingsWindMotion
extends RefCounted

## The Graphics tab's "Wind motion" slider (graphics/wind_motion, 0..1, default 1), split out of
## settings_menu.gd to keep that file under the lint budget. The slider shows percent. It scales
## how far plants, cloth and weather lean and sway (the Wind autoload's motion scale: amplitudes
## only, never the clock, so peers stay in step); 0 holds everything still. The OS reduce-motion
## setting also holds the wind still and wins over this value. It is a per-player setting, never
## a level field. Moving the slider applies at once; Apply saves it with the other settings.

const KEY := "wind_motion"
const DEFAULT := 1.0
const TOOLTIP := (
	"How much plants, cloth and weather lean and sway in the wind. Lower it if the motion "
	+ "bothers you; 0 holds everything still. Your computer's reduce-motion setting also holds "
	+ "the wind still and wins over this. Only your own screen changes."
)


## The slider's percent for a stored 0..1 [param scale] (clamped).
static func percent_of(scale: float) -> float:
	return clampf(scale, 0.0, 1.0) * 100.0


## The 0..1 motion scale for a slider [param percent] (clamped).
static func scale_of(percent: float) -> float:
	return clampf(percent / 100.0, 0.0, 1.0)


## The text beside the slider.
static func label_for(percent: float) -> String:
	return "%d%%" % int(round(percent))


## Reads the stored scale from [param config] (the default when absent or not a number).
static func stored(config: ConfigFile) -> float:
	var value: Variant = config.get_value("graphics", KEY, DEFAULT)
	return clampf(float(value), 0.0, 1.0) if value is float or value is int else DEFAULT


## Puts the saved value on the slider without firing its handler, and applies nothing (the
## Wind autoload read the file at startup).
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	_show(menu, percent_of(stored(config)))


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value("graphics", KEY, scale_of(menu.wind_motion_slider.value))


## The slider moved (or Reset tweened it): the label follows and the wind changes at once.
static func on_changed(value: float, menu: SettingsMenu) -> void:
	menu.wind_motion_label.text = label_for(value)
	Wind.set_wind_motion(scale_of(value))
	menu._slider_tick()


## Puts the wind back to the scale saved in the settings file at [param path] (the default when
## the file or the value is missing). The menu calls it as it closes: the slider changes the wind
## at once, so a close without Apply must not keep the moved value until the next start (after
## Apply the saved value is the applied one, so the same call leaves it alone). Returns the scale.
static func revert(path: String = Paths.SETTINGS_PATH) -> float:
	var config := ConfigFile.new()
	var scale := stored(config) if config.load(path) == OK else DEFAULT
	Wind.set_wind_motion(scale)
	return scale


static func apply_tooltip(menu: SettingsMenu) -> void:
	menu.wind_motion_slider.tooltip_text = TOOLTIP


static func _show(menu: SettingsMenu, percent: float) -> void:
	menu.wind_motion_slider.set_value_no_signal(percent)
	menu.wind_motion_label.text = label_for(menu.wind_motion_slider.value)
