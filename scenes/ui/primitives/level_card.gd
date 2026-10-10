class_name LevelCard
extends Button

## A saved level as a card: thumbnail, name, and a caption with the token count
## and when it was last edited. Press selects (the caption strip takes the selected fill;
## the ring stays focus's), double-click activates, and the
## overflow menu in the thumbnail corner offers Set up tokens (the Level Editor, by the name
## the title gives it), Edit map (authoring mode), Rename
## (inline), Duplicate and Delete. Delete is disabled while the card is locked (the level
## being played).

signal selected(level_info: Dictionary)
signal activated(level_info: Dictionary)
signal action_requested(level_info: Dictionary, action: StringName)
signal rename_committed(level_info: Dictionary, new_name: String)

enum { ACTION_EDIT, ACTION_RENAME, ACTION_DUPLICATE, ACTION_DELETE, ACTION_EDIT_MAP }

const THUMB_ASPECT := 16.0 / 9.0
## The thumbnail's inset from the card edge. The name and caption sit inside the theme's
## CardText margin as well, 12 px in from the card's sides and bottom in all, so text never
## runs into the rounded edge.
const INSET := 4.0
const THUMB_HOVER_SCALE := Vector2(1.04, 1.04)
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## Keys the black void of older thumbnails out to the well's wash.
const THUMB_SHADER := preload("res://shaders/ui_card_thumb.gdshader")

static var _shared_thumb_material: ShaderMaterial

var level_info: Dictionary = {}
var locked: bool = false:
	set(value):
		locked = value
		if _menu:
			_menu.set_item_disabled(_menu.get_item_index(ACTION_DELETE), locked)
## False hides the overflow menu: a card in a picker (choose a map) offers no management.
var manageable: bool = true:
	set(value):
		manageable = value
		if _menu_button:
			_menu_button.visible = value
## Accept (Enter, pad A) on the card while it is not selected only selects it; Accept on the
## selected card activates it (the library, where selecting opens the detail strip).
var accept_selects_first: bool = false

var _column: VBoxContainer
var _strip: PanelContainer
var _thumb: TextureRect
var _placeholder: MapPlaceholder
var _name: Label
var _caption: Label
var _menu_button: IconButton
var _menu: PopupMenu
var _rename: LineEdit
var _tween: Tween


func _init() -> void:
	toggle_mode = true
	theme_type_variation = &"Card"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column.offset_left = INSET
	_column.offset_top = INSET
	_column.offset_right = -INSET
	_column.offset_bottom = -INSET
	_column.add_theme_constant_override("separation", 4)
	_column.minimum_size_changed.connect(_update_minimum_size_from_content)
	add_child(_column)

	# The thumbnail well (the CardThumb variation) draws the paper-inset wash and clips the
	# picture to its rounded shape, hover zoom included, so no square corner pokes out of
	# the card.
	var thumb_slot := Panel.new()
	thumb_slot.name = "ThumbSlot"
	thumb_slot.theme_type_variation = &"CardThumb"
	thumb_slot.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	thumb_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb_slot.custom_minimum_size = Vector2(0, 90)
	_column.add_child(thumb_slot)
	_thumb = TextureRect.new()
	_thumb.name = "Thumb"
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.material = _thumb_material()
	_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thumb.resized.connect(_update_thumb_pivot)
	thumb_slot.add_child(_thumb)
	# A map with no thumbnail yet paints its placeholder, a child of the picture so it zooms
	# with it on hover.
	_placeholder = MapPlaceholder.new()
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thumb.add_child(_placeholder)
	thumb_slot.resized.connect(_on_thumb_slot_resized)

	_menu_button = IconButton.new()
	_menu_button.name = "Menu"
	_menu_button.icon_name = "dots-vertical"
	_menu_button.tooltip_text = "More"
	# On a paper disc: the bare glyph vanished over a dark thumbnail.
	_menu_button.disc = true
	_menu_button.custom_minimum_size = Vector2(28, 28)
	_menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu_button.position = Vector2(-32, 4)
	_menu_button.pressed.connect(_on_menu_pressed)
	thumb_slot.add_child(_menu_button)
	_menu = PopupMenu.new()
	_menu.name = "Actions"
	_menu.add_item(TitleScreen.SET_UP_TOKENS, ACTION_EDIT)
	_menu.add_item("Edit map", ACTION_EDIT_MAP)
	_menu.add_item("Rename", ACTION_RENAME)
	_menu.add_item("Duplicate", ACTION_DUPLICATE)
	_menu.add_item("Delete", ACTION_DELETE)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)

	# The caption strip: clear at rest, the selected fill under ON_SELECTED text when the card
	# is selected. It runs to the card's bottom inset, so the fill is concentric with the card.
	_strip = PanelContainer.new()
	_strip.name = "Strip"
	_strip.theme_type_variation = &"CardStrip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_strip)
	var text_margin := MarginContainer.new()
	text_margin.name = "TextMargin"
	text_margin.theme_type_variation = &"CardText"
	text_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(text_margin)
	var text_column := VBoxContainer.new()
	text_column.name = "Text"
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_margin.add_child(text_column)

	_name = Label.new()
	_name.name = "Name"
	_name.theme_type_variation = &"Body"
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_name)
	_rename = LineEdit.new()
	_rename.name = "Rename"
	_rename.visible = false
	_rename.text_submitted.connect(_on_rename_submitted)
	_rename.focus_exited.connect(_cancel_rename)
	_rename.gui_input.connect(_on_rename_gui_input)
	text_column.add_child(_rename)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.theme_type_variation = &"Caption"
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_caption)

	pressed.connect(_on_pressed)
	toggled.connect(_show_selected)
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	_update_minimum_size_from_content()


