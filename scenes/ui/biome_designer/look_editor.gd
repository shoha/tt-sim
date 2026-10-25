class_name DesignerLookEditor
extends VBoxContainer

## The ground look editor of the biome designer (step S9), shown in place of the rule inspector
## when the ground strip's Look... is pressed. One row per field of DesignerLookFields, in the
## contract's groups: sliders for numbers, three sliders for a triple, a colour picker for a
## colour, and the zone colours as a short list. An edit goes to the model (DesignerLookEdits) and
## from there to the map: the session lays the draft over the palette and bakes the ground look
## again in place (GroundLookBake, one GPU pass), so the proving ground follows the slider. A field
## that differs from the library's is marked; right-click its label to put it back. The words under
## the title say where an edit lands (every season, or one season's changes: the ground strip's
## "Applies to"), the validators' lines about the look show under them, and a note says the game
## draws the looks of at most four biomes per map.

signal closed

const MAX_NOTE := (
	"The game draws the ground look of at most %d biomes on one map; a map with more draws the "
	+ "rest with the plain ground. This proving ground uses %d."
)
const NO_LOOK := (
	"This biome has no ground look: its ground is drawn plain, with the surface's own colour."
)
const NEEDS_BASE := "Add a look for every season first; a season then changes parts of it."
const COLOR_ROWS_MAX := 4

var session: BiomeDesignerSession = null

var _rows: Dictionary = {}
var _title_words: Label
var _reset_all: Button
var _no_look: Label
var _add_look: Button
var _slots_note: Label
var _issues: VBoxContainer
var _body: VBoxContainer
var _colors_box: VBoxContainer
var _color_add: Button
var _color_remove: Button
var _syncing: bool = false


func _init() -> void:
	name = "LookEditor"
	visible = false


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	var head := HBoxContainer.new()
	head.name = "Head"
	var title := Label.new()
	title.text = "Ground look"
	title.theme_type_variation = &"H3"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_reset_all = Button.new()
	_reset_all.name = "ResetAll"
	_reset_all.text = "Reset all"
	_reset_all.tooltip_text = "Put every field back to the library's look."
	_reset_all.pressed.connect(
		func() -> void: DesignerLookEdits.reset_all(session.model, session.edit_season)
	)
	head.add_child(_reset_all)
	var close := Button.new()
	close.name = "Close"
	close.text = "Done"
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)
	add_child(head)
	_title_words = DesignerRows.caption("Target", "")
	add_child(_title_words)
	_slots_note = DesignerRows.caption("SlotsNote", "")
	add_child(_slots_note)
	_no_look = DesignerRows.caption("NoLook", NO_LOOK)
	add_child(_no_look)
	_add_look = Button.new()
	_add_look.name = "AddLook"
	_add_look.text = "Add a ground look"
	_add_look.pressed.connect(func() -> void: DesignerLookEdits.add_look(session.model))
	add_child(_add_look)
	_issues = VBoxContainer.new()
	_issues.name = "Issues"
	add_child(_issues)
	_body = VBoxContainer.new()
	_body.name = "Groups"
	add_child(_body)
	for group in DesignerLookFields.GROUPS:
		_body.add_child(_build_group(group))
	session.model.changed.connect(func(_reason: String) -> void: _sync())
	session.edit_target_changed.connect(func(_season: String) -> void: _sync())
	session.compare.changed.connect(_sync)
	_sync()


## The PropertyRows of (`group`, `key`): one, or three for a triple; [] when there is none.
func rows_of(group: String, key: String) -> Array:
	return _rows.get("%s.%s" % [group, key], [])


