class_name BiomeDesignerPicker
extends AnimatedCanvasLayerPanel

## The title's "Design a biome" sheet (the user's decision: the designer is for everyone, from
## the title and the collections manager). Two lists over the collections served from a folder:
## the biomes of the player's own collections, each opening in the designer, and the biomes of
## the collections that ship with the game, which open to try (their changes cannot be saved
## there) or to copy: "New biome from a core biome" names a new collection of the player's own,
## copies the biome into it (its plants stay in the collection they came from) and opens the
## copy. Opening is EventBus.biome_designer_requested; Root prepares and enters the session.
## A paper sheet over a scrim like the other dialogs (AnimatedCanvasLayerPanel), built in code.

signal closed

const WIDTH := 640.0
const LIST_HEIGHT := 260.0
const ROW_HEIGHT := 44.0

var _collection_dialog: DesignerCollectionDialog = null
var _pending: Dictionary = {}
var _body: VBoxContainer


## Shows the sheet over `parent` (Root, a menu); it frees itself when closed.
static func show_over(parent: Node) -> BiomeDesignerPicker:
	var sheet := BiomeDesignerPicker.new()
	parent.add_child(sheet)
	return sheet


func _init() -> void:
	name = "BiomeDesignerPicker"
	layer = Constants.LAYER_DIALOG
	var scrim := Scrim.new()
	scrim.name = "ColorRect"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.name = "CenterContainer"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var sheet := PanelContainer.new()
	sheet.name = "PanelContainer"
	sheet.custom_minimum_size = Vector2(WIDTH, 0.0)
	centre.add_child(sheet)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.theme_type_variation = &"BoxContainerSpaced"
	sheet.add_child(_body)


func _on_panel_ready() -> void:
	var header := MenuHeader.new()
	header.setup(
		"Design a biome",
		"Shape how a place grows. A test map opens where every change shows at once.",
		true
	)
	header.close_requested.connect(animate_out)
	_body.add_child(header)
	var all := BiomeDesignerEntry.designable()
	var own := all.filter(func(row: Dictionary) -> bool: return row["writable"])
	var shipped := all.filter(func(row: Dictionary) -> bool: return not row["writable"])
	_body.add_child(_section("Your biomes", own, false))
	_body.add_child(_section("Start from a core biome", shipped, true))
	UIManager.register_overlay($ColorRect as Control)


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not is_instance_valid(_collection_dialog):
		animate_out()
		get_viewport().set_input_as_handled()


func _section(title_text: String, rows: Array, copies: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "Section_" + title_text.validate_node_name()
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"H3"
	box.add_child(title)
	if rows.is_empty():
		var none := (
			"No collection with biomes is installed."
			if copies
			else "Nothing yet. Copy a core biome below, and it will be here."
		)
		box.add_child(DesignerRows.caption("None", none))
		return box
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, minf(LIST_HEIGHT, ROW_HEIGHT * rows.size()))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for row: Dictionary in rows:
		list.add_child(_row(row, copies))
	return box


func _row(row: Dictionary, copies: bool) -> Control:
	var line := HBoxContainer.new()
	line.name = "Row_%s_%s" % [row["library"], row["biome"]]
	var label := Label.new()
	label.text = String(row["name"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)
	var where := Label.new()
	where.text = String(row["library_name"])
	where.theme_type_variation = &"Caption"
	line.add_child(where)
	if copies:
		var copy := Button.new()
		copy.name = "Copy"
		copy.text = "Make my own copy..."
		copy.theme_type_variation = &"Secondary"
		copy.tooltip_text = "Copy this biome into a new collection of yours, then design the copy."
		copy.pressed.connect(_ask_name.bind(row))
		line.add_child(copy)
	var open := Button.new()
	open.name = "Open"
	open.text = "Try it" if copies else "Design"
	open.theme_type_variation = &"Ghost" if copies else &"Secondary"
	open.tooltip_text = (
		"Open it to experiment. Its changes can be kept only as a copy."
		if copies
		else "Open this biome in the designer."
	)
	open.pressed.connect(_open.bind(row))
	line.add_child(open)
	return line


func _open(row: Dictionary) -> void:
	animate_out()
	EventBus.biome_designer_requested.emit(row["library"], row["biome"])


func _ask_name(row: Dictionary) -> void:
	if is_instance_valid(_collection_dialog):
		return
	_pending = row
	_collection_dialog = DesignerCollectionDialog.new(false)
	_collection_dialog.cancelled.connect(
		func() -> void:
			_collection_dialog.queue_free()
			_collection_dialog = null
	)
	_collection_dialog.confirmed.connect(_make_copy)
	add_child(_collection_dialog)
	var taken: Array[String] = []
	for entry in LibraryRegistry.list():
		taken.append(String(entry["id"]))
	_collection_dialog.open(
		"My %s" % String(row["name"]), taken, "Make my own copy", "Make the copy"
	)


func _make_copy(collection_id: String, collection_name: String) -> void:
	var made := BiomeDesignerEntry.new_from(
		String(_pending["library"]), String(_pending["biome"]), collection_id, collection_name
	)
	if not made["ok"]:
		UIManager.show_error(String(made["error"]))
		return
	animate_out()
	EventBus.biome_designer_requested.emit(made["library"], made["biome"])
