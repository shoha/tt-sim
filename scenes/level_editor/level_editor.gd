extends AnimatedVisibilityContainer
class_name LevelEditor

## Level Editor UI for creating and editing game levels
## Allows map selection, token placement, and level save/load

signal editor_closed
signal play_level_requested(level_data: LevelData)

# Animation tweens for subdialogs
var _popup_tween: Tween

# UI References
@onready var level_name_edit: LineEdit = %LevelNameEdit
@onready var level_description_edit: TextEdit = %LevelDescriptionEdit
@onready var author_edit: LineEdit = %AuthorEdit
@onready var map_path_label: Label = %MapPathLabel
@onready var select_map_button: Button = %SelectMapButton
@onready var map_file_dialog: FileDialog = %MapFileDialog
@onready var map_offset_x_spin: SpinBox = %MapOffsetXSpin
@onready var map_offset_y_spin: SpinBox = %MapOffsetYSpin
@onready var map_offset_z_spin: SpinBox = %MapOffsetZSpin
@onready var map_scale_slider_spin: SliderSpinBox = %MapScaleSliderSpin

@onready var token_list: ItemList = %TokenList
@onready var pokemon_search: LineEdit = %PokemonSearch
@onready var add_token_button: Button = %AddTokenButton

@onready var right_panel: VBoxContainer = $MainContainer/VBox/ContentSplit/RightPanel
@onready var placement_panel: PanelContainer = %PlacementPanel
@onready var placement_name_edit: LineEdit = %PlacementNameEdit
@onready var placement_pokemon_label: Label = %PlacementPokemonLabel
@onready var placement_shiny_check: CheckBox = %PlacementShinyCheck
@onready var placement_player_check: CheckBox = %PlacementPlayerCheck
@onready var placement_max_hp_spin: SpinBox = %PlacementMaxHPSpin
@onready var placement_current_hp_spin: SpinBox = %PlacementCurrentHPSpin
@onready var placement_visible_check: CheckBox = %PlacementVisibleCheck
@onready var placement_pos_x_spin: SpinBox = %PlacementPosXSpin
@onready var placement_pos_y_spin: SpinBox = %PlacementPosYSpin
@onready var placement_pos_z_spin: SpinBox = %PlacementPosZSpin
@onready var placement_rotation_spin: SpinBox = %PlacementRotationSpin
@onready var placement_scale_slider_spin: SliderSpinBox = %PlacementScaleSliderSpin
@onready var delete_placement_button: Button = %DeletePlacementButton
@onready var apply_placement_button: Button = %ApplyPlacementButton

@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var new_button: Button = %NewButton
@onready var close_button: Button = %CloseButton
@onready var export_button: Button = %ExportButton
@onready var import_button: Button = %ImportButton

@onready var saved_levels_list: ItemList = %SavedLevelsList
@onready var load_dialog: ConfirmationDialog = %LoadDialog
@onready var delete_level_button: Button = %DeleteLevelButton
@onready var delete_confirm_dialog: ConfirmationDialog = %DeleteConfirmDialog
@onready var export_dialog: FileDialog = %ExportDialog
@onready var import_dialog: FileDialog = %ImportDialog
@onready var status_label: Label = %StatusLabel
@onready var play_button: Button = %PlayButton

# Pokemon selector popup
@onready var pokemon_selector_popup: Window = %PokemonSelectorPopup
@onready var pokemon_selector_list: ItemList = %PokemonSelectorList
@onready var pokemon_selector_search: LineEdit = %PokemonSelectorSearch
@onready var pokemon_selector_shiny: CheckBox = %PokemonSelectorShiny

# Lighting editor mode
@onready var edit_lighting_button: Button = %EditLightingButton
@onready var lighting_mode_container: Control = %LightingModeContainer
@onready var lighting_viewport_container: SubViewportContainer = %SubViewportContainer
@onready var lighting_viewport: SubViewport = %SubViewport
@onready var lighting_world_env: WorldEnvironment = %WorldEnvironment
@onready var lighting_camera: Camera3D = %Camera3D
@onready var lighting_map_container: Node3D = %MapContainer
@onready var lighting_editor_panel: LightingEditorPanel = %LightingEditorPanel
@onready var main_container: MarginContainer = $MainContainer