func _build_group(group: Dictionary) -> Foldout:
	var section := DesignerRows.section("Group_" + String(group["id"]), String(group["label"]))
	section.tooltip_text = String(group["tip"])
	for field: Dictionary in group["fields"]:
		var made: Array = []
		var group_id := String(group["id"])
		var key := String(field["key"])
		match String(field["kind"]):
			"number":
				made.append(_number_row(section, group_id, field, -1))
			"triple":
				for i in 3:
					made.append(_number_row(section, group_id, field, i))
			"color":
				made.append(_color_row(section, group_id, field, "Row_%s_%s" % [group_id, key], -1))
			"colors":
				_colors_box = VBoxContainer.new()
				_colors_box.name = "ZoneColours"
				section.add_child(_colors_box)
				var buttons := HBoxContainer.new()
				buttons.name = "ColourButtons"
				_color_add = DesignerRows.chip("AddColour", "+ colour", "Add a fourth zone colour.")
				_color_add.pressed.connect(_on_add_color)
				buttons.add_child(_color_add)
				_color_remove = DesignerRows.chip(
					"RemoveColour", "- colour", "Remove the last zone colour (three stay)."
				)
				_color_remove.pressed.connect(
					func() -> void:
						var count: int = _colors_box.get_child_count()
						DesignerLookEdits.remove_zone_color(
							session.model, session.edit_season, count - 1
						)
				)
				buttons.add_child(_color_remove)
				section.add_child(buttons)
		_rows["%s.%s" % [group_id, key]] = made
	return section


func _number_row(parent: Control, group: String, field: Dictionary, index: int) -> PropertyRow:
	var key := String(field["key"])
	var label := String(field["label"])
	if index >= 0:
		label = "%s, %s" % [label, (field["labels"] as Array)[index]]
	var row := DesignerRows.number(
		"Row_%s_%s%s" % [group, key, "" if index < 0 else "_%d" % index],
		label,
		float(field["low"]),
		float(field["high"]),
		float(field["step"]),
		String(field["tip"]),
		String(field.get("unit", ""))
	)
	row.allow_greater = false
	row.value_changed.connect(_on_number.bind(group, key, index))
	row.reset_requested.connect(_on_reset.bind(group, key))
	parent.add_child(row)
	return row


func _color_row(
	parent: Control, group: String, field: Dictionary, row_name: String, index: int
) -> PropertyRow:
	var row := PropertyRow.new()
	row.name = row_name
	row.label = String(field["label"]) if index < 0 else "Zone %d" % (index + 1)
	row.show_slider = false
	row.show_color = true
	row.tooltip_text = String(field.get("tip", ""))
	if index < 0:
		row.color_changed.connect(_on_color.bind(group, String(field["key"])))
		row.reset_requested.connect(_on_reset.bind(group, String(field["key"])))
	else:
		row.color_changed.connect(_on_zone_color.bind(index))
		row.reset_requested.connect(_on_reset.bind("zones", "colors_linear"))
	parent.add_child(row)
	return row


func _sync() -> void:
	if session == null:
		return
	_syncing = true
	var model := session.model
	var season := session.edit_season
	var base_look := DesignerLookEdits.has_look(model, "")
	var has_look := DesignerLookEdits.has_look(model, season)
	_title_words.text = (
		"Editing the biome's own look, which every season shares."
		if season == ""
		else "Editing %s only; its other fields come from the biome's look." % season.capitalize()
	)
	_no_look.text = NO_LOOK if season == "" else NEEDS_BASE
	_no_look.visible = not base_look
	_add_look.visible = not base_look and season == ""
	_body.visible = base_look
	_reset_all.disabled = not base_look
	var looked := DesignerLookEdits.looked_biomes(session.compare.ids())
	_slots_note.text = MAX_NOTE % [GroundLookUniforms.SLOTS, looked]
	if base_look or has_look:
		for entry in DesignerLookFields.GROUPS:
			for field: Dictionary in entry["fields"]:
				_sync_field(season, String(entry["id"]), field)
		_sync_colors(season)
	_show_issues(season)
	_syncing = false


func _sync_field(season: String, group: String, field: Dictionary) -> void:
	var key := String(field["key"])
	var rows: Array = _rows.get("%s.%s" % [group, key], [])
	var shown: Variant = DesignerLookEdits.value(session.model, season, group, key)
	var changed := DesignerLookEdits.is_changed(session.model, season, group, key)
	var problem := DesignerLookEdits.field_problem(session.model, season, group, key)
	match String(field["kind"]):
		"number":
			var row := rows[0] as PropertyRow
			row.set_value_no_signal(float(shown) if shown is float or shown is int else 0.0)
			_mark(row, changed, field, problem)
		"triple":
			if not shown is Array or (shown as Array).size() != 3:
				return
			for i in 3:
				var row := rows[i] as PropertyRow
				row.set_value_no_signal(float((shown as Array)[i]))
				_mark(row, changed, field, problem)
		"color":
			var row := rows[0] as PropertyRow
			row.set_color_no_signal(DesignerLookEdits.display_color(shown))
			_mark(row, changed, field, problem)


