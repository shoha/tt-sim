class_name LevelEditPanel
extends DrawerContainer

## Slide-out drawer for real-time visual tuning during gameplay. A rail of six
## icons (sun, sky, color, weather, film, world) shows one pane at a time in a
## PaneStack, with Cancel/Save pinned below it. Each pane owns the fields it
## edits (see LevelEditPane); the Sky and Color panes share an
## EnvironmentEditModel. The panel relays pane signals under the names
## GameplayMenuController has always listened to, tracks dirty state per pane
## (rail badges) and as a whole, and owns the discard-changes prompt.

signal save_requested(state: LevelVisualState)
signal cancel_requested
signal intensity_changed(new_scale: float)
signal scale_config_changed(
	grid_cell_size: float, display_unit: String, display_unit_per_cell: float
)
signal environment_changed(preset: String, overrides: Dictionary)
signal lofi_changed(overrides: Dictionary)
signal weather_changed(overrides: Dictionary)
signal foliage_changed(overrides: Dictionary)
signal sun_changed(settings: SunSettings)
signal water_style_changed(style: String)
signal revert_to_map_defaults_requested

## Emitted when the user toggles "Aim on map". GameplayMenuController owns the
## GameMap reference, so it toggles the actual tool.
signal aim_sun_toggled(active: bool)

## Emitted when the drawer opens (before the animation starts).
## The controller should snapshot current values and call initialize().
signal drawer_opened

## Emitted when the drawer finishes closing.
## The controller should revert changes if not saved.
signal drawer_closed

const PANE_IDS: Array[StringName] = [&"sun", &"sky", &"color", &"weather", &"film", &"world"]
const RAIL_ITEMS: Array[Dictionary] = [
	{"id": &"sun", "icon": "sun", "tooltip": "Sun"},
	{"id": &"sky", "icon": "haze", "tooltip": "Sky"},
	{"id": &"color", "icon": "contrast", "tooltip": "Color"},
	{"id": &"weather", "icon": "cloud-rain", "tooltip": "Weather"},
	{"id": &"film", "icon": "grain", "tooltip": "Film"},
	{"id": &"world", "icon": "ruler-measure", "tooltip": "World"},
]

var sun_pane: SunPane
var sky_pane: SkyPane
var color_pane: ColorPane
var weather_pane: WeatherPane
var film_pane: FilmPane
var world_pane: WorldPane

var _env_model := EnvironmentEditModel.new()
var _stack: PaneStack
## True once a live edit has been made and neither saved nor cancelled.
## Only mark_clean() clears it -- reopening the drawer does not.
var _dirty: bool = false
## The live "discard changes" prompt, while one is on screen. Kept so a second
## close request reuses it instead of stacking a second dialog.
var _close_prompt: Node = null

@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton


func _on_ready() -> void:
	edge = DrawerEdge.RIGHT
	drawer_width = 350.0
	tab_width = 44.0
	play_sounds = true
	rail_items = RAIL_ITEMS.duplicate()

	var margin_node := _panel.get_child(0) as MarginContainer
	if margin_node:
		margin_node.add_theme_constant_override("margin_left", 16)
		margin_node.add_theme_constant_override("margin_right", 16)
		margin_node.add_theme_constant_override("margin_top", 16)
		margin_node.add_theme_constant_override("margin_bottom", 16)

	_env_model.changed.connect(_on_env_model_changed)

	_stack = PaneStack.new()
	_stack.name = "PaneStack"
	_stack.slide_from_right = true
	content_container.add_child(_stack)
	_build_panes()

	# Pinned footer: the scene-defined ButtonsRow moves under the stack.
	# remove_child() clears `owner` on the moved subtree, which breaks the
	# %unique_name lookups; re-establish ownership afterwards.
	var buttons_row: HBoxContainer = %ButtonsRow
	buttons_row.get_parent().remove_child(buttons_row)
	content_container.add_child(buttons_row)
	NodeUtils.set_own_children(self)

	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	pane_requested.connect(_on_pane_requested)
	_stack.show_pane(&"sun", false)


func _build_panes() -> void:
	sun_pane = SunPane.new()
	sky_pane = SkyPane.new()
	color_pane = ColorPane.new()
	weather_pane = WeatherPane.new()
	film_pane = FilmPane.new()
	world_pane = WorldPane.new()
	sky_pane.set_model(_env_model)
	color_pane.set_model(_env_model)
	var panes := {
		&"sun": sun_pane,
		&"sky": sky_pane,
		&"color": color_pane,
		&"weather": weather_pane,
		&"film": film_pane,
		&"world": world_pane,
	}
	for id in PANE_IDS:
		var pane: LevelEditPane = panes[id]
		pane.name = String(id).capitalize() + "Pane"
		_stack.add_pane(id, pane)
		pane.changed.connect(_on_pane_changed.bind(id))

	sun_pane.sun_changed.connect(sun_changed.emit)
	sun_pane.aim_toggled.connect(aim_sun_toggled.emit)
	sky_pane.intensity_changed.connect(intensity_changed.emit)
	sky_pane.revert_to_map_defaults_requested.connect(revert_to_map_defaults_requested.emit)
	weather_pane.weather_changed.connect(weather_changed.emit)
	film_pane.lofi_changed.connect(lofi_changed.emit)
	world_pane.scale_config_changed.connect(scale_config_changed.emit)
	world_pane.water_style_changed.connect(water_style_changed.emit)
	world_pane.foliage_changed.connect(foliage_changed.emit)


func _panes() -> Array[LevelEditPane]:
	return [sun_pane, sky_pane, color_pane, weather_pane, film_pane, world_pane]


# ============================================================================
# Drawer Lifecycle
# ============================================================================


