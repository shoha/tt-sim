class_name RoomRows
extends RefCounted

## The rows RoomPanel lists, built fresh from RoomModel data on every refresh.
##
## A player row is a portrait well with the name's initial in Inter semibold, the name on a
## line of its own (the full width the row has), and a caption line under it in one fixed
## order in every view: the GM chip, "You", then the selected map's download state as an icon
## and a word (download_state()). Your own row ends in a compact framed button with the shirt
## icon and the word Avatar, which opens the avatar roster.
##
## A shelf map is a plain list row like a player (the ListRow button: clear at rest, the
## hover wash, the selected fill when picked): its picture, name and a caption. Every map
## picture sits in a CardThumb well, and a map with no thumbnail shows its painted placeholder
## (MapPlaceholder), never a flat box. For the GM, the selected row of a map that changed this
## session has its actions on a line under it (changes_line()).
##
## Both kinds of row hold their content ROW_INSET in from the column, a shelf row inside its
## button so the selected fill has a margin round the picture, a player row by its own margin,
## so the portraits and the map pictures share one left edge under the section headings.

const PORTRAIT := Vector2(40, 40)
const SHELF_THUMB := Vector2(64, 36)
const SHELF_ROW_HEIGHT := 52.0
## Every row's content inset from the column's sides (a shelf row's inside its button).
const ROW_INSET := 8
## The download state's icon, beside its caption word.
const STATE_ICON := Vector2(16, 16)
const HAS_IT := "Has it"
const GETS_IT := "Gets it at the table"
const GETTING_IT := "Getting it · %d%%"
const WAITING := "Waiting to get it"
## A changed map's row action beside Save into map (changes_line()).
const DISCARD := "Discard"
## Why a changed map with no level folder here has Discard alone (changes_line()).
const NOT_IN_LIBRARY := "Kept for this session; not in your library"

static var _thumb_material: ShaderMaterial


## A CardThumb well of `well_size` (x 0: fills its width) holding a map's thumbnail, or its
## painted placeholder when `texture` is null. `key` and `mood` paint the placeholder
## (MapPlaceholder.paint()). The well clips the picture to its shape.
static func map_well(well_size: Vector2, texture: Texture2D, key: String, mood: String) -> Panel:
	var well := _well(well_size)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.material = thumb_material()
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(picture)
	var placeholder := MapPlaceholder.new()
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(placeholder)
	set_map_well(well, texture, key, mood)
	return well


## Show `texture` in a map well, or the placeholder painted for `key` in `mood`.
static func set_map_well(well: Panel, texture: Texture2D, key: String, mood: String) -> void:
	(well.get_node("Picture") as TextureRect).texture = texture
	var placeholder := well.get_node("Placeholder") as MapPlaceholder
	placeholder.visible = texture == null
	if texture == null:
		placeholder.paint(key, mood)


## A player's portrait: a CardThumb well with the initial of `player_name` in Inter semibold
## (T3: Fraunces never in rows).
static func portrait(player_name: String) -> Panel:
	var well := _well(PORTRAIT)
	var letter := Label.new()
	letter.name = "Letter"
	letter.theme_type_variation = &"H3"
	letter.text = LevelCard.initial_of(player_name)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(letter)
	return well


## The level card's shader that keys an older thumbnail's black void out to the well's wash.
static func thumb_material() -> ShaderMaterial:
	if _thumb_material == null:
		_thumb_material = ShaderMaterial.new()
		_thumb_material.shader = LevelCard.THUMB_SHADER
	return _thumb_material


