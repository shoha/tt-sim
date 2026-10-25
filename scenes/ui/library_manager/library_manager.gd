class_name LibraryManager
extends AnimatedCanvasLayerPanel

## The collections the game can draw from, and the way to add more (step S6; the player-facing
## word is LibraryNames, the internals say library). A sheet over the title screen or the New map
## dialog: the list at the left (a LibraryRow each: name, version and author, whether it is the
## game's own or the player's, an on switch, or for a collection that fails the "Needs attention"
## pill in place of the switch), the selected one's card at the right (LibraryDetail: what it
## holds and needs, its biomes, why it fails in plain words, Verify, Show in folder, Remove), and
## the ways in below: Import file..., Import folder..., or a file dropped on the sheet, each
## through the install card (LibraryImportFlow). `core` is always on and cannot be removed; a
## library the game ships cannot be removed either. Every change (a switch, an install, a removal)
## rescans the folders and serves the libraries again (LibraryImportFlow.refresh_all), which also
## tells the open New map dialog.
##
## Rescanning (owner question 8, 2026-10-25: wary of file watches): NOTHING watches the disk. The
## folders are read again when the sheet opens, when the game window regains focus while it is
## open (NOTIFICATION_APPLICATION_FOCUS_IN) and on the Refresh button, each time behind a cheap
## change check (LibraryRegistry.disk_signature: one directory listing per root and two stat calls
## per folder); a rescan, which reads every library.json, runs only when that differs (or on the
## button). With the sheet closed there is no cost at all.
##
## Extension points for other modules (the host-received cache section, extra chips): `list_extras`
## (a box under the list, above the hint), `footer_extras` (a box in the footer before Refresh)
## and LibraryDetail.detail_extensions (callables run at the end of show_library). See
## docs/systems/library.md "Collections manager".
##
## Built in code (no scene), like the install card: the scrim, the centring and the sheet the
## base class expects.

signal closed
## A library was turned on or off, installed, replaced or removed, or the folders changed on disk.
signal libraries_changed

const SHEET_WIDTH := 1120.0
const LIST_WIDTH := 540.0
const MAX_BODY_HEIGHT := 640.0
const MIN_BODY_HEIGHT := 240.0
const ICON_PX := 20.0
const STATUS_ERROR := "error"
const STATUS_OK := "ok"

var header: MenuHeader
var list_box: VBoxContainer
var detail: LibraryDetail
var flow: LibraryImportFlow
var import_file_button: Button
var import_folder_button: Button
var refresh_button: Button
var done_button: Button
var status_label: Label
var status_icon: TextureRect
## "ok", "error" or "" for the last footer line.
var status_kind: String = ""
## The persistent one-line hint under the list: the two ways in, and Find collections.
var hint_label: Label
var catalog_button: Button = null
var summary_box: HBoxContainer
var summary_label: Label
## Verify all (button, bar with Stop, one list of results).
var verify_all: LibraryVerifyAll
## Extension point: a box under the list (the cache section of the host-received collections).
var list_extras: VBoxContainer
## Extension point: a box at the start of the footer's buttons.
var footer_extras: HBoxContainer
var selected_id: String = ""
## The palette the built-in core is read from and the libraries are verified under (tests).
var palette_root: String = PaletteLibrary.DEFAULT_ROOT
## How long one frame of Verify may spend checking (at least one file is always checked).
var verify_slice_usec: int = 6000:
	set(value):
		verify_slice_usec = value
		if verify_all != null:
			verify_all.slice_usec = value

var _closing := false
var _body: VBoxContainer
var _split: HBoxContainer
var _list_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _rows: Dictionary = {}
var _keys: Array[String] = []
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
	LibraryCacheSection.attach(self, _body)  # hook: the downloaded-collections row (own file)
	_build_footer()
	flow = LibraryImportFlow.new()
	flow.name = "ImportFlow"
	flow.host = get_tree().root
	add_child(flow)
	flow.installed.connect(_on_installed)
	flow.install_failed.connect(_on_install_failed)
	flow.busy_changed.connect(_on_flow_busy)
	LibraryImporter.sweep_incoming()
	# The folders are read again every time the sheet opens, when they differ from the last read.
	if LibraryRegistry.disk_signature() != LibraryRegistry.seen_signature():
		LibraryImportFlow.refresh_all()
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


