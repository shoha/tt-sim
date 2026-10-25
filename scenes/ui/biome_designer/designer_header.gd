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
signal thumbnail_requested
signal leave_requested

const SEASON_TIP := (
	"The season on the map. Each season is a biome of its own: the plants, ground and look it "
	+ "changes are the ones set for it."
)
const TITLE_WIDTH := 120.0
const SCRUB_WIDTH := 84.0
const MENU_ADD_BASE := 100
const MENU_REMOVE := 1
const MENU_CLEAR := 2
const COMPARE_OFF := 0
const COMPARE_BASE := 10
const COMPARE_BIOME_BASE := 1000
const COMPARE_LABEL_MAX := 26

var session: BiomeDesignerSession = null
var meter: DesignerBudgetMeter = null

var _title: Label
var _dirty: Label
var _season: OptionButton
var _scrub: HSlider
var _seasons_menu: MenuButton
var _add_menu: PopupMenu
var _add_names: Array[String] = []
var _compare_menu: MenuButton
var _biome_menu: PopupMenu
var _compare_options: Array[Dictionary] = []
var _undo: IconButton
var _redo: IconButton
var _save: Button
var _save_as: Button
var _revert: Button
var _thumbnail: Button
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
	_season.tooltip_text = SEASON_TIP
	_season.item_selected.connect(
		func(index: int) -> void:
			if not _syncing:
				session.set_season(index)
	)
	top.add_child(_season)
	_build_season_controls(top)
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
		"Copy this biome into %s of your own. " % LibraryNames.article()
		+ "Its plants stay in the %s they came from." % LibraryNames.lower()
	)
	_save_as.pressed.connect(func() -> void: save_as_requested.emit())
	top.add_child(_save_as)
	_revert = Button.new()
	_revert.name = "Revert"
	_revert.text = "Revert"
	_revert.tooltip_text = "Throw away every change since the last save."
	_revert.pressed.connect(func() -> void: revert_requested.emit())
	top.add_child(_revert)
	_thumbnail = Button.new()
	_thumbnail.name = "Thumbnail"
	_thumbnail.text = "Thumbnail"
	_thumbnail.pressed.connect(func() -> void: thumbnail_requested.emit())
	top.add_child(_thumbnail)
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
		var changes := int(DesignerSeasonEdits.summary(model, model.season_ids()[i])["total"])
		var words := model.season_ids()[i].capitalize()
		_season.add_item(words if changes == 0 else "%s (%d)" % [words, changes], i)
	_season.select(session.season_index)
	_season.disabled = model.season_ids().size() < 2
	_scrub.visible = model.season_ids().size() > 1
	_scrub.max_value = maxi(model.season_ids().size() - 1, 1)
	_scrub.tick_count = model.season_ids().size()
	_scrub.set_value_no_signal(session.season_index)
	_syncing = false
	_refresh_compare_button()
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
		else "%s is read-only: save a copy with Save as..." % model.library_name
	)
	_revert.disabled = not model.is_dirty()
	var picture_ok := LibraryThumbnailer.designer_writable(model.source, model.folder)
	_thumbnail.disabled = not picture_ok
	_thumbnail.tooltip_text = (
		(
			"Take this biome's picture (the one the New map dialog and the manager show) from "
			+ "the draft on a standard map, and save it to %s." % model.library_name
		)
		if picture_ok
		else "%s is read-only: its pictures come from the build." % model.library_name
	)
	_show_status()