# State
var current_level: LevelData = null
var selected_placement_index: int = -1
var _filtered_pokemon: Array = []
var _selected_level_path_for_delete: String = ""
var _is_updating_ui: bool = false  # Flag to prevent feedback loops when setting UI values
var _pending_map_source_path: String = ""  # Source map path to be bundled on save (for new/edited levels)

# Lighting mode state
var _in_lighting_mode: bool = false
var _lighting_original_intensity: float = 1.0
var _lighting_original_preset: String = "indoor_neutral"
var _lighting_original_overrides: Dictionary = {}
var _lighting_original_lofi: Dictionary = {}
var _loaded_map_instance: Node = null
var _original_light_energies: Dictionary = {}  # Stores original light energies for re-scaling
var _lighting_lofi_material: ShaderMaterial = null  # Lo-fi shader for lighting preview


func _ready() -> void:
	# Configure animation for the level editor panel
	fade_in_duration = 0.25
	fade_out_duration = 0.15
	scale_in_from = Vector2(0.95, 0.95)
	scale_out_to = Vector2(0.98, 0.98)
	trans_in_type = Tween.TRANS_CUBIC
	trans_out_type = Tween.TRANS_CUBIC
	super._ready()

	_connect_signals()
	_setup_file_dialogs()
	_populate_pokemon_list()
	_create_new_level()
	right_panel.visible = false


func _connect_signals() -> void:
	select_map_button.pressed.connect(_on_select_map_pressed)
	map_file_dialog.file_selected.connect(_on_map_file_selected)

	add_token_button.pressed.connect(_on_add_token_pressed)
	token_list.item_selected.connect(_on_token_list_item_selected)

	delete_placement_button.pressed.connect(_on_delete_placement_pressed)
	apply_placement_button.pressed.connect(_on_apply_placement_pressed)

	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	new_button.pressed.connect(_on_new_pressed)
	close_button.pressed.connect(_on_close_pressed)
	export_button.pressed.connect(_on_export_pressed)
	import_button.pressed.connect(_on_import_pressed)

	saved_levels_list.item_activated.connect(_on_saved_level_activated)
	saved_levels_list.item_selected.connect(_on_saved_level_selected)
	load_dialog.confirmed.connect(_on_load_confirmed)
	load_dialog.close_requested.connect(_on_load_dialog_close_requested)
	delete_level_button.pressed.connect(_on_delete_level_pressed)
	delete_confirm_dialog.confirmed.connect(_on_delete_level_confirmed)
	delete_confirm_dialog.close_requested.connect(_on_delete_confirm_close_requested)
	export_dialog.file_selected.connect(_on_export_file_selected)
	import_dialog.file_selected.connect(_on_import_file_selected)

	pokemon_selector_popup.close_requested.connect(_on_pokemon_selector_closed)
	pokemon_selector_list.item_activated.connect(_on_pokemon_selector_activated)
	pokemon_selector_search.text_changed.connect(_on_pokemon_selector_search_changed)

	level_name_edit.text_changed.connect(_on_level_metadata_changed)
	level_description_edit.text_changed.connect(_on_level_metadata_changed)
	author_edit.text_changed.connect(_on_level_metadata_changed)

	map_offset_x_spin.value_changed.connect(_on_map_transform_changed)
	map_offset_y_spin.value_changed.connect(_on_map_transform_changed)
	map_offset_z_spin.value_changed.connect(_on_map_transform_changed)
	map_scale_slider_spin.value_changed.connect(_on_map_scale_changed)

	play_button.pressed.connect(_on_play_pressed)

	# Lighting editor signals
	edit_lighting_button.pressed.connect(_on_edit_lighting_pressed)
	lighting_editor_panel.save_requested.connect(_on_lighting_save_requested)
	lighting_editor_panel.cancel_requested.connect(_on_lighting_cancel_requested)
	lighting_editor_panel.intensity_changed.connect(_on_lighting_intensity_changed)
	lighting_editor_panel.lofi_changed.connect(_on_lofi_changed)


func _setup_file_dialogs() -> void:
	# Map file dialog - allow both resources and filesystem for map imports
	map_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	map_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	map_file_dialog.filters = [
		"*.glb ; GLB Models", "*.gltf ; GLTF Models", "*.tscn ; Godot Scenes"
	]
	# Start in a reasonable location - project maps folder if it exists
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Paths.MAPS_DIR)):
		map_file_dialog.current_dir = ProjectSettings.globalize_path(Paths.MAPS_DIR)

	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = ["*.json ; JSON Files"]

	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters = ["*.json ; JSON Files"]