func _notification(what: int) -> void:
	# Back in the game after a visit to the file manager: look at the folders again (cheaply).
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_inside_tree() and not _closing:
		if _body != null and list_box != null:
			rescan()


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
	_build_summary(left)
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "ListScroll"
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The rows' focus rings and the switches sit at this clip's edges: room for the ring.
	ShadowGutter.wrap(_list_scroll, ShadowGutter.Kind.RING)
	left.add_child(_list_scroll)
	list_box = VBoxContainer.new()
	list_box.name = "List"
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(list_box)
	_list_scroll.add_child(ScrollFade.new())
	_build_verify_all(left)
	list_extras = VBoxContainer.new()
	list_extras.name = "ListExtras"
	list_extras.theme_type_variation = &"BoxContainerTight"
	left.add_child(list_extras)
	_build_hint(left)
	_split.add_child(VSeparator.new())
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "DetailScroll"
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The card's buttons sit at the edge of this clipping scroll: their shadows need room.
	ShadowGutter.wrap(_detail_scroll)
	_split.add_child(_detail_scroll)
	_detail_scroll.add_child(ScrollFade.new())
	detail = LibraryDetail.new()
	_detail_scroll.add_child(detail)
	detail.verify_requested.connect(_on_verify_requested)
	detail.verify_cancelled.connect(func() -> void: _verify_cancel = true)
	detail.folder_requested.connect(_on_folder_requested)
	detail.remove_requested.connect(_on_remove_requested)
	detail.path_copied.connect(func(_path: String) -> void: _say("Folder path copied."))
	detail.new_biome_requested.connect(_on_new_biome_requested)


## The top of the list: how many collections need attention (empty when none does).
func _build_summary(parent: Control) -> void:
	summary_box = HBoxContainer.new()
	summary_box.name = "Summary"
	summary_box.theme_type_variation = &"BoxContainerSpaced"
	summary_box.visible = false
	parent.add_child(summary_box)
	var mark := TextureRect.new()
	mark.name = "Icon"
	mark.texture = IconButton.load_icon("alert-circle")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_box.add_child(mark)
	# Built inside _ready(), so the sheet is already in the tree: tint now, not on entering.
	mark.self_modulate = ThemeColors.of(mark, ThemeColors.DANGER)
	summary_label = Label.new()
	summary_label.name = "Label"
	summary_label.theme_type_variation = &"Body"
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_box.add_child(summary_label)


## Verify all: one button, a bar with Stop while it runs, and ONE result list afterwards.
func _build_verify_all(parent: Control) -> void:
	verify_all = LibraryVerifyAll.new()
	parent.add_child(verify_all)
	verify_all.button.pressed.connect(_on_verify_all_requested)


## The persistent hint under the list: the two ways in, and a link to find collections when the
## owner has named a catalogue (LibraryNames.CATALOG_URL, empty hides the link).
func _build_hint(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "HintRow"
	row.theme_type_variation = &"BoxContainerSpaced"
	parent.add_child(row)
	hint_label = Label.new()
	hint_label.name = "EmptyHint"
	hint_label.text = LibraryNames.drop_hint()
	hint_label.theme_type_variation = &"Caption"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint_label)
	if LibraryNames.CATALOG_URL != "":
		catalog_button = _small_button(
			"CatalogButton", "Find %s" % LibraryNames.lower(2), "download", row
		)
		catalog_button.pressed.connect(func() -> void: OS.shell_open(LibraryNames.CATALOG_URL))


func _build_footer() -> void:
	_body.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.theme_type_variation = &"BoxContainerSpaced"
	_body.add_child(footer)
	var status := HBoxContainer.new()
	status.name = "StatusRow"
	status.theme_type_variation = &"BoxContainerSpaced"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	status_icon = TextureRect.new()
	status_icon.name = "StatusIcon"
	status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_icon.visible = false
	status.add_child(status_icon)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"Caption"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_child(status_label)
	footer_extras = HBoxContainer.new()
	footer_extras.name = "FooterExtras"
	footer_extras.theme_type_variation = &"BoxContainerSpaced"
	footer.add_child(footer_extras)
	refresh_button = _footer_button("RefreshButton", "Refresh", "rotate-clockwise", &"Secondary")
	refresh_button.tooltip_text = "Look at the %s folder again" % LibraryNames.lower(2)
	refresh_button.pressed.connect(func() -> void: _on_refresh_pressed())
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
	button.custom_minimum_size = Vector2(UiActions.SECONDARY_HEIGHT, UiActions.SECONDARY_HEIGHT)
	button.set_meta("ui_silent", true)
	$CenterContainer/PanelContainer/Body/Footer.add_child(button)
	return button