func setup(info: Dictionary) -> void:
	level_info = info
	_name.text = String(info.get("name", "Untitled"))
	_caption.text = caption_for(info, int(Time.get_unix_time_from_system()))
	tooltip_text = _name.text
	var thumbnail: String = info.get("thumbnail", "")
	var texture: Texture2D = null
	if not thumbnail.is_empty():
		var image := Image.load_from_file(ProjectSettings.globalize_path(thumbnail))
		if image:
			texture = ImageTexture.create_from_image(image)
	# No picture yet: the map's painted placeholder, keyed by its folder so a rename keeps it.
	_thumb.texture = texture
	_placeholder.visible = texture == null
	if texture == null:
		var folder := String(info.get("folder", ""))
		_placeholder.paint(
			folder if folder != "" else _name.text, String(info.get("environment_preset", ""))
		)


## A name's initial (a portrait's letter): its first letter or digit, so "_camp" shows C,
## not "_".
static func initial_of(level_name: String) -> String:
	for i in range(level_name.length()):
		var ch := level_name.substr(i, 1)
		if ch.to_upper() != ch.to_lower() or ch.is_valid_int():
			return ch.to_upper()
	return ""


## Select or clear the card without emitting: the toggle state and its caption strip.
func set_selected(on: bool) -> void:
	set_pressed_no_signal(on)
	_show_selected(on)


## "1 token, edited 3 h ago"; "No tokens" alone when the level is empty and has
## never been saved with a time.
static func caption_for(info: Dictionary, now_unix: int) -> String:
	var count := int(info.get("token_count", 0))
	var tokens := "No tokens" if count == 0 else ("1 token" if count == 1 else "%d tokens" % count)
	var modified := int(info.get("modified_at", 0))
	if modified <= 0:
		return tokens
	return "%s, edited %s" % [tokens, relative_time(now_unix - modified, modified)]


static func relative_time(seconds_ago: int, modified_unix: int) -> String:
	if seconds_ago < 60:
		return "just now"
	if seconds_ago < 3600:
		return "%d min ago" % (seconds_ago / 60)
	if seconds_ago < 86400:
		return "%d h ago" % (seconds_ago / 3600)
	if seconds_ago < 2 * 86400:
		return "yesterday"
	if seconds_ago < 14 * 86400:
		return "%d days ago" % (seconds_ago / 86400)
	var date := Time.get_datetime_dict_from_unix_time(modified_unix)
	return "%d %s %d" % [date["day"], MONTHS[int(date["month"]) - 1], date["year"]]