func _populate_pokemon_list() -> void:
	_filtered_pokemon = []
	for asset in AssetPackManager.get_assets("pokemon"):
		_filtered_pokemon.append(asset.asset_id)
	_filtered_pokemon.sort_custom(func(a, b): return int(a) < int(b))
	_update_pokemon_selector_list()


func _update_pokemon_selector_list() -> void:
	pokemon_selector_list.clear()
	var search_text = pokemon_selector_search.text.to_lower() if pokemon_selector_search else ""

	for asset_id in _filtered_pokemon:
		var display_name = AssetPackManager.get_asset_display_name("pokemon", asset_id)

		if (
			search_text != ""
			and not display_name.to_lower().contains(search_text)
			and not asset_id.contains(search_text)
		):
			continue

		var display_text = "#%s %s" % [asset_id, display_name]
		pokemon_selector_list.add_item(display_text)
		pokemon_selector_list.set_item_metadata(pokemon_selector_list.item_count - 1, asset_id)


func _create_new_level() -> void:
	current_level = LevelManager.create_new_level()
	_pending_map_source_path = ""  # Clear any pending map from previous level
	_update_ui_from_level()
	_set_status("New level created")


func _update_ui_from_level() -> void:
	if not current_level:
		return

	# Block change handlers while we update UI programmatically
	_is_updating_ui = true

	level_name_edit.text = current_level.level_name
	level_description_edit.text = current_level.level_description
	author_edit.text = current_level.author

	# Update map path display based on level type
	if _pending_map_source_path != "":
		# New map selected but not yet saved
		map_path_label.text = _pending_map_source_path.get_file() + " (will be bundled)"
	elif current_level.is_folder_based():
		# Folder-based level with bundled map
		map_path_label.text = current_level.map_path + " (bundled)"
	elif current_level.map_path != "":
		# Legacy res:// path
		map_path_label.text = current_level.map_path.get_file()
	else:
		map_path_label.text = "No map selected"

	# Update map transform controls
	map_offset_x_spin.value = current_level.map_offset.x
	map_offset_y_spin.value = current_level.map_offset.y
	map_offset_z_spin.value = current_level.map_offset.z
	map_scale_slider_spin.set_value_no_signal(current_level.map_scale.x)

	_is_updating_ui = false

	_refresh_token_list()
	right_panel.visible = false
	selected_placement_index = -1


func _refresh_token_list() -> void:
	token_list.clear()

	if not current_level:
		return

	if current_level.token_placements.is_empty():
		token_list.add_item("No tokens — click Add Token to begin")
		token_list.set_item_disabled(0, true)
		token_list.set_item_selectable(0, false)
		return

	for placement in current_level.token_placements:
		var display_name = placement.get_display_name()
		if placement.variant_id == "shiny":
			display_name += " (Shiny)"
		token_list.add_item(display_name)


func _update_placement_panel(placement: TokenPlacement) -> void:
	if not placement:
		right_panel.visible = false
		return

	right_panel.visible = true

	placement_name_edit.text = placement.token_name

	# Display asset info using pack-based system
	var asset_name = AssetPackManager.get_asset_display_name(placement.pack_id, placement.asset_id)
	placement_pokemon_label.text = "#%s %s" % [placement.asset_id, asset_name]

	placement_shiny_check.button_pressed = (placement.variant_id == "shiny")
	placement_player_check.button_pressed = placement.is_player_controlled
	placement_max_hp_spin.value = placement.max_health
	placement_current_hp_spin.value = placement.current_health
	placement_visible_check.button_pressed = placement.is_visible_to_players
	placement_pos_x_spin.value = placement.position.x
	placement_pos_y_spin.value = placement.position.y
	placement_pos_z_spin.value = placement.position.z
	placement_rotation_spin.value = rad_to_deg(placement.rotation_y)
	placement_scale_slider_spin.set_value_no_signal(placement.scale.x)


