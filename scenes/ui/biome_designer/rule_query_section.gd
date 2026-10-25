class_name DesignerQuerySection
extends Foldout

## The Assets section of the rule inspector (design doc 4.3): what the rule's query selects,
## live. The matched assets by group (each with a pin), the query's clauses as chips that can be
## removed, controls that add a filter (a category and subtype, the rule's own role), the shared
## filters (tags, size class, season mode) and the count and order, and a few near misses with
## the one condition each fails. Every edit is a model command; the list is recomputed from the
## model after each (resolved_assets is cached per revision).

const MAX_GROUP_ROWS := 14
const MAX_NEAR_MISSES := 5
const ORDER_OPTIONS: Array = [
	["hash", "Spread by hash"], ["id", "By name"], ["explicit", "As listed"]
]
const SEASON_OPTIONS: Array = [["auto", "Only in season"], ["any", "Any season"]]
const SIZE_CLASSES: Array[String] = ["large", "medium", "small", "ground"]

var session: BiomeDesignerSession = null

var _key: String = ""
var _summary: Label
var _matched: VBoxContainer
var _clauses: HFlowContainer
var _category: OptionButton
var _subtype: LineEdit
var _tags: Dictionary = {}
var _classes: Dictionary = {}
var _count: PropertyRow
var _all_count: Button
var _order: OptionButton
var _seasons: OptionButton
var _near: VBoxContainer
var _syncing: bool = false


func _init() -> void:
	name = "Assets"
	title = "Assets"
	button_room = true
	expanded = true


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	_summary = DesignerRows.caption("Summary", "")
	add_child(_summary)
	_matched = VBoxContainer.new()
	_matched.name = "Matched"
	add_child(_matched)
	add_child(DesignerRows.caption("QueryCaption", "Query"))
	_clauses = HFlowContainer.new()
	_clauses.name = "Clauses"
	add_child(_clauses)
	_build_adders()
	_build_shared()
	_near = VBoxContainer.new()
	_near.name = "NearMisses"
	add_child(_near)
	session.model.changed.connect(func(_reason: String) -> void: _sync())


func show_rule(key: String) -> void:
	_key = key
	_sync()


func _build_adders() -> void:
	var cats: Array = [["", "Any category"]]
	for category: String in LibraryContracts.CATEGORIES:
		cats.append([category, DesignerSlots.category_label(category)])
	_category = DesignerRows.option(
		self,
		"FilterCategory",
		"Add filter",
		cats,
		"Select every asset of a category (and subtype)."
	)
	_subtype = LineEdit.new()
	_subtype.name = "FilterSubtype"
	_subtype.placeholder_text = "subtype (optional), then Enter"
	_subtype.text_submitted.connect(func(_text: String) -> void: _add_filter())
	add_child(_subtype)
	var buttons := HBoxContainer.new()
	var add := Button.new()
	add.name = "AddFilter"
	add.text = "Add filter"
	add.pressed.connect(_add_filter)
	buttons.add_child(add)
	var by_role := Button.new()
	by_role.name = "AddRole"
	by_role.text = "Add assets used as this role"
	by_role.tooltip_text = "Select every catalog asset the library says is used as the rule's role."
	by_role.pressed.connect(
		func() -> void:
			session.model.add_clause(_key, {"role": String(session.model.value(_key, "role", ""))})
	)
	buttons.add_child(by_role)
	add_child(buttons)