## One player: `player` is a RoomModel.players() entry, `selected` the selected map's key (""
## for none: no download state). Your own row carries Choose avatar, which calls
## `choose_avatar`. The row's content sits ROW_INSET in from both sides of the column, as a
## shelf row's does inside its button: the content is laid in a plain holder with those
## offsets, and the holder takes the content's height.
static func player_row(player: Dictionary, selected: String, choose_avatar: Callable) -> Control:
	var holder := Control.new()
	holder.name = "Player_%s" % str(player.id).validate_node_name()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.name = "Row"
	row.theme_type_variation = &"BoxContainerSpaced"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = PORTRAIT.y
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = ROW_INSET
	row.offset_right = -ROW_INSET
	holder.add_child(row)
	var fit := func() -> void: holder.custom_minimum_size.y = row.get_combined_minimum_size().y
	row.minimum_size_changed.connect(fit)
	var face := portrait(str(player.name))
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(face)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_label := _caption(str(player.name), &"Body")
	name_label.name = "Name"
	name_label.tooltip_text = str(player.name)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(name_label)
	# A flow, so on your own row, beside the Avatar button, the download state wraps under
	# You whole rather than lose its words to an ellipsis.
	var line := HFlowContainer.new()
	line.name = "CaptionLine"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(line)
	if player.gm:
		var chip := PanelContainer.new()
		chip.name = "GmBadge"
		chip.theme_type_variation = &"KeyChip"
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(_caption("GM", &"CaptionState", false))
		line.add_child(chip)
	if player.you:
		var you := _caption("You", &"Caption", false)
		you.name = "You"
		line.add_child(you)
	if selected != "":
		line.add_child(download_state(RoomModel.download_state(player, selected)))
	line.visible = line.get_child_count() > 0

	if player.you:
		row.add_child(_choose_avatar_button(choose_avatar))
	fit.call()
	return holder


## The selected map's download state for one player (`state`, RoomModel.download_state()),
## an icon and a word (C7: never colour alone): the lake check and "Has it"; the lake download
## arrow and "Getting it · 40%" while it comes; the soft arrow and "Waiting to get it" while it
## waits its turn, or "Gets it at the table" when this player is not fetching it. Progress is
## lake and a word, never a bar. The word never trims: the caption line wraps it whole onto a
## line of its own. show_download_state() updates it in place as the percent moves.
static func download_state(state: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.name = "Download"
	box.theme_type_variation = &"BoxContainerTight"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = STATE_ICON
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A white icon tinted by hand, read once the icon is under its paper or glass parent.
	icon.theme_changed.connect(func() -> void: _tint_state_icon(icon))
	box.add_child(icon)
	var word := _caption("", &"Caption", false)
	word.name = "Word"
	box.add_child(word)
	show_download_state(box, state)
	return box


## Show `state` (RoomModel.download_state()) on a download_state() box.
static func show_download_state(box: Control, state: Dictionary) -> void:
	var kind: StringName = state.get("state", RoomModel.TABLE)
	var icon := box.get_node("Icon") as TextureRect
	icon.texture = IconButton.load_icon("circle-check" if kind == RoomModel.HAS else "download")
	# Lake (state) for has it and getting it, the soft text role for not yet.
	var lake := kind == RoomModel.HAS or kind == RoomModel.GETTING
	icon.set_meta(&"role", ThemeColors.STATE if lake else ThemeColors.TEXT_SOFT)
	if icon.is_inside_tree():
		_tint_state_icon(icon)
	(box.get_node("Word") as Label).text = download_word(state)


## The word for a download state (RoomModel.download_state()).
static func download_word(state: Dictionary) -> String:
	match state.get("state", RoomModel.TABLE):
		RoomModel.HAS:
			return HAS_IT
		RoomModel.GETTING:
			return GETTING_IT % int(state.get("percent", 0))
		RoomModel.WAITING:
			return WAITING
	return GETS_IT


static func _tint_state_icon(icon: TextureRect) -> void:
	icon.self_modulate = ThemeColors.of(icon, icon.get_meta(&"role", ThemeColors.TEXT_SOFT))


## One shelf map: `entry` is a RoomModel.shelf() entry, `mood` its environment preset (for the
## placeholder). A toggle row; `selectable` false makes it read-only.
static func shelf_row(
	entry: Dictionary, texture: Texture2D, mood: String, caption: String, selectable: bool
) -> Button:
	var row := Button.new()
	row.name = "Map_%s" % str(entry.key).validate_node_name()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.custom_minimum_size = Vector2(0, SHELF_ROW_HEIGHT)
	row.tooltip_text = str(entry.name)
	row.focus_mode = Control.FOCUS_ALL if selectable else Control.FOCUS_NONE
	row.mouse_filter = Control.MOUSE_FILTER_STOP if selectable else Control.MOUSE_FILTER_IGNORE
	if selectable:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.theme_type_variation = &"BoxContainerSpaced"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = ROW_INSET
	inner.offset_right = -ROW_INSET
	row.add_child(inner)
	var key := str(entry.folder) if str(entry.folder) != "" else str(entry.name)
	var well := map_well(SHELF_THUMB, texture, key, mood)
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(well)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text)
	var name_label := _caption(str(entry.name), &"Body")
	name_label.name = "Name"
	text.add_child(name_label)
	var caption_label := _caption(caption, &"Caption")
	caption_label.name = "Caption"
	caption_label.visible = caption != ""
	text.add_child(caption_label)
	return row


