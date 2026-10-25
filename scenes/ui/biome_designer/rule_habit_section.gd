class_name DesignerHabitSection
extends Foldout

## The last section of the rule inspector (design doc 4.3): where the rule's plants live and
## what they keep company with. The water habit (from the role, none, bank, emergent, arid) and
## charred; how the plants stand on a slope (align); the clump (off, or a preset of scattered
## stones, patches of flowers, drifts, or the grass mass, with its four main numbers); the near
## and avoid relations (a rule or a whole role, a distance, a transition and an influence). The
## per-season changes of a rule are DesignerSeasonSection's.

const WATER_OPTIONS: Array = [
	[null, "From the role"],
	["", "Away from water"],
	["bank", "On the bank"],
	["emergent", "In the water"],
	["arid", "Arid ground"],
]
const ALIGN_OPTIONS: Array = [
	[null, "From the role"], ["upright", "Upright"], ["normal", "Along the ground"]
]
const CLUMP_PRESETS := {
	"scattered":
	{"children_spacing_m": 0.25, "parents_per_m2": 0.05, "radius_m": 1.2, "transition_m": 0.8},
	"patches":
	{"children_spacing_m": 0.12, "parents_per_m2": 0.08, "radius_m": 0.9, "transition_m": 0.8},
	"drifts":
	{"children_spacing_m": 0.12, "parents_per_m2": 0.12, "radius_m": 2.2, "transition_m": 1.4},
}
const CLUMP_OPTIONS: Array = [
	["off", "Off"],
	["scattered", "Scattered"],
	["patches", "Patches"],
	["drifts", "Drifts"],
	["custom", "Custom"]
]
const CLUMP_ROWS: Array[Dictionary] = [
	{
		"field": "parents_per_m2",
		"label": "Clumps per m2",
		"low": 0.005,
		"high": 1.0,
		"step": 0.005,
		"unit": ""
	},
	{
		"field": "radius_m",
		"label": "Clump radius",
		"low": 0.2,
		"high": 8.0,
		"step": 0.05,
		"unit": "m"
	},
	{
		"field": "transition_m",
		"label": "Clump edge",
		"low": 0.0,
		"high": 6.0,
		"step": 0.05,
		"unit": "m"
	},
	{
		"field": "children_spacing_m",
		"label": "Spacing inside",
		"low": 0.0,
		"high": 2.0,
		"step": 0.01,
		"unit": "m"
	},
]
const RELATION_MAX := 32

var session: BiomeDesignerSession = null

var _key: String = ""
var _water: OptionButton
var _charred: CheckBox
var _align: OptionButton
var _clump: OptionButton
var _clump_rows: Dictionary = {}
var _near_box: VBoxContainer
var _avoid_box: VBoxContainer
var _syncing: bool = false


func _init() -> void:
	name = "Habit"
	title = "Habit, clump and company"
	button_room = true


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	_water = DesignerRows.option(
		self,
		"Water",
		"Water",
		WATER_OPTIONS,
		"Where the rule's plants grow relative to water: the role's habit unless set here."
	)
	_water.item_selected.connect(func(_index: int) -> void: _write_habit())
	_charred = CheckBox.new()
	_charred.name = "Charred"
	_charred.text = "Burnt (charred) plants"
	_charred.tooltip_text = "Plants of burnt ground: they stand where fire has been."
	_charred.toggled.connect(func(_on: bool) -> void: _write_habit())
	add_child(_charred)
	_align = DesignerRows.option(
		self,
		"Align",
		"Stands",
		ALIGN_OPTIONS,
		"Upright, or tilted to lie along the slope (rocks do)."
	)
	_align.item_selected.connect(
		func(index: int) -> void:
			if not _syncing:
				session.model.set_field(_key, "align", _align.get_item_metadata(index))
	)
	_clump = DesignerRows.option(
		self,
		"Clump",
		"Clump",
		CLUMP_OPTIONS,
		"Plants gather in clumps instead of spreading evenly."
	)
	_clump.item_selected.connect(_on_clump_preset)
	for spec in CLUMP_ROWS:
		var row := DesignerRows.number(
			"Clump_" + String(spec["field"]),
			String(spec["label"]),
			float(spec["low"]),
			float(spec["high"]),
			float(spec["step"]),
			"",
			String(spec["unit"])
		)
		row.value_changed.connect(_on_clump_number.bind(String(spec["field"])))
		add_child(row)
		_clump_rows[spec["field"]] = row
	add_child(Label.new())
	_near_box = _relation_box("near", "Keeps near")
	_avoid_box = _relation_box("avoid", "Keeps away from")
	session.model.changed.connect(func(_reason: String) -> void: _sync())


func show_rule(key: String) -> void:
	_key = key
	_sync()


func _relation_box(field: String, caption: String) -> VBoxContainer:
	var heading := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var add := DesignerRows.chip(
		"Add_" + field, "+", "Add a rule or a role to %s." % caption.to_lower()
	)
	add.pressed.connect(_on_add_relation.bind(field))
	heading.add_child(add)
	add_child(heading)
	var box := VBoxContainer.new()
	box.name = "Relations_" + field
	add_child(box)
	return box