func _small_button(node_name: String, label: String, icon: String, parent: Control) -> Button:
	var button := AnimatedButton.new()
	button.name = node_name
	button.text = label
	button.icon = IconButton.load_icon(icon)
	button.theme_type_variation = &"Secondary"
	button.custom_minimum_size = Vector2(0, UiActions.SECONDARY_HEIGHT)
	parent.add_child(button)
	return button


# ---- the list ----


## Reads the registry again and rebuilds the list, keeping the selection when it still exists.
func refresh_list() -> void:
	_items = _keyed(LibraryRegistry.list(palette_root))
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_keys.clear()
	var keep := selected_id
	var attention := 0
	for item in _items:
		_add_row(item)
		if String(item["status"]) == LibraryResolver.ERROR:
			attention += 1
	var count := _items.size()
	if status_label.text == "":
		_say(LibraryNames.counted(count))
	summary_box.visible = attention > 0
	summary_label.text = LibraryNames.attention_summary(attention)
	var wanted := keep if _rows.has(keep) else (_keys[0] if count > 0 else "")
	select(wanted)


## `items` with a `key` each (the id; "id@folder" for a second folder holding an id already
## listed, so both rows can be addressed) and `same_id` on every entry that shares its id.
static func _keyed(items: Array[Dictionary]) -> Array[Dictionary]:
	var seen := {}
	for item in items:
		seen[item["id"]] = int(seen.get(item["id"], 0)) + 1
	var used := {}
	for item in items:
		var id := String(item["id"])
		var key := id if not used.has(id) else "%s@%s" % [id, String(item["folder"]).get_file()]
		used[id] = true
		item["key"] = key
		item["same_id"] = int(seen[id]) > 1
	return items


## Selects the entry with list key `library_id` (its id; the row and the card).
func select(library_id: String) -> void:
	selected_id = library_id
	for key: String in _rows:
		(_rows[key] as LibraryRow).set_selected(key == library_id)
	detail.show_library(info_of(library_id))
	_verifying = false


## The list entry shown for `library_id` (a key), {} when none.
func info_of(library_id: String) -> Dictionary:
	for item in _items:
		if item["key"] == library_id:
			return item
	return {}


## The selectable row button of list key `library_id`, null when none.
func row_of(library_id: String) -> Button:
	return (_rows[library_id] as LibraryRow).button if _rows.has(library_id) else null


## The on/off switch of list key `library_id`; null when none or when the entry fails (it has the
## "Needs attention" pill instead).
func toggle_of(library_id: String) -> CheckButton:
	return (_rows[library_id] as LibraryRow).toggle if _rows.has(library_id) else null


## The whole row of list key `library_id` (button, chip slot, switch or pill), null when none.
func library_row(library_id: String) -> LibraryRow:
	return _rows.get(library_id)


## The list keys in the order shown.
func keys() -> Array[String]:
	return _keys.duplicate()


func _add_row(item: Dictionary) -> void:
	var row := LibraryRow.new()
	row.setup(item)
	list_box.add_child(row)
	row.chosen.connect(select)
	row.switched.connect(_on_toggled)
	_rows[row.key] = row
	_keys.append(row.key)


## The second line of a row (kept here for callers that name it through the manager). Pure.
static func caption_of(item: Dictionary) -> String:
	return LibraryRow.caption_of(item)


## The third line of a row. Pure.
static func facts_of(item: Dictionary) -> String:
	return LibraryRow.facts_of(item)


# ---- rescanning ----


## Reads the folders again when they differ on disk from the last read (or always with `force`),
## serves what changed and rebuilds the list. True when it rescanned. Cheap when nothing changed:
## see the class comment.
func rescan(force: bool = false) -> bool:
	if not force and LibraryRegistry.disk_signature() == LibraryRegistry.seen_signature():
		return false
	LibraryImportFlow.refresh_all()
	refresh_list()
	libraries_changed.emit()
	return true


func _on_refresh_pressed() -> void:
	rescan(true)
	_say("Looked at the folders again: %s." % LibraryNames.counted(_items.size()))


# ---- actions ----


