class_name LibraryManager
extends AnimatedCanvasLayerPanel

## The collections the game can draw from, and the way to add more (step S6; the player-facing
## word is LibraryNames, the internals say library). A sheet over the title screen or the New map
## dialog: the list at the left (name, version and author, whether it is the game's own or the
## player's, an on switch, a problem marked), the selected one's card at the right (LibraryDetail:
## what it holds and needs, its biomes, its warnings, Verify, Show in folder, Remove), and the
## ways in below: Import file..., Import folder..., or a file dropped on the sheet, each through
## the install card (LibraryImportFlow). `core` is always on and cannot be removed; a library the
## game ships cannot be removed either. Every change (a switch, an install, a removal) rescans
## the folders and serves the libraries again (LibraryImportFlow.refresh_all), which also tells
## the open New map dialog.
##
## Built in code (no scene), like the install card: the scrim, the centring and the sheet the
## base class expects.

signal closed
## A library was turned on or off, installed, replaced or removed.
signal libraries_changed

const SHEET_WIDTH := 960.0
const LIST_WIDTH := 360.0
const MAX_BODY_HEIGHT := 540.0
const MIN_BODY_HEIGHT := 240.0
const ROW_HEIGHT := 76.0
const ICON_PX := 20.0
const VERIFY_SLICE_USEC := 6000
const ALWAYS_ON := "This one comes with the game and is always on."

var header: MenuHeader
var list_box: VBoxContainer
var detail: LibraryDetail
var flow: LibraryImportFlow
var import_file_button: Button
var import_folder_button: Button
var done_button: Button
var status_label: Label
var empty_hint: Label
var selected_id: String = ""
## The palette the built-in core is read from and the libraries are verified under (tests).
var palette_root: String = PaletteLibrary.DEFAULT_ROOT

var _closing := false
var _body: VBoxContainer
var _split: HBoxContainer
var _list_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _rows: Dictionary = {}
var _items: Array[Dictionary] = []
var _verifying := false
var _verify_cancel := false


func _init() -> void:
	name = "LibraryManager"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = Constants.LAYER_DIALOG
	var scrim := Scrim.new()
	scrim.name = "ColorRect"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.name = "CenterContainer"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var sheet := PanelContainer.new()
	sheet.name = "PanelContainer"
	sheet.custom_minimum_size.x = SHEET_WIDTH
	centre.add_child(sheet)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.theme_type_variation = &"BoxContainerSpaced"
	sheet.add_child(_body)


## Opens the manager under `parent` (the tree's root from the title or the New map dialog).
static func open(parent: Node) -> LibraryManager:
	var manager := LibraryManager.new()
	parent.add_child(manager)
	return manager


func _on_panel_ready() -> void:
	header = MenuHeader.new()
	header.name = "Header"
	header.setup(LibraryNames.title(2), LibraryNames.manager_caption(), true)
	header.close_requested.connect(close)
	_body.add_child(header)
	_build_split()
	_build_footer()
	flow = LibraryImportFlow.new()
	flow.name = "ImportFlow"
	flow.host = get_tree().root
	add_child(flow)
	flow.installed.connect(_on_installed)
	flow.busy_changed.connect(_on_flow_busy)
	LibraryImporter.sweep_incoming()
	refresh_list()
	UIManager.register_overlay($ColorRect as Control)
	get_viewport().size_changed.connect(_fit_to_canvas)
	_fit_to_canvas()
	get_window().files_dropped.connect(_on_files_dropped)


func _exit_tree() -> void:
	super._exit_tree()
	var window := get_window()
	if window != null and window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.disconnect(_on_files_dropped)
	if get_viewport() != null and get_viewport().size_changed.is_connected(_fit_to_canvas):
		get_viewport().size_changed.disconnect(_fit_to_canvas)


