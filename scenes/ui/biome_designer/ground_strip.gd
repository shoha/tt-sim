class_name DesignerGroundStrip
extends HFlowContainer

## Panel 5 of the biome designer (design doc 4.3): the biome's ground in one strip. Pickers for
## the ground, cliff, scree, water bed and shore surfaces (the palette's surfaces by role, "the
## game's choice" for none), the accents as chips with a "+" to add one, the path surfaces the
## same way, and the ground look, which opens in the ground look editor of step S9 (not built
## yet; the strip passes the look through untouched). Ground edits rebuild the proving ground's
## terrain (the session reopens the map), so they are slower than a rule edit.

const SURFACE_FIELDS: Array[Dictionary] = [
	{"field": "surface", "label": "Ground", "role": "ground"},
	{"field": "cliff", "label": "Cliff", "role": "cliff"},
	{"field": "scree", "label": "Scree", "role": "ground"},
	{"field": "water_bed", "label": "Water bed", "role": "ground"},
	{"field": "shore", "label": "Shore", "role": "ground"},
]
const PICKER_WIDTH := 124.0
const CHIPS_WIDTH := 400.0
const ACCENT_MAX := 8
const ACCENT_COVERAGE_MAX := 0.6
const ACCENT_DEFAULT := {"coverage": 0.12, "scale_m": 3.0}

var session: BiomeDesignerSession = null

var _pickers: Dictionary = {}
var _accents: HFlowContainer
var _paths: HFlowContainer
var _menu: PopupMenu
var _menu_target: String = ""
var _menu_names: Array[String] = []
var _syncing: bool = false


func _init() -> void:
	name = "GroundStrip"


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
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
		add_child(column)
		_pickers[spec["field"]] = picker
	_accents = _chip_column(
		"Accents", "accents", "Patches of other ground that show through the main one."
	)
	_paths = _chip_column(
		"Paths", "paths", "The path surfaces the Paint tool offers first on this biome."
	)
	var look := Button.new()
	look.name = "OpenLook"
	look.text = "Look..."
	look.disabled = true
	look.tooltip_text = (
		"The ground look editor (zones, cover, scale, light) is the next designer step. "
		+ "The biome's look is kept as it is."
	)
	add_child(look)
	_menu = PopupMenu.new()
	_menu.name = "SurfaceMenu"
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	session.model.changed.connect(func(_reason: String) -> void: _sync())
	_fill_pickers()
	_sync()


func picker_of(field: String) -> OptionButton:
	return _pickers.get(field)


func _chip_column(caption_text: String, field: String, tip: String) -> HFlowContainer:
	var column := VBoxContainer.new()
	column.name = "Column_" + field
	column.custom_minimum_size = Vector2(CHIPS_WIDTH, 0.0)
	var head := HBoxContainer.new()
	var caption := Label.new()
	caption.text = caption_text
	caption.theme_type_variation = &"Caption"
	caption.tooltip_text = tip
	head.add_child(caption)
	var add := DesignerRows.chip("Add_" + field, "+", "Add a surface.")
	add.pressed.connect(_on_add.bind(field, add))
	head.add_child(add)
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


func _sync() -> void:
	_syncing = true
	for spec in SURFACE_FIELDS:
		var value: Variant = DesignerBiomeEdits.ground_value(session.model, String(spec["field"]))
		var picker: OptionButton = _pickers[spec["field"]]
		# A `lib://<library>/<surface>` reference names the palette surface of that library.
		var runtime := "" if value == null else SurfaceStore.runtime_name(String(value))
		if not DesignerRows.select(picker, runtime):
			picker.add_item(AuthoringPanel.surface_label(runtime), picker.item_count)
			picker.set_item_metadata(picker.item_count - 1, runtime)
			picker.select(picker.item_count - 1)
	_show_chips(_accents, "accents")
	_show_chips(_paths, "paths")
	_syncing = false


func _show_chips(flow: HFlowContainer, field: String) -> void:
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	var items: Array = (
		DesignerBiomeEdits.ground_value(session.model, field)
		if DesignerBiomeEdits.ground_value(session.model, field) != null
		else []
	)
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
	DesignerBiomeEdits.set_ground(session.model, field, String(picker.get_item_metadata(index)))


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
	var held: Variant = DesignerBiomeEdits.ground_value(session.model, _menu_target)
	var items: Array = (held as Array).duplicate(true) if held is Array else []
	if _menu_target == "paths":
		if not surface in items and items.size() < 32:
			items.append(surface)
		DesignerBiomeEdits.set_paths(session.model, items)
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
	DesignerBiomeEdits.set_accents(session.model, items)


func _remove(field: String, index: int) -> void:
	var held: Variant = DesignerBiomeEdits.ground_value(session.model, field)
	if not held is Array or index >= (held as Array).size():
		return
	var items: Array = (held as Array).duplicate(true)
	items.remove_at(index)
	if field == "paths":
		DesignerBiomeEdits.set_paths(session.model, items)
	else:
		DesignerBiomeEdits.set_accents(session.model, items)