func _get_placement_from_panel() -> TokenPlacement:
	if (
		selected_placement_index < 0
		or selected_placement_index >= current_level.token_placements.size()
	):
		return null

	var placement = current_level.token_placements[selected_placement_index]
	placement.token_name = placement_name_edit.text
	placement.variant_id = "shiny" if placement_shiny_check.button_pressed else "default"
	placement.is_player_controlled = placement_player_check.button_pressed
	placement.max_health = int(placement_max_hp_spin.value)
	placement.current_health = int(placement_current_hp_spin.value)
	placement.is_visible_to_players = placement_visible_check.button_pressed
	placement.position = Vector3(
		placement_pos_x_spin.value, placement_pos_y_spin.value, placement_pos_z_spin.value
	)
	placement.rotation_y = deg_to_rad(placement_rotation_spin.value)
	placement.scale = Vector3.ONE * placement_scale_slider_spin.value

	return placement


func _set_status(message: String) -> void:
	status_label.text = message

	# Visual flash: green for success, red for errors
	if (
		message.begins_with("Error")
		or message.begins_with("Failed")
		or message.begins_with("Cannot")
	):
		_flash_status(Color(1.0, 0.5, 0.4))
		AudioManager.play_error()
	elif (
		message.begins_with("Level saved")
		or message.begins_with("Lighting")
		or message.begins_with("Level exported")
		or message.begins_with("Level imported")
	):
		_flash_status(Color(0.6, 0.9, 0.5))
		AudioManager.play_success()


## Brief color flash on the status label for visual feedback
func _flash_status(color: Color) -> void:
	status_label.add_theme_color_override("font_color", color)
	var tw = status_label.create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func(): status_label.remove_theme_color_override("font_color"))


func _refresh_saved_levels_list() -> void:
	saved_levels_list.clear()
	var levels = LevelManager.get_saved_levels()

	if levels.is_empty():
		saved_levels_list.add_item("No saved levels yet")
		saved_levels_list.set_item_disabled(0, true)
		saved_levels_list.set_item_selectable(0, false)
	else:
		for level_info in levels:
			var display_text = "%s (%d tokens)" % [level_info.name, level_info.token_count]
			saved_levels_list.add_item(display_text)
			saved_levels_list.set_item_metadata(saved_levels_list.item_count - 1, level_info.path)

	# Disable delete button until a level is selected
	delete_level_button.disabled = true


# Signal handlers


func _on_select_map_pressed() -> void:
	map_file_dialog.popup_centered(Vector2i(800, 600))


func _on_map_file_selected(path: String) -> void:
	# Store the source path for bundling on save
	_pending_map_source_path = path

	# For display, just show the filename - actual bundling happens on save
	map_path_label.text = path.get_file() + " (will be bundled)"
	_set_status("Map selected: " + path.get_file())

	# Clear the old map_path since we're selecting a new one
	# It will be set properly when saved
	current_level.map_path = ""


func _on_add_token_pressed() -> void:
	pokemon_selector_search.text = ""
	_update_pokemon_selector_list()
	pokemon_selector_popup.popup_centered(Vector2i(400, 500))
	var popup_content = pokemon_selector_popup.get_node("VBox")
	_animate_popup_in(pokemon_selector_popup, popup_content)


func _on_pokemon_selector_closed() -> void:
	var popup_content = pokemon_selector_popup.get_node("VBox")
	_animate_popup_out(pokemon_selector_popup, popup_content)


func _on_pokemon_selector_activated(index: int) -> void:
	var pokemon_number = pokemon_selector_list.get_item_metadata(index)
	var is_shiny = pokemon_selector_shiny.button_pressed

	var placement = TokenPlacement.new()
	# Use pack-based asset system
	placement.pack_id = "pokemon"
	placement.asset_id = pokemon_number
	placement.variant_id = "shiny" if is_shiny else "default"
	placement.position = Vector3.ZERO

	# Set default name from asset pack
	placement.token_name = AssetPackManager.get_asset_display_name("pokemon", pokemon_number)

	current_level.add_token_placement(placement)
	_refresh_token_list()

	# Select the new token
	token_list.select(token_list.item_count - 1)
	_on_token_list_item_selected(token_list.item_count - 1)

	var popup_content = pokemon_selector_popup.get_node("VBox")
	_animate_popup_out(pokemon_selector_popup, popup_content)
	_set_status("Added token: " + placement.get_display_name())
	AudioManager.play_success()


func _on_pokemon_selector_search_changed(_text: String) -> void:
	_update_pokemon_selector_list()


func _on_token_list_item_selected(index: int) -> void:
	selected_placement_index = index
	if index >= 0 and index < current_level.token_placements.size():
		_update_placement_panel(current_level.token_placements[index])


