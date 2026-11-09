class_name LevelEditPanel
extends DrawerContainer

## Slide-out drawer for real-time visual tuning during gameplay. A rail of seven
## icons (sun, sky, color, weather, water, film, world) shows one pane at a time in a
## PaneStack, with the foot (Revert look, Save look) pinned below it. Each pane owns the
## fields it edits (see LevelEditPane); the Sky and Color panes share an
## EnvironmentEditModel. The panel relays pane signals under the names
## GameplayMenuController has always listened to, tracks dirty state per pane
## (rail badges) and as a whole, and owns the discard-changes prompt.
##
## The foot shows only while the look has a change standing (docs/UI_TASTE.md C5: the one
## fill is for an action that can happen): with nothing to save there is nothing to revert
## either, so a clean drawer is panes alone and the first change brings Save look in as the
## drawer's one Primary with Revert look quiet beside it. Saving or reverting takes the foot
## away again (mark_clean).
##
## The rail's last item is the GM's Events pane (EventsPane, controlled by PlayEvents): live map
## changes for the whole table, undone rather than saved, so the foot steps out while it shows
## and it takes no part in the dirty state.
##
## Every pane is made the first time it is shown or read (PaneStack builders, the pane
## properties below): the drawer is part of the game map, which play builds on every load and
## authoring builds without ever showing it, and its panes were about 1500 Controls (perfaudit
## F-system-8). A pane made later loads the state the drawer was last initialized with, and Save
## starts from that state, so a pane never opened saves what it would have shown.

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
signal water_changed(overrides: Dictionary)

## Emitted when the user toggles "Aim on map". GameplayMenuController owns the
## GameMap reference, so it toggles the actual tool.
signal aim_sun_toggled(active: bool)

## Emitted when the drawer opens (before the animation starts).
## The controller should snapshot current values and call initialize().
signal drawer_opened

## Emitted when the drawer finishes closing.
## The controller should revert changes if not saved.
signal drawer_closed

## Emitted when the Events pane is made (its first show or read of events_pane), so its
## controller (PlayEvents) wires itself to it then.
signal events_pane_built(pane: EventsPane)

const PANE_IDS: Array[StringName] = [
	&"sun", &"sky", &"color", &"weather", &"water", &"film", &"world"
]
## The Events pane's rail item.
const EVENTS_ID := &"events"
const RAIL_ITEMS: Array[Dictionary] = [
	{"id": &"sun", "icon": "sun", "tooltip": "Sun"},
	{"id": &"sky", "icon": "haze", "tooltip": "Sky"},
	{"id": &"color", "icon": "contrast", "tooltip": "Color"},
	{"id": &"weather", "icon": "cloud-rain", "tooltip": "Weather"},
	{"id": &"water", "icon": "droplet", "tooltip": "Water"},
	{"id": &"film", "icon": "grain", "tooltip": "Film"},
	{"id": &"world", "icon": "ruler-measure", "tooltip": "World"},
	{"id": EVENTS_ID, "icon": "wand", "tooltip": "Events: change the map for everyone"},
]
const RAIL_FOOTER_ITEMS: Array[Dictionary] = [
	{"id": &"values", "icon": "hash", "tooltip": "Show values"},
]
## How long the foot takes to fade in when the first change stands.
const FOOT_FADE_S := 0.18

## The panes, each made on its first read or show (see the header).
var sun_pane: SunPane:
	get:
		return _stack.get_pane(&"sun") as SunPane
var sky_pane: SkyPane:
	get:
		return _stack.get_pane(&"sky") as SkyPane
var color_pane: ColorPane:
	get:
		return _stack.get_pane(&"color") as ColorPane
var weather_pane: WeatherPane:
	get:
		return _stack.get_pane(&"weather") as WeatherPane
var water_pane: WaterPane:
	get:
		return _stack.get_pane(&"water") as WaterPane
var film_pane: FilmPane:
	get:
		return _stack.get_pane(&"film") as FilmPane
var world_pane: WorldPane:
	get:
		return _stack.get_pane(&"world") as WorldPane
var events_pane: EventsPane:
	get:
		return _stack.get_pane(EVENTS_ID) as EventsPane

