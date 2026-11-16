class_name AuthoringPanes
extends RefCounted

## The panes AuthoringPanel builds itself for the tools that predate ToolRegistry (Biome, Place,
## Sculpt, Paint), split out of the panel to keep it under the file-size cap (card ui-authoring3).
## Each builder takes the panel, sets the panel's field for its tiles (biome_field, place_rows,
## sculpt_field, paint_fields) and wires the tiles to the panel's signals. Every pane opens with
## its header, then the picker and the size row (the basics, above the fold of a 720p card), and
## keeps the gestures behind More and the strength behind Advanced.


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


## Biome: the size row, the gesture behind More, the nine biome tiles and the Advanced foldout.
static func biome(panel: AuthoringPanel, tool: ToolDescriptor) -> Control:
	var pane := _column("BiomePane", "BiomeHeader", tool)
	# The picker and the size come first; the gesture sits behind More (the nine biomes are five
	# rows, and the basics must fit a 720p card without scrolling).
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
	pane.add_child(more)
	var field := TileField.new()
	field.name = "BiomeField"
	field.caption = "Biomes"
	field.tiles.photo_icons = true
	field.tiles.tile_min_size = AuthoringPanel.BIOME_TILE_SIZE
	field.tiles.columns = AuthoringPanel.BIOME_COLUMNS
	for entry in PaletteLibrary.biomes(panel.palette_root):
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
	for entry in PaletteLibrary.biomes(panel.palette_root):
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
		pane.add_child(foldout)
		panel.place_rows[biome_id] = row
		panel._place_foldouts[biome_id] = foldout
	return pane


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
	field.tiles.columns = AuthoringPanel.SCULPT_TILES.size()
	for tile in AuthoringPanel.SCULPT_TILES:
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