func _on_delete_placement_pressed() -> void:
	if selected_placement_index < 0:
		return

	var placement = current_level.token_placements[selected_placement_index]
	current_level.remove_token_placement(placement.placement_id)
	_refresh_token_list()
	right_panel.visible = false
	selected_placement_index = -1
	_set_status("Token deleted")
	AudioManager.play_cancel()


func _on_apply_placement_pressed() -> void:
	var placement = _get_placement_from_panel()
	if placement:
		current_level.update_token_placement(placement)
		_refresh_token_list()
		token_list.select(selected_placement_index)
		_set_status("Token updated")


func _on_level_metadata_changed(_new_text = null) -> void:
	# Don't update level data if we're programmatically setting UI values
	if _is_updating_ui or not current_level:
		return
	current_level.level_name = level_name_edit.text
	current_level.level_description = level_description_edit.text
	current_level.author = author_edit.text


func _on_map_transform_changed(_value: float = 0.0) -> void:
	# Don't update level data if we're programmatically setting UI values
	if _is_updating_ui or not current_level:
		return
	current_level.map_offset = Vector3(
		map_offset_x_spin.value, map_offset_y_spin.value, map_offset_z_spin.value
	)
	current_level.map_scale = Vector3.ONE * map_scale_slider_spin.value


func _on_map_scale_changed(value: float) -> void:
	_on_map_transform_changed(value)


func _on_save_pressed() -> void:
	# Update metadata and map transform before saving
	_on_level_metadata_changed()
	_on_map_transform_changed()

	# Determine if we should use folder-based save
	var use_folder_save = _pending_map_source_path != "" or current_level.is_folder_based()

	if use_folder_save:
		_save_level_folder()
	else:
		# Legacy save for levels with res:// map paths
		var errors = current_level.validate()
		if errors.size() > 0:
			_set_status("Error: " + errors[0])
			return

		var path = LevelManager.save_level(current_level)
		if path != "":
			_set_status("Level saved: " + path.get_file())
		else:
			_set_status("Failed to save level")


## Save level using folder-based format with bundled map
func _save_level_folder() -> void:
	# Validate basic requirements (skip map validation since we're bundling it)
	if current_level.level_name.strip_edges() == "":
		_set_status("Error: Level name is required")
		return

	# Check if we have a map source or existing bundled map
	if _pending_map_source_path == "" and current_level.map_path == "":
		_set_status("Error: No map selected")
		return

	# If we have a pending map source, verify it exists
	if _pending_map_source_path != "" and not FileAccess.file_exists(_pending_map_source_path):
		_set_status("Error: Map file not found: " + _pending_map_source_path)
		return

	# Save using folder-based format
	var result = LevelManager.save_level_folder(current_level, "", _pending_map_source_path)
	if result != "":
		_pending_map_source_path = ""  # Clear pending map after successful save
		_update_ui_from_level()  # Refresh UI to show bundled status
		_set_status("Level saved: " + current_level.level_folder)
	else:
		_set_status("Failed to save level")


func _on_load_pressed() -> void:
	_refresh_saved_levels_list()
	load_dialog.popup_centered(Vector2i(500, 400))
	var dialog_content = load_dialog.get_node("LoadVBox")
	_animate_popup_in(load_dialog, dialog_content)


func _on_saved_level_activated(index: int) -> void:
	var path = saved_levels_list.get_item_metadata(index)
	var dialog_content = load_dialog.get_node("LoadVBox")
	_animate_popup_out(load_dialog, dialog_content)
	# Load async - doesn't block so animation runs smoothly
	_load_level_async(path)


func _on_load_confirmed() -> void:
	var selected_items = saved_levels_list.get_selected_items()
	if selected_items.size() > 0:
		var path = saved_levels_list.get_item_metadata(selected_items[0])
		# Load async - doesn't block so dialog hide animation runs smoothly
		_load_level_async(path)


func _on_load_dialog_close_requested() -> void:
	AudioManager.play_close()


func _on_saved_level_selected(index: int) -> void:
	# Update delete button state based on selection
	delete_level_button.disabled = index < 0


func _on_delete_level_pressed() -> void:
	var selected_items = saved_levels_list.get_selected_items()
	if selected_items.size() == 0:
		return

	var path = saved_levels_list.get_item_metadata(selected_items[0])
	var level_name = saved_levels_list.get_item_text(selected_items[0])

	_selected_level_path_for_delete = path
	delete_confirm_dialog.dialog_text = (
		"Are you sure you want to delete '%s'? This cannot be undone." % level_name
	)
	delete_confirm_dialog.popup_centered()


