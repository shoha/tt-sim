class_name SettingsLayout
extends RefCounted

## Builds the Settings menu's groups, per SettingsSpec, around the rows settings_menu.tscn
## declares: each tab's rows move under group headings (a Heading label and a quiet Reset button),
## each row gets its one-sentence description, and the Accessibility tab is made. The rows keep
## their nodes and unique names, so no code that reads a control changes.
##
## Each row stands in a `RowBlock` (the row, then its description flush under it) so a row and its
## sentence read as one item between the group's wider gaps. The same blocks are what the search
## box filters: a block shows when every word typed is in its label, sentence or group title, a
## group shows when any block does, and a tab shows in the rail when any group does.

const NO_RESULTS := "No settings match. Try fewer or different words."
## Names of the tscn's old captions and rules, replaced by group headings and descriptions.
const RETIRED := [
	"GridInfo", "NetworkInfo", "P2PDescription", "PrereleasesDescription", "HSeparator",
	"HSeparator2", "HSeparator2a",
]
const MORE_GROUP := {"title": "More", "rows": []}

## One per group, in tab order: {id, title, tab, box, reset (Button or null), controls (Array of
## the value controls its Reset puts back), derived (Array of controls that refresh themselves)}.
var groups: Array[Dictionary] = []
## One per row: {block, row, tab, group (index into groups), text (lower case), match}.
var entries: Array[Dictionary] = []

var _menu: SettingsMenu
var _empty: Label


func _init(menu: SettingsMenu) -> void:
	_menu = menu


## Makes the Accessibility tab, then builds every tab's groups.
func build() -> void:
	_make_accessibility_tab()
	for tab_name in SettingsSpec.TABS:
		_build_tab(String(tab_name))
	_empty = Label.new()
	_empty.name = "NoResults"
	_empty.theme_type_variation = &"Caption"
	_empty.text = NO_RESULTS
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.visible = false
	var tabs := _menu.tab_container
	tabs.get_parent().add_child(_empty)
	tabs.get_parent().move_child(_empty, tabs.get_index() + 1)


## The group `title` holds `control` in (the one whose Reset covers it), or an empty dictionary.
func group_of(control: Node) -> Dictionary:
	for group in groups:
		if (group.controls as Array).has(control) or (group.derived as Array).has(control):
			return group
	return {}


## Shows only the blocks matching `text` (words separated by spaces; empty shows everything),
## hides groups and rail sections left with none, and says so when nothing matches. Moves to the
## first section with a match when the current one has none.
func set_filter(text: String) -> void:
	var words := text.strip_edges().to_lower().split(" ", false)
	var group_hits := {}
	var name_hits := {}
	var tab_hits := {}
	var previous_match := true
	for entry in entries:
		var entry_match := _matches(entry, words, previous_match)
		entry.match = entry_match
		if not (entry.text as String).is_empty():
			previous_match = entry_match
		_sync_block(entry)
		if entry_match and (entry.row as Control).visible:
			group_hits[entry.group] = true
			tab_hits[entry.tab] = true
			if _names(entry, words):
				name_hits[entry.group] = true
	_rank(name_hits)
	for i in groups.size():
		(groups[i].box as Control).visible = group_hits.has(i)
	var current := String(_menu.section_rail.selected)
	var first := ""
	for spec in SettingsMenu.SECTIONS:
		var tab_name := String(spec[0])
		var shown: bool = tab_hits.has(tab_name) or words.is_empty()
		if not (tab_name == "Updates" and not OS.get_environment("SteamAppId").is_empty()):
			_menu.section_rail.set_item_visible(StringName(tab_name), shown)
		if shown and first.is_empty():
			first = tab_name
	if not words.is_empty() and not tab_hits.has(current) and not first.is_empty():
		_menu.section_rail.select(StringName(first))
	_menu.tab_container.visible = words.is_empty() or not tab_hits.is_empty()
	_empty.visible = not _menu.tab_container.visible


## Whether every word is in the row's own name (not only in its sentence). An empty search
## names nothing, so the groups keep their order.
func _names(entry: Dictionary, words: PackedStringArray) -> bool:
	if words.is_empty() or (entry.label as String).is_empty():
		return false
	for word in words:
		if not (entry.label as String).contains(word):
			return false
	return true