func _build_shared() -> void:
	for field in ["tags_any", "tags_all", "tags_none"]:
		var edit := LineEdit.new()
		edit.name = field
		edit.placeholder_text = "%s: tag, tag" % field.replace("_", " ")
		edit.tooltip_text = {
			"tags_any": "Keep assets that have at least one of these tags.",
			"tags_all": "Keep assets that have all of these tags.",
			"tags_none": "Drop assets that have any of these tags.",
		}[field]
		edit.text_submitted.connect(_on_tags.bind(field))
		edit.focus_exited.connect(func() -> void: _on_tags(edit.text, field))
		add_child(edit)
		_tags[field] = edit
	var classes := HBoxContainer.new()
	classes.name = "Classes"
	for size_class in SIZE_CLASSES:
		var chip := DesignerRows.chip(
			"Class_" + size_class,
			size_class.capitalize(),
			"Keep only assets of the %s size class." % size_class
		)
		chip.toggle_mode = true
		chip.toggled.connect(_on_class_toggled.bind(size_class))
		classes.add_child(chip)
		_classes[size_class] = chip
	add_child(classes)
	_count = DesignerRows.number(
		"Count",
		"Groups to take",
		1.0,
		16.0,
		1.0,
		"How many groups of variants the query takes (after the pinned ones)."
	)
	_count.value_changed.connect(
		func(value: float) -> void:
			if not _syncing:
				session.model.set_query_field(_key, "count", roundi(value))
	)
	add_child(_count)
	_all_count = DesignerRows.chip(
		"AllGroups", "Take all groups", "Use every group that passes the filters."
	)
	_all_count.toggle_mode = true
	_all_count.toggled.connect(
		func(on: bool) -> void:
			if not _syncing:
				session.model.set_query_field(_key, "count", "all" if on else roundi(_count.value))
	)
	add_child(_all_count)
	_order = DesignerRows.option(
		self,
		"Order",
		"Pick groups",
		ORDER_OPTIONS,
		"How the groups are ordered before the first few are taken."
	)
	_order.item_selected.connect(
		func(index: int) -> void:
			session.model.set_query_field(_key, "order", _order.get_item_metadata(index))
	)
	_seasons = DesignerRows.option(
		self,
		"SeasonMode",
		"Season",
		SEASON_OPTIONS,
		"Only assets made for the season being compiled, or any."
	)
	_seasons.item_selected.connect(
		func(index: int) -> void:
			session.model.set_query_field(_key, "seasons", _seasons.get_item_metadata(index))
	)


func _add_filter() -> void:
	var clause := {}
	var category: Variant = DesignerRows.selected(_category)
	if category != null and String(category) != "":
		clause["category"] = category
	if _subtype.text.strip_edges() != "":
		clause["subtype"] = _subtype.text.strip_edges()
	if clause.is_empty():
		return
	session.model.add_clause(_key, clause)
	_subtype.text = ""


func _on_tags(text: String, field: String) -> void:
	if _syncing or _key == "":
		return
	var tags: Array = []
	for part in text.split(",", false):
		var tag := part.strip_edges()
		if tag != "" and not tag in tags:
			tags.append(tag)
	session.model.set_query_field(_key, field, tags)


func _on_class_toggled(on: bool, size_class: String) -> void:
	if _syncing or _key == "":
		return
	var held: Array = session.model.rule(_key)["query"].get("size_class", []).duplicate()
	if on and not size_class in held:
		held.append(size_class)
	elif not on:
		held.erase(size_class)
	session.model.set_query_field(_key, "size_class", held)


func _sync() -> void:
	if _key == "" or session == null or not session.model.has_rule(_key):
		return
	_syncing = true
	var model := session.model
	var query: Dictionary = model.rule(_key)["query"]
	var season := model.season_ids()[session.season_index]
	var found := model.resolved_assets(_key, season)
	var groups := {}
	for candidate in found:
		groups[candidate["group"]] = true
	_summary.text = "%d assets in %d groups" % [found.size(), groups.size()]
	_show_matched(found, query)
	_show_clauses(query)
	for field: String in _tags:
		var edit: LineEdit = _tags[field]
		if not edit.has_focus():
			edit.text = ", ".join(PackedStringArray(query.get(field, [])))
	for size_class: String in _classes:
		(_classes[size_class] as Button).set_pressed_no_signal(
			size_class in query.get("size_class", [])
		)
	var count: Variant = query.get("count", "all")
	_all_count.set_pressed_no_signal(count is String)
	_count.set_value_no_signal(float(count) if not count is String else 3.0)
	_count.modulate.a = 0.5 if count is String else 1.0
	DesignerRows.select(_order, query.get("order", "hash"))
	DesignerRows.select(_seasons, query.get("seasons", "auto"))
	_show_near_misses(query, season)
	_syncing = false


