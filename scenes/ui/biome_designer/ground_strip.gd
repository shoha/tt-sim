class_name DesignerGroundStrip
extends HFlowContainer

## Panel 5 of the biome designer (design doc 4.3): the biome's ground in one strip. Pickers for
## the ground, cliff, scree, water bed and shore surfaces (the palette's surfaces by role, "the
## game's choice" for none), the accents as chips with a "+" to add one, the path surfaces the
## same way, and the ground look, which opens in the ground look editor (DesignerLookEditor).
## "Applies to" says where an edit lands (step S9): every season, or one season only, in which case
## the pickers show that season's ground and write its overrides (DesignerSeasonEdits), and a
## picker left at "Same as every season" has none. Ground edits rebuild the proving ground's
## terrain (the session reopens the map), so they are slower than a rule edit.

signal look_requested

const SURFACE_FIELDS: Array[Dictionary] = [
	{"field": "surface", "label": "Ground", "role": "ground"},
	{"field": "cliff", "label": "Cliff", "role": "cliff"},
	{"field": "scree", "label": "Scree", "role": "ground"},
	{"field": "water_bed", "label": "Water bed", "role": "ground"},
	{"field": "shore", "label": "Shore", "role": "ground"},
]
const PICKER_WIDTH := 112.0
const ACCENTS_WIDTH := 230.0
const PATHS_WIDTH := 380.0
const TARGET_WIDTH := 118.0
const ACCENT_MAX := 8
const ACCENT_COVERAGE_MAX := 0.6
const ACCENT_DEFAULT := {"coverage": 0.12, "scale_m": 3.0}

var session: BiomeDesignerSession = null

var _target_column: Control
var _target: OptionButton
var _pickers: Dictionary = {}
var _hints: Dictionary = {}
var _accents: HFlowContainer
var _paths: HFlowContainer
var _menu: PopupMenu
var _menu_target: String = ""
var _menu_names: Array[String] = []
var _look_button: Button
var _density_button: Button
var _density: DesignerDensityPopup
var _syncing: bool = false


func _init() -> void:
	name = "GroundStrip"


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	_build_target()
	for spec in SURFACE_FIELDS:
		var column := VBoxContainer.new()
		column.name = "Column_" + String(spec["field"])
		var caption := Label.new()
		caption.text = String(spec["label"])
		caption.theme_type_variation = &"Caption"
		column.add_child(caption)
		var picker := OptionButton.new()
		picker.name = "Pick_" + String(spec["field"])
		picker.custom_minimum_size = Vector2(PICKER_WIDTH, 0.0)
		picker.item_selected.connect(_on_picked.bind(String(spec["field"])))
		column.add_child(picker)
		var hint := Label.new()
		hint.name = "Hint_" + String(spec["field"])
		hint.theme_type_variation = &"Caption"
		hint.visible = false
		column.add_child(hint)
		add_child(column)
		_pickers[spec["field"]] = picker
		_hints[spec["field"]] = hint
	_accents = _chip_column(
		"Accents", "accents", "Patches of other ground that show through the main one.", ACCENTS_WIDTH
	)
	_paths = _chip_column(
		"Paths", "paths", "The path surfaces the Paint tool offers first on this biome.", PATHS_WIDTH
	)
	_look_button = Button.new()
	_look_button.name = "OpenLook"
	_look_button.text = "Look..."
	_look_button.toggle_mode = true
	_look_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_look_button.tooltip_text = (
		"The ground look editor: the colour zones, the painted light, the grass masses and the "
		+ "rims, shown on the map as you edit."
	)
	_look_button.toggled.connect(func(_on: bool) -> void: look_requested.emit())
	add_child(_look_button)
	_density_button = Button.new()
	_density_button.name = "OpenDensity"
	_density_button.text = "Density..."
	_density_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_density_button.tooltip_text = (
		"A multiplier of the density of every rule of a size class, for the biome or one season."
	)
	_density_button.pressed.connect(_on_density)
	add_child(_density_button)
	_density = DesignerDensityPopup.new()
	_density.setup(session)
	add_child(_density)
	_menu = PopupMenu.new()
	_menu.name = "SurfaceMenu"
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	session.model.changed.connect(func(_reason: String) -> void: _sync())
	session.season_changed.connect(func(_index: int) -> void: _sync())
	session.edit_target_changed.connect(func(_season: String) -> void: _sync())
	_fill_pickers()
	_sync()