## Orders each tab's groups: those holding a row whose name matches come before those that only
## mention the words in a sentence ("Shadow quality" before "Quality"), each side in its own
## order; with no search every group is back in its place.
func _rank(name_hits: Dictionary) -> void:
	var by_tab := {}
	for i in groups.size():
		var ids: Array = by_tab.get(groups[i].tab, [])
		ids.append(i)
		by_tab[groups[i].tab] = ids
	for tab_name in by_tab:
		var ids: Array = by_tab[tab_name]
		# The places the tab's groups hold now (a retired caption freed after the build leaves
		# gaps in any index noted earlier), in order.
		var slots: Array = ids.map(func(i: int) -> int: return (groups[i].box as Control).get_index())
		slots.sort()
		var order := ids.duplicate()
		order.sort_custom(
			func(a: int, b: int) -> bool:
				var rank_a := 0 if name_hits.has(a) else 1
				var rank_b := 0 if name_hits.has(b) else 1
				return a < b if rank_a == rank_b else rank_a < rank_b
		)
		for k in order.size():
			var box := groups[order[k]].box as Control
			box.get_parent().move_child(box, slots[k])


func _matches(entry: Dictionary, words: PackedStringArray, previous_match: bool) -> bool:
	if words.is_empty():
		return true
	if (entry.text as String).is_empty():
		return previous_match
	for word in words:
		if not (entry.text as String).contains(word):
			return false
	return true


func _sync_block(entry: Dictionary) -> void:
	(entry.block as Control).visible = bool(entry.match) and (entry.row as Control).visible


func _make_accessibility_tab() -> void:
	var tabs := _menu.tab_container
	var scroll := ScrollContainer.new()
	scroll.name = "Accessibility"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.theme_type_variation = &"TabContentMargin"
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.theme_type_variation = &"BoxContainerSpaced"
	margin.add_child(content)
	tabs.add_child(scroll)
	tabs.move_child(scroll, 2)
	# Interface size, Reduce motion and Wind motion were Graphics rows: they come here.
	var graphics := tabs.get_node("Graphics/Margin/Content")
	for row_name in ["InterfaceSize", "ReduceMotion", "WindMotion"]:
		var row := graphics.find_child(row_name, true, false)
		if row:
			_move(row, content)


func _build_tab(tab_name: String) -> void:
	var tab := _menu.tab_container.get_node_or_null(tab_name) as ScrollContainer
	if tab == null:
		return
	var content := tab.get_node("Margin/Content") as VBoxContainer
	content.theme_type_variation = &"BoxContainerGroups"
	var listed := {}
	for spec in SettingsSpec.TABS[tab_name]:
		listed[spec.get("foldout", "")] = true
		for row_spec in spec.rows:
			listed[row_spec.row] = true
			listed[row_spec.get("desc_node", "")] = true
	var strays: Array = []
	for child in content.get_children():
		if RETIRED.has(String(child.name)):
			child.queue_free()
		elif not listed.has(String(child.name)) and not String(child.name).begins_with("Group_"):
			strays.append({"row": String(child.name)})
	for spec in SettingsSpec.TABS[tab_name]:
		_build_group(tab_name, content, spec)
	if not strays.is_empty():
		_build_group(tab_name, content, {"title": MORE_GROUP.title, "rows": strays})


func _build_group(tab_name: String, content: VBoxContainer, spec: Dictionary) -> void:
	var title := String(spec.title)
	var foldout: Foldout = null
	if spec.has("foldout"):
		foldout = content.find_child(String(spec.foldout), true, false) as Foldout
	var box: Control
	var rows_parent: Control
	if foldout:
		box = foldout
		rows_parent = foldout.body
		content.move_child(foldout, -1)
	else:
		var vbox := VBoxContainer.new()
		vbox.name = "Group_" + title.replace(" ", "")
		vbox.theme_type_variation = &"BoxContainerSpaced"
		content.add_child(vbox)
		box = vbox
		rows_parent = vbox
	var group := {
		"id": StringName("%s/%s" % [tab_name, title]),
		"title": title,
		"tab": tab_name,
		"box": box,
		"reset": null,
		"controls": [],
		"derived": [],
	}
	var group_index := groups.size()
	groups.append(group)
	if not foldout:
		var header := _header(title, bool(spec.get("reset", true)), group)
		rows_parent.add_child(header)
		if spec.has("blurb"):
			rows_parent.add_child(_describe(String(spec.blurb)))
	for row_spec in spec.rows:
		_build_row(content, rows_parent, row_spec, group, group_index, tab_name, title)
	# A group of one setting needs no Reset of its own: the row is the reset (T-S3).
	var alone := (group.controls as Array).size() <= 1
	if not foldout and alone and group.reset:
		(group.reset as Button).queue_free()
		group.reset = null
	if foldout and bool(spec.get("reset", true)) and not alone:
		var line := HBoxContainer.new()
		line.name = "ResetLine"
		line.alignment = BoxContainer.ALIGNMENT_END
		line.add_child(_reset_button(group))
		rows_parent.add_child(line)