## Override open to emit signal before the animation starts.
## The controller uses this to snapshot values and initialize the panel.
## Registering as an overlay routes Escape through request_close().
func open() -> void:
	UIManager.register_overlay(self)
	drawer_opened.emit()
	super.open()


## Override _on_closed to notify the controller when the drawer finishes closing.
func _on_closed() -> void:
	UIManager.unregister_overlay(self)
	drawer_closed.emit()


func _on_pane_requested(id: StringName) -> void:
	_stack.show_pane(id)


# ============================================================================
# Unsaved Changes
# ============================================================================


## Whether the drawer holds live edits that have been neither saved nor reverted.
func is_dirty() -> bool:
	return _dirty


## Called by the controller after Save, Cancel or a level change.
func mark_clean() -> void:
	_dismiss_close_prompt()
	_dirty = false
	set_tab_badge(false)


func _mark_dirty() -> void:
	_dirty = true


func _on_pane_changed(id: StringName) -> void:
	_mark_dirty()
	set_rail_badge(id, true)


## The shared environment model is edited by two panes; its change is the
## single environment_changed broadcast. Pane badges come from each pane's
## own changed signal.
func _on_env_model_changed(preset: String, overrides: Dictionary) -> void:
	_mark_dirty()
	environment_changed.emit(preset, overrides)


## Close if clean; otherwise ask before discarding. Used by the rail and by
## UIManager's Escape handling, which pops the overlay before dispatching -- so
## every branch that leaves the drawer open re-registers it, or the next Escape
## falls through to the pause menu. register_overlay() is idempotent.
func request_close() -> void:
	# close() is a no-op mid-animation, and a second Escape must not stack a
	# second dialog -- both leave the drawer open with nothing else to do.
	if _is_animating or _is_close_prompt_open():
		UIManager.register_overlay(self)
		return
	if not _dirty:
		close()
		return
	UIManager.register_overlay(self)
	_close_prompt = UIManager.show_danger_confirmation(
		"Unsaved visual changes",
		"Discard the changes made in this drawer? Save is still available in the drawer.",
		_on_discard_confirmed,
		"Discard changes",
		"Keep editing"
	)
	if _close_prompt:
		_close_prompt.closed.connect(_on_close_prompt_closed)


## Whether the discard prompt is currently on screen. Also true while the
## prompt is animating out (about 0.2 s after "Keep editing"), so a rail press
## or Escape in that window is a no-op rather than a second prompt -- that is
## intended.
func _is_close_prompt_open() -> bool:
	return is_instance_valid(_close_prompt) and _close_prompt.is_inside_tree()


## The dialog frees itself after animating out, so drop the reference with it.
func _on_close_prompt_closed(_confirmed: bool) -> void:
	_close_prompt = null


## Dismiss any open close prompt so it cannot outlive the state it was asked
## about -- e.g. a level change that calls mark_clean() while the "Discard
## changes" prompt from the OLD level is still on screen. queue_free() bypasses
## the dialog's own animate-out/closed signal, so the reference is dropped here
## directly rather than relying on _on_close_prompt_closed.
func _dismiss_close_prompt() -> void:
	if _is_close_prompt_open():
		_close_prompt.queue_free()
	_close_prompt = null


## The rail must not close a drawer with unsaved work; it prompts instead.
func _can_close_from_tab() -> bool:
	if _dirty:
		request_close()
		return false
	return true


## The controller listens for cancel_requested: it reverts and closes the drawer.
## The dialog is still inside its own confirm handler here and will animate out
## by itself, so the reference is dropped first: otherwise the controller's
## mark_clean() would queue_free() it mid-handler and cut the fade short.
func _on_discard_confirmed() -> void:
	_close_prompt = null
	cancel_requested.emit()


# ============================================================================
# Initialize / Save
# ============================================================================


## Initialize every pane from the current level data. Call this in response to
## drawer_opened, before the panel animates in. [param map_defaults] is the
## environment config extracted from the map's embedded WorldEnvironment
## (empty dict if none); it is the base layer when the preset is "" and it
## enables the "Map Defaults" preset and the revert button.
func initialize(
	level_data: LevelData, map_defaults: Dictionary = {}, has_map_sky: bool = false
) -> void:
	var state := LevelVisualState.from_level_data(level_data)
	_env_model.load_from(state.environment_preset, state.environment_overrides, map_defaults)
	sky_pane.set_map_options(not map_defaults.is_empty(), has_map_sky)
	for pane in _panes():
		pane.load_state(state)
	# The gizmo does not survive a level change, so the toggle must not either.
	sun_pane.set_aim_pressed(false)


## Apply new environment state from outside (e.g. after reverting to map
## defaults) and refresh the Sky and Color panes without re-broadcasting.
func apply_environment_state(preset: String, overrides: Dictionary) -> void:
	_env_model.load_from(preset, overrides, _env_model.map_defaults)


## Everything the drawer currently shows, as one independent LevelVisualState.
func _build_state() -> LevelVisualState:
	var state := LevelVisualState.new()
	for pane in _panes():
		pane.write_state(state)
	return state


func _on_save_pressed() -> void:
	save_requested.emit(_build_state())


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


# ============================================================================
# Sun gizmo forwards (GameplayMenuController owns the tool)
# ============================================================================


## Called when the gizmo reports a drag, so the numeric rows track the handle.
func set_sun_direction_from_gizmo(azimuth_degrees: float, elevation_degrees: float) -> void:
	sun_pane.apply_gizmo_direction(azimuth_degrees, elevation_degrees)


## Called when the gizmo deactivates by any route (RMB, or the measure tool
## taking over), so the toggle cannot be left pressed for an inactive tool.
func set_aim_sun_pressed(pressed: bool) -> void:
	sun_pane.set_aim_pressed(pressed)