func _show_matched(found: Array[Dictionary], query: Dictionary) -> void:
	for child in _matched.get_children():
		_matched.remove_child(child)
		child.queue_free()
	var shown := {}
	var pins: Array = query.get("pin", [])
	for candidate in found:
		var group := String(candidate["group"])
		if shown.has(group):
			shown[group] += 1
			continue
		shown[group] = 1
	var rows := 0
	var done := {}
	for candidate in found:
		var group := String(candidate["group"])
		if done.has(group):
			continue
		done[group] = true
		rows += 1
		if rows > MAX_GROUP_ROWS:
			_matched.add_child(
				DesignerRows.caption("More", "and %d more groups" % (shown.size() - MAX_GROUP_ROWS))
			)
			break
		_matched.add_child(_matched_row(candidate, int(shown[group]), pins))


func _matched_row(candidate: Dictionary, variants: int, pins: Array) -> Control:
	var entry: Dictionary = candidate["entry"]
	var line := HBoxContainer.new()
	line.name = "Group_" + String(candidate["group"]).validate_node_name()
	var label := Label.new()
	label.text = (
		String(entry.get("name", candidate["id"])) + ("  x%d" % variants if variants > 1 else "")
	)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = (
		"%s\n%d triangles, %s"
		% [candidate["ref"], int(entry.get("triangles", 0)), candidate["library"]]
	)
	line.add_child(label)
	var ref := String(candidate["ref"])
	var pinned := ref in pins or String(candidate["group"]) in pins
	var pin := DesignerRows.chip(
		"Pin", "Pinned" if pinned else "Pin", "Always take this group, whatever the filters say."
	)
	pin.toggle_mode = true
	pin.set_pressed_no_signal(pinned)
	pin.toggled.connect(func(on: bool) -> void: session.model.set_pin(_key, ref, on))
	line.add_child(pin)
	return line


func _show_clauses(query: Dictionary) -> void:
	for child in _clauses.get_children():
		_clauses.remove_child(child)
		child.queue_free()
	var matches: Array = query.get("match", [])
	for i in matches.size():
		var chip := DesignerRows.chip(
			"Clause_%d" % i,
			_clause_text(matches[i]) + "  x",
			"Click to remove this clause from the query."
		)
		chip.pressed.connect(func() -> void: session.model.remove_clause(_key, i))
		_clauses.add_child(chip)


static func _clause_text(clause: Variant) -> String:
	if not clause is Dictionary:
		return "?"
	if (clause as Dictionary).has("ref"):
		return "ref " + String(clause["ref"])
	var parts: Array[String] = []
	for field in LibraryContracts.QUERY_CLAUSE_KEYS:
		if (clause as Dictionary).has(field):
			var value: Variant = clause[field]
			parts.append(
				(
					("%s %s" % [field, value])
					if not value is Array
					else "%s [%d]" % [field, (value as Array).size()]
				)
			)
	return " / ".join(PackedStringArray(parts)) if not parts.is_empty() else "everything"


func _show_near_misses(query: Dictionary, season: String) -> void:
	for child in _near.get_children():
		_near.remove_child(child)
		child.queue_free()
	if LibraryQuery.filter_clauses(query).is_empty():
		return
	var chosen := {}
	for candidate in session.model.resolved_assets(_key, season):
		chosen[candidate["local"]] = true
	var lines: Array[String] = []
	for candidate in session.model.catalog():
		if chosen.has(candidate["local"]) or lines.size() >= MAX_NEAR_MISSES:
			continue
		var why := LibraryQuery.why_not(query, candidate, season)
		if why.size() == 1:
			lines.append(
				"%s: %s" % [(candidate["entry"] as Dictionary).get("name", candidate["id"]), why[0]]
			)
	if not lines.is_empty():
		_near.add_child(DesignerRows.caption("NearCaption", "Nearly matched:"))
		_near.add_child(DesignerRows.caption("NearList", "\n".join(PackedStringArray(lines))))
