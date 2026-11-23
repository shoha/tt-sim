class_name AuthoringPanes
extends RefCounted

## The panes AuthoringPanel builds itself for the tools that predate ToolRegistry (Biome, Place,
## Sculpt, Paint), split out of the panel to keep it under the file-size cap (card ui-authoring3).
## Each builder takes the panel, sets the panel's field for its tiles (biome_field, place_rows,
## sculpt_field, paint_fields) and wires the tiles to the panel's signals. Every pane opens with
## its header, then the picker and the size row (the basics, above the fold of a 720p card), and
## keeps the gestures behind More and the strength behind Advanced.


## Hides a pane's own title: the card's title row (AuthoringTitleRow) names the tool, and the pane
## keeps its one-line summary.
static func hide_titles(pane: Control) -> void:
	# A pane with its own lead line (a direct "...Hint" caption) gets one lead only: the header's
	# summary would be a second, saying the same in other words.
	var has_lead := false
	for child in pane.get_children():
		if child is Label and String(child.name).ends_with("Hint") and (child as Label).visible:
			has_lead = true
	for header: Node in pane.find_children("*", "MenuHeader", true, false):
		(header as MenuHeader).title_label.visible = false
		if has_lead:
			(header as MenuHeader).caption_label.visible = false
	if has_lead:
		_lead_first(pane)


## Whether a visible control (a size row, a picker: not a caption) sits among `pane`'s children
## from index `from` up to, not including, `to`.
static func _control_between(pane: Control, from: int, to: int) -> bool:
	for i in range(from, to):
		var child := pane.get_child(i) as Control
		if child != null and child.visible and not child is Label:
			return true
	return false


## Moves a pane's lead (a direct "...Hint" label, with its "...HintMore" foldout) up under the
## header when the size row or another control sits between them, so the lead is the first line
## of the card (Paint and Sculpt had the header's rule, a gap, Size and only then the lead).
static func _lead_first(pane: Control) -> void:
	var at := -1
	for child in pane.get_children():
		if child is MenuHeader:
			at = child.get_index() + 1
			break
	if at < 0:
		return
	for child in pane.get_children():
		if child is Label and String(child.name).ends_with("Hint") and child.visible:
			var more := pane.get_node_or_null(NodePath(String(child.name) + "More"))
			if _control_between(pane, at, child.get_index()):
				pane.move_child(child, at)
			if more != null:
				pane.move_child(more, child.get_index() + 1)
			# The header's rule (and its empty band) goes: the lead block carries its own rule
			# below it, as a header's caption does, so every card reads title, lead, rule, picker.
			(pane.get_child(at - 1) as Control).visible = false
			var rule := HSeparator.new()
			rule.name = "LeadRule"
			pane.add_child(rule)
			pane.move_child(rule, (more.get_index() if more != null else child.get_index()) + 1)
			return


## The palette's biome entries sorted by the name the tiles show (the picker reads alphabetically,
## not by the id the catalogue lists them in).
static func by_display_name(entries: Array) -> Array:
	var sorted := entries.duplicate()
	sorted.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				AuthoringPanel.short_name(String(a["name"])).naturalnocasecmp_to(
					AuthoringPanel.short_name(String(b["name"]))
				)
				< 0
			)
	)
	return sorted


## A wrapped caption line saying a pane's gestures.
static func hint(hint_name: String, text: String) -> Label:
	return AuthoringChrome.help_label(hint_name, text)


## A pane's help: a lead of two lines that says enough to start, and the rest behind "More".
static func add_help(pane: Control, hint_name: String, lead: String, more: String) -> void:
	pane.add_child(hint(hint_name, lead))
	if more != "":
		pane.add_child(AuthoringChrome.more_foldout(hint_name + "More", more))


## The step a section label (Biomes, Brush) keeps over and above the pane's gap, so it reads
## as the start of its tiles and not as a last line of the hint paragraph above it (S4: more
## room above a label than below it).
static func section_gap(gap_name: String) -> Control:
	var gap := Control.new()
	gap.name = gap_name
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(0, AuthoringPanel.SECTION_ABOVE)
	return gap


## The pane's root: a plain column with the 8 px step and a header.
static func _column(pane_name: String, header_name: String, tool: ToolDescriptor) -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.name = pane_name
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = header_name
	header.setup(tool.label, tool.summary)
	pane.add_child(header)
	return pane


