class_name DesignerCollectionDialog
extends Control

## "Save as new collection" (design doc 4.4 and the user's decision that the official library is
## read-only): asks for the new collection's name, shows the id it will have (the name in
## lower-case words with underscores, made unique among the libraries that exist) and says what
## the copy is: the biome, with its plants still in the collection they came from, as a
## dependency. Emits `confirmed(id, name)` or `cancelled`. The id rules are LibraryIds'.

signal confirmed(collection_id: String, collection_name: String)
signal cancelled

const MAX_NAME := 48
const MAX_ID := LibraryContracts.MAX_LIBRARY_ID
## Characters left free in the id for a "_2" that makes it unique.
const ID_SUFFIX_ROOM := 4

var existing: Array[String] = []

var _name_edit: LineEdit
var _id_label: Label
var _problem: Label
var _create: Button
var _header: MenuHeader


## `with_scrim` false when the dialog stands over a sheet that has its own scrim (one scrim:
## UI_TASTE G1).
func _init(with_scrim: bool = true) -> void:
	name = "CollectionDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if with_scrim:
		var scrim := Scrim.new()
		scrim.name = "Scrim"
		scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(460.0, 0.0)
	centre.add_child(sheet)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"BoxContainerSpaced"
	sheet.add_child(column)
	_header = MenuHeader.new()
	_header.setup(
		"Save as new %s" % LibraryNames.lower(),
		"A copy of this biome in %s of your own." % LibraryNames.article()
	)
	column.add_child(_header)
	column.add_child(DesignerRows.caption("Explain", explanation()))
	_name_edit = LineEdit.new()
	_name_edit.name = "CollectionName"
	_name_edit.placeholder_text = "Name of the %s" % LibraryNames.lower()
	_name_edit.max_length = MAX_NAME
	_name_edit.text_changed.connect(func(_text: String) -> void: _check())
	_name_edit.text_submitted.connect(func(_text: String) -> void: _confirm())
	column.add_child(_name_edit)
	_id_label = DesignerRows.caption("IdLine", "")
	column.add_child(_id_label)
	_problem = DesignerRows.caption("Problem", "")
	column.add_child(_problem)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.theme_type_variation = &"Secondary"
	cancel.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(cancel)
	_create = Button.new()
	_create.name = "Create"
	_create.text = "Create"
	_create.theme_type_variation = &"Primary"
	_create.pressed.connect(_confirm)
	buttons.add_child(_create)
	column.add_child(buttons)


## Opens the dialog with `default_name`; `heading` and `action` word it for where it was asked
## (the picker says "Make my own copy").
func open(
	default_name: String, taken: Array[String], heading: String = "", action: String = "Create"
) -> void:
	_header.title_label.text = heading if heading != "" else "Save as new %s" % LibraryNames.lower()
	_create.text = action
	existing = taken
	_name_edit.text = default_name
	_check()
	_name_edit.grab_focus()
	_name_edit.select_all()


## The id a collection called `wanted_name` would get among `taken` ids: lower-case words joined
## by underscores, a leading digit prefixed, a number appended when it is taken.
static func id_for(wanted_name: String, taken: Array[String]) -> String:
	var id := ""
	for character in wanted_name.strip_edges().to_lower():
		var code := character.unicode_at(0)
		var letter := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if letter or digit:
			id += character
		elif not id.ends_with("_") and id != "":
			id += "_"
	id = id.trim_suffix("_")
	if id == "" or (id.unicode_at(0) >= 48 and id.unicode_at(0) <= 57) or id.length() < 2:
		id = "my_" + id if id != "" else "my_" + LibraryNames.lower()
	id = id.substr(0, MAX_ID - ID_SUFFIX_ROOM).trim_suffix("_")
	var candidate := id
	var n := 2
	while (
		candidate in taken
		or candidate in LibraryContracts.RESERVED_LIBRARY_IDS
		or candidate == LibraryContracts.CORE_ID
	):
		candidate = "%s_%d" % [id, n]
		n += 1
	return candidate


## What the dialog says the copy is.
static func explanation() -> String:
	return (
		(
			"The copy keeps using the plants of the %s it came from, so you can design from "
			% LibraryNames.lower()
		)
		+ "its assets without copying them. You can add plants of your own later."
	)


func current_id() -> String:
	return id_for(_name_edit.text, existing)


func _check() -> void:
	var id := current_id()
	var problems := LibraryIds.library_problems(id)
	_id_line(id)
	_problem.text = String(problems[0]) if not problems.is_empty() else ""
	_create.disabled = _name_edit.text.strip_edges() == "" or not problems.is_empty()


func _id_line(id: String) -> void:
	_id_label.text = "Folder and id: %s" % id


func _confirm() -> void:
	if _create.disabled:
		return
	confirmed.emit(current_id(), _name_edit.text.strip_edges())
