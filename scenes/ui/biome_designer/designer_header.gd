class_name DesignerHeader
extends VBoxContainer

## Panel 6 of the biome designer (design doc 4.3): the header. The biome and its collection, a
## dot while there are unsaved edits, the season, Undo and Redo, Save (the screen's one primary),
## Save as a new collection, Revert and Leave; and under them the budget meter, the regeneration
## progress with Cancel, and the validators' count. Buttons only emit: the host decides what each
## does (save to the folder, ask for a new collection's name, leave with a prompt).

signal save_requested
signal save_as_requested
signal revert_requested
signal leave_requested

const TITLE_WIDTH := 120.0

var session: BiomeDesignerSession = null
var meter: DesignerBudgetMeter = null

var _title: Label
var _dirty: Label
var _season: OptionButton
var _undo: IconButton
var _redo: IconButton
var _save: Button
var _save_as: Button
var _revert: Button
var _progress: ProgressBar
var _progress_label: Label
var _cancel: Button
var _status: Label
var _syncing: bool = false


func _init() -> void:
	name = "Header"


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	var top := HBoxContainer.new()
	top.name = "Top"
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"H3"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.custom_minimum_size = Vector2(TITLE_WIDTH, 0.0)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_title)
	_dirty = Label.new()
	_dirty.name = "Dirty"
	_dirty.theme_type_variation = &"CaptionState"
	top.add_child(_dirty)
	_season = OptionButton.new()
	_season.name = "Season"
	_season.tooltip_text = (
		"The season whose plants are on the map. (The season scrub is the next designer step.)"
	)
	_season.item_selected.connect(
		func(index: int) -> void:
			if not _syncing:
				session.set_season(index)
	)
	top.add_child(_season)
	_undo = _icon_button("Undo", "arrow-back-up", "Undo (Ctrl+Z)")
	_undo.pressed.connect(func() -> void: session.model.undo())
	top.add_child(_undo)
	_redo = _icon_button("Redo", "arrow-forward-up", "Redo (Ctrl+Y)")
	_redo.pressed.connect(func() -> void: session.model.redo())
	top.add_child(_redo)
	_save = Button.new()
	_save.name = "Save"
	_save.text = "Save"
	_save.theme_type_variation = &"Primary"
	_save.pressed.connect(func() -> void: save_requested.emit())
	top.add_child(_save)
	_save_as = Button.new()
	_save_as.name = "SaveAs"
	_save_as.text = "Save as..."
	_save_as.tooltip_text = (
		"Copy this biome into a collection of your own. "
		+ "Its plants stay in the collection they came from."
	)
	_save_as.pressed.connect(func() -> void: save_as_requested.emit())
	top.add_child(_save_as)
	_revert = Button.new()
	_revert.name = "Revert"
	_revert.text = "Revert"
	_revert.tooltip_text = "Throw away every change since the last save."
	_revert.pressed.connect(func() -> void: revert_requested.emit())
	top.add_child(_revert)
	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: leave_requested.emit())
	top.add_child(leave)
	add_child(top)
	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	meter = DesignerBudgetMeter.new()
	meter.setup(session)
	bottom.add_child(meter)
	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.custom_minimum_size = Vector2(160.0, 0.0)
	_progress.show_percentage = false
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_progress)
	_progress_label = Label.new()
	_progress_label.name = "ProgressWords"
	_progress_label.theme_type_variation = &"Caption"
	bottom.add_child(_progress_label)
	_cancel = Button.new()
	_cancel.name = "Cancel"
	_cancel.text = "Cancel"
	_cancel.tooltip_text = (
		"Stop regenerating. The map then shows a mix of the old and the new rules "
		+ "until you regenerate."
	)
	_cancel.pressed.connect(func() -> void: session.cancel())
	bottom.add_child(_cancel)
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"Caption"
	bottom.add_child(_status)
	add_child(bottom)
	session.model.changed.connect(func(_reason: String) -> void: refresh())
	session.model.saved.connect(refresh)
	session.progress_changed.connect(_on_progress)
	session.compiled.connect(func(_result: Dictionary) -> void: _show_status())
	refresh()
	_on_progress(session.state, session.progress())


## Syncs the title, the dot, the buttons and the status from the model.
func refresh() -> void:
	var model := session.model
	_title.text = "%s  in  %s" % [String(model.def.get("name", model.biome_id)), model.library_name]
	_dirty.text = "unsaved changes" if model.is_dirty() else ""
	_syncing = true
	_season.clear()
	for i in model.season_ids().size():
		_season.add_item(model.season_ids()[i].capitalize(), i)
	_season.select(session.season_index)
	_season.disabled = model.season_ids().size() < 2
	_syncing = false
	_undo.disabled = not model.can_undo()
	_undo.tooltip_text = (
		"Undo %s (Ctrl+Z)" % model.history_label() if model.can_undo() else "Nothing to undo"
	)
	_redo.disabled = not model.can_redo()
	_redo.tooltip_text = (
		"Redo %s (Ctrl+Y)" % model.history_label(true) if model.can_redo() else "Nothing to redo"
	)
	_save.disabled = not model.writable
	_save.tooltip_text = (
		"Write the biome to %s" % model.library_name
		if model.writable
		else "%s is read-only: save a copy with Save as new collection" % model.library_name
	)
	_revert.disabled = not model.is_dirty()
	_show_status()


func _show_status() -> void:
	var verdict := session.model.validation()
	var errors := (verdict["errors"] as Array).size()
	var warnings := (verdict["warnings"] as Array).size()
	if errors > 0:
		_status.text = (
			"%d problem%s: edits are not applied until fixed" % [errors, "" if errors == 1 else "s"]
		)
	elif warnings > 0:
		_status.text = "%d warning%s" % [warnings, "" if warnings == 1 else "s"]
	else:
		_status.text = "no problems"


func _on_progress(state: int, progress: Dictionary) -> void:
	var busy := state == BiomeDesignerSession.State.REGENERATING
	_progress.visible = busy
	_cancel.visible = busy
	var total := maxi(int(progress["total"]), 1)
	_progress.max_value = total
	_progress.value = total - int(progress["left"])
	match state:
		BiomeDesignerSession.State.REGENERATING:
			_progress_label.text = (
				"Regenerating: %d of %d cells" % [total - int(progress["left"]), total]
			)
		BiomeDesignerSession.State.WAITING:
			_progress_label.text = "Applying..."
		BiomeDesignerSession.State.CANCELLED:
			_progress_label.text = "Cancelled: the map mixes old and new rules"
		_:
			var stats := session.stats
			_progress_label.text = (
				"Updated in %d ms" % roundi(float(stats.get("total_ms", 0.0)))
				if not stats.is_empty()
				else ""
			)


func _icon_button(node_name: String, icon: String, tip: String) -> IconButton:
	var button := IconButton.new()
	button.name = node_name
	button.icon_name = icon
	button.tooltip_text = tip
	return button