func picker_of(field: String) -> OptionButton:
	return _pickers.get(field)


## The density popup, for tests and probes.
func density_popup() -> DesignerDensityPopup:
	return _density


## Opens the density popup above its button (the strip is at the bottom of the screen).
func _on_density() -> void:
	_density.reset_size()
	var at := Vector2i(_density_button.get_screen_position())
	_density.popup(Rect2i(Vector2i(at.x, 0), Vector2i.ZERO))
	_density.position = Vector2i(at.x, maxi(at.y - _density.size.y - 4, 0))


## The Look... button, so the editor's visibility and the button agree.
func look_button() -> Button:
	return _look_button


## The picker of where an edit lands, for tests and probes.
func target_picker() -> OptionButton:
	return _target


func _build_target() -> void:
	_target_column = VBoxContainer.new()
	_target_column.name = "Column_target"
	var caption := Label.new()
	caption.text = "Applies to"
	caption.theme_type_variation = &"Caption"
	_target_column.add_child(caption)
	_target = OptionButton.new()
	_target.name = "Target"
	_target.custom_minimum_size = Vector2(TARGET_WIDTH, 0.0)
	_target.tooltip_text = (
		"Every season, or the changes of one season only (the other seasons keep the biome's "
		+ "own ground and look)."
	)
	_target.item_selected.connect(
		func(index: int) -> void:
			if not _syncing:
				session.set_edit_season(String(_target.get_item_metadata(index)))
	)
	_target_column.add_child(_target)
	add_child(_target_column)


func _chip_column(
	caption_text: String, field: String, tip: String, width: float
) -> HFlowContainer:
	var column := VBoxContainer.new()
	column.name = "Column_" + field
	column.custom_minimum_size = Vector2(width, 0.0)
	var head := HBoxContainer.new()
	var caption := Label.new()
	caption.text = caption_text
	caption.theme_type_variation = &"Caption"
	caption.tooltip_text = tip
	head.add_child(caption)
	var add := DesignerRows.chip("Add_" + field, "+", "Add a surface.")
	add.pressed.connect(_on_add.bind(field, add))
	head.add_child(add)
	var back := DesignerRows.chip(
		"Same_" + field, "same as every season", "Take this season's change away."
	)
	back.visible = false
	back.pressed.connect(_on_same.bind(field))
	head.add_child(back)
	column.add_child(head)
	var flow := HFlowContainer.new()
	flow.name = "Chips_" + field
	column.add_child(flow)
	add_child(column)
	return flow


func _fill_pickers() -> void:
	for spec in SURFACE_FIELDS:
		var picker: OptionButton = _pickers[spec["field"]]
		picker.clear()
		picker.add_item("Automatic", 0)
		picker.set_item_metadata(0, "")
		var names := PaletteLibrary.surfaces_with_role(String(spec["role"]))
		for i in names.size():
			picker.add_item(AuthoringPanel.surface_label(names[i]), i + 1)
			picker.set_item_metadata(i + 1, names[i])


## The ground field `field` as the target sees it: the biome's, or the season's.
func _view(field: String) -> Variant:
	var season := session.edit_season
	var def := BiomeSeasons.effective(session.model.def, season) if season != "" else session.model.def
	var ground: Variant = def.get("ground")
	return (ground as Dictionary).get(field) if ground is Dictionary else null


func _overridden(field: String) -> bool:
	return (
		session.edit_season != ""
		and DesignerSeasonEdits.has_ground_override(session.model, session.edit_season, field)
	)


func _sync() -> void:
	_syncing = true
	_sync_target()
	var season := session.edit_season
	for spec in SURFACE_FIELDS:
		var field := String(spec["field"])
		var value: Variant = _view(field)
		var picker: OptionButton = _pickers[field]
		picker.set_item_text(0, "As biome" if season != "" else "Automatic")
		var runtime := "" if value == null else SurfaceStore.runtime_name(String(value))
		if season != "" and not _overridden(field):
			runtime = ""  # Shown as "same as every season"; the effective value is in the hint.
		if not DesignerRows.select(picker, runtime):
			picker.add_item(AuthoringPanel.surface_label(runtime), picker.item_count)
			picker.set_item_metadata(picker.item_count - 1, runtime)
			picker.select(picker.item_count - 1)
		var hint: Label = _hints[field]
		hint.visible = season != "" and _overridden(field)
		hint.text = "%s only" % season.capitalize()
		picker.tooltip_text = (
			"" if season == "" or _overridden(field) else "Now: %s" % _surface_words(value)
		)
	_show_chips(_accents, "accents")
	_show_chips(_paths, "paths")
	_syncing = false