var _env_model := EnvironmentEditModel.new()
var _stack: PaneStack
## The state the drawer was last initialized with (initialize), or null before the first: a pane
## made later loads it, and _build_state starts from it.
var _state: LevelVisualState = null
## initialize's map options for the Sky pane, kept for a Sky pane made later.
var _has_map_defaults: bool = false
var _has_map_sky: bool = false
## Whether every PropertyRow shows its numeric chip. Persisted per user.
var _values_visible: bool = false
## True once a live edit has been made and neither saved nor cancelled.
## Only mark_clean() clears it -- reopening the drawer does not.
var _dirty: bool = false
## The live "discard changes" prompt, while one is on screen. Kept so a second
## close request reuses it instead of stacking a second dialog.
var _close_prompt: Node = null
## The pane on show, so the foot steps out under Events.
var _shown_pane: StringName = &"sun"
## The foot's fade in, replaced by the next one.
var _foot_tween: Tween

@onready var save_button: Button = %SaveButton
@onready var revert_button: Button = %RevertButton
@onready var _foot: HBoxContainer = %ButtonsRow


func _on_ready() -> void:
	edge = DrawerEdge.RIGHT
	drawer_width = 350.0
	tab_width = 44.0
	play_sounds = true
	rail_items = RAIL_ITEMS.duplicate()
	rail_footer_items = RAIL_FOOTER_ITEMS.duplicate()

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
	_stack.bar_in_margin = true
	content_container.add_child(_stack)
	for id in PANE_IDS:
		_stack.add_pane_builder(id, _make_pane.bind(id))
	_stack.add_pane_builder(EVENTS_ID, EventsPane.new)
	_stack.pane_built.connect(_on_pane_built)

	# Pinned footer: the scene-defined ButtonsRow moves under the stack.
	# remove_child() clears `owner` on the moved subtree, which breaks the
	# %unique_name lookups; re-establish ownership afterwards.
	_foot.get_parent().remove_child(_foot)
	content_container.add_child(_foot)
	NodeUtils.set_own_children(self)

	save_button.pressed.connect(_on_save_pressed)
	revert_button.pressed.connect(_on_revert_pressed)
	# The first open selects the rail's first item (DrawerContainer.open), which shows it.
	pane_requested.connect(_on_pane_requested)
	_update_foot()
	rail_footer_pressed.connect(_on_rail_footer_pressed)
	_values_visible = UiPreferences.load_show_values()
	_apply_values_visible()


## Look pane `id`, made on its first show or read (PaneStack builder) and wired to the panel's
## relays; _on_pane_built loads it once it is in the tree.
func _make_pane(id: StringName) -> LevelEditPane:
	var pane: LevelEditPane
	match id:
		&"sun":
			var sun := SunPane.new()
			sun.sun_changed.connect(sun_changed.emit)
			sun.aim_toggled.connect(aim_sun_toggled.emit)
			pane = sun
		&"sky":
			var sky := SkyPane.new()
			sky.set_model(_env_model)
			pane = sky
		&"color":
			var color := ColorPane.new()
			color.set_model(_env_model)
			color.intensity_changed.connect(intensity_changed.emit)
			pane = color
		&"weather":
			var weather := WeatherPane.new()
			weather.weather_changed.connect(weather_changed.emit)
			pane = weather
		&"water":
			var water := WaterPane.new()
			water.water_changed.connect(water_changed.emit)
			pane = water
		&"film":
			var film := FilmPane.new()
			film.lofi_changed.connect(lofi_changed.emit)
			pane = film
		_:
			var world := WorldPane.new()
			world.scale_config_changed.connect(scale_config_changed.emit)
			world.foliage_changed.connect(foliage_changed.emit)
			pane = world
	pane.name = String(id).capitalize() + "Pane"
	pane.changed.connect(_on_pane_changed.bind(id))
	return pane


## A pane was made (its controls exist now): it takes the values toggle, a look pane loads the
## state the drawer was last initialized with, and the Events pane is announced to its controller.
func _on_pane_built(id: StringName, pane: Control) -> void:
	_apply_values_to(pane)
	if id == EVENTS_ID:
		events_pane_built.emit(pane as EventsPane)
		return
	if _state == null:
		return
	if pane is SkyPane:
		(pane as SkyPane).set_map_options(_has_map_defaults, _has_map_sky)
	(pane as LevelEditPane).load_state(_state)


## The look panes made so far (the others hold the initialized state unchanged).
func _panes() -> Array[LevelEditPane]:
	var out: Array[LevelEditPane] = []
	for id in PANE_IDS:
		if _stack.is_built(id):
			out.append(_stack.get_pane(id) as LevelEditPane)
	return out


## Whether pane `id` (a PANE_IDS entry or EVENTS_ID) has been made.
func is_pane_built(id: StringName) -> bool:
	return _stack.is_built(id)


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
	# The first pane shown comes in with the drawer, not crossfaded over it.
	_stack.show_pane(id, _stack.current != &"")
	_shown_pane = id
	_update_foot()


