class_name LibraryMismatchDialog
extends RefCounted

## The question a map asks when it names a collection this game lacks or has at another major
## version (MapLibraryGate.ask_dialog). A UIManager choice dialog, dressed for the player who has
## to fix it (owner decisions 2026-10-25, review UX-7):
##
##   - one plain sentence per collection (MapLibraries.describe), and its link when the map's
##     record or the installed copy has one (a button that opens it, so the player does not copy
##     a web address by hand);
##   - Import file... and Import folder... in the dialog itself, through the same install card
##     as the manager (LibraryImportFlow); a successful install ends the dialog with
##     MapLibraryGate.RETRY and the gate checks the map again;
##   - Manage collections, which opens the manager OVER THE SCRIM (after this dialog has left:
##     opened while it was still on screen, the manager borrowed its scrim and lost it when the
##     dialog faded, and showed over a live title);
##   - Open without those collections, and Cancel (also Escape).
##
## ask() is a coroutine: it returns when the dialog is gone.

## Emitted once with the answer: true, false or MapLibraryGate.RETRY.
signal answered(result: Variant)

var _settled := false
var _dialog: ConfirmationDialogUI = null
var _flow: LibraryImportFlow = null


## Shows the dialog for `report` (MapLibraries.check's answer) and waits for the answer. `host`
## is where the dialog and the install card are added (the tree's root unless a test sets its own).
static func ask(report: Dictionary, host: Node = null) -> Variant:
	var asker := LibraryMismatchDialog.new()
	asker._show(report, host)
	return await asker.answered


## The dialog as built, for a caller that needs to reach its buttons (tests).
static func show(report: Dictionary, host: Node = null) -> LibraryMismatchDialog:
	var asker := LibraryMismatchDialog.new()
	asker._show(report, host)
	return asker


## The dialog node (null once it is gone).
func dialog() -> ConfirmationDialogUI:
	return _dialog if is_instance_valid(_dialog) else null


## The import flow the dialog's Import buttons use.
func flow() -> LibraryImportFlow:
	return _flow


func _show(report: Dictionary, host: Node) -> void:
	var root := host if host != null else (Engine.get_main_loop() as SceneTree).root
	var dialog_node := (
		UIManager.show_choice(
			LibraryNames.mismatch_title(),
			MapLibraries.describe(report) + MapLibraryGate.HINT,
			LibraryNames.open_without(),
			"Manage %s" % LibraryNames.lower(2),
			"Cancel",
			func() -> void: _settle(true),
			_manage,
			func() -> void: _settle(false)
		)
		as ConfirmationDialogUI
	)
	_dialog = dialog_node
	dialog_node.hold_width(600.0)
	_add_links(dialog_node, report)
	_add_import_buttons(dialog_node, root)


## "Manage collections": this dialog answers false first and the manager opens a frame later,
## once the dialog is leaving, so the manager lays its own scrim over the title.
func _manage() -> void:
	_settle(false)
	var open_manager := func() -> void:
		LibraryManager.open((Engine.get_main_loop() as SceneTree).root)
	open_manager.call_deferred()


func _settle(result: Variant) -> void:
	if _settled:
		return
	_settled = true
	answered.emit(result)


## One button per missing or incompatible collection that has a link: it opens the page.
func _add_links(dialog_node: ConfirmationDialogUI, report: Dictionary) -> void:
	var shown := {}
	for list_name: String in ["missing", "incompatible"]:
		for item: Dictionary in report[list_name]:
			var link := String(item.get("url", ""))
			if link == "" or shown.has(link) or not MapLibraries.is_link(link):
				continue
			shown[link] = true
			# A Ghost button, not a LinkButton: the engine's link colour is near-white and reads
			# as nothing on paper. The address is the button's text and its `uri` meta.
			var button := AnimatedButton.new()
			button.name = "Link_%s" % String(item["id"]).validate_node_name()
			button.text = "%s: %s" % [item["name"], link]
			button.icon = IconButton.load_icon("share")
			button.theme_type_variation = &"Ghost"
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.set_meta("uri", link)
			button.set_meta("ui_silent", true)
			button.pressed.connect(func() -> void: OS.shell_open(link))
			button.tooltip_text = "Open this address in your browser"
			button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var holder := dialog_node.message_label.get_parent()
			holder.add_child(button)
			holder.move_child(button, dialog_node.message_label.get_index() + 1)


## Import file... and Import folder... in a row of their own under the sentences (the footer
## already holds three choices). They do not close the dialog: the install card opens over it
## (dimming it), and only a successful install settles the dialog with RETRY and closes it.
func _add_import_buttons(dialog_node: ConfirmationDialogUI, root: Node) -> void:
	_flow = LibraryImportFlow.new()
	_flow.name = "ImportFlow"
	_flow.host = root
	dialog_node.add_child(_flow)
	_flow.installed.connect(_on_installed)
	var holder := dialog_node.message_label.get_parent()
	var row := HBoxContainer.new()
	row.name = "ImportRow"
	row.theme_type_variation = &"BoxContainerSpaced"
	holder.add_child(row)
	holder.move_child(row, holder.get_child_count() - 3)
	var file_button := _import_button("ImportFileButton", "Import file...", "upload", row)
	file_button.tooltip_text = "Add a .ttlib or .zip file you were given"
	file_button.pressed.connect(func() -> void: _flow.pick_file())
	var folder_button := _import_button("ImportFolderButton", "Import folder...", "folder", row)
	folder_button.tooltip_text = "Add a %s that is already unpacked" % LibraryNames.lower()
	folder_button.pressed.connect(func() -> void: _flow.pick_folder())
	dialog_node.rebuild_focus_trap()


func _import_button(node_name: String, text: String, icon: String, row: Node) -> Button:
	var button := AnimatedButton.new()
	button.name = node_name
	button.text = text
	button.icon = IconButton.load_icon(icon)
	button.theme_type_variation = &"Secondary"
	button.custom_minimum_size = Vector2(0, UiActions.SECONDARY_HEIGHT)
	button.set_meta("ui_silent", true)
	row.add_child(button)
	return button


## A collection was installed: the map is checked again, so end the dialog with RETRY.
func _on_installed(_library_id: String, _replaced: bool) -> void:
	_settle(MapLibraryGate.RETRY)
	if dialog() != null:
		dialog().cancel_button.pressed.emit()
