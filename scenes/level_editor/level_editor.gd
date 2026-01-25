extends Control
class_name LevelEditor

## Level Editor UI for creating and editing game levels
## Allows map selection, token placement, and level save/load

signal editor_closed
signal play_level_requested(level_data: LevelData)

# UI References
@onready var level_name_edit: LineEdit = %LevelNameEdit
@onready var level_description_edit: TextEdit = %LevelDescriptionEdit
@onready var author_edit: LineEdit = %AuthorEdit
@onready var map_path_label: Label = %MapPathLabel
@onready var select_map_button: Button = %SelectMapButton
@onready var map_file_dialog: FileDialog = %MapFileDialog

@onready var token_list: ItemList = %TokenList
@onready var pokemon_search: LineEdit = %PokemonSearch
@onready var add_token_button: Button = %AddTokenButton

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
@onready var placement_scale_x_spin: SpinBox = %PlacementScaleXSpin
@onready var placement_scale_y_spin: SpinBox = %PlacementScaleYSpin
@onready var placement_scale_z_spin: SpinBox = %PlacementScaleZSpin
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

# State
var current_level: LevelData = null
var selected_placement_index: int = -1
var _filtered_pokemon: Array = []
var _selected_level_path_for_delete: String = ""


func _ready() -> void:
	_connect_signals()
	_setup_file_dialogs()
	_populate_pokemon_list()
	_create_new_level()
	placement_panel.visible = false


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
	delete_level_button.pressed.connect(_on_delete_level_pressed)
	delete_confirm_dialog.confirmed.connect(_on_delete_level_confirmed)
	export_dialog.file_selected.connect(_on_export_file_selected)
	import_dialog.file_selected.connect(_on_import_file_selected)
	
	pokemon_selector_popup.close_requested.connect(_on_pokemon_selector_closed)
	pokemon_selector_list.item_activated.connect(_on_pokemon_selector_activated)
	pokemon_selector_search.text_changed.connect(_on_pokemon_selector_search_changed)
	
	level_name_edit.text_changed.connect(_on_level_metadata_changed)
	level_description_edit.text_changed.connect(_on_level_metadata_changed)
	author_edit.text_changed.connect(_on_level_metadata_changed)
	
	play_button.pressed.connect(_on_play_pressed)


func _setup_file_dialogs() -> void:
	map_file_dialog.access = FileDialog.ACCESS_RESOURCES
	map_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	map_file_dialog.filters = ["*.glb ; GLB Models", "*.gltf ; GLTF Models", "*.tscn ; Godot Scenes"]
	map_file_dialog.current_dir = "res://assets/models/maps/"
	
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = ["*.json ; JSON Files"]
	
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters = ["*.json ; JSON Files"]


func _populate_pokemon_list() -> void:
	_filtered_pokemon = PokemonAutoload.available_pokemon.keys()
	_filtered_pokemon.sort_custom(func(a, b): return int(a) < int(b))
	_update_pokemon_selector_list()


func _update_pokemon_selector_list() -> void:
	pokemon_selector_list.clear()
	var search_text = pokemon_selector_search.text.to_lower() if pokemon_selector_search else ""
	
	for num in _filtered_pokemon:
		var poke_data = PokemonAutoload.available_pokemon[num]
		var poke_name = poke_data.name
		
		if search_text != "" and not poke_name.contains(search_text) and not num.contains(search_text):
			continue
		
		var display_text = "#%s %s" % [num, poke_name.capitalize()]
		pokemon_selector_list.add_item(display_text)
		pokemon_selector_list.set_item_metadata(pokemon_selector_list.item_count - 1, num)


func _create_new_level() -> void:
	current_level = LevelManager.create_new_level()
	_update_ui_from_level()
	_set_status("New level created")


func _update_ui_from_level() -> void:
	if not current_level:
		return
	
	level_name_edit.text = current_level.level_name
	level_description_edit.text = current_level.level_description
	author_edit.text = current_level.author
	
	if current_level.map_glb_path != "":
		map_path_label.text = current_level.map_glb_path.get_file()
	else:
		map_path_label.text = "No map selected"
	
	_refresh_token_list()
	placement_panel.visible = false
	selected_placement_index = -1


func _refresh_token_list() -> void:
	token_list.clear()
	
	if not current_level:
		return
	
	for placement in current_level.token_placements:
		var display_name = placement.get_display_name()
		if placement.is_shiny:
			display_name += " (Shiny)"
		token_list.add_item(display_name)


func _update_placement_panel(placement: TokenPlacement) -> void:
	if not placement:
		placement_panel.visible = false
		return
	
	placement_panel.visible = true
	
	placement_name_edit.text = placement.token_name
	
	var poke_name = "Unknown"
	if PokemonAutoload.available_pokemon.has(placement.pokemon_number):
		poke_name = PokemonAutoload.available_pokemon[placement.pokemon_number].name.capitalize()
	placement_pokemon_label.text = "#%s %s" % [placement.pokemon_number, poke_name]
	
	placement_shiny_check.button_pressed = placement.is_shiny
	placement_player_check.button_pressed = placement.is_player_controlled
	placement_max_hp_spin.value = placement.max_health
	placement_current_hp_spin.value = placement.current_health
	placement_visible_check.button_pressed = placement.is_visible_to_players
	placement_pos_x_spin.value = placement.position.x
	placement_pos_y_spin.value = placement.position.y
	placement_pos_z_spin.value = placement.position.z
	placement_rotation_spin.value = rad_to_deg(placement.rotation_y)
	placement_scale_x_spin.value = placement.scale.x
	placement_scale_y_spin.value = placement.scale.y
	placement_scale_z_spin.value = placement.scale.z