func _build_split() -> void:
	_split = HBoxContainer.new()
	_split.name = "Split"
	_split.theme_type_variation = &"BoxContainerSpaced"
	_body.add_child(_split)
	var left := VBoxContainer.new()
	left.name = "ListColumn"
	left.theme_type_variation = &"BoxContainerSpaced"
	left.custom_minimum_size.x = LIST_WIDTH
	_split.add_child(left)
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "ListScroll"
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_list_scroll)
	list_box = VBoxContainer.new()
	list_box.name = "List"
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(list_box)
	_list_scroll.add_child(ScrollFade.new())
	empty_hint = Label.new()
	empty_hint.name = "EmptyHint"
	empty_hint.text = "Add more with Import, or drop %s file here." % LibraryNames.article()
	empty_hint.theme_type_variation = &"Caption"
	empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(empty_hint)
	_split.add_child(VSeparator.new())
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "DetailScroll"
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.add_child(_detail_scroll)
	_detail_scroll.add_child(ScrollFade.new())
	detail = LibraryDetail.new()
	_detail_scroll.add_child(detail)
	detail.verify_requested.connect(_on_verify_requested)
	detail.verify_cancelled.connect(func() -> void: _verify_cancel = true)
	detail.folder_requested.connect(_on_folder_requested)
	detail.remove_requested.connect(_on_remove_requested)


func _build_footer() -> void:
	_body.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.theme_type_variation = &"BoxContainerSpaced"
	_body.add_child(footer)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"Caption"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(status_label)
	import_file_button = _footer_button(
		"ImportFileButton", "Import file...", "upload", &"Secondary"
	)
	import_file_button.tooltip_text = "Add a .ttlib or .zip file"
	import_file_button.pressed.connect(func() -> void: flow.pick_file())
	import_folder_button = _footer_button(
		"ImportFolderButton", "Import folder...", "folder", &"Secondary"
	)
	import_folder_button.tooltip_text = "Add a %s that is already unpacked" % LibraryNames.lower()
	import_folder_button.pressed.connect(func() -> void: flow.pick_folder())
	done_button = _footer_button("DoneButton", "Done", "", &"Primary")
	done_button.pressed.connect(close)


func _footer_button(
	node_name: String, label: String, icon: String, variation: StringName
) -> Button:
	var button := AnimatedButton.new()
	button.name = node_name
	button.text = label
	if icon != "":
		button.icon = IconButton.load_icon(icon)
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(120, UiActions.SECONDARY_HEIGHT)
	button.set_meta("ui_silent", true)
	$CenterContainer/PanelContainer/Body/Footer.add_child(button)
	return button


# ---- the list ----


## Reads the registry again and rebuilds the list, keeping the selection when it still exists.
func refresh_list() -> void:
	_items = LibraryRegistry.list(palette_root)
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	var keep := selected_id
	for item in _items:
		_add_row(item)
	var count := _items.size()
	if status_label.text == "":
		status_label.text = LibraryNames.counted(count)
	empty_hint.visible = count <= 1
	var wanted := keep if _rows.has(keep) else (String(_items[0]["id"]) if count > 0 else "")
	select(wanted)


## Selects library `library_id` (the list row and the card).
func select(library_id: String) -> void:
	selected_id = library_id
	for id: String in _rows:
		var row: Button = _rows[id]["row"]
		row.set_pressed_no_signal(id == library_id)
		_show_selected(row, id == library_id)
	var info := {}
	for item in _items:
		if item["id"] == library_id:
			info = item
	detail.show_library(info)
	_verifying = false


## The list entry shown for `library_id`, {} when none.
func info_of(library_id: String) -> Dictionary:
	for item in _items:
		if item["id"] == library_id:
			return item
	return {}


func row_of(library_id: String) -> Button:
	return _rows[library_id]["row"] if _rows.has(library_id) else null


func toggle_of(library_id: String) -> CheckButton:
	return _rows[library_id]["toggle"] if _rows.has(library_id) else null


