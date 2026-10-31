extends RefCounted

## Render-job probe for the Licences page (Settings, About, Licences; job `licences_look.json`).
##
## Call it with `{"op": "call", "script": "res://tools/render_jobs/probes/licences.gd",
## "action": ...}`:
## - `about`: open Settings (when it is not open) on the About section.
## - `open`: press About's "View licences" button, as a click does.
## - `select` (`id`): put the keyboard focus on the list row of the entry with that id (focus moves
##   the selection, as Up and Down do).
## - `scroll` (`to`, a fraction 0..1): scroll the notice pane to that share of its length.
## - `focus_text`: give the notice pane the keyboard focus (what Right does from the list).
## - `report`: log the page's size, the entry count, the selected entry and the pane's scroll.
## - `close`: close the page (Escape's path), then Settings.


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "report")):
		"about":
			return _about(base)
		"open":
			return _open(base)
		"select":
			return _select(base, String(step.get("id", "")))
		"scroll":
			return _scroll(base, float(step.get("to", 0.0)))
		"focus_text":
			var page := _page(base)
			if page == null:
				return "no page"
			page.text_pane.grab_focus()
			return "text focused"
		"report":
			return _report(base)
		"close":
			return _close(base)
	return "unknown action %s" % step.get("action", "")


static func _menu(base: Node) -> SettingsMenu:
	for child in base.get_tree().root.get_children():
		if child is SettingsMenu and not child.is_queued_for_deletion():
			return child
	return null


static func _page(base: Node) -> LicencesPanel:
	for child in base.get_tree().root.get_children():
		if child is LicencesPanel and not child.is_queued_for_deletion():
			return child
	return null


static func _about(base: Node) -> String:
	var menu := _menu(base)
	if menu == null:
		menu = UIManager.open_settings() as SettingsMenu
	menu.section_rail.select(&"About")
	return "settings on %s" % menu.section_rail.selected


static func _open(base: Node) -> String:
	var menu := _menu(base)
	if menu == null:
		return "settings not open"
	menu.licences_button.pressed.emit()
	return "licences opening"


static func _select(base: Node, id: String) -> String:
	var page := _page(base)
	if page == null:
		return "no page"
	var entries := LicenceCatalog.entries()
	for index in entries.size():
		if entries[index]["id"] == id:
			page.row_at(index).grab_focus()
			return "focused %s (%d)" % [id, index]
	return "no entry %s" % id


static func _scroll(base: Node, to: float) -> String:
	var page := _page(base)
	if page == null:
		return "no page"
	var bar := page.text_pane.get_v_scroll_bar()
	bar.value = (bar.max_value - bar.page) * clampf(to, 0.0, 1.0)
	return "scrolled to %.0f of %.0f" % [bar.value, bar.max_value]


static func _report(base: Node) -> String:
	var page := _page(base)
	if page == null:
		return "no page"
	var sheet := page.get_node("CenterContainer/PanelContainer") as Control
	var bar := page.text_pane.get_v_scroll_bar()
	return (
		"sheet %s at %s, %d entries, selected %d (%s), text %d chars, scroll %.0f/%.0f, canvas %s"
		% [
			sheet.size,
			sheet.global_position,
			page.entry_count(),
			page.selected_index(),
			page.title_label.text,
			page.text_pane.text.length(),
			bar.value,
			bar.max_value,
			page.get_viewport().get_visible_rect().size,
		]
	)


static func _close(base: Node) -> String:
	var page := _page(base)
	if page != null:
		page.close()
	var menu := _menu(base)
	if menu != null:
		menu.animate_out()
	return "closing"
