extends AnimatedVisibilityContainer
class_name LevelEditor

## Level Editor UI for creating and editing game levels
## Allows map selection, token placement, and level save/load

signal editor_closed
signal play_level_requested(level_data: LevelData)

const POPUP_SIZE_SMALL := Vector2i(400, 500)
const POPUP_SIZE_LARGE := Vector2i(800, 600)
const DIALOG_SIZE := Vector2i(500, 400)
const STATUS_FLASH_DURATION := 1.0

# Animation tweens for subdialogs
var _popup_tween: Tween

# Delegated undo/redo + autosave handler (initialised in _ready)
var _history: LevelEditorHistory

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

@onready var main_container: MarginContainer = $MainContainer

# State
var current_level: LevelData = null
var selected_placement_index: int = -1
var _filtered_pokemon: Array = []
var _selected_level_path_for_delete: String = ""
var _is_updating_ui: bool = false  # Flag to prevent feedback loops when setting UI values
var _pending_map_source_path: String = ""  # Source map path to be bundled on save (for new/edited levels)


func _ready() -> void:
	# Configure animation for the level editor panel
	fade_in_duration = 0.25
	fade_out_duration = Constants.ANIM_FADE_OUT_DURATION
	scale_in_from = Vector2(0.95, 0.95)
	scale_out_to = Vector2(0.98, 0.98)
	trans_in_type = Tween.TRANS_CUBIC
	trans_out_type = Tween.TRANS_CUBIC
	super._ready()

	_connect_signals()
	_setup_file_dialogs()
	_populate_pokemon_list()

	_history = LevelEditorHistory.new(
		self,
		func() -> LevelData: return current_level,
		func(level: LevelData) -> void:
			current_level = level
			_update_ui_from_level(),
		_set_status,
	)
	_check_autosave_recovery()
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
	for asset in AssetManager.get_assets("pokemon"):
		_filtered_pokemon.append(asset.asset_id)
	_filtered_pokemon.sort_custom(func(a, b): return int(a) < int(b))
	_update_pokemon_selector_list()


func _update_pokemon_selector_list() -> void:
	pokemon_selector_list.clear()
	var search_text = pokemon_selector_search.text.to_lower() if pokemon_selector_search else ""

	for asset_id in _filtered_pokemon:
		var display_name = AssetManager.get_asset_display_name("pokemon", asset_id)

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
	_history.clear()
	_history.set_saved_snapshot(current_level.to_dict())
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


# =============================================================================
# UNDO / REDO  (delegated to LevelEditorHistory)
# =============================================================================


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_undo"):
		_history.undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_redo"):
		_history.redo()
		get_viewport().set_input_as_handled()


# =============================================================================
# AUTOSAVE  (delegated to LevelEditorHistory)
# =============================================================================


## Check for autosave recovery on startup.
func _check_autosave_recovery() -> void:
	if not _history.has_autosave():
		return
	call_deferred("_show_autosave_recovery_prompt")


func _show_autosave_recovery_prompt() -> void:
	UIManager.show_confirmation(
		"Recover Autosave?",
		"An autosaved level was found. Would you like to recover it?",
		"Recover",
		"Discard",
		func() -> void: _history.recover_autosave(),
		func() -> void: _history.discard_autosave(),
	)


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
		var display_name = AssetManager.get_asset_display_name(
			placement.pack_id, placement.asset_id
		)
		if placement.token_name != "":
			display_name = placement.token_name
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
	var asset_name = AssetManager.get_asset_display_name(placement.pack_id, placement.asset_id)
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
		or message.begins_with("Level exported")
		or message.begins_with("Level imported")
	):
		_flash_status(Color(0.6, 0.9, 0.5))
		AudioManager.play_success()


## Brief color flash on the status label for visual feedback
func _flash_status(color: Color) -> void:
	status_label.add_theme_color_override("font_color", color)
	var tw = status_label.create_tween()
	tw.tween_interval(STATUS_FLASH_DURATION)
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
	map_file_dialog.popup_centered(POPUP_SIZE_LARGE)


func _on_map_file_selected(path: String) -> void:
	_history.save_undo_snapshot()

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
	pokemon_selector_popup.popup_centered(POPUP_SIZE_SMALL)
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
	placement.token_name = AssetManager.get_asset_display_name("pokemon", pokemon_number)

	_history.save_undo_snapshot()
	current_level.add_token_placement(placement)
	_refresh_token_list()

	# Select the new token
	token_list.select(token_list.item_count - 1)
	_on_token_list_item_selected(token_list.item_count - 1)

	var popup_content = pokemon_selector_popup.get_node("VBox")
	_animate_popup_out(pokemon_selector_popup, popup_content)
	_set_status("Added token: " + placement.token_name)
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

	_history.save_undo_snapshot()
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
		_history.save_undo_snapshot()
		current_level.update_token_placement(placement)
		_refresh_token_list()
		token_list.select(selected_placement_index)
		_set_status("Token updated")


func _on_level_metadata_changed(_new_text = null) -> void:
	# Don't update level data if we're programmatically setting UI values
	if _is_updating_ui or not current_level:
		return
	_history.save_undo_snapshot()
	current_level.level_name = level_name_edit.text
	current_level.level_description = level_description_edit.text
	current_level.author = author_edit.text


func _on_map_transform_changed(_value: float = 0.0) -> void:
	# Don't update level data if we're programmatically setting UI values
	if _is_updating_ui or not current_level:
		return
	_history.save_undo_snapshot()
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
			_history.mark_saved()
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
		_history.mark_saved()
		_update_ui_from_level()  # Refresh UI to show bundled status
		_set_status("Level saved: " + current_level.level_folder)
	else:
		_set_status("Failed to save level")


func _on_load_pressed() -> void:
	_refresh_saved_levels_list()
	load_dialog.popup_centered(DIALOG_SIZE)
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
		_history.clear()
		_history.set_saved_snapshot(current_level.to_dict())
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
		_history.clear()
		_history.set_saved_snapshot(current_level.to_dict())
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
	export_dialog.popup_centered(POPUP_SIZE_LARGE)


func _on_export_file_selected(path: String) -> void:
	if LevelManager.export_level_json(current_level, path):
		_set_status("Level exported: " + path.get_file())
	else:
		_set_status("Failed to export level")


func _on_import_pressed() -> void:
	import_dialog.popup_centered(POPUP_SIZE_LARGE)


func _on_import_file_selected(path: String) -> void:
	var level = LevelManager.import_level_json(path)
	if level:
		current_level = level
		_history.clear()
		_history.set_saved_snapshot(current_level.to_dict())
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
		_history.clear()
		_history.set_saved_snapshot(current_level.to_dict())
		_update_ui_from_level()
		_set_status("Editing: " + level_data.level_name)


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
	_popup_tween.tween_property(content, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	_popup_tween.tween_property(content, "scale", Vector2.ONE, Constants.ANIM_FADE_IN_DURATION)

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
	_popup_tween.tween_property(content, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	_popup_tween.tween_property(
		content, "scale", Vector2(0.95, 0.95), Constants.ANIM_FADE_OUT_DURATION
	)
	_popup_tween.finished.connect(popup.hide, CONNECT_ONE_SHOT)

	AudioManager.play_close()
