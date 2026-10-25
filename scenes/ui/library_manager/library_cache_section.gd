class_name LibraryCacheSection
extends HBoxContainer

## The row of the collections manager that manages what hosts sent (docs/systems/library.md "The
## cache of downloaded collections"): how many from-host collections there are and how much room
## they take, a button that clears them all after a confirmation naming how many collections, how
## many megabytes and how many saved maps use them, and the size limit (the oldest unused ones
## are removed first when a new download would pass it). One collection can also be removed
## through the manager's ordinary Remove. The row is hidden while nothing was downloaded.
##
## Its own file, attached by one line in LibraryManager (`attach`); the rules are in
## LibraryFromHost, the words below and in LibraryNames. A person-facing sentence names the
## content through LibraryNames only.

## A collection was removed here: the manager scans and shows the folders again.
signal cleared

## Added to the Remove confirmation of a collection a host sent.
const REMOVE_NOTE := " If a host's map needs it again, you are asked before it is downloaded again."
const CAP_CHOICES_MB: Array[int] = [256, 512, 1024, 2048, 4096]
const MIB := 1024 * 1024
const GIB := 1024 * 1024 * 1024

var summary_label: Label
var clear_button: Button
var cap_option: OptionButton


## Adds a section to `body` (the manager's column) for `manager` and keeps it current: it reads
## the cache again whenever the manager reports a change, and a clear makes the manager scan.
static func attach(manager: Node, body: Control) -> LibraryCacheSection:
	var section := LibraryCacheSection.new()
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
	name = "CacheSection"
	theme_type_variation = &"BoxContainerSpaced"
	summary_label = Label.new()
	summary_label.name = "Summary"
	summary_label.theme_type_variation = &"Caption"
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(summary_label)
	var limit := Label.new()
	limit.name = "LimitLabel"
	limit.theme_type_variation = &"Caption"
	limit.text = "Limit"
	add_child(limit)
	cap_option = OptionButton.new()
	cap_option.name = "CapOption"
	var tip := "When new downloads would pass this, the oldest ones no open map uses go first."
	cap_option.tooltip_text = tip
	cap_option.item_selected.connect(_on_cap_selected)
	add_child(cap_option)
	clear_button = Button.new()
	clear_button.name = "ClearButton"
	clear_button.theme_type_variation = &"Secondary"
	clear_button.text = clear_label()
	clear_button.pressed.connect(request_clear)
	add_child(clear_button)
	_fill_cap_choices()
	refresh()


# ---- the words (pure) ----


## "Clear downloaded collections".
static func clear_label() -> String:
	return "Clear downloaded %s" % LibraryNames.lower(2)


## "2 collections downloaded from hosts, 45.0 MB of 1.0 GB".
static func summary_text(count: int, bytes: int, cap_bytes: int) -> String:
	return (
		"%s downloaded from hosts: %s of %s"
		% [_sentence(LibraryNames.counted(count)), size_text(bytes), size_text(cap_bytes)]
	)


## `text` with its first letter capitalised (the rest as it is).
static func _sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


## "45.0 MB", "1.0 GB": the importer's size text, with gigabytes added.
static func size_text(bytes: int) -> String:
	if bytes >= GIB:
		return "%.1f GB" % (float(bytes) / GIB)
	return LibraryImporter.size_text(bytes)


## The confirmation: what goes (how many, how much), what it touches (saved maps that use them),
## and what it does not touch.
static func clear_message(count: int, bytes: int, map_count: int) -> String:
	var goes := (
		"%s (%s) that hosts sent you will be deleted from this computer."
		% [_sentence(LibraryNames.counted(count)), size_text(bytes)]
	)
	var maps := "No saved map uses them."
	if map_count > 0:
		maps = (
			(
				"%s use them; opening one will ask the host again when you join, and ask you before"
				+ " anything is downloaded."
			)
			% LibraryNames.count_of(map_count, "saved map", "saved maps")
		)
	return "%s %s Your own %s are not touched." % [goes, maps, LibraryNames.lower(2)]


## The number of saved maps (folders under `levels_dir`) that use any of `ids`. Reads each map's
## manifest only, so call it on demand.
static func maps_using(ids: Array, levels_dir: String) -> int:
	var seen := {}
	for id: Variant in ids:
		for folder in LibraryInstall.levels_using(String(id), levels_dir):
			seen[folder] = true
	return seen.size()


# ---- the row ----


## Reads the cache again: the count and size, whether the row shows at all, the cap.
func refresh() -> void:
	var items := LibraryFromHost.inventory()
	var bytes := 0
	for item in items:
		bytes += int(item["bytes"])
	var cap := LibraryFromHost.cap_bytes()
	summary_label.text = summary_text(items.size(), bytes, cap)
	clear_button.disabled = items.is_empty()
	visible = not items.is_empty()
	_select_cap(cap)


## What the clear would do: {ids, count, bytes, maps, message}. Reads the saved maps' manifests.
func describe_clear() -> Dictionary:
	var ids: Array[String] = []
	var bytes := 0
	for item in LibraryFromHost.inventory():
		ids.append(String(item["id"]))
		bytes += int(item["bytes"])
	var maps := maps_using(ids, LevelManager.levels_dir)
	return {
		"ids": ids,
		"count": ids.size(),
		"bytes": bytes,
		"maps": maps,
		"message": clear_message(ids.size(), bytes, maps),
	}


## The button: asks first, naming how many collections, how much room and how many saved maps.
func request_clear() -> void:
	var plan := describe_clear()
	if int(plan["count"]) == 0:
		refresh()
		return
	UIManager.show_danger_confirmation(clear_label(), String(plan["message"]), clear_now, "Clear")


## Removes every from-host collection (LibraryFromHost.clear_all: SafeDelete, nothing else), then
## serves the rest again. Returns clear_all's report.
func clear_now() -> Dictionary:
	var report := LibraryFromHost.clear_all()
	for id: String in report["removed"]:
		# A collection turned off and then removed must not come back turned off.
		LibraryRegistry.set_enabled(id, true)
	LibraryImportFlow.refresh_all()
	refresh()
	var removed := (report["removed"] as Array).size()
	if removed > 0:
		UIManager.show_success("Removed %s" % LibraryNames.counted(removed))
	if not (report["failed"] as Array).is_empty():
		var left := LibraryNames.counted((report["failed"] as Array).size())
		UIManager.show_error("%s could not be removed." % _sentence(left))
	cleared.emit()
	return report


func _fill_cap_choices() -> void:
	cap_option.clear()
	for megabytes in CAP_CHOICES_MB:
		cap_option.add_item(size_text(megabytes * MIB), megabytes)


## Shows the saved cap; a value that is none of the choices is added so it still shows.
func _select_cap(cap_bytes: int) -> void:
	var megabytes := int(float(cap_bytes) / MIB)
	var at := cap_option.get_item_index(megabytes)
	if at < 0:
		cap_option.add_item(size_text(cap_bytes), megabytes)
		at = cap_option.get_item_index(megabytes)
	cap_option.select(at)


func _on_cap_selected(index: int) -> void:
	LibraryFromHost.set_cap_mb(cap_option.get_item_id(index))
	refresh()
