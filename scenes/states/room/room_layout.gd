class_name RoomLayout
extends RefCounted

## Builds RoomPanel's controls, in its two forms, and hands them to the panel's fields; the
## panel fills and shows them (RoomPanel "Showing").
##
## The room, full screen: the heading top left with the room code, Copy and Invite top right;
## below, the side sheet (players, then the shelf with Add a map, then Leave or End session)
## and the stage in the centre (the selected map large, its name, its readiness and the one
## action). The side sheet ends at its content; a shelf too long for the screen scrolls inside
## a full-height sheet (RoomPanel._fit_side()). No word stands straight on the painted
## backdrop: the heading and the code row each sit on a paper plaque that ends at them, and
## the map's name and readiness on a plaque as wide as its picture, like a caption plate.
##
## The drawer, over a table: the heading with the full width for "On the table: ...", the code
## row on its own line under it, then one column (players and shelf) and directly under the
## shelf its action, Move the table to the selected map (or a caption saying what moves it),
## then the foot. There is no second picture of the selected map: its shelf row already shows
## the picture, the name and the state. The action follows the content and pins to the foot
## only when the column runs past the drawer, which then scrolls (RoomPanel._fit_drawer()).
##
## The Shelf heading has more space above it than below (S4): a gap the height of one more
## separation sits between the players and the shelf.

## Copy: a compact, framed icon button (S6 controls 40).
const COMPACT := Vector2(40, 40)
## The width the room's action takes at least, so Set out reads as the screen's one fill.
const ACTION_MIN_WIDTH := 280.0
const ACTION_HEIGHT := 44.0


## Build `panel`'s controls into it, as a drawer when `panel.in_drawer`.
static func build(panel: RoomPanel) -> void:
	var layout := _vbox("Layout", &"BoxContainerSpaced")
	panel.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if panel.in_drawer:
		_build_drawer(panel, layout)
	else:
		_build_room(panel, layout)


static func _build_drawer(panel: RoomPanel, layout: VBoxContainer) -> void:
	# The code row has its own line, so the caption ("On the table: ...") gets the full width.
	layout.add_child(_build_heading(panel))
	layout.add_child(_build_code_row(panel))
	# The column scrolls only when it runs past the drawer (RoomPanel._fit_drawer()); until
	# then it is as tall as its content and the action sits right under the shelf.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	panel.column_scroll = scroll
	var column := _vbox("Column", &"BoxContainerSpaced")
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(_build_players(panel))
	column.add_child(_spacer(Vector2.ZERO))
	column.add_child(_build_shelf(panel))
	layout.add_child(_build_stage(panel))
	# What is left of the drawer's height, between the action and the foot, while the column
	# fits; hidden when it scrolls, so the action pins to the foot.
	panel.drawer_rest = _spacer(Vector2.ZERO)
	panel.drawer_rest.name = "Rest"
	panel.drawer_rest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(panel.drawer_rest)
	layout.add_child(_build_footer(panel))


static func _build_room(panel: RoomPanel, layout: VBoxContainer) -> void:
	layout.offset_left = RoomPanel.EDGE
	layout.offset_top = RoomPanel.EDGE
	layout.offset_right = -RoomPanel.EDGE
	layout.offset_bottom = -RoomPanel.EDGE
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(top)
	# The heading and the code row stand on the painting, each on its own plaque that ends at
	# its words; the heading's words take their whole width there, so nothing ellipsizes.
	var heading := _build_heading(panel)
	for label: Label in [panel.title_label, panel.caption_label]:
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var heading_plaque := _plaque("HeadingPlaque", heading)
	heading_plaque.size_flags_horizontal = Control.SIZE_EXPAND
	heading_plaque.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(heading_plaque)
	var code_plaque := _plaque("CodePlaque", _build_code_row(panel))
	code_plaque.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(code_plaque)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(body)
	panel.body = body
	var side := PanelContainer.new()
	side.name = "Side"
	side.custom_minimum_size.x = RoomPanel.SIDE_WIDTH
	side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(side)
	panel.side = side
	var side_box := _vbox("SideBox", &"BoxContainerSpaced")
	side.add_child(side_box)
	side_box.add_child(_build_players(panel))
	side_box.add_child(_spacer(Vector2.ZERO))
	var shelf := _build_shelf(panel)
	shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_box.add_child(shelf)
	side_box.add_child(_build_footer(panel))
	body.add_child(_spacer(Vector2(RoomPanel.GAP, 0)))
	var stage_box := _build_stage(panel)
	stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(stage_box)


static func _build_heading(panel: RoomPanel) -> VBoxContainer:
	var box := _vbox("Heading", &"")
	panel.title_label = Label.new()
	panel.title_label.name = "Title"
	panel.title_label.theme_type_variation = &"Heading" if panel.in_drawer else &"Title"
	panel.title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(panel.title_label)
	panel.caption_label = Label.new()
	panel.caption_label.name = "Caption"
	panel.caption_label.theme_type_variation = &"Caption"
	panel.caption_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(panel.caption_label)
	return box