func _on_delete_level_confirmed() -> void:
	if _selected_level_path_for_delete == "":
		return

	if LevelManager.delete_level(_selected_level_path_for_delete):
		_set_status("Level deleted")
		_refresh_saved_levels_list()
	else:
		_set_status("Failed to delete level")

	_selected_level_path_for_delete = ""


func _on_delete_confirm_close_requested() -> void:
	AudioManager.play_close()


func _load_level_from_path(path: String) -> void:
	# Load without emitting signal to prevent auto-play
	var level = LevelManager.load_level(path)
	if level:
		current_level = level
		_pending_map_source_path = ""  # Clear pending map when loading existing level
		_update_ui_from_level()
		_set_status("Level loaded: " + level.level_name)
	else:
		_set_status("Failed to load level")


## Load a level asynchronously (does not block the main thread)
## This allows UI animations to run smoothly while loading
func _load_level_async(path: String) -> void:
	_set_status("Loading...")

	# Load without emitting signal to prevent auto-play
	var level = await LevelManager.load_level_async(path, false)
	if level:
		current_level = level
		_pending_map_source_path = ""  # Clear pending map when loading existing level
		_update_ui_from_level()
		_set_status("Level loaded: " + level.level_name)
	else:
		_set_status("Failed to load level")


func _on_new_pressed() -> void:
	_create_new_level()


func _on_close_pressed() -> void:
	animate_out()


# Emit editor_closed after animate out completes so the parent can safely queue_free
func _on_after_animate_out() -> void:
	editor_closed.emit()


func _on_export_pressed() -> void:
	export_dialog.current_file = LevelManager._sanitize_filename(current_level.level_name) + ".json"
	export_dialog.popup_centered(Vector2i(800, 600))


func _on_export_file_selected(path: String) -> void:
	if LevelManager.export_level_json(current_level, path):
		_set_status("Level exported: " + path.get_file())
	else:
		_set_status("Failed to export level")


func _on_import_pressed() -> void:
	import_dialog.popup_centered(Vector2i(800, 600))


func _on_import_file_selected(path: String) -> void:
	var level = LevelManager.import_level_json(path)
	if level:
		current_level = level
		_update_ui_from_level()
		_set_status("Level imported: " + level.level_name)
	else:
		_set_status("Failed to import level")


func _on_play_pressed() -> void:
	# Update metadata and map transform before playing
	_on_level_metadata_changed()
	_on_map_transform_changed()

	var errors = current_level.validate()
	if errors.size() > 0:
		_set_status("Cannot play: " + errors[0])
		return

	play_level_requested.emit(current_level)
	_set_status("Starting level: " + current_level.level_name)


## Open the level editor with animation
func open_editor() -> void:
	animate_in()


## Set the current level (e.g., from an active playing level)
func set_level(level_data: LevelData) -> void:
	if level_data:
		current_level = level_data
		_pending_map_source_path = ""  # Clear pending map when setting existing level
		_update_ui_from_level()
		_set_status("Editing: " + level_data.level_name)


# ============================================================================
# Lighting Editor Mode
# ============================================================================


func _on_edit_lighting_pressed() -> void:
	if not current_level:
		_set_status("Create or load a level first")
		return

	# Check if we have a map to load
	var map_path = _get_current_map_path()
	if map_path == "":
		_set_status("Select a map file first")
		return

	# Store original values for cancel
	_lighting_original_intensity = current_level.light_intensity_scale
	_lighting_original_preset = current_level.environment_preset
	_lighting_original_overrides = current_level.environment_overrides.duplicate()
	_lighting_original_lofi = current_level.lofi_overrides.duplicate()

	# Enter lighting mode
	_enter_lighting_mode(map_path)


## Get the effective map path (pending source or current level map)
func _get_current_map_path() -> String:
	if _pending_map_source_path != "":
		return _pending_map_source_path
	if current_level:
		if current_level.is_folder_based():
			# For folder-based levels, use the absolute path resolver
			return current_level.get_absolute_map_path()
		elif current_level.map_path != "":
			return current_level.map_path
	return ""


