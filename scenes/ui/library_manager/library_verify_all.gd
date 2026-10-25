class_name LibraryVerifyAll
extends VBoxContainer

## "Verify all" in the manager's list column: one button, and while it runs one bar with Stop;
## afterwards ONE list of results, a line per collection (a check mark or an alert, and what it
## found), the files that failed under it, and the collections that were not checked and why.
## Every collection that is on and served is checked, one file at a time and at least one file a
## frame, so the sheet keeps drawing and Stop always has a frame to land in.

signal started
signal finished

const MAX_LINES := 10
const MAX_FILE_LINES := 2
const ICON_PX := 16.0

var button: Button
var box: VBoxContainer
var bar: ProgressBar
var label: Label
var stop_button: Button
var results_box: VBoxContainer
## How long one frame may spend checking (at least one file is always checked).
var slice_usec: int = 6000
## True while a run is going.
var running: bool = false

var _cancel := false


func _init() -> void:
	name = "VerifyAll"
	theme_type_variation = &"BoxContainerSpaced"
	var row := HBoxContainer.new()
	row.name = "Row"
	row.theme_type_variation = &"BoxContainerSpaced"
	add_child(row)
	button = AnimatedButton.new()
	button.name = "VerifyAllButton"
	button.text = "Verify all"
	button.icon = IconButton.load_icon("circle-check")
	button.theme_type_variation = &"Secondary"
	button.custom_minimum_size = Vector2(0, UiActions.SECONDARY_HEIGHT)
	button.tooltip_text = "Check the files of every %s that is turned on" % LibraryNames.lower()
	row.add_child(button)
	box = VBoxContainer.new()
	box.name = "Box"
	box.theme_type_variation = &"BoxContainerTight"
	box.visible = false
	add_child(box)
	label = Label.new()
	label.name = "Label"
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var bar_row := HBoxContainer.new()
	bar_row.name = "BarRow"
	bar_row.theme_type_variation = &"BoxContainerSpaced"
	box.add_child(bar_row)
	bar = ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(bar)
	stop_button = AnimatedButton.new()
	stop_button.name = "VerifyAllStop"
	stop_button.text = "Stop"
	stop_button.icon = IconButton.load_icon("x")
	stop_button.theme_type_variation = &"Secondary"
	stop_button.custom_minimum_size = Vector2(0, UiActions.SECONDARY_HEIGHT)
	stop_button.pressed.connect(stop)
	bar_row.add_child(stop_button)
	results_box = VBoxContainer.new()
	results_box.name = "Results"
	results_box.theme_type_variation = &"BoxContainerTight"
	box.add_child(results_box)


## Stops after the file being checked.
func stop() -> void:
	_cancel = true


## Checks every collection of `items` (LibraryManager's entries) that is on and served under
## `palette_root`; the others are listed as not checked. A coroutine: it returns when the last
## file was checked or Stop was pressed.
func run(items: Array[Dictionary], palette_root: String) -> void:
	if running:
		return
	var jobs: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	var queue: Array = []
	for item in items:
		var plan := LibraryVerify.plan(String(item["id"]), palette_root)
		var served: bool = String(item["status"]) == LibraryResolver.OK
		served = served and plan["state"] == LibraryVerify.READY
		# A second folder holding an id is not the one served: it is not checked.
		if not served or String(item["key"]) != String(item["id"]):
			skipped.append(item)
			continue
		for asset: Variant in plan["assets"] as Array:
			queue.append([jobs.size(), String(asset)])
		jobs.append({"item": item, "results": []})
	running = true
	_cancel = false
	button.disabled = true
	box.visible = true
	_clear_results()
	bar.visible = true
	stop_button.visible = true
	bar.max_value = maxf(queue.size(), 1)
	bar.value = 0
	label.text = "Checking %s..." % LibraryNames.count_of(queue.size(), "file")
	started.emit()
	var index := 0
	while index < queue.size():
		var slice_end := Time.get_ticks_usec() + slice_usec
		while true:
			var step: Array = queue[index]
			var results: Array = jobs[int(step[0])]["results"]
			results.append(LibraryVerify.check(String(step[1]), palette_root))
			index += 1
			if index >= queue.size() or Time.get_ticks_usec() >= slice_end:
				break
		bar.value = index
		label.text = "Checking %d of %d..." % [index, queue.size()]
		await get_tree().process_frame
		if not is_inside_tree() or _cancel:
			break
	if not is_inside_tree():
		return
	running = false
	button.disabled = false
	bar.visible = false
	stop_button.visible = false
	_show(jobs, skipped, _cancel and index < queue.size(), index)
	finished.emit()


func _show(
	jobs: Array[Dictionary], skipped: Array[Dictionary], stopped: bool, checked: int
) -> void:
	_clear_results()
	var bad := 0
	var lines := 0
	for job in jobs:
		var summary := LibraryVerify.summarize(job["results"])
		var failed: Array = summary["failed"]
		var shown := String((job["item"] as Dictionary)["name"])
		var text := ""
		if int(summary["checked"]) == 0 and stopped:
			text = "%s: not checked" % shown
		elif failed.is_empty():
			text = (
				"%s: all %s check out"
				% [shown, LibraryNames.count_of(int(summary["checked"]), "file")]
			)
		else:
			bad += 1
			text = (
				"%s: %d of %d files have a problem"
				% [shown, failed.size(), int(summary["checked"])]
			)
		if lines < MAX_LINES:
			var good := failed.is_empty()
			var icon := "circle-check" if good else "alert-circle"
			_line(icon, ThemeColors.SUCCESS if good else ThemeColors.DANGER, text)
			lines += 1
		for i in mini(failed.size(), MAX_FILE_LINES):
			if lines >= MAX_LINES:
				break
			var result: Dictionary = failed[i]
			var plain := LibraryVerify.plain_error(String(result["error"]))
			var name_of := LibraryVerify.short_name(String(result["asset"]))
			_line("alert-circle", ThemeColors.DANGER, "    %s: %s" % [name_of, plain])
			lines += 1
	for item in skipped:
		if lines >= MAX_LINES:
			break
		var why := "turned off"
		if String(item["status"]) == LibraryResolver.ERROR:
			why = "needs attention"
		elif bool(item["enabled"]):
			why = "not in use yet"
		_line("info-circle", ThemeColors.STATE, "%s: not checked (%s)" % [item["name"], why])
		lines += 1
	if stopped:
		label.text = "Stopped after %s." % LibraryNames.count_of(checked, "file")
	elif bad == 0:
		label.text = "Checked %s: every file checks out." % LibraryNames.counted(jobs.size())
	else:
		label.text = "%d of %d %s have a problem." % [bad, jobs.size(), LibraryNames.lower(2)]


func _clear_results() -> void:
	for child in results_box.get_children():
		results_box.remove_child(child)
		child.queue_free()


func _line(icon: String, role: StringName, text: String) -> void:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"BoxContainerSpaced"
	results_box.add_child(row)
	var mark := TextureRect.new()
	mark.texture = IconButton.load_icon(icon)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var words := Label.new()
	words.theme_type_variation = &"Caption"
	words.text = text.strip_edges(true, false)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.custom_minimum_size.x = 120
	row.add_child(words)
	if row.is_inside_tree():
		mark.self_modulate = ThemeColors.of(row, role)
	else:
		row.tree_entered.connect(func() -> void: mark.self_modulate = ThemeColors.of(row, role))