## Show a shelf row selected (the row's selected fill, its text on that fill) or not.
static func show_shelf_selected(row: Button, on: bool) -> void:
	row.set_pressed_no_signal(on)
	var text := row.get_node("Inner/Text")
	(text.get_node("Name") as Label).theme_type_variation = &"BodyOnSelected" if on else &"Body"
	(text.get_node("Caption") as Label).theme_type_variation = (
		&"CaptionOnSelected" if on else &"Caption"
	)


## The GM's actions on the selected shelf row of a map that changed this session (`key`), under
## the row and ROW_INSET in from the column as the row's picture is: Save into map (only when
## `can_save`: a level folder here to write) calling `on_save`, and Discard (DISCARD, Discard
## changes in its tooltip) calling `on_discard`, each with its key. Quiet buttons: the confirm
## each opens carries the weight (and Discard's red). Without Save into map a caption over the
## buttons says why (NOT_IN_LIBRARY), so its absence is never a puzzle. The line wraps rather
## than clip at a large interface size.
static func changes_line(
	key: String, can_save: bool, on_save: Callable, on_discard: Callable
) -> Control:
	# As a player row's: the line laid in a plain holder with the inset as offsets, a little
	# space above it and a row inset below, and the holder takes the line's height.
	var holder := Control.new()
	holder.name = "Changes_%s" % key.validate_node_name()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.name = "Box"
	box.theme_type_variation = &"BoxContainerTight"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = ROW_INSET
	box.offset_right = -ROW_INSET
	box.offset_top = ROW_INSET * 0.5
	box.offset_bottom = -ROW_INSET
	holder.add_child(box)
	if not can_save:
		var why := _caption(NOT_IN_LIBRARY, &"Caption", false)
		why.name = "Why"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(why)
	var line := HFlowContainer.new()
	line.name = "Line"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	var fit := func() -> void:
		holder.custom_minimum_size.y = box.get_combined_minimum_size().y + ROW_INSET * 1.5
	box.minimum_size_changed.connect(fit)
	if can_save:
		var save := _row_action("SaveIntoMap", TableMover.SAVE_TEXT, "device-floppy", on_save, key)
		line.add_child(save)
	# "Discard" beside "Save into map" keeps the line to one row in the 396 column (the
	# caption above says what changed; the tooltip and the confirm say Discard changes).
	var discard := _row_action("DiscardChanges", DISCARD, "restore", on_discard, key)
	discard.tooltip_text = TableMover.DISCARD_TEXT
	discard.accessibility_name = TableMover.DISCARD_TEXT
	line.add_child(discard)
	fit.call()
	return holder


static func _row_action(
	node_name: String, text: String, icon: String, callback: Callable, key: String
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.icon = IconButton.load_icon(icon)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback.bind(key))
	return button


static func _well(well_size: Vector2) -> Panel:
	var well := Panel.new()
	well.name = "Well"
	well.theme_type_variation = &"CardThumb"
	well.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.custom_minimum_size = well_size
	return well


## Your own row's Choose avatar: compact, framed at rest so it reads as a button, the shirt
## icon with the word Avatar (an icon alone did not say what it opens), the full name in its
## tooltip and for screen readers (W7).
static func _choose_avatar_button(choose_avatar: Callable) -> Button:
	var choose := Button.new()
	choose.name = "ChooseAvatar"
	choose.text = "Avatar"
	choose.icon = IconButton.load_icon("shirt")
	choose.tooltip_text = "Choose avatar"
	choose.accessibility_name = "Choose avatar"
	choose.custom_minimum_size = Vector2(0, PORTRAIT.y)
	choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	choose.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	choose.pressed.connect(choose_avatar)
	return choose


## A label; `trim` ellipsizes it, for text that fills a column (a trimmed label asks for no
## width, so a short tag such as "GM" must not trim or it collapses to nothing).
static func _caption(text: String, variation: StringName, trim := true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if trim:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