## Water: WaterToolPane, its signals relayed (a river's Width row sets the brush radius; a pond has
## the Size row).
static func water(panel: AuthoringPanel) -> Control:
	var pane := WaterToolPane.new()
	panel.water_pane = pane
	pane.set_pond_row(panel.build_size_row("Pond"))
	pane.depth_selected.connect(func(depth: int) -> void: panel.water_depth_selected.emit(depth))
	pane.speed_changed.connect(func(speed: float) -> void: panel.water_speed_changed.emit(speed))
	pane.width_changed.connect(
		func(width: float) -> void: panel.brush_size_changed.emit(width * 0.5)
	)
	return pane


## Bridge: BridgeToolPane, its kind tiles relayed.
static func bridge(panel: AuthoringPanel) -> Control:
	var pane := BridgeToolPane.new()
	panel.bridge_pane = pane
	pane.kind_selected.connect(func(kind: int) -> void: panel.bridge_kind_selected.emit(kind))
	return pane


## Biome: the size row, the gesture behind More, the nine biome tiles and the Advanced foldout.
static func biome(panel: AuthoringPanel, tool: ToolDescriptor) -> Control:
	var pane := _column("BiomePane", "BiomeHeader", tool)
	# The size and the picker come first (the nine biomes are five rows, which must fit a 720p
	# card without scrolling); the gesture sits behind More, under the picker.
	pane.add_child(panel.build_size_row("Biome"))
	var more := AuthoringChrome.more_foldout(
		"BiomeHintMore", "Shift + scroll or [ and ] size the brush; right-click puts the brush down."
	)
	more.add_child(
		AuthoringChrome.help_label(
			"BiomeHint", "Pick a biome, then drag on the map. Linger to thicken it."
		)
	)
	more.move_child(more.get_child(more.get_child_count() - 1), 0)
	var field := TileField.new()
	field.name = "BiomeField"
	# No caption (the card's title says Biome) and labels that wrap between words: three columns
	# of nine tiles are three rows, so the picker, More and Advanced fit a 720p card.
	field.tiles.wrap_labels = true
	field.tiles.photo_icons = true
	field.tiles.tile_min_size = AuthoringPanel.BIOME_TILE_SIZE
	field.tiles.columns = AuthoringPanel.BIOME_COLUMNS
	for entry in by_display_name(PaletteLibrary.biomes(panel.palette_root)):
		field.tiles.add_tile(
			StringName(String(entry["id"])),
			AuthoringPanel.short_name(String(entry["name"])),
			"",
			String(entry["name"]),
			# Deferred: the drawer is built in the open's first frame, and a cold ground albedo
			# bakes on the prebake lane instead (card authbake).
			BiomeThumbnail.of(entry, AuthoringPanel.BIOME_THUMB_PX, panel.palette_root, true)
		)
	field.tiles.selection_changed.connect(
		func(id: StringName) -> void: panel.biome_selected.emit(String(id))
	)
	pane.add_child(field)
	pane.add_child(more)
	pane.add_child(panel.build_advanced("Biome"))
	panel.biome_field = field
	return pane


## Place: one foldout per palette biome (headed by its thumbnail), holding a tile per
## species big enough to place by hand. The selected biome's group starts open.
static func place(panel: AuthoringPanel, tool: ToolDescriptor) -> Control:
	var pane := _column("PlacePane", "PlaceHeader", tool)
	add_help(
		pane,
		"PlaceHint",
		"Pick one, then click the map. Drag while pressed to turn it.",
		"Over a placed one, Shift + scroll resizes it and right-click or Delete removes it."
	)
	var foldouts: Array[Foldout] = []
	for entry in by_display_name(PaletteLibrary.biomes(panel.palette_root)):
		var biome_id := String(entry["id"])
		var groups := AuthoringPanel.place_species(biome_id, panel.palette_root)
		if groups.is_empty():
			continue
		var foldout := Foldout.new()
		foldout.name = "Place_" + biome_id.validate_node_name()
		# The same short name as the Biome pane's tile, in ink: "Deciduous Forest" in both places.
		foldout.title = AuthoringPanel.short_name(String(entry["name"]))
		foldout.title_variation = &"FoldoutTitle"
		foldout.icon = BiomeThumbnail.of(entry, 28, panel.palette_root, true)
		var row := TileRow.new()
		row.name = "PlaceTiles"
		row.tile_min_size = AuthoringPanel.PLACE_TILE_SIZE
		row.columns = AuthoringPanel.PLACE_COLUMNS
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for rule in groups:
			var key := String(rule.get("key", ""))
			var kind := String(rule.get("kind", ""))
			row.add_tile(
				StringName(biome_id + "|" + key),
				AuthoringPanel.species_label(key),
				AuthoringChrome.place_icon(
					key, AuthoringPanel.PLACE_ICONS.get(kind, AuthoringPanel.PLACE_DEFAULT_ICON)
				),
				"%s (%s)" % [AuthoringPanel.species_label(key), String(entry["name"])]
			)
		row.selection_changed.connect(panel._on_place_tile.bind(row))
		foldout.add_child(row)
		foldouts.append(foldout)
		panel.place_rows[biome_id] = row
		panel._place_foldouts[biome_id] = foldout
	# The map's current biome (the Biome tool's pick: AuthoringPanel.select_biome moves its group
	# here) leads, open; the other biomes are a closed switcher under a caption.
	var others := AuthoringChrome.help_label("PlaceOthers", "Other biomes")
	panel._place_others = others
	for i in foldouts.size():
		if i == 1:
			pane.add_child(others)
		pane.add_child(foldouts[i])
	return pane