func _add_row(item: Dictionary) -> void:
	var id := String(item["id"])
	var holder := HBoxContainer.new()
	holder.name = "Item_%s" % id.validate_node_name()
	holder.theme_type_variation = &"BoxContainerTight"
	list_box.add_child(holder)
	var row := Button.new()
	row.name = "Row"
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.tooltip_text = String(item["name"])
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.pressed.connect(select.bind(id))
	holder.add_child(row)
	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.theme_type_variation = &"BoxContainerSpaced"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 8
	inner.offset_right = -8
	row.add_child(inner)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text)
	var title := _row_label(String(item["name"]), &"Body")
	title.name = "Name"
	text.add_child(title)
	var caption := _row_label(caption_of(item), &"Caption")
	caption.name = "Caption"
	text.add_child(caption)
	var facts := _row_label(facts_of(item), &"Caption")
	facts.name = "Facts"
	text.add_child(facts)
	var origin := LibraryDetail.chip(LibraryDetail.origin_badge(item), "Origin")
	origin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(origin)
	if String(item["status"]) == LibraryResolver.ERROR:
		var mark := TextureRect.new()
		mark.name = "Problem"
		mark.texture = IconButton.load_icon("alert-circle")
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.tooltip_text = _first(item["reasons"])
		inner.add_child(mark)
		mark.tree_entered.connect(
			func() -> void: mark.self_modulate = ThemeColors.of(mark, ThemeColors.DANGER)
		)
	var toggle := CheckButton.new()
	toggle.name = "Toggle"
	toggle.button_pressed = bool(item["enabled"])
	toggle.focus_mode = Control.FOCUS_ALL
	var locked := id == LibraryContracts.CORE_ID or String(item["source"]) == "dev"
	toggle.disabled = locked
	toggle.tooltip_text = (
		ALWAYS_ON
		if locked
		else ("Turn off %s" if toggle.button_pressed else "Turn on %s") % String(item["name"])
	)
	toggle.toggled.connect(_on_toggled.bind(id))
	holder.add_child(toggle)
	_rows[id] = {"row": row, "toggle": toggle, "holder": holder}


## The second line of a row: "v0.3.1 by Test Author", with "Off · " in front of a library that is
## turned off. Pure.
static func caption_of(item: Dictionary) -> String:
	var line := LibraryDetail.subtitle_of(item).split(" · ")[0]
	if not bool(item["enabled"]):
		line = ("Off · " + line) if line != "" else "Off"
	return line


## The third line: what it holds ("2 assets, 1 biome · 5 KB"), or, for a library that fails, why.
## Pure.
static func facts_of(item: Dictionary) -> String:
	if String(item["status"]) == LibraryResolver.ERROR:
		return _first(item["reasons"])
	var line := LibraryDetail.contents_text(item)
	if String(item["source"]) != "builtin":
		line += " · " + LibraryImporter.size_text(int(item["bytes"]))
	return line


static func _first(lines: Array) -> String:
	return String(lines[0]) if not lines.is_empty() else ""


func _row_label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _show_selected(row: Button, on: bool) -> void:
	var text := row.get_node("Inner/Text")
	(text.get_node("Name") as Label).theme_type_variation = &"BodyOnSelected" if on else &"Body"
	for line: String in ["Caption", "Facts"]:
		(text.get_node(line) as Label).theme_type_variation = (
			&"CaptionOnSelected" if on else &"Caption"
		)


# ---- actions ----


func _on_toggled(on: bool, library_id: String) -> void:
	if not LibraryRegistry.set_enabled(library_id, on):
		_say("That could not be saved.")
		refresh_list()
		return
	LibraryImportFlow.refresh_all()
	var shown := String(info_of(library_id).get("name", library_id))
	_say("%s turned %s." % [shown, "on" if on else "off"])
	refresh_list()
	libraries_changed.emit()


func _on_installed(library_id: String, replaced: bool) -> void:
	var shown := String(info_of(library_id).get("name", library_id))
	selected_id = library_id
	status_label.text = ""
	refresh_list()
	_say(
		(
			"%s %s."
			% [String(info_of(library_id).get("name", shown)), "updated" if replaced else "added"]
		)
	)
	libraries_changed.emit()


func _on_flow_busy(busy: bool) -> void:
	import_file_button.disabled = busy
	import_folder_button.disabled = busy


func _on_files_dropped(files: PackedStringArray) -> void:
	if _closing or flow.is_busy() or files.is_empty():
		return
	flow.begin(files[0])


func _on_folder_requested(folder: String) -> void:
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(folder), true)


