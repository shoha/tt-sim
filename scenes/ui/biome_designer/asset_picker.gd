class_name DesignerAssetPicker
extends VBoxContainer

## Panel 1 of the biome designer (design doc 4.3): the library's catalog as tiles. Search, a
## row of category chips, a row of tag chips, the grid of tiles (one per group of variants, with
## the number of rules that use it), the count of matches, and below them what to do with the
## chosen tile: add it to the selected rule, pin it there, or start a rule from it. Tiles can be
## dragged straight onto a rule chip or a slot. The catalog is the model's (the library's and its
## dependencies'); the filters are DesignerCatalog's.

signal add_requested(ref: String)
signal pin_requested(ref: String)
signal new_rule_requested(ref: String)

const GRID_COLUMNS := 3
const TILES_MIN_HEIGHT := 160.0
const TAG_CHIPS := 14
const EMPTY_TEXT := "Nothing matches. Clear a filter or search for something else."
const MORE_TEXT := "Showing the first %d of %d. Narrow the search to see the rest."

var session: BiomeDesignerSession = null

var _all: Array[Dictionary] = []
var _search: LineEdit
var _categories: HFlowContainer
var _tags: HFlowContainer
var _grid: GridContainer
var _count: Label
var _actions: HBoxContainer
var _add_button: Button
var _pin_button: Button
var _new_button: Button
var _tiles: Dictionary = {}
var _chosen: String = ""
var _picked_tags: Array = []
var _picked_categories: Array = []
var _role_filter: String = ""
var _rebuilding: bool = false
var _usage_dirty: bool = false


func _init() -> void:
	name = "AssetPicker"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "Assets"
	title.theme_type_variation = &"H3"
	add_child(title)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search the catalog"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _refilter())
	add_child(_search)
	_categories = HFlowContainer.new()
	_categories.name = "Categories"
	add_child(_categories)
	var tag_section := DesignerRows.section("TagSection", "Tags")
	_tags = HFlowContainer.new()
	_tags.name = "Tags"
	tag_section.add_child(_tags)
	add_child(tag_section)
	var scroll := ScrollContainer.new()
	scroll.name = "TileScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, TILES_MIN_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "Tiles"
	_grid.columns = GRID_COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	_count = Label.new()
	_count.name = "Count"
	_count.theme_type_variation = &"Caption"
	add_child(_count)
	_actions = HBoxContainer.new()
	_actions.name = "Actions"
	add_child(_actions)
	_add_button = _action("Add", "Add", "Add the chosen asset to the selected rule")
	_add_button.pressed.connect(func() -> void: add_requested.emit(_chosen))
	_pin_button = _action("Pin", "Pin", "Always use this asset's group in the selected rule")
	_pin_button.pressed.connect(func() -> void: pin_requested.emit(_chosen))
	_new_button = _action("NewRule", "New rule", "Start a rule from the chosen asset")
	_new_button.pressed.connect(func() -> void: new_rule_requested.emit(_chosen))
	_set_actions()


## Binds the picker to a session: the catalog of its model, and the usage badges that follow
## its edits.
func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	_all = DesignerCatalog.groups(session.model.catalog())
	_build_category_chips()
	_build_tag_chips()
	session.model.changed.connect(func(_reason: String) -> void: _refresh_usage())
	session.selection_changed.connect(func(_key: String) -> void: _set_actions())
	_refilter()


## Limits the tiles to the usual category of `role` ("" lifts it): the slot's "+" asks for it.
func set_role_filter(role: String) -> void:
	_role_filter = role
	_refilter()


## The tile of group or asset `ref`, null when it is not drawn.
func tile_of(ref: String) -> DesignerAssetTile:
	return _tiles.get(ref)


func chosen_ref() -> String:
	return _chosen


func shown_count() -> int:
	return _tiles.size()


func choose(ref: String) -> void:
	_chosen = ref
	for key: String in _tiles:
		(_tiles[key] as DesignerAssetTile).set_chosen(key == ref)
	_set_actions()


func search_for(text: String) -> void:
	_search.text = text
	_refilter()


func _action(node_name: String, label: String, tip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.tooltip_text = tip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(button)
	return button


func _build_category_chips() -> void:
	for category in DesignerCatalog.categories_in(_all):
		var chip := DesignerRows.chip(
			"Category_" + category, DesignerSlots.category_label(category), "Show only %s." % category
		)
		chip.toggle_mode = true
		chip.toggled.connect(_on_category_toggled.bind(category))
		_categories.add_child(chip)


func _build_tag_chips() -> void:
	for child in _tags.get_children():
		child.queue_free()
	var counts := DesignerCatalog.tag_counts(_all)
	for i in mini(counts.size(), TAG_CHIPS):
		var chip := Button.new()
		chip.text = String(counts[i]["tag"])
		chip.toggle_mode = true
		chip.theme_type_variation = &"Chip"
		chip.tooltip_text = "%d groups" % counts[i]["count"]
		chip.toggled.connect(_on_tag_toggled.bind(String(counts[i]["tag"])))
		_tags.add_child(chip)


func _on_category_toggled(on: bool, category: String) -> void:
	if on:
		_picked_categories.append(category)
	else:
		_picked_categories.erase(category)
	_refilter()


func _on_tag_toggled(on: bool, tag: String) -> void:
	if on:
		_picked_tags.append(tag)
	else:
		_picked_tags.erase(tag)
	_refilter()


func _refilter() -> void:
	if _rebuilding or _search == null:
		return
	_rebuilding = true
	var found := DesignerCatalog.filter(
		_all, _search.text, _picked_categories, _picked_tags, _role_filter
	)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tiles.clear()
	for record in found.slice(0, DesignerCatalog.MAX_TILES):
		var tile := DesignerAssetTile.new()
		tile.name = "Tile_" + String(record["group"]).validate_node_name()
		tile.setup(record, _uses_of(record))
		tile.set_chosen(String(record["ref"]) == _chosen)
		tile.selected_by_click.connect(choose)
		tile.activated.connect(func(ref: String) -> void: add_requested.emit(ref))
		_grid.add_child(tile)
		_tiles[record["ref"]] = tile
	if found.is_empty():
		_count.text = EMPTY_TEXT
	elif found.size() > DesignerCatalog.MAX_TILES:
		_count.text = MORE_TEXT % [DesignerCatalog.MAX_TILES, found.size()]
	else:
		_count.text = "%d of %d match" % [found.size(), _all.size()]
	_rebuilding = false


func _uses_of(record: Dictionary) -> int:
	if session == null:
		return 0
	var users := {}
	for ref: String in record["members"]:
		for key in session.model.rules_using(ref, session.model.season_ids()[session.season_index]):
			users[key] = true
	return users.size()


## Marks the usage badges stale; they are recounted once, next frame (a slider drag changes the
## draft many times a second).
func _refresh_usage() -> void:
	_usage_dirty = true
	set_process(true)


func _process(_delta: float) -> void:
	set_process(false)
	if not _usage_dirty:
		return
	_usage_dirty = false
	for key: String in _tiles:
		var tile: DesignerAssetTile = _tiles[key]
		tile.set_used_by(_uses_of(tile.info))


func _set_actions() -> void:
	var has_rule := session != null and session.selected_rule != ""
	var has_tile := _chosen != ""
	_add_button.disabled = not (has_rule and has_tile)
	_pin_button.disabled = not (has_rule and has_tile)
	_new_button.disabled = not has_tile