## The foot shows while the look has a change standing and the pane on show is a look pane
## (Events are undone, not saved). It fades in over the state band (M1) so Save look arrives
## rather than pops; it leaves at once, as exits are faster.
func _update_foot() -> void:
	var shown := _dirty and _shown_pane != EVENTS_ID
	if shown == _foot.visible:
		return
	if _foot_tween and _foot_tween.is_valid():
		_foot_tween.kill()
	_foot.visible = shown
	_foot.modulate.a = 1.0
	if shown and is_inside_tree():
		_foot.modulate.a = 0.0
		_foot_tween = create_tween()
		_foot_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_foot_tween.tween_property(_foot, "modulate:a", 1.0, FOOT_FADE_S)


func _on_rail_footer_pressed(id: StringName) -> void:
	if id != &"values":
		return
	_values_visible = not _values_visible
	UiPreferences.save_show_values(_values_visible)
	_apply_values_visible()


## One toggle for every row in every pane made so far (a pane made later takes it in
## _on_pane_built), mirrored on the rail footer item.
func _apply_values_visible() -> void:
	_apply_values_to(_stack)
	set_footer_item_active(&"values", _values_visible)
	set_footer_item_tooltip(&"values", "Hide values" if _values_visible else "Show values")


## Every PropertyRow under `root` shows its numeric chip or not, per the toggle.
func _apply_values_to(root: Node) -> void:
	for row in root.find_children("*", "PropertyRow", true, false):
		row.values_visible = _values_visible


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
	for item in RAIL_ITEMS:
		set_rail_item_tooltip(item["id"], item["tooltip"])
	_update_foot()


func _mark_dirty() -> void:
	_dirty = true
	_update_foot()


## A changed pane's rail item takes the lake dot (it says what is, C5) and a tooltip that
## names the state in words, since a dot alone is colour as the only cue.
func _on_pane_changed(id: StringName) -> void:
	_mark_dirty()
	set_rail_badge(id, true)
	set_rail_item_tooltip(id, pending_tooltip(id))


## The tooltip of pane `id`'s rail item while it holds unsaved edits.
static func pending_tooltip(id: StringName) -> String:
	for item in RAIL_ITEMS:
		if item["id"] == id:
			return "%s: unsaved changes to this map's look" % item["tooltip"]
	return "Unsaved changes to this map's look"


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
		"Discard changes?",
		"The changes to this map's look are not saved. Save look keeps them instead.",
		_on_discard_confirmed,
		"Discard changes",
		"Cancel"
	)
	if _close_prompt:
		_close_prompt.closed.connect(_on_close_prompt_closed)


## Whether the discard prompt is currently on screen. Also true while the
## prompt is animating out (about 0.2 s after Cancel), so a rail press
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
## enables the "Map Defaults" preset.
func initialize(
	level_data: LevelData, map_defaults: Dictionary = {}, has_map_sky: bool = false
) -> void:
	var state := LevelVisualState.from_level_data(level_data)
	_state = state
	_has_map_defaults = not map_defaults.is_empty()
	_has_map_sky = has_map_sky
	_env_model.load_from(state.environment_preset, state.environment_overrides, map_defaults)
	# Panes not made yet load the state when they are (_on_pane_built).
	if _stack.is_built(&"sky"):
		sky_pane.set_map_options(_has_map_defaults, _has_map_sky)
	for pane in _panes():
		pane.load_state(state)
	# The gizmo does not survive a level change, so the toggle must not either.
	if _stack.is_built(&"sun"):
		sun_pane.set_aim_pressed(false)


## Apply new environment state from outside and refresh the Sky and Color panes without
## re-broadcasting.
func apply_environment_state(preset: String, overrides: Dictionary) -> void:
	_env_model.load_from(preset, overrides, _env_model.map_defaults)


## Everything the drawer currently shows, as one independent LevelVisualState: the initialized
## state (what a pane not made yet would show), the environment model the Sky and Color panes
## edit, then each pane made so far.
func _build_state() -> LevelVisualState:
	var state := _state.copy() if _state != null else LevelVisualState.new()
	state.environment_preset = _env_model.preset
	state.environment_overrides = _env_model.overrides.duplicate()
	for pane in _panes():
		pane.write_state(state)
	return state


func _on_save_pressed() -> void:
	save_requested.emit(_build_state())


## Revert look: the controller puts the look back as it was when the drawer opened (or as last
## saved) and closes the drawer, as the discard prompt's confirm does.
func _on_revert_pressed() -> void:
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