func _sync() -> void:
	if _key == "" or session == null or not session.model.has_rule(_key):
		return
	_syncing = true
	var model := session.model
	var habit: Dictionary = model.value(_key, "habit", {})
	DesignerRows.select(_water, habit.get("water"))
	_charred.set_pressed_no_signal(bool(habit.get("charred", false)))
	DesignerRows.select(_align, model.value(_key, "align"))
	var clump: Variant = model.value(_key, "clump")
	var shape := "off"
	if clump is Dictionary:
		shape = _preset_of(clump)
	DesignerRows.select(_clump, shape)
	for field: String in _clump_rows:
		var row: PropertyRow = _clump_rows[field]
		row.visible = clump is Dictionary
		if clump is Dictionary:
			row.set_value_no_signal(float((clump as Dictionary).get(field, 0.0)))
	_show_relations(_near_box, "near")
	_show_relations(_avoid_box, "avoid")
	_syncing = false


func _write_habit() -> void:
	if _syncing or _key == "":
		return
	var habit := {}
	var water: Variant = DesignerRows.selected(_water)
	if water != null:
		habit["water"] = water
	if _charred.button_pressed:
		habit["charred"] = true
	session.model.set_field(_key, "habit", habit if not habit.is_empty() else null)


func _on_clump_preset(index: int) -> void:
	if _syncing or _key == "":
		return
	var shape := String(_clump.get_item_metadata(index))
	if shape == "off":
		session.model.set_field(_key, "clump", null)
	elif CLUMP_PRESETS.has(shape):
		var current: Variant = session.model.value(_key, "clump")
		var merged: Dictionary = (
			(current as Dictionary).duplicate() if current is Dictionary else {}
		)
		merged.merge((CLUMP_PRESETS[shape] as Dictionary).duplicate(), true)
		session.model.set_field(_key, "clump", merged)


func _on_clump_number(value: float, field: String) -> void:
	if _syncing or _key == "":
		return
	var current: Variant = session.model.value(_key, "clump")
	if not current is Dictionary:
		return
	var changed: Dictionary = (current as Dictionary).duplicate()
	changed[field] = value
	session.model.set_field(_key, "clump", changed, true)


static func _preset_of(clump: Dictionary) -> String:
	for shape: String in CLUMP_PRESETS:
		var same := true
		for field: String in CLUMP_PRESETS[shape]:
			same = (
				same
				and is_equal_approx(
					float(clump.get(field, -1.0)), float(CLUMP_PRESETS[shape][field])
				)
			)
		if same:
			return shape
	return "custom"


func _targets() -> Array:
	var out: Array = []
	for key in session.model.rule_keys():
		if key != _key:
			out.append(["rule:" + key, "Rule: " + key])
	for role: String in LibraryContracts.ROLES:
		out.append(["role:" + role, "Role: " + DesignerSlots.role_label(role)])
	return out


func _show_relations(box: VBoxContainer, field: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var items: Array = session.model.value(_key, field, [])
	for i in items.size():
		box.add_child(_relation_row(field, i, items[i]))


func _relation_row(field: String, index: int, item: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.name = "%s_%d" % [field, index]
	var line := HBoxContainer.new()
	var targets := _targets()
	var target := OptionButton.new()
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in targets.size():
		target.add_item(String(targets[i][1]), i)
		target.set_item_metadata(i, targets[i][0])
	var wanted := (
		("rule:" + String(item["rule"]))
		if item.has("rule")
		else ("role:" + String(item.get("role", "")))
	)
	DesignerRows.select(target, wanted)
	target.item_selected.connect(
		func(at: int) -> void: _edit_relation(field, index, "target", target.get_item_metadata(at))
	)
	line.add_child(target)
	var remove := DesignerRows.chip("Remove", "x", "Remove this relation.")
	remove.pressed.connect(func() -> void: _edit_relation(field, index, "remove", null))
	line.add_child(remove)
	column.add_child(line)
	for spec in [
		["distance_m", "Distance", 0.0, 30.0, 0.1, "m"],
		["transition_m", "Transition", 0.0, 20.0, 0.1, "m"],
		["influence", "Influence", 0.0, 1.0, 0.01, ""]
	]:
		var row := DesignerRows.number(
			"%s_%d_%s" % [field, index, spec[0]],
			String(spec[1]),
			float(spec[2]),
			float(spec[3]),
			float(spec[4]),
			"",
			String(spec[5])
		)
		row.set_value_no_signal(float(item.get(spec[0], 1.0 if spec[0] == "influence" else 0.0)))
		row.value_changed.connect(
			func(value: float) -> void: _edit_relation(field, index, String(spec[0]), value)
		)
		column.add_child(row)
	return column


func _on_add_relation(field: String) -> void:
	if _key == "":
		return
	var items: Array = (session.model.value(_key, field, []) as Array).duplicate(true)
	if items.size() >= RELATION_MAX:
		return
	var targets := _targets()
	if targets.is_empty():
		return
	var first := String(targets[0][0])
	var entry := {"distance_m": 3.0, "transition_m": 2.0, "influence": 0.5}
	entry[first.get_slice(":", 0)] = first.get_slice(":", 1)
	items.append(entry)
	session.model.set_field(_key, field, items)


func _edit_relation(field: String, index: int, what: String, value: Variant) -> void:
	if _syncing or _key == "":
		return
	var items: Array = (session.model.value(_key, field, []) as Array).duplicate(true)
	if index >= items.size():
		return
	if what == "remove":
		items.remove_at(index)
	elif what == "target":
		var item: Dictionary = items[index]
		item.erase("rule")
		item.erase("role")
		item[String(value).get_slice(":", 0)] = String(value).get_slice(":", 1)
	else:
		(items[index] as Dictionary)[what] = value
	session.model.set_field(_key, field, items, what != "remove" and what != "target")