## Remove: names the maps that use it (a lazy scan of the saved levels' manifests) and asks.
func _on_remove_requested(library_id: String) -> void:
	var info := info_of(library_id)
	if info.is_empty() or String(info["source"]) != "user":
		return
	var users := LibraryInstall.levels_using(library_id, LevelManager.levels_dir)
	UIManager.show_danger_confirmation(
		"Remove %s" % info["name"],
		remove_message(String(info["name"]), users.size()),
		func() -> void: _remove_confirmed(library_id),
		"Remove"
	)


## The confirmation's words: what is deleted and what the maps that use it will do. Pure.
static func remove_message(library_name: String, map_count: int) -> String:
	var gone := (
		"%s is deleted from this computer. You can add it again from its file." % library_name
	)
	if map_count == 0:
		return gone + " No saved map uses it."
	var maps := "1 saved map uses" if map_count == 1 else "%d saved maps use" % map_count
	return gone + " %s it; opening one will ask whether to open it without those plants." % maps


func _remove_confirmed(library_id: String) -> void:
	var shown := String(info_of(library_id).get("name", library_id))
	var done := LibraryInstall.remove(library_id)
	if not bool(done["ok"]):
		UIManager.show_error(String(done["error"]))
		return
	# A library turned off and then removed must not come back turned off when it is added again.
	LibraryRegistry.set_enabled(library_id, true)
	LibraryImportFlow.refresh_all()
	selected_id = ""
	status_label.text = ""
	refresh_list()
	_say("%s removed." % shown)
	UIManager.show_success("%s removed" % shown)
	libraries_changed.emit()


## Verify: every file of the selected library against the catalog, a few per frame so the sheet
## keeps drawing, with a bar and Stop.
func _on_verify_requested(library_id: String) -> void:
	if _verifying:
		return
	var plan := LibraryVerify.plan(library_id, palette_root)
	if plan["state"] == LibraryVerify.BUILTIN:
		detail.say_cannot_verify(
			"This comes with the game; its files are checked when the game is built."
		)
		return
	if plan["state"] != LibraryVerify.READY:
		detail.say_cannot_verify("Turn it on (and fix what is listed above) to check its files.")
		return
	var assets: Array = plan["assets"]
	_verifying = true
	_verify_cancel = false
	detail.begin_verify(assets.size())
	var results: Array = []
	var index := 0
	while index < assets.size():
		var slice_end := Time.get_ticks_usec() + VERIFY_SLICE_USEC
		while index < assets.size() and Time.get_ticks_usec() < slice_end:
			results.append(LibraryVerify.check(String(assets[index]), palette_root))
			index += 1
		detail.set_verify_progress(index, assets.size())
		await get_tree().process_frame
		if not is_inside_tree() or selected_id != library_id or _verify_cancel:
			break
	if not is_inside_tree() or selected_id != library_id:
		return
	_verifying = false
	detail.finish_verify(LibraryVerify.summarize(results), _verify_cancel and index < assets.size())


## A line in the footer: the last thing that happened, in words.
func _say(text: String) -> void:
	if status_label != null:
		status_label.text = text


# ---- layout and closing ----


func _fit_to_canvas() -> void:
	if not is_inside_tree() or _split == null:
		return
	var canvas := get_viewport().get_visible_rect().size
	var sheet := $CenterContainer/PanelContainer as PanelContainer
	var margin := sheet.get_theme_constant(&"space_5", &"Space")
	sheet.custom_minimum_size.x = minf(SHEET_WIDTH, canvas.x - 2.0 * margin)
	var chrome := sheet.get_combined_minimum_size().y - _split.get_combined_minimum_size().y
	var room := canvas.y - 2.0 * margin - chrome
	var height := clampf(minf(MAX_BODY_HEIGHT, room), MIN_BODY_HEIGHT, MAX_BODY_HEIGHT)
	height = minf(height, maxf(room, 0.0))
	_list_scroll.custom_minimum_size.y = height
	_detail_scroll.custom_minimum_size.y = height


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children(_body)


func _on_after_animate_in() -> void:
	done_button.grab_focus()


func close() -> void:
	if _closing:
		return
	_closing = true
	_verify_cancel = true
	AudioManager.play(&"cancel")
	animate_out()


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