func _enter_lighting_mode(map_path: String) -> void:
	_in_lighting_mode = true

	# Hide main editor UI
	main_container.visible = false

	# Show lighting mode container
	lighting_mode_container.visible = true

	# Set up lo-fi shader on the lighting preview viewport
	_setup_lighting_lofi_material()

	# Wait a frame for layout to update
	await get_tree().process_frame

	# Load the map into the viewport
	await _load_map_into_viewport(map_path)

	# Initialize the lighting panel with current settings
	lighting_editor_panel.initialize(
		lighting_world_env,
		current_level.light_intensity_scale,
		current_level.environment_preset,
		current_level.environment_overrides,
		current_level.lofi_overrides
	)

	_set_status("Editing lighting & effects - adjust settings and click Save")


func _load_map_into_viewport(map_path: String) -> void:
	# Clear any existing map
	for child in lighting_map_container.get_children():
		child.queue_free()
	_loaded_map_instance = null
	_original_light_energies.clear()

	await get_tree().process_frame

	# Load the map using unified pipeline — handles both res:// and user:// paths.
	# Load WITHOUT intensity scaling first so we can store original energies
	# and scale dynamically in the lighting editor.
	var map_instance: Node3D = null
	var result = await GlbUtils.load_map_async(map_path, false, 1.0)
	if result.success and result.scene:
		map_instance = result.scene

	if map_instance:
		lighting_map_container.add_child(map_instance)
		_loaded_map_instance = map_instance

		# Apply map transform from level data
		map_instance.position = current_level.map_offset
		map_instance.scale = current_level.map_scale

		# Store original light energies and apply current scale
		_store_original_light_energies(map_instance)
		_apply_light_intensity_scale(current_level.light_intensity_scale)

		# Center camera on the loaded map
		_center_lighting_camera()


func _store_original_light_energies(node: Node) -> void:
	if node is Light3D:
		_original_light_energies[node.get_instance_id()] = node.light_energy
	for child in node.get_children():
		_store_original_light_energies(child)


func _apply_light_intensity_scale(intensity_scale: float) -> void:
	for instance_id in _original_light_energies:
		var light = instance_from_id(instance_id)
		if is_instance_valid(light) and light is Light3D:
			light.light_energy = _original_light_energies[instance_id] * intensity_scale


func _on_lighting_intensity_changed(new_scale: float) -> void:
	# Re-apply light intensity to all lights in the preview
	_apply_light_intensity_scale(new_scale)


func _center_lighting_camera() -> void:
	if not _loaded_map_instance:
		return

	# Calculate scene bounds
	var aabb = AABB()
	var first_mesh = true

	for child in _loaded_map_instance.get_children():
		if child is MeshInstance3D:
			var mesh_aabb = child.get_aabb()
			mesh_aabb = Transform3D(child.global_basis, child.global_position) * mesh_aabb
			if first_mesh:
				aabb = mesh_aabb
				first_mesh = false
			else:
				aabb = aabb.merge(mesh_aabb)

	if first_mesh:
		# No meshes found, use default position
		lighting_camera.position = Vector3(0, 10, 15)
		lighting_camera.look_at(Vector3.ZERO)
		return

	# Position camera to see the whole scene
	var center = aabb.get_center()
	var aabb_size = aabb.size.length()
	var distance = aabb_size * 1.2

	lighting_camera.position = center + Vector3(0, distance * 0.5, distance * 0.7)
	lighting_camera.look_at(center)


func _exit_lighting_mode() -> void:
	_in_lighting_mode = false

	# Clear loaded map
	for child in lighting_map_container.get_children():
		child.queue_free()
	_loaded_map_instance = null

	# Clean up lo-fi material
	_cleanup_lighting_lofi_material()

	# Hide lighting mode container
	lighting_mode_container.visible = false

	# Show main editor UI
	main_container.visible = true


func _on_lighting_save_requested(
	intensity: float, preset: String, overrides: Dictionary, lofi_overrides: Dictionary
) -> void:
	# Apply the lighting and effects settings to the level data
	current_level.light_intensity_scale = intensity
	current_level.environment_preset = preset
	current_level.environment_overrides = overrides.duplicate()
	current_level.lofi_overrides = lofi_overrides.duplicate()

	# Save the level file
	_save_level_from_lighting_mode()

	_exit_lighting_mode()


