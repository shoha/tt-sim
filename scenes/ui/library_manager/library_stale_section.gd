class_name LibraryStaleSection
extends HBoxContainer

## The row of the collections manager that offers to remove the leftovers of the earlier
## session-only cache (`<libraries>/.received/<id>`) whose collection is installed by now:
## nothing reads them, so they only take room. The row is hidden while there are none. Removal
## always asks first and goes through LibraryFromHost.remove_stale_received (SafeDelete); it is
## never silent. Attached by one line in LibraryManager, like LibraryCacheSection.

## A leftover was removed: the manager scans again.
signal cleared

var summary_label: Label
var remove_button: Button


## Adds the section to `body` for `manager` and keeps it current.
static func attach(manager: Node, body: Control) -> LibraryStaleSection:
	var section := LibraryStaleSection.new()
	body.add_child(section)
	if manager.has_signal("libraries_changed"):
		manager.connect("libraries_changed", section.refresh)
	section.cleared.connect(
		func() -> void:
			if manager.has_method("refresh_list"):
				manager.call("refresh_list")
			if manager.has_signal("libraries_changed"):
				manager.emit_signal("libraries_changed")
	)
	return section


func _init() -> void:
	name = "StaleSection"
	theme_type_variation = &"BoxContainerSpaced"
	summary_label = Label.new()
	summary_label.name = "Summary"
	summary_label.theme_type_variation = &"Caption"
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(summary_label)
	remove_button = Button.new()
	remove_button.name = "RemoveButton"
	remove_button.theme_type_variation = &"Secondary"
	remove_button.text = remove_label()
	remove_button.pressed.connect(request_remove)
	add_child(remove_button)
	refresh()


# ---- the words (pure) ----


## "Remove old copies".
static func remove_label() -> String:
	return "Remove old copies"


## "2 old copies of collections you already have take up room."
static func summary_text(count: int) -> String:
	var copies := LibraryNames.count_of(count, "old copy", "old copies")
	return (
		"%s of %s you already have %s up room."
		% [copies, LibraryNames.lower(2), "takes" if count == 1 else "take"]
	)


## The confirmation: what goes and what stays.
static func remove_message(count: int) -> String:
	return (
		"%s of %s you already have will be deleted from this computer. The %s themselves are not touched."
		% [
			LibraryNames.count_of(count, "old copy", "old copies"),
			LibraryNames.lower(2),
			LibraryNames.lower(2)
		]
	)


# ---- the row ----


## Reads the leftovers again and shows the row only when there are some.
func refresh() -> void:
	var ids := LibraryFromHost.stale_received()
	summary_label.text = summary_text(ids.size())
	visible = not ids.is_empty()


## The button: asks first.
func request_remove() -> void:
	var ids := LibraryFromHost.stale_received()
	if ids.is_empty():
		refresh()
		return
	UIManager.show_danger_confirmation(
		remove_label(), remove_message(ids.size()), remove_now, "Remove"
	)


## Removes every stale leftover through SafeDelete. Returns {removed: ids, failed: ids}.
func remove_now() -> Dictionary:
	var report := {"removed": [] as Array[String], "failed": [] as Array[String]}
	for id in LibraryFromHost.stale_received():
		var result := LibraryFromHost.remove_stale_received(id)
		(report["removed" if bool(result["ok"]) else "failed"] as Array[String]).append(id)
	refresh()
	if not (report["failed"] as Array).is_empty():
		UIManager.show_error("Some old copies could not be removed.")
	elif not (report["removed"] as Array).is_empty():
		UIManager.show_success("Removed old copies")
	cleared.emit()
	return report