func _on_toggled(on: bool, key: String) -> void:
	var library_id := String(info_of(key).get("id", key))
	if not LibraryRegistry.set_enabled(library_id, on):
		_say("That could not be saved.", STATUS_ERROR)
		refresh_list()
		return
	LibraryImportFlow.refresh_all()
	var shown := String(info_of(key).get("name", library_id))
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
		),
		STATUS_OK
	)
	libraries_changed.emit()


## The card showed the reason and Retry; the footer keeps it too, in red with an icon, since the
## footer is the one line that always says the last thing that happened.
func _on_install_failed(message: String) -> void:
	_say(message, STATUS_ERROR)


func _on_flow_busy(busy: bool) -> void:
	import_file_button.disabled = busy
	import_folder_button.disabled = busy


func _on_files_dropped(files: PackedStringArray) -> void:
	if _closing or flow.is_busy() or files.is_empty():
		return
	flow.begin(files[0])


func _on_folder_requested(folder: String) -> void:
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(folder), true)


## The designer's picker, over this sheet: it sits on a layer above this one (review UX-1).
func _on_new_biome_requested(library_id: String) -> void:
	BiomeDesignerPicker.show_over(self, library_id)


## Remove: names the maps that use it (a lazy scan of the saved levels' manifests) and asks.
func _on_remove_requested(key: String) -> void:
	var info := info_of(key)
	if info.is_empty() or String(info["source"]) != "user":
		return
	var users := LibraryInstall.levels_using(String(info["id"]), LevelManager.levels_dir)
	var words := remove_message(String(info["name"]), users.size())
	if bool(info.get("received", false)):
		words += LibraryCacheSection.REMOVE_NOTE  # the host sends it again when a map needs it
	UIManager.show_danger_confirmation(
		"Remove %s" % info["name"], words, func() -> void: _remove_confirmed(key), "Remove"
	)


## The confirmation's words: what is deleted and what the maps that use it will do. Pure.
static func remove_message(library_name: String, map_count: int) -> String:
	var gone := (
		"%s is deleted from this computer. You can add it again from its file." % library_name
	)
	return gone + LibraryNames.remove_tail(map_count)


func _remove_confirmed(key: String) -> void:
	var info := info_of(key)
	var library_id := String(info.get("id", key))
	var shown := String(info.get("name", library_id))
	# A second folder holding an id that is listed is removed by its folder: removing by id
	# would delete the copy that stays.
	var duplicate := key != library_id
	var done := (
		LibraryInstall.remove_folder(String(info["folder"]).get_file())
		if duplicate
		else LibraryInstall.remove(library_id)
	)
	if not bool(done["ok"]):
		UIManager.show_error(String(done["error"]))
		_say(String(done["error"]), STATUS_ERROR)
		return
	# A library turned off and then removed must not come back turned off when it is added again.
	if not duplicate:
		LibraryRegistry.set_enabled(library_id, true)
	LibraryImportFlow.refresh_all()
	selected_id = ""
	status_label.text = ""
	refresh_list()
	_say("%s removed." % shown, STATUS_OK)
	UIManager.show_success("%s removed" % shown)
	libraries_changed.emit()


# ---- verify ----


## Verify: every file of the selected library against the catalog, a few per frame so the sheet
## keeps drawing, with a bar and Stop.
func _on_verify_requested(key: String) -> void:
	if _verifying or verify_all.running:
		return
	var library_id := String(info_of(key).get("id", key))
	var plan := LibraryVerify.plan(library_id, palette_root)
	if plan["state"] != LibraryVerify.READY:
		detail.say_cannot_verify("Turn it on (and fix what is listed above) to check its files.")
		return
	var assets: Array = plan["assets"]
	_verifying = true
	_verify_cancel = false
	detail.begin_verify(assets.size())
	var run := await _check_slices(
		assets,
		func(done: int, total: int) -> void: detail.set_verify_progress(done, total),
		func() -> bool: return selected_id == key
	)
	if not is_inside_tree() or selected_id != key:
		return
	_verifying = false
	var done := int(run["done"])
	var stopped := _verify_cancel and done < assets.size()
	detail.finish_verify(LibraryVerify.summarize(run["results"]), stopped)