## Save the level file after lighting/effects changes
func _save_level_from_lighting_mode() -> void:
	if not current_level:
		_set_status("Error: No level to save")
		return

	# Use folder-based save if applicable
	if current_level.is_folder_based():
		var result = LevelManager.save_level_folder(current_level, "", "")
		if result != "":
			_set_status("Lighting & effects saved to: " + current_level.level_name)
		else:
			_set_status("Error: Failed to save level")
	else:
		# Legacy save for levels with res:// map paths
		var path = LevelManager.save_level(current_level)
		if path != "":
			_set_status("Lighting & effects saved: " + path.get_file())
		else:
			_set_status("Error: Failed to save level")


func _on_lighting_cancel_requested() -> void:
	# Restore original values
	current_level.light_intensity_scale = _lighting_original_intensity
	current_level.environment_preset = _lighting_original_preset
	current_level.environment_overrides = _lighting_original_overrides.duplicate()
	current_level.lofi_overrides = _lighting_original_lofi.duplicate()

	_exit_lighting_mode()
	_set_status("Lighting & effects changes cancelled")


func _on_lofi_changed(overrides: Dictionary) -> void:
	# Apply lo-fi shader changes in real-time for preview
	if _lighting_lofi_material:
		for param_name in overrides:
			_lighting_lofi_material.set_shader_parameter(param_name, overrides[param_name])


## Set up the lo-fi shader material for the lighting preview viewport
func _setup_lighting_lofi_material() -> void:
	if not lighting_viewport_container:
		return

	# Create a new lo-fi material for the preview
	var shader = load("res://shaders/lofi_canvas.gdshader")
	_lighting_lofi_material = ShaderMaterial.new()
	_lighting_lofi_material.shader = shader

	# Set default values (these will be overridden by initialize() call)
	_lighting_lofi_material.set_shader_parameter("pixelation", 0.003)
	_lighting_lofi_material.set_shader_parameter("saturation", 0.85)
	_lighting_lofi_material.set_shader_parameter("color_tint", Color(1.02, 1.0, 0.96))
	_lighting_lofi_material.set_shader_parameter("vignette_strength", 0.3)
	_lighting_lofi_material.set_shader_parameter("vignette_radius", 0.8)
	_lighting_lofi_material.set_shader_parameter("grain_intensity", 0.025)
	_lighting_lofi_material.set_shader_parameter("grain_speed", 0.2)
	_lighting_lofi_material.set_shader_parameter("grain_scale", 0.12)
	_lighting_lofi_material.set_shader_parameter("color_levels", 32.0)
	_lighting_lofi_material.set_shader_parameter("dither_strength", 0.5)

	# Apply any existing lofi_overrides from level data
	if current_level and current_level.lofi_overrides.size() > 0:
		for param_name in current_level.lofi_overrides:
			_lighting_lofi_material.set_shader_parameter(
				param_name, current_level.lofi_overrides[param_name]
			)

	# Apply to the viewport container
	lighting_viewport_container.material = _lighting_lofi_material


## Clean up the lo-fi material when exiting lighting mode
func _cleanup_lighting_lofi_material() -> void:
	if lighting_viewport_container:
		lighting_viewport_container.material = null
	_lighting_lofi_material = null


## Animate a window popup in
func _animate_popup_in(_popup: Window, content: Control) -> void:
	if _popup_tween:
		_popup_tween.kill()

	# Start scaled down and transparent
	content.modulate.a = 0.0
	content.scale = Vector2(0.9, 0.9)
	content.pivot_offset = content.size / 2

	_popup_tween = create_tween()
	_popup_tween.set_parallel(true)
	_popup_tween.set_ease(Tween.EASE_OUT)
	_popup_tween.set_trans(Tween.TRANS_BACK)
	_popup_tween.tween_property(content, "modulate:a", 1.0, 0.2)
	_popup_tween.tween_property(content, "scale", Vector2.ONE, 0.2)

	AudioManager.play_open()


## Animate a window popup out and hide it
func _animate_popup_out(popup: Window, content: Control) -> void:
	if _popup_tween:
		_popup_tween.kill()

	content.pivot_offset = content.size / 2

	_popup_tween = create_tween()
	_popup_tween.set_parallel(true)
	_popup_tween.set_ease(Tween.EASE_IN)
	_popup_tween.set_trans(Tween.TRANS_CUBIC)
	_popup_tween.tween_property(content, "modulate:a", 0.0, 0.15)
	_popup_tween.tween_property(content, "scale", Vector2(0.95, 0.95), 0.15)
	_popup_tween.finished.connect(popup.hide, CONNECT_ONE_SHOT)

	AudioManager.play_close()
