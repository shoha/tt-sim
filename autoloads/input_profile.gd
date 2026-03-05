extends Node

## Manages input device profiles (Mouse vs Trackpad) and provides profile-aware
## key label lookups for hint overlays and settings UI.
##
## Both original and alternative keybindings always work simultaneously.
## The active profile only controls which labels are shown in the UI.
##
## Persisted in user://settings.cfg [controls] section.

enum Profile { AUTO, MOUSE, TRACKPAD }

## The resolved profile (never AUTO — AUTO resolves to MOUSE or TRACKPAD).
var active_profile: Profile = Profile.MOUSE

## The user-chosen profile setting (may be AUTO).
var _selected_profile: Profile = Profile.AUTO

signal profile_changed(new_profile: Profile)

## Label table: action_id -> [mouse_label, trackpad_label]
const LABELS := {
	&"pan": ["MMB Drag", "RMB Drag"],
	&"zoom": ["Scroll", "Scroll"],
	&"reset_camera": ["Home", "C"],
	&"rotate": ["MMB Drag", "R+Drag"],
	&"scale": ["Shift+MMB", "Shift+R+Drag"],
	&"reset_transform": ["MMB DblClick", "R+DblClick"],
	&"measure": ["M", "M"],
	&"grid": ["G", "G"],
	&"pause": ["ESC", "ESC"],
	&"wasd": ["WASD", "WASD"],
	&"place_point": ["LMB", "LMB"],
	&"snap_token": ["Ctrl+LMB", "Ctrl+LMB"],
	&"undo_cancel": ["RMB", "RMB"],
	&"cancel_drag": ["RMB", "RMB"],
	&"drag_height": ["Scroll", "Scroll"],
	&"free_move": ["Shift", "Shift"],
	&"cycle_mode": ["Tab", "Tab"],
	&"done": ["M", "M"],
}


func _ready() -> void:
	_load_profile()
	_resolve_profile()


## Return the display string for [param action_id] under the current profile.
func label(action_id: StringName) -> String:
	if action_id not in LABELS:
		push_warning("InputProfile: unknown action_id '%s'" % action_id)
		return ""
	var pair: Array = LABELS[action_id]
	return pair[1] if active_profile == Profile.TRACKPAD else pair[0]


## Set the profile selection. Called from settings UI.
## Persists to settings.cfg and emits profile_changed if the resolved profile changes.
func set_profile(profile: Profile) -> void:
	_selected_profile = profile
	_save_profile()
	_resolve_profile()


## Call when an actual middle-mouse-button press is observed.
## If the user is in AUTO mode, this resolves the profile to MOUSE.
func notify_middle_click() -> void:
	if _selected_profile != Profile.AUTO:
		return
	if active_profile == Profile.MOUSE:
		return
	active_profile = Profile.MOUSE
	_save_detected_profile()
	profile_changed.emit(active_profile)


## Call when a trackpad gesture (pan, magnify) is observed.
## If the user is in AUTO mode, this resolves the profile to TRACKPAD.
func notify_trackpad_gesture() -> void:
	if _selected_profile != Profile.AUTO:
		return
	if active_profile == Profile.TRACKPAD:
		return
	active_profile = Profile.TRACKPAD
	_save_detected_profile()
	profile_changed.emit(active_profile)


## Return the raw selected profile (may be AUTO). Used by settings UI.
func get_selected_profile() -> Profile:
	return _selected_profile


func _resolve_profile() -> void:
	var old_profile := active_profile
	if _selected_profile == Profile.MOUSE:
		active_profile = Profile.MOUSE
	elif _selected_profile == Profile.TRACKPAD:
		active_profile = Profile.TRACKPAD
	else:
		# AUTO: use last-detected hardware if available, otherwise heuristic
		var detected := _load_detected_profile()
		if detected != Profile.AUTO:
			active_profile = detected
		elif DisplayServer.is_touchscreen_available():
			active_profile = Profile.TRACKPAD
		else:
			active_profile = Profile.MOUSE
	if active_profile != old_profile:
		profile_changed.emit(active_profile)


func _load_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load(Paths.SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("InputProfile: failed to load settings: %d" % err)
	_selected_profile = config.get_value("controls", "input_profile", Profile.AUTO) as Profile


func _save_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load(Paths.SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("InputProfile: failed to load settings for save: %d" % err)
	config.set_value("controls", "input_profile", _selected_profile)
	config.save(Paths.SETTINGS_PATH)


## Persist the auto-detected hardware profile so it survives across sessions.
func _save_detected_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load(Paths.SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("InputProfile: failed to load settings for save: %d" % err)
	config.set_value("controls", "detected_profile", active_profile)
	config.save(Paths.SETTINGS_PATH)


## Load the previously auto-detected hardware profile, or AUTO if none saved.
func _load_detected_profile() -> Profile:
	var config := ConfigFile.new()
	var err := config.load(Paths.SETTINGS_PATH)
	if err != OK:
		return Profile.AUTO
	return config.get_value("controls", "detected_profile", Profile.AUTO) as Profile