## Moves the Place group `chosen` to the lead, just above the "Other biomes" caption `others`; the
## group that led drops under the caption, closed.
static func lead_place(others: Control, chosen: Foldout) -> void:
	if others == null or others.get_parent() != chosen.get_parent():
		return
	var pane := chosen.get_parent()
	var at := others.get_index()
	var lead := pane.get_child(at - 1) as Foldout
	if lead != chosen:
		lead.expanded = false
		pane.move_child(lead, at)
		pane.move_child(chosen, at - 1)


## Sculpt: four tiles (Raise, Smooth, Flatten, Tier), Raise preselected; the gestures and
## modifiers in the hint line.
static func sculpt(panel: AuthoringPanel, tool: ToolDescriptor) -> Control:
	var pane := _column("SculptPane", "SculptHeader", tool)
	pane.add_child(panel.build_size_row("Sculpt"))
	add_help(
		pane,
		"SculptHint",
		"Pick a brush, then drag on the map; linger to build.",
		(
			"Hold Ctrl as you press to lower or cut down, Shift to smooth. Tier steps up a level"
			+ " from where you press, or extends the level whose edge you start on."
		)
	)
	pane.add_child(section_gap("SculptGap"))
	var field := TileField.new()
	field.name = "SculptField"
	field.caption = "Brush"
	field.tiles.tile_min_size = AuthoringPanel.SCULPT_TILE_SIZE
	# With the terrain core on, Terrace and Soften join (two rows of three).
	var tiles := SculptTool.tiles()
	field.tiles.columns = tiles.size() if tiles.size() <= 4 else 3
	for tile in tiles:
		field.tiles.add_tile(
			AuthoringPanel.sculpt_tile_id(int(tile.op)),
			String(tile.label),
			String(tile.icon),
			String(tile.tooltip)
		)
	field.tiles.select(AuthoringPanel.sculpt_tile_id(HeightBrush.RAISE))
	field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			var op := AuthoringPanel.sculpt_tile_op(id)
			if op >= 0:
				panel.sculpt_selected.emit(op)
	)
	pane.add_child(field)
	pane.add_child(panel.build_advanced("Sculpt"))
	panel.sculpt_field = field
	return pane


## Paint: the header, the size, the gestures, and the surface groups (filled by
## AuthoringPanel.ensure_paint_tiles()), ending in the Advanced foldout.
static func paint(panel: AuthoringPanel, tool: ToolDescriptor) -> Control:
	var pane := _column("PaintPane", "PaintHeader", tool)
	pane.add_child(panel.build_size_row("Paint"))
	add_help(
		pane,
		"PaintHint",
		"Pick a surface, then drag on the map; linger to cover it fully.",
		(
			"Hold Ctrl as you press to erase paint back to the natural ground. Paths stop at rock"
			+ " faces: climb them with a ramp. Built surfaces clear the plants under them."
		)
	)
	for group in AuthoringPanel.PAINT_GROUPS:
		var field := TileField.new()
		field.name = "Paint" + String(group.caption) + "Field"
		field.caption = String(group.caption)
		field.tiles.photo_icons = true
		field.tiles.tile_min_size = AuthoringPanel.PAINT_TILE_SIZE
		field.tiles.columns = AuthoringPanel.PAINT_COLUMNS
		field.tiles.selection_changed.connect(panel._on_paint_tile.bind(field.tiles))
		pane.add_child(field)
		panel.paint_fields[group.role] = field
	pane.add_child(panel.build_advanced("Paint"))
	return pane