## Checks `assets` one frame's slice at a time (at least one file a frame, so Stop always has a
## frame to land in), calling `progress(done, total)` after each slice and stopping when Stop was
## pressed, the sheet left the tree or `wanted` says no. {results, done}.
func _check_slices(assets: Array, progress: Callable, wanted: Callable) -> Dictionary:
	var results: Array = []
	var index := 0
	while index < assets.size():
		var slice_end := Time.get_ticks_usec() + verify_slice_usec
		results.append(LibraryVerify.check(String(assets[index]), palette_root))
		index += 1
		while index < assets.size() and Time.get_ticks_usec() < slice_end:
			results.append(LibraryVerify.check(String(assets[index]), palette_root))
			index += 1
		progress.call(index, assets.size())
		await get_tree().process_frame
		if not is_inside_tree() or _verify_cancel or not bool(wanted.call()):
			break
	return {"results": results, "done": index}


## Verify all: every collection that is on and served, one pass, one bar with Stop, one list of
## results (a line per collection, the files that failed under it, and the ones not checked).
func _on_verify_all_requested() -> void:
	if _verifying or verify_all.running:
		return
	verify_all.slice_usec = verify_slice_usec
	await verify_all.run(_items, palette_root)


## A line in the footer: the last thing that happened, in words. `kind` "error" shows it in red
## with an alert icon, "ok" with a check, "" plain (an icon and words, never colour alone).
func _say(text: String, kind: String = "") -> void:
	if status_label == null:
		return
	status_label.text = text
	status_kind = kind
	status_icon.visible = kind != ""
	if kind == "":
		status_label.remove_theme_color_override(&"font_color")
		return
	var role := ThemeColors.DANGER if kind == STATUS_ERROR else ThemeColors.SUCCESS
	status_icon.texture = IconButton.load_icon(
		"alert-circle" if kind == STATUS_ERROR else "circle-check"
	)
	var colour := ThemeColors.of(status_label, role)
	status_icon.self_modulate = colour
	if kind == STATUS_ERROR:
		status_label.add_theme_color_override(&"font_color", colour)
	else:
		status_label.remove_theme_color_override(&"font_color")


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
	_list_scroll.custom_minimum_size.y = maxf(height - _list_chrome(), 120.0)
	_detail_scroll.custom_minimum_size.y = height


## The height of what stands in the list column besides the scrolling list.
func _list_chrome() -> float:
	var chrome := 0.0
	for child in _list_scroll.get_parent().get_children():
		if child != _list_scroll and child is Control and (child as Control).visible:
			chrome += (child as Control).get_combined_minimum_size().y + 8.0
	return chrome


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children(_body)


func _on_after_animate_in() -> void:
	done_button.grab_focus()


func close() -> void:
	if _closing:
		return
	_closing = true
	_verify_cancel = true
	if verify_all != null:
		verify_all.stop()
	AudioManager.play(&"cancel")
	animate_out()


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# An open install card takes Escape first (it closes itself); this closes the sheet.
		if flow != null and flow.is_busy():
			return
		close()
		get_viewport().set_input_as_handled()


## Arrow keys in the list: Up and Down move to the previous or next collection (selecting it),
## Right goes from a row to its switch and Left back. Enter or Space on a row selects it and on a
## switch turns it on or off, as buttons do.
func _input(event: InputEvent) -> void:
	if _closing or list_box == null or not is_top_trap():
		return
	var holder := get_viewport().gui_get_focus_owner()
	if holder == null or not list_box.is_ancestor_of(holder):
		return
	if event.is_action_pressed("ui_down"):
		_step_selection(1)
	elif event.is_action_pressed("ui_up"):
		_step_selection(-1)
	elif event.is_action_pressed("ui_right") and holder is Button and holder.name == "Row":
		var row := holder.get_parent() as LibraryRow
		if row == null or row.toggle == null or row.toggle.disabled:
			return
		row.toggle.grab_focus()
	elif event.is_action_pressed("ui_left") and holder is CheckButton:
		var row := holder.get_parent().get_parent() as LibraryRow
		if row == null:
			return
		row.button.grab_focus()
	else:
		return
	get_viewport().set_input_as_handled()


## Moves the selection `step` rows (clamped) and the focus with it.
func _step_selection(step: int) -> void:
	if _keys.is_empty():
		return
	var at := _keys.find(selected_id)
	var next := clampi(at + step, 0, _keys.size() - 1)
	select(_keys[next])
	var row: LibraryRow = _rows[_keys[next]]
	row.button.grab_focus()
	_list_scroll.ensure_control_visible(row)