func _surface_words(value: Variant) -> String:
	if value == null or String(value) == "":
		return "automatic"
	return AuthoringPanel.surface_label(SurfaceStore.runtime_name(String(value)))


func _sync_target() -> void:
	var ids := session.model.season_ids()
	_target_column.visible = ids.size() > 1
	_target.clear()
	_target.add_item("Every season", 0)
	_target.set_item_metadata(0, "")
	for i in ids.size():
		_target.add_item("%s only" % ids[i].capitalize(), i + 1)
		_target.set_item_metadata(i + 1, ids[i])
	DesignerRows.select(_target, session.edit_season)


func _show_chips(flow: HFlowContainer, field: String) -> void:
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	var items: Array = _view(field) if _view(field) is Array else []
	var back := flow.get_parent().find_child("Same_" + field, true, false) as Button
	back.visible = _overridden(field)
	for i in items.size():
		var surface := String(items[i]["surface"]) if items[i] is Dictionary else String(items[i])
		var tip := "Remove %s." % surface
		if items[i] is Dictionary:
			tip += (
				" Coverage %s, patch %s m."
				% [items[i].get("coverage", "?"), items[i].get("scale_m", "?")]
			)
		var chip := DesignerRows.chip(
			"Item_%d" % i, AuthoringPanel.surface_label(surface) + "  x", tip
		)
		chip.pressed.connect(_remove.bind(field, i))
		flow.add_child(chip)


func _on_picked(index: int, field: String) -> void:
	if _syncing:
		return
	var picker: OptionButton = _pickers[field]
	var surface := String(picker.get_item_metadata(index))
	if session.edit_season != "":
		DesignerSeasonEdits.set_ground(
			session.model, session.edit_season, field, surface if surface != "" else null
		)
		return
	DesignerBiomeEdits.set_ground(session.model, field, surface)


func _on_same(field: String) -> void:
	if session.edit_season != "":
		DesignerSeasonEdits.set_ground(session.model, session.edit_season, field, null)


func _on_add(field: String, button: Button) -> void:
	_menu_target = field
	_menu.clear()
	_menu_names = PaletteLibrary.surfaces_with_role("built" if field == "paths" else "ground")
	for i in _menu_names.size():
		_menu.add_item(AuthoringPanel.surface_label(_menu_names[i]), i)
	_menu.position = Vector2i(button.get_screen_position() + Vector2(0.0, button.size.y))
	_menu.popup()


func _on_menu(id: int) -> void:
	if id < 0 or id >= _menu_names.size():
		return
	var surface := _menu_names[id]
	var held: Variant = _view(_menu_target)
	var items: Array = (held as Array).duplicate(true) if held is Array else []
	if _menu_target == "paths":
		if not surface in items and items.size() < 32:
			items.append(surface)
		_write_list("paths", items)
		return
	if items.size() >= ACCENT_MAX:
		return
	var used := 0.0
	for accent: Dictionary in items:
		used += float(accent.get("coverage", 0.0))
	var coverage := minf(float(ACCENT_DEFAULT["coverage"]), ACCENT_COVERAGE_MAX - used)
	if coverage <= 0.0:
		return
	items.append({"surface": surface, "coverage": coverage, "scale_m": ACCENT_DEFAULT["scale_m"]})
	_write_list("accents", items)


func _remove(field: String, index: int) -> void:
	var held: Variant = _view(field)
	if not held is Array or index >= (held as Array).size():
		return
	var items: Array = (held as Array).duplicate(true)
	items.remove_at(index)
	_write_list(field, items)


## Writes the paths or the accents: the biome's (an empty list erases them) or the season's (an
## empty list is a season with none).
func _write_list(field: String, items: Array) -> void:
	if session.edit_season != "":
		DesignerSeasonEdits.set_ground(session.model, session.edit_season, field, items)
	elif field == "paths":
		DesignerBiomeEdits.set_paths(session.model, items)
	else:
		DesignerBiomeEdits.set_accents(session.model, items)