func _mark(row: PropertyRow, changed: bool, field: Dictionary, problem: String) -> void:
	row.overridden = changed
	var tip := String(field["tip"])
	if changed:
		tip += " Right-click the name to put the library's value back."
	if problem != "":
		tip += " Problem: %s." % problem
	row.tooltip_text = tip


## The zone colour rows, one per colour the look has.
func _sync_colors(season: String) -> void:
	var colors: Array = DesignerLookEdits.value(session.model, season, "zones", "colors_linear")
	var field := DesignerLookFields.spec("zones", "colors_linear")
	var changed := DesignerLookEdits.is_changed(session.model, season, "zones", "colors_linear")
	while _colors_box.get_child_count() > colors.size():
		var extra := _colors_box.get_child(_colors_box.get_child_count() - 1)
		_colors_box.remove_child(extra)
		extra.queue_free()
	while _colors_box.get_child_count() < colors.size():
		var index := _colors_box.get_child_count()
		_color_row(_colors_box, "zones", field, "Colour_%d" % index, index)
	for i in colors.size():
		var row := _colors_box.get_child(i) as PropertyRow
		row.set_color_no_signal(DesignerLookEdits.display_color(colors[i]))
		row.overridden = changed
	_color_add.visible = colors.size() < GroundLook.MAX_COLORS
	_color_remove.visible = colors.size() > GroundLook.MIN_COLORS


func _show_issues(season: String) -> void:
	for child in _issues.get_children():
		_issues.remove_child(child)
		child.queue_free()
	var lines: Array[String] = DesignerLookEdits.warnings(session.model, season)
	for entry in DesignerLookFields.GROUPS:
		for field: Dictionary in entry["fields"]:
			var problem := DesignerLookEdits.field_problem(
				session.model, season, String(entry["id"]), String(field["key"])
			)
			if problem != "":
				lines.append("%s.%s %s" % [entry["id"], field["key"], problem])
	for line in lines:
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = IconButton.load_icon("alert-triangle")
		icon.modulate = ThemeColors.of(self, ThemeColors.WARNING)
		icon.custom_minimum_size = Vector2(18.0, 18.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		row.add_child(DesignerRows.caption("Issue", line))
		_issues.add_child(row)


func _on_number(value: float, group: String, key: String, index: int) -> void:
	if _syncing:
		return
	var model := session.model
	var season := session.edit_season
	if index < 0:
		DesignerLookEdits.set_value(model, season, group, key, value, true)
		return
	var triple: Array = DesignerLookEdits.value(model, season, group, key)
	triple[index] = value
	DesignerLookEdits.set_value(model, season, group, key, triple, true)


func _on_color(color: Color, group: String, key: String) -> void:
	if _syncing:
		return
	var linear := color.srgb_to_linear()
	var triple := [snappedf(linear.r, 0.0001), snappedf(linear.g, 0.0001), snappedf(linear.b, 0.0001)]
	DesignerLookEdits.set_value(session.model, session.edit_season, group, key, triple, true)


func _on_zone_color(color: Color, index: int) -> void:
	if not _syncing:
		DesignerLookEdits.set_zone_color(session.model, session.edit_season, index, color, true)


func _on_add_color() -> void:
	var colors: Array = DesignerLookEdits.value(
		session.model, session.edit_season, "zones", "colors_linear"
	)
	if not colors.is_empty() and colors.size() < GroundLook.MAX_COLORS:
		var last: Color = DesignerLookEdits.display_color(colors[colors.size() - 1])
		DesignerLookEdits.set_zone_color(
			session.model, session.edit_season, colors.size(), last.lightened(0.15)
		)


func _on_reset(group: String, key: String) -> void:
	DesignerLookEdits.reset_value(session.model, session.edit_season, group, key)