func _build_row(
	content: VBoxContainer,
	parent: Control,
	row_spec: Dictionary,
	group: Dictionary,
	group_index: int,
	tab_name: String,
	title: String
) -> void:
	var row := content.find_child(String(row_spec.row), true, false) as Control
	if row == null:
		push_warning("SettingsLayout: no row %s in %s" % [row_spec.row, tab_name])
		return
	if bool(row_spec.get("attach", false)) and not entries.is_empty():
		# A line that belongs to the row above it (a note the row's own code shows and hides):
		# it joins that row's block, flush under its sentence, and takes no entry of its own.
		_move(row, (entries.back().block as Control))
		return
	var block := VBoxContainer.new()
	block.name = "RowBlock_" + String(row_spec.row)
	var old_parent := row.get_parent()
	if parent.is_ancestor_of(row):
		# A Foldout's rows already stand in its body: the block takes the row's place there.
		old_parent.add_child(block)
		old_parent.move_child(block, row.get_index())
	else:
		parent.add_child(block)
	_move(row, block)
	var sentence := String(row_spec.get("desc", ""))
	if row_spec.has("desc_node"):
		var node := content.find_child(String(row_spec.desc_node), true, false) as Label
		if node:
			_move(node, block)
			_left(node)
			# A hard line break in a scene label would leave a ragged second line.
			node.text = node.text.replace("\n", " ")
			sentence = node.text
	elif not sentence.is_empty():
		block.add_child(_describe(sentence))
	if bool(row_spec.get("note", false)) and row is Label:
		_left(row as Label)
	if not (row is Label and not bool(row_spec.get("note", false))):
		_collect_controls(row, group, bool(row_spec.get("derived", false)))
	var label_text := ""
	if row is HBoxContainer and row.get_child_count() > 0 and row.get_child(0) is Label:
		label_text = (row.get_child(0) as Label).text
	elif row is Label:
		label_text = (row as Label).text
	var text := ""
	if not label_text.is_empty() or not sentence.is_empty():
		text = ("%s %s %s %s" % [label_text, sentence, title, tab_name]).to_lower()
	var entry := {
		"block": block, "row": row, "tab": tab_name, "group": group_index, "text": text,
		"label": label_text.to_lower(), "match": true,
	}
	entries.append(entry)
	row.visibility_changed.connect(_sync_block.bind(entry))
	_sync_block(entry)


func _collect_controls(row: Node, group: Dictionary, derived: bool) -> void:
	for node in row.find_children("*", "Control", true, false):
		if node is HSlider or node is CheckButton or node is OptionButton:
			(group.derived if derived else group.controls).append(node)


func _header(title: String, with_reset: bool, group: Dictionary) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header_" + title.replace(" ", "")
	var label := Label.new()
	label.name = "Title"
	label.text = title
	label.theme_type_variation = &"Heading"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	if with_reset:
		header.add_child(_reset_button(group))
	return header


## The group's quiet Reset button (the session wires its press and its enabled state).
func _reset_button(group: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Reset"
	button.text = "Reset"
	button.theme_type_variation = &"Ghost"
	button.tooltip_text = "Put the settings in this group back to their defaults"
	group.reset = button
	return button


static func _describe(text: String) -> Label:
	var label := Label.new()
	label.name = "Description"
	label.theme_type_variation = &"Caption"
	label.text = text
	_left(label)
	return label


static func _left(label: Label) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Moves `node` under `parent` and keeps the owner of everything in its subtree: remove_child
## clears them, and every `%UniqueName` lookup on the menu goes with them (Foldout does the same).
static func _move(node: Node, parent: Node) -> void:
	var owners := {}
	_collect_owners(node, owners)
	if node.get_parent():
		node.get_parent().remove_child(node)
	parent.add_child(node)
	for moved in owners:
		moved.owner = owners[moved]


static func _collect_owners(node: Node, out: Dictionary) -> void:
	if node.owner:
		out[node] = node.owner
	for child in node.get_children():
		_collect_owners(child, out)