func begin_rename() -> void:
	_rename.text = _name.text
	_name.visible = false
	_rename.visible = true
	_rename.grab_focus()
	_rename.select_all()


func _cancel_rename() -> void:
	if not _rename.visible:
		return
	_rename.visible = false
	_name.visible = true


## Escape falls through to a modal picker's _unhandled_input and closes the
## whole dialog mid-edit unless the rename field claims it first.
func _on_rename_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_rename()
		_rename.accept_event()


func _on_rename_submitted(new_name: String) -> void:
	_rename.visible = false
	_name.visible = true
	if new_name.strip_edges().is_empty() or new_name == _name.text:
		return
	rename_committed.emit(level_info, new_name.strip_edges())


func _on_pressed() -> void:
	selected.emit(level_info)


func _show_selected(on: bool) -> void:
	_strip.theme_type_variation = &"CardStripSelected" if on else &"CardStrip"
	_name.theme_type_variation = &"BodyOnSelected" if on else &"Body"
	_caption.theme_type_variation = &"CaptionOnSelected" if on else &"Caption"


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.double_click and mouse.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(level_info)
	elif event.is_action_pressed("ui_accept") and has_focus():
		# The signal comes before the button's own press, so button_pressed is the state the
		# card had: the press that follows selects it.
		if accept_selects_first and not button_pressed:
			return
		activated.emit(level_info)


func _on_menu_pressed() -> void:
	_menu.position = Vector2i(_menu_button.get_screen_position()) + Vector2i(0, 28)
	_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	match id:
		ACTION_EDIT:
			action_requested.emit(level_info, &"edit")
		ACTION_EDIT_MAP:
			action_requested.emit(level_info, &"edit_map")
		ACTION_RENAME:
			begin_rename()
		ACTION_DUPLICATE:
			action_requested.emit(level_info, &"duplicate")
		ACTION_DELETE:
			if not locked:
				action_requested.emit(level_info, &"delete")


## Button's own get_minimum_size() (C++) never consults a GDScript
## `_get_minimum_size()` override, so the card's content height cannot be
## reported that way. custom_minimum_size is different: Control's
## get_combined_minimum_size() takes the max of it and the button's own
## (small, icon/text-only) minimum, so driving custom_minimum_size.y directly
## from the column's content height is what actually makes the card as tall
## as its content. Only .y is touched -- .x is LevelGrid's column width
## (set via custom_minimum_size in _fit_columns()), which this must not clobber.
func _update_minimum_size_from_content() -> void:
	if _column == null:
		return
	custom_minimum_size.y = _column.get_combined_minimum_size().y + INSET * 2.0


func _on_thumb_slot_resized() -> void:
	var slot := _thumb.get_parent() as Control
	var height := slot.size.x / THUMB_ASPECT
	if not is_equal_approx(slot.custom_minimum_size.y, height):
		slot.custom_minimum_size = Vector2(0, height)
		_update_minimum_size_from_content()
	_update_thumb_pivot()


static func _thumb_material() -> ShaderMaterial:
	if _shared_thumb_material == null:
		_shared_thumb_material = ShaderMaterial.new()
		_shared_thumb_material.shader = THUMB_SHADER
	return _shared_thumb_material


func _update_thumb_pivot() -> void:
	_thumb.pivot_offset = _thumb.size * 0.5


## The thumbnail zoom is a HOVER affordance only -- pressing deliberately does not
## touch it. It used to: button_down dipped the scale back to 1.0 over ANIM_PRESS
## (0.06s) and button_up regrew it over ANIM_HOVER_SOFT_IN (0.24s), each killing the
## other's tween. A double-click lands well inside 240ms, so the slow regrow was
## interrupted twice and the thumbnail pumped instead of reading as a press. A single
## click's real feedback is the selection highlight (the selected caption strip), which is
## state rather than motion, and Host Game / Play Solo act on that selection.
func _on_hover(entered: bool) -> void:
	if _rename.visible:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	var target := THUMB_HOVER_SCALE if entered else Vector2.ONE
	var duration := Constants.ANIM_HOVER_SOFT_IN if entered else Constants.ANIM_HOVER_SOFT_OUT
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_thumb, "scale", target, duration)