func _get_placement_from_panel() -> TokenPlacement:
	if selected_placement_index < 0 or selected_placement_index >= current_level.token_placements.size():
		return null
	
	var placement = current_level.token_placements[selected_placement_index]
	placement.token_name = placement_name_edit.text
	placement.is_shiny = placement_shiny_check.button_pressed
	placement.is_player_controlled = placement_player_check.button_pressed
	placement.max_health = int(placement_max_hp_spin.value)
	placement.current_health = int(placement_current_hp_spin.value)
	placement.is_visible_to_players = placement_visible_check.button_pressed
	placement.position = Vector3(
		placement_pos_x_spin.value,
		placement_pos_y_spin.value,
		placement_pos_z_spin.value
	)
	placement.rotation_y = deg_to_rad(placement_rotation_spin.value)
	placement.scale = Vector3(
		placement_scale_x_spin.value,
		placement_scale_y_spin.value,
		placement_scale_z_spin.value
	)
	
	return placement


func _set_status(message: String) -> void:
	status_label.text = message


func _refresh_saved_levels_list() -> void:
	saved_levels_list.clear()
	var levels = LevelManager.get_saved_levels()
	
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
	current_level.map_glb_path = path
	map_path_label.text = path.get_file()
	_set_status("Map selected: " + path.get_file())


func _on_add_token_pressed() -> void:
	pokemon_selector_search.text = ""
	_update_pokemon_selector_list()
	pokemon_selector_popup.popup_centered(Vector2i(400, 500))


func _on_pokemon_selector_closed() -> void:
	pokemon_selector_popup.hide()


func _on_pokemon_selector_activated(index: int) -> void:
	var pokemon_number = pokemon_selector_list.get_item_metadata(index)
	var is_shiny = pokemon_selector_shiny.button_pressed
	
	var placement = TokenPlacement.new()
	placement.pokemon_number = pokemon_number
	placement.is_shiny = is_shiny
	placement.position = Vector3.ZERO
	
	# Set default name from pokemon
	if PokemonAutoload.available_pokemon.has(pokemon_number):
		placement.token_name = PokemonAutoload.available_pokemon[pokemon_number].name.capitalize()
	
	current_level.add_token_placement(placement)
	_refresh_token_list()
	
	# Select the new token
	token_list.select(token_list.item_count - 1)
	_on_token_list_item_selected(token_list.item_count - 1)
	
	pokemon_selector_popup.hide()
	_set_status("Added token: " + placement.get_display_name())


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
	placement_panel.visible = false
	selected_placement_index = -1
	_set_status("Token deleted")


func _on_apply_placement_pressed() -> void:
	var placement = _get_placement_from_panel()
	if placement:
		current_level.update_token_placement(placement)
		_refresh_token_list()
		token_list.select(selected_placement_index)
		_set_status("Token updated")


func _on_level_metadata_changed(_new_text = null) -> void:
	if not current_level:
		return
	current_level.level_name = level_name_edit.text
	current_level.level_description = level_description_edit.text
	current_level.author = author_edit.text


func _on_save_pressed() -> void:
	# Update metadata before saving
	_on_level_metadata_changed()
	
	var errors = current_level.validate()
	if errors.size() > 0:
		_set_status("Error: " + errors[0])
		return
	
	var path = LevelManager.save_level(current_level)
	if path != "":
		_set_status("Level saved: " + path.get_file())
	else:
		_set_status("Failed to save level")


func _on_load_pressed() -> void:
	_refresh_saved_levels_list()
	load_dialog.popup_centered(Vector2i(500, 400))


func _on_saved_level_activated(index: int) -> void:
	var path = saved_levels_list.get_item_metadata(index)
	_load_level_from_path(path)
	load_dialog.hide()


func _on_load_confirmed() -> void:
	var selected_items = saved_levels_list.get_selected_items()
	if selected_items.size() > 0:
		var path = saved_levels_list.get_item_metadata(selected_items[0])
		_load_level_from_path(path)


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
	delete_confirm_dialog.dialog_text = "Are you sure you want to delete '%s'? This cannot be undone." % level_name
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


func _load_level_from_path(path: String) -> void:
	var level = LevelManager.load_level(path)
	if level:
		current_level = level
		_update_ui_from_level()
		_set_status("Level loaded: " + level.level_name)
	else:
		_set_status("Failed to load level")


func _on_new_pressed() -> void:
	_create_new_level()


func _on_close_pressed() -> void:
	editor_closed.emit()
	hide()


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
	# Update metadata before playing
	_on_level_metadata_changed()
	
	var errors = current_level.validate()
	if errors.size() > 0:
		_set_status("Cannot play: " + errors[0])
		return
	
	print("LevelEditor: Playing level with map: ", current_level.map_glb_path)
	print("LevelEditor: Token count: ", current_level.token_placements.size())
	
	play_level_requested.emit(current_level)
	_set_status("Starting level: " + current_level.level_name)