## The room code in its chip, Copy (a compact framed icon button, named in its tooltip) and
## Invite (a quiet button with its word).
static func _build_code_row(panel: RoomPanel) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CodeRow"
	row.theme_type_variation = &"BoxContainerSpaced"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if not panel.in_drawer:
		var caption := Label.new()
		caption.text = "Room code"
		caption.theme_type_variation = &"Caption"
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(caption)
	var chip := PanelContainer.new()
	chip.name = "CodeChip"
	chip.theme_type_variation = &"CodeChip"
	chip.tooltip_text = "Room code"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	panel.code_label = Label.new()
	panel.code_label.name = "Code"
	panel.code_label.theme_type_variation = &"Code"
	chip.add_child(panel.code_label)
	panel.set_code("")
	panel.copy_button = _button("Copy", "copy", "")
	panel.copy_button.tooltip_text = "Copy code"
	panel.copy_button.accessibility_name = "Copy code"
	panel.copy_button.custom_minimum_size = COMPACT
	panel.copy_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(panel.copy_button)
	panel.invite_button = _button("Invite", "share", "Invite")
	panel.invite_button.tooltip_text = "Invite friends through Steam"
	row.add_child(panel.invite_button)
	return row


static func _build_players(panel: RoomPanel) -> VBoxContainer:
	var box := _vbox("Players", &"BoxContainerSpaced")
	box.add_child(_section_label("Players"))
	panel.player_rows = _vbox("PlayerRows", &"BoxContainerSpaced")
	box.add_child(panel.player_rows)
	return box


static func _build_shelf(panel: RoomPanel) -> VBoxContainer:
	var box := _vbox("Shelf", &"BoxContainerSpaced")
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var label := _section_label("Shelf")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	panel.add_button = _button("AddMap", "plus", "Add a map")
	head.add_child(panel.add_button)
	panel.shelf_rows = _vbox("ShelfRows", &"")
	panel.shelf_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if panel.in_drawer:
		box.add_child(panel.shelf_rows)
		return box
	panel.shelf_scroll = ScrollContainer.new()
	panel.shelf_scroll.name = "ShelfScroll"
	panel.shelf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.shelf_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.shelf_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panel.shelf_scroll)
	panel.shelf_scroll.add_child(panel.shelf_rows)
	return box


## The selected map and its action. The room shows it large in the centre (with no map
## selected the picture is the painted placeholder under what goes there). The drawer has only
## the action, full width and named for the map (it ellipsizes, its tooltip the whole), or in
## its place a caption saying what moves the table (RoomModel.drawer_hint()).
static func _build_stage(panel: RoomPanel) -> VBoxContainer:
	var stage := _vbox("Stage", &"BoxContainerSpaced")
	panel.stage = stage
	panel.action_button = Button.new()
	panel.action_button.name = "Action"
	if panel.in_drawer:
		panel.action_button.custom_minimum_size = Vector2(0, ACTION_HEIGHT)
		panel.action_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		panel.hint_label = Label.new()
		panel.hint_label.name = "Hint"
		panel.hint_label.theme_type_variation = &"Caption"
		panel.hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stage.add_child(panel.hint_label)
		stage.add_child(panel.action_button)
		return stage
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.preview = RoomRows.map_well(Vector2.ZERO, null, "", "")
	panel.preview.name = "Preview"
	panel.preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(panel.preview)
	# The name and readiness on a plaque as wide as the picture: its caption plate.
	var words := _vbox("Words", &"BoxContainerTight")
	var plate := _plaque("NamePlaque", words)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(plate)
	var preview := panel.preview
	preview.minimum_size_changed.connect(
		func() -> void: plate.custom_minimum_size.x = preview.custom_minimum_size.x
	)
	panel.map_name_label = Label.new()
	panel.map_name_label.name = "MapName"
	panel.map_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(panel.map_name_label)
	panel.readiness_label = Label.new()
	panel.readiness_label.name = "Readiness"
	panel.readiness_label.theme_type_variation = &"Caption"
	panel.readiness_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.readiness_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(panel.readiness_label)
	panel.action_button.custom_minimum_size = Vector2(ACTION_MIN_WIDTH, ACTION_HEIGHT)
	panel.action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.add_child(panel.action_button)
	return stage


static func _build_footer(panel: RoomPanel) -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.leave_button = _button("Leave", "logout", "")
	footer.add_child(panel.leave_button)
	return footer


## A quiet button (the default Button: framed at rest) with an icon and `text`.
static func _button(node_name: String, icon: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.icon = IconButton.load_icon(icon)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


## `content` on a plaque: the few words that stand on the room's painted backdrop get paper of
## their own (the Plaque variation), crisp, so they read in every mood.
static func _plaque(node_name: String, content: Control) -> PanelContainer:
	var plaque := PanelContainer.new()
	plaque.name = node_name
	plaque.theme_type_variation = &"Plaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(content)
	return plaque


static func _vbox(node_name: String, variation: StringName) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.theme_type_variation = variation
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionHeader"
	return label


static func _spacer(min_size: Vector2) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = min_size
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