## The season dropdown's neighbours: the scrub slider over the seasons, the Seasons menu (add,
## remove, clear the changes of the one on the map) and the A/B menu.
func _build_season_controls(top: HBoxContainer) -> void:
	_scrub = HSlider.new()
	_scrub.name = "SeasonScrub"
	_scrub.min_value = 0
	_scrub.max_value = 1
	_scrub.step = 1
	_scrub.scrollable = false
	_scrub.ticks_on_borders = true
	_scrub.custom_minimum_size = Vector2(SCRUB_WIDTH, 0.0)
	_scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrub.tooltip_text = "Scrub through the seasons: the map shows each one's biome."
	_scrub.value_changed.connect(
		func(value: float) -> void:
			if not _syncing:
				session.set_season(roundi(value))
	)
	top.add_child(_scrub)
	_seasons_menu = MenuButton.new()
	_seasons_menu.name = "SeasonsMenu"
	_seasons_menu.text = "Seasons"
	_seasons_menu.tooltip_text = "Add a season, remove one, or clear what one changes."
	var popup := _seasons_menu.get_popup()
	_add_menu = PopupMenu.new()
	_add_menu.name = "AddSeason"
	_add_menu.id_pressed.connect(_on_add_season)
	popup.add_child(_add_menu)
	popup.about_to_popup.connect(_fill_seasons_menu)
	popup.id_pressed.connect(_on_seasons_menu)
	top.add_child(_seasons_menu)
	_compare_menu = MenuButton.new()
	_compare_menu.name = "CompareMenu"
	_compare_menu.tooltip_text = (
		"Compare the draft with the saved version, another season or another biome: the map "
		+ "is split by a divider you drag, the draft on the left."
	)
	var compare_popup := _compare_menu.get_popup()
	_biome_menu = PopupMenu.new()
	_biome_menu.name = "AnotherBiome"
	_biome_menu.id_pressed.connect(_on_compare_picked)
	compare_popup.add_child(_biome_menu)
	compare_popup.about_to_popup.connect(_fill_compare_menu)
	compare_popup.id_pressed.connect(_on_compare_picked)
	top.add_child(_compare_menu)
	session.season_changed.connect(func(_index: int) -> void: refresh())
	session.compare.changed.connect(_refresh_compare_button)


func _fill_seasons_menu() -> void:
	var model := session.model
	var popup := _seasons_menu.get_popup()
	popup.clear()
	_add_menu.clear()
	_add_names = DesignerSeasonEdits.unused_names(model)
	for i in _add_names.size():
		_add_menu.add_item(_add_names[i].capitalize(), MENU_ADD_BASE + i)
	var room := model.season_ids().size() < LibraryContracts.MAX_SEASONS
	popup.add_submenu_node_item("Add a season", _add_menu)
	popup.set_item_disabled(0, _add_names.is_empty() or not room)
	var here := session.season_id()
	popup.add_item("Remove %s" % here.capitalize(), MENU_REMOVE)
	popup.set_item_disabled(popup.get_item_index(MENU_REMOVE), model.season_ids().size() < 2)
	var changes := int(DesignerSeasonEdits.summary(model, here)["total"])
	popup.add_item("Clear what %s changes (%d)" % [here.capitalize(), changes], MENU_CLEAR)
	popup.set_item_disabled(popup.get_item_index(MENU_CLEAR), changes == 0)


func _on_add_season(id: int) -> void:
	var at := id - MENU_ADD_BASE
	if at >= 0 and at < _add_names.size():
		if DesignerSeasonEdits.add_season(session.model, _add_names[at]):
			session.set_season(session.model.season_ids().size() - 1)


func _on_seasons_menu(id: int) -> void:
	var here := session.season_id()
	if id == MENU_REMOVE:
		DesignerSeasonEdits.remove_season(session.model, here)
	elif id == MENU_CLEAR:
		DesignerSeasonEdits.clear(session.model, here)


func _fill_compare_menu() -> void:
	var popup := _compare_menu.get_popup()
	popup.clear()
	_biome_menu.clear()
	_compare_options = DesignerReference.options(session.model, session.season_id())
	popup.add_item("Off", COMPARE_OFF)
	popup.set_item_disabled(0, not session.compare.active)
	popup.add_separator()
	var biomes_at := -1
	for i in _compare_options.size():
		var option := _compare_options[i]
		if option["kind"] == "biome":
			_biome_menu.add_item(String(option["label"]), COMPARE_BIOME_BASE + i)
		else:
			popup.add_item(String(option["label"]), COMPARE_BASE + i)
	if _biome_menu.item_count > 0:
		popup.add_submenu_node_item("Another biome", _biome_menu)
		biomes_at = popup.item_count - 1
	if biomes_at >= 0:
		popup.set_item_disabled(biomes_at, false)


func _on_compare_picked(id: int) -> void:
	if id == COMPARE_OFF:
		session.compare.stop()
		return
	var at := id - COMPARE_BIOME_BASE if id >= COMPARE_BIOME_BASE else id - COMPARE_BASE
	if at < 0 or at >= _compare_options.size():
		return
	var made := session.compare.start(_compare_options[at])
	if not made["ok"]:
		UIManager.show_toast(String(made["error"]), UIManager.TOAST_WARNING, 5.0)


func _refresh_compare_button() -> void:
	if _compare_menu == null:
		return
	if session.compare.active:
		var label := session.compare.reference_label()
		if label.length() > COMPARE_LABEL_MAX:
			label = label.substr(0, COMPARE_LABEL_MAX - 3) + "..."
		_compare_menu.text = "A/B: vs %s" % label
	else:
		_compare_menu.text = "A/B: off"


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
