class_name PlayTogetherCard
extends VBoxContainer

## The title's Play together card: the one question "Play together?" (an italic eyebrow, the
## card's own question and never a category over a heading) answered on a pill where two
## watercolour washes meet at a crisp hand-painted seam with a thin paper line along it, never a
## soft bleed (user verdict 2026-10-10; shaders/ui_wash_split.gdshader on a ColorRect).
## Host is the persimmon face on the left, "Open a room": a room needs no map (room first, user
## verdict 2026-10-09), so it acts on nothing selected. Join is the lake face on the right,
## "Enter a code". Two transparent face Buttons over the wash take the mouse and carry the
## tooltips; the pill itself is the one focus stop. Each wash lightens only away from its words
## (the shader reads their rects, text_rects()), so paper words keep their contrast.
##
## Picking a face (hover, or Left and Right on the focused pill: keys, D-pad or stick) swings
## the seam SWING of the width away from it over MOTION_WASH (sine out), deepens that face to
## its hover colour, lifts its icon 2 px and lifts the card's shadow; with keyboard focus a thin
## paper ring also marks the picked face inside the card's own ring. On an end face Left or
## Right is not consumed, so focus moves on and nothing traps it. Accept (Enter, Space, pad A)
## presses the picked face: the pill squashes to PRESS_SCALE; Host floods the card with
## persimmon and then asks for a room (host_pressed); Join opens Join in place.
##
## Join in place (user verdict 2026-10-09: there is no join screen): the lake widens to the
## whole card and becomes a room-code field and a Join button, the one persimmon fill there
## (C5), and Host's wash draws into a blot at the left and dries away under a paper back disc
## with a persimmon arrow; the disc, or Esc or pad B anywhere in the card, goes back. Join (or
## Enter in the field) asks to join with the code (join_submitted). The join's progress and its
## failure show in place, on a line under the pill (show_connecting(), show_joining(),
## show_error()); going back while a join is under way drops it (join_cancelled). In Join mode
## the control with focus rings itself in paper, and the card's lake ring is gone: one ring.
##
## Under the pill is one slot (PlayTogetherSlot, set_under()): the title's Resume and the
## join's line trade places in it. With Resume showing, or in Join mode, it holds the taller of
## Resume and a three-line failure, so entering Join or a failure never moves the card or
## anything below it; at rest with no saved session it takes no height, and Join eases it open.
##
## Discipline from the theme probe: an instant state set kills every easing still running (an
## easing that lands after it undid it), LineEdit.grab_focus() does not start editing in 4.7
## (edit() follows it), and pad input is ignored while the window is not focused (a controller
## used in another game moved focus here).

## Host was pressed: open a room (after the flood).
signal host_pressed
## Join with `code`, as typed (trimmed).
signal join_submitted(code: String)
## Join mode closed while a join was under way: drop it.
signal join_cancelled
## Join in place opened (true) or closed (false).
signal join_mode_changed(open: bool)

enum Face { NONE, HOST, JOIN }

const EYEBROW := "Play together?"
const HOST_TITLE := "Host"
const HOST_CAPTION := "Open a room"
const JOIN_TITLE := "Join"
const JOIN_CAPTION := "Enter a code"
const HOST_TIP := "Open a room for your friends; maps are added there"
const JOIN_TIP := "Join a friend's room with the code they share"
const BACK_TIP := "Back to Host or Join"
const CODE_PLACEHOLDER := "Room code"
const JOIN_TEXT := "Join"
const CONNECTING := "Connecting to the room..."
const JOINING := "Connected. Joining the room..."
const NO_CODE := "Type the room code your host shared, then Join."
const HOST_ICON := "network"
const JOIN_ICON := "hash"
const BACK_ICON := "arrow-left"
const ERROR_ICON := "alert-circle"

## 336 wide, not the recommendation's 304: at 304 an 8% swing put the seam over the end of a
## 118 px text block. At 336 with a 6% swing and a 5 px wander the seam stays clear of both
## (theme probe section 2: the seam reaches 143 against Host's text end at 127, and 193
## against Join's text start at 198).
const CARD_SIZE := Vector2(336, 112)
## Each face's words sit in a fixed block anchored to its outer edge, so the seam's travel
## never reflows them; a longer caption ends in an ellipsis.
const TEXT_BLOCK := 118.0
const TEXT_PAD := 20.0
const TITLE_Y := 22.0
const CAPTION_Y := 62.0
const CAPTION_HEIGHT := 22.0
const ICON_SIZE := 20.0
const ICON_Y := 33.0
const ICON_LIFT := 2.0
const SWING := 0.06
const SEAM_AMP := 5.0
const MOTION_WASH := 0.28
const PRESS_SCALE := 0.97
const PRESS_IN := 0.07
const PRESS_OUT := 0.14
const FIELD_HEIGHT := 40.0
const DISC_SIZE := 48.0
## The back disc's edge to the code field: one 8 px step.
const FIELD_GAP := 8.0
const FIELD_LEFT := CARD_SIZE.y * 0.5 + DISC_SIZE * 0.5 + FIELD_GAP
const FIELD_RIGHT_PAD := 16.0
const JOIN_MIN_WIDTH := 64.0
## The field and the back disc fade in after the wash has started to move.
const FIELD_FADE := 0.18
const FIELD_DELAY := 0.12

## The face picked (hover or keys), NONE at rest.
var hot: Face = Face.NONE
## Join in place is open.
var joining := false
## A join is under way: the field and Join are locked until it fails or the room opens.
var busy := false
## A sheet's scrim covers the title: its own primary is the screen's one fill (C5), so Host's
## persimmon steps back to paper inset with soft ink until the sheet closes.
var stepped_back := false
## Whether the window has focus, read before acting on pad input; tests replace it.
var window_focused: Callable = _window_has_focus

var eyebrow: Label
## The pill: the one focus stop, holding the wash and everything on it.
var pill: Control
var host_face: Button
var join_face: Button
var code_edit: LineEdit
var join_button: Button
var disc_button: Button
## The slot under the pill: the join's line, or the control set_under() gave it.
var slot: PlayTogetherSlot
## The line under the pill (the slot's): the join's progress or why it failed.
var status_row: HBoxContainer
var status_label: Label
var status_icon: TextureRect

var _material: ShaderMaterial
var _shadow: Panel
var _ring: Panel
var _icons := {}
var _titles := {}
var _captions := {}
var _field_row: HBoxContainer
var _wash_tween: Tween
var _colour_tween: Tween
var _press_tween: Tween
var _field_tween: Tween


func _ready() -> void:
	theme_type_variation = &"BoxContainerTight"
	eyebrow = Label.new()
	eyebrow.name = "Eyebrow"
	eyebrow.text = EYEBROW
	eyebrow.theme_type_variation = &"Eyebrow"
	add_child(eyebrow)
	_build_pill()
	_build_slot()
	_refresh_texts()
	_apply_wash(0.0)
	_fit_text_rects()
	slot.fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and slot != null:
		_fit_text_rects()
		slot.fit()


# =============================================================================
# STATE
# =============================================================================


## Puts the card back at rest at once: seam centred, no face picked, Join closed and empty.
func reset() -> void:
	_close_join_mode()
	code_edit.text = ""
	hot = Face.NONE
	_kill(_press_tween)
	pill.offset_transform_scale = Vector2.ONE
	_material.set_shader_parameter("press", 0.0)
	_refresh_texts()
	_apply_wash(0.0)
	for word in _join_words():
		word.modulate.a = 1.0


## Picks a face (hover or keys): the seam swings away from it and it deepens.
func set_hot(face: Face) -> void:
	if joining or face == hot:
		return
	hot = face
	_refresh_texts()
	_apply_wash(_motion(MOTION_WASH))


## Host steps back from its fill while a sheet is up (`on`), and takes it back after.
func step_back(on: bool) -> void:
	if on == stepped_back:
		return
	stepped_back = on
	(_titles[Face.HOST] as Label).theme_type_variation = (
		&"WashTitleQuiet" if on else &"WashTitle"
	)
	(_captions[Face.HOST] as Label).theme_type_variation = (
		&"WashCaptionQuiet" if on else &"WashCaption"
	)
	(_icons[Face.HOST] as Control).self_modulate = ThemeColors.INK_SOFT if on else ThemeColors.PAPER
	_apply_wash(0.0)


## Puts `control` (the title's Resume) in the slot under the pill, where it trades places with
## the join's line (PlayTogetherSlot.set_under()).
func set_under(control: Control) -> void:
	slot.set_under(control)


## Presses a face as a click or Accept does.
func press(face: Face) -> void:
	if joining or face == Face.NONE:
		return
	_squash()
	if face == Face.HOST:
		hot = Face.HOST
		var flood_s := _motion(MOTION_WASH * 1.4)
		_set_colours(ThemeColors.PERSIMMON_PRESS, ThemeColors.LAKE, 0.0)
		var flood := _tween_wash(1.0, 0.0, flood_s)
		if flood == null:
			_host_flooded()
			return
		# The pigment holds its press depth through the press, then eases back toward the
		# bloom's lighter step as it floods; Join's words fade as the flood passes over them.
		_colour_tween = create_tween()
		_colour_tween.tween_property(
			_material, "shader_parameter/warm", ThemeColors.PERSIMMON_HOVER, flood_s - PRESS_IN
		).set_delay(PRESS_IN)
		for word in _join_words():
			flood.tween_property(word, "modulate:a", 0.0, flood_s * 0.55).set_delay(flood_s * 0.15)
		flood.finished.connect(_host_flooded)
	else:
		open_join()


## The flood has filled the card: ask for the room, and let the wash and Join's words settle
## back under the "Opening a room..." wait, so a failed or cancelled hosting finds the card at
## rest.
func _host_flooded() -> void:
	host_pressed.emit()
	if not is_inside_tree():
		return
	_apply_wash(_motion(MOTION_WASH))
	for word in _join_words():
		if _wash_tween != null and _wash_tween.is_valid():
			_wash_tween.tween_property(word, "modulate:a", 1.0, MOTION_WASH)
		else:
			word.modulate.a = 1.0


## Join's words on its face: its icon, title and caption.
func _join_words() -> Array[Control]:
	return [_icons[Face.JOIN], _titles[Face.JOIN], _captions[Face.JOIN]]


## Join in place: the lake takes the card, Host's wash dries away under the back disc, the
## code field takes focus and starts editing.
func open_join() -> void:
	var was_open := joining
	var duration := _motion(MOTION_WASH)
	joining = true
	hot = Face.JOIN
	# The slot opens before Resume steps aside, so it never drops to nothing in between.
	slot.set_open(true, duration)
	if not was_open:
		join_mode_changed.emit(true)
	_refresh_texts()
	_set_colours(ThemeColors.PERSIMMON, ThemeColors.LAKE, duration)
	_tween_wash(0.25, 1.0, duration)
	_field_row.visible = true
	disc_button.visible = true
	_kill(_field_tween)
	var shown := 0.0 if duration > 0.0 else 1.0
	_field_row.modulate.a = shown
	disc_button.modulate.a = shown
	if duration > 0.0:
		_field_tween = create_tween().set_parallel(true)
		for faded: Control in [_field_row, disc_button]:
			_field_tween.tween_property(faded, "modulate:a", 1.0, FIELD_FADE).set_delay(FIELD_DELAY)
	code_edit.grab_focus()
	# Focus from code does not start editing in 4.7; without edit() typing goes nowhere.
	code_edit.edit()
	_refresh_ring()


## Back from Join in place to the two faces, Join still picked and the pill focused. A join
## under way is dropped (join_cancelled).
func close_join() -> void:
	if not joining:
		return
	var was_busy := busy
	_close_join_mode(_motion(MOTION_WASH))
	hot = Face.JOIN
	_refresh_texts()
	_apply_wash(_motion(MOTION_WASH))
	pill.grab_focus()
	if was_busy:
		join_cancelled.emit()


## The join is connecting: the field and Join lock, and the line under the pill says so.
func show_connecting() -> void:
	_set_busy(true)
	_show_status(CONNECTING, false)


## Connected, waiting for the host to place this player in the room or at the table.
func show_joining() -> void:
	_set_busy(true)
	_show_status(JOINING, false)


## The join failed with `message` (W3: what failed and how to recover): Join mode stays open
## with the field focused and the message under the pill. `code_wrong` selects the code to
## correct (no room has it); a failure the code did not cause (the versions differ, the room
## did not answer) leaves it as typed, the caret at its end.
func show_error(message: String, code_wrong := true) -> void:
	_set_busy(false)
	if not joining:
		open_join()
	_show_status(message, true)
	code_edit.grab_focus()
	code_edit.edit()
	if code_wrong:
		code_edit.select_all()
	else:
		code_edit.deselect()
		code_edit.caret_column = code_edit.text.length()


## Submits the code in the field: an empty one says what to type instead.
func submit() -> void:
	if busy:
		return
	var code := code_edit.text.strip_edges()
	if code.is_empty():
		_show_status(NO_CODE, true)
		code_edit.grab_focus()
		code_edit.edit()
		return
	join_submitted.emit(code)


## The seam's share of the width and the disc's growth now (for tests and probes).
func wash() -> Dictionary:
	return {
		"split": float(_material.get_shader_parameter("split")),
		"disc": float(_material.get_shader_parameter("disc")),
		"warm": _material.get_shader_parameter("warm"),
		"cool": _material.get_shader_parameter("cool"),
		"focus": float(_material.get_shader_parameter("focus")),
		"focus_side": float(_material.get_shader_parameter("focus_side")),
	}


## The rects (in the pill's own pixels) the shader never lightens: each face's words and icon,
## Face.HOST and Face.JOIN to a Rect2.
func text_rects() -> Dictionary:
	var rects := {}
	for face: Face in [Face.HOST, Face.JOIN]:
		var key := "text_warm" if face == Face.HOST else "text_cool"
		var r: Vector4 = _material.get_shader_parameter(key)
		rects[face] = Rect2(r.x, r.y, r.z - r.x, r.w - r.y)
	return rects


## The words' own extent on a face (icon, title and caption as drawn, not their blocks), in
## the pill's pixels.
func words_rect(face: Face) -> Rect2:
	var icon := _icons[face] as Control
	var rect := Rect2(icon.position.x, ICON_Y - ICON_LIFT, ICON_SIZE, ICON_SIZE + ICON_LIFT)
	for label: Label in [_titles[face], _captions[face]]:
		var width := minf(_text_width(label), label.size.x)
		var x := label.position.x
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			x += label.size.x - width
		rect = rect.merge(Rect2(x, label.position.y, width, label.size.y))
	return rect


## Whether the card's own ring shows (the pill has focus, Join closed).
func ring_shown() -> bool:
	return _ring.visible


## The wash colour under `control` when it is a face's words or icon (the colour its words are
## read against); transparent for anything else, whose ground is its own or the sheet's. The
## shader keeps each wash at or below this colour under its words.
func wash_under(control: Control) -> Color:
	var colours := wash()
	for node: Control in [_titles[Face.HOST], _captions[Face.HOST], _icons[Face.HOST]]:
		if node == control:
			return colours.warm
	for node: Control in [_titles[Face.JOIN], _captions[Face.JOIN], _icons[Face.JOIN]]:
		if node == control:
			return colours.cool
	return Color.TRANSPARENT


# =============================================================================
# INPUT
# =============================================================================


func _on_pill_input(event: InputEvent) -> void:
	if _is_pad(event) and not window_focused.call():
		pill.accept_event()
		return
	if joining:
		if event.is_action_pressed("ui_cancel"):
			close_join()
			pill.accept_event()
		return
	if event.is_action_pressed("ui_left") and hot != Face.HOST:
		set_hot(Face.HOST)
		pill.accept_event()
	elif event.is_action_pressed("ui_right") and hot != Face.JOIN:
		set_hot(Face.JOIN)
		pill.accept_event()
	elif event.is_action_pressed("ui_accept") and hot != Face.NONE:
		press(hot)
		pill.accept_event()


## Esc or pad B on the field, Join or the disc goes back.
func _on_inner_input(event: InputEvent, control: Control) -> void:
	if _is_pad(event) and not window_focused.call():
		control.accept_event()
		return
	if event.is_action_pressed("ui_cancel"):
		close_join()
		control.accept_event()


static func _is_pad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _window_has_focus() -> bool:
	return is_inside_tree() and get_window().has_focus()


func _on_pill_focus_entered() -> void:
	if hot == Face.NONE and not joining:
		set_hot(Face.HOST)
	_refresh_ring()


func _on_pill_focus_exited() -> void:
	if not joining and not _mouse_over_face():
		hot = Face.NONE
		_refresh_texts()
		_apply_wash(_motion(MOTION_WASH))
	_refresh_ring()


func _on_face_mouse_exited() -> void:
	if not pill.has_focus() and not _mouse_over_face():
		hot = Face.NONE
		_refresh_texts()
		_apply_wash(_motion(MOTION_WASH))


func _mouse_over_face() -> bool:
	return host_face.is_hovered() or join_face.is_hovered()


func _on_code_changed(_text: String) -> void:
	if not busy:
		slot.hide_status()


# =============================================================================
# BUILDING
# =============================================================================


func _build_pill() -> void:
	pill = Control.new()
	pill.name = "Pill"
	pill.custom_minimum_size = CARD_SIZE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.focus_mode = Control.FOCUS_ALL
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	pill.offset_transform_enabled = true
	pill.accessibility_name = EYEBROW
	add_child(pill)
	_shadow = _panel("Shadow", &"WashShadow")
	var wash_rect := ColorRect.new()
	wash_rect.name = "Wash"
	wash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/ui_wash_split.gdshader")
	_material.set_shader_parameter("rect_size", CARD_SIZE)
	_material.set_shader_parameter("seam_amp", SEAM_AMP)
	_material.set_shader_parameter("paper", ThemeColors.PAPER)
	_material.set_shader_parameter("drift", 0.0 if UiMotion.reduced() else 1.0)
	_material.set_shader_parameter("focus", 0.0)
	wash_rect.material = _material
	pill.add_child(wash_rect)
	host_face = _build_face(Face.HOST)
	join_face = _build_face(Face.JOIN)
	_build_join_field()
	_ring = _panel("Ring", &"WashRing")
	_ring.visible = false
	pill.gui_input.connect(_on_pill_input)
	pill.focus_entered.connect(_on_pill_focus_entered)
	pill.focus_exited.connect(_on_pill_focus_exited)


## A full-size Panel on the pill in theme variation `variation` (the shadow, the ring).
func _panel(node_name: String, variation: StringName) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.theme_type_variation = variation
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pill.add_child(panel)
	return panel


func _build_face(face: Face) -> Button:
	var left := face == Face.HOST
	var button := Button.new()
	button.name = "HostFace" if left else "JoinFace"
	button.theme_type_variation = &"WashFace"
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.position = Vector2(0.0 if left else CARD_SIZE.x * 0.5, 0.0)
	button.size = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	button.tooltip_text = HOST_TIP if left else JOIN_TIP
	button.accessibility_name = HOST_CAPTION if left else JOIN_CAPTION
	button.mouse_entered.connect(set_hot.bind(face))
	button.mouse_exited.connect(_on_face_mouse_exited)
	button.pressed.connect(press.bind(face))
	pill.add_child(button)

	var block_x := TEXT_PAD if left else CARD_SIZE.x - TEXT_PAD - TEXT_BLOCK
	var icon := TextureRect.new()
	icon.name = "HostIcon" if left else "JoinIcon"
	icon.texture = IconButton.load_icon(HOST_ICON if left else JOIN_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2.ONE * ICON_SIZE
	icon.position = Vector2(block_x if left else block_x + TEXT_BLOCK - ICON_SIZE, ICON_Y)
	icon.self_modulate = ThemeColors.PAPER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(icon)
	_icons[face] = icon

	var title := _label(HOST_TITLE if left else JOIN_TITLE, &"WashTitle", left)
	title.name = "HostTitle" if left else "JoinTitle"
	title.position = Vector2(block_x + (ICON_SIZE + 8.0 if left else 0.0), TITLE_Y)
	title.size = Vector2(TEXT_BLOCK - ICON_SIZE - 8.0, 36.0)
	_titles[face] = title

	var caption := _label(HOST_CAPTION if left else JOIN_CAPTION, &"WashCaption", left)
	caption.name = "HostCaption" if left else "JoinCaption"
	caption.position = Vector2(block_x, CAPTION_Y)
	caption.size = Vector2(TEXT_BLOCK, CAPTION_HEIGHT)
	caption.clip_text = true
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_captions[face] = caption
	return button


func _label(text: String, variation: StringName, left: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(label)
	return label


func _build_join_field() -> void:
	_field_row = HBoxContainer.new()
	_field_row.name = "JoinField"
	_field_row.theme_type_variation = &"BoxContainerSpaced"
	# From one step past the disc to 16 px short of the right end: a 13-character code fits.
	_field_row.position = Vector2(FIELD_LEFT, (CARD_SIZE.y - FIELD_HEIGHT) * 0.5)
	_field_row.size = Vector2(CARD_SIZE.x - FIELD_LEFT - FIELD_RIGHT_PAD, FIELD_HEIGHT)
	_field_row.visible = false
	pill.add_child(_field_row)

	code_edit = LineEdit.new()
	code_edit.name = "RoomCode"
	code_edit.theme_type_variation = &"WashField"
	code_edit.placeholder_text = CODE_PLACEHOLDER
	code_edit.accessibility_name = CODE_PLACEHOLDER
	code_edit.max_length = 16
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.custom_minimum_size.y = FIELD_HEIGHT
	code_edit.text_submitted.connect(func(_text: String) -> void: submit())
	code_edit.text_changed.connect(_on_code_changed)
	_field_row.add_child(code_edit)

	join_button = Button.new()
	join_button.name = "JoinButton"
	join_button.text = JOIN_TEXT
	join_button.theme_type_variation = &"WashJoin"
	join_button.custom_minimum_size = Vector2(JOIN_MIN_WIDTH, FIELD_HEIGHT)
	join_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	join_button.pressed.connect(submit)
	_field_row.add_child(join_button)

	disc_button = Button.new()
	disc_button.name = "HostDisc"
	disc_button.theme_type_variation = &"WashDisc"
	disc_button.icon = IconButton.load_icon(BACK_ICON)
	disc_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disc_button.tooltip_text = BACK_TIP
	disc_button.accessibility_name = BACK_TIP
	disc_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	disc_button.visible = false
	disc_button.pressed.connect(close_join)
	# Sized once in the tree: sized before, the default theme's wider minimum (its icon
	# unbounded) stuck, and the disc stood 52 wide.
	pill.add_child(disc_button)
	var middle := CARD_SIZE.y * 0.5
	disc_button.position = Vector2.ONE * (middle - DISC_SIZE * 0.5)
	disc_button.size = Vector2.ONE * DISC_SIZE

	for inner: Control in [code_edit, join_button, disc_button]:
		inner.gui_input.connect(_on_inner_input.bind(inner))
	code_edit.focus_next = code_edit.get_path_to(join_button)
	join_button.focus_next = join_button.get_path_to(disc_button)
	disc_button.focus_next = disc_button.get_path_to(code_edit)
	code_edit.focus_previous = code_edit.get_path_to(disc_button)
	join_button.focus_previous = join_button.get_path_to(code_edit)
	disc_button.focus_previous = disc_button.get_path_to(join_button)


## The slot under the pill and the join's line in it.
func _build_slot() -> void:
	slot = PlayTogetherSlot.new()
	slot.build(CARD_SIZE.x, IconButton.load_icon(ERROR_ICON))
	add_child(slot)
	status_row = slot.status_row
	status_label = slot.status_label
	status_icon = slot.status_icon


## Tell the shader where each face's words are, so it never lightens a wash under them.
func _fit_text_rects() -> void:
	for face: Face in [Face.HOST, Face.JOIN]:
		var rect := words_rect(face)
		var key := "text_warm" if face == Face.HOST else "text_cool"
		var corners := Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y)
		_material.set_shader_parameter(key, corners)


static func _text_width(label: Label) -> float:
	var font := label.get_theme_font(&"font")
	if font == null:
		return label.size.x
	var font_size := label.get_theme_font_size(&"font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


# =============================================================================
# SHOWING
# =============================================================================


## The faces' words, the picked face's icon lift, and Join mode's field, disc and words.
func _refresh_texts() -> void:
	for face: Face in [Face.HOST, Face.JOIN]:
		var shown := not joining
		(_titles[face] as Control).visible = shown
		(_captions[face] as Control).visible = shown
		(_icons[face] as Control).visible = shown
		(_icons[face] as Control).position.y = ICON_Y - (ICON_LIFT if face == hot else 0.0)
	host_face.visible = not joining
	join_face.visible = not joining
	_shadow.theme_type_variation = &"WashShadowLifted" if hot != Face.NONE else &"WashShadow"
	_refresh_ring()


## The card's ring with the pill focused (Join closed), and inside it the soft ring on the
## picked face.
func _refresh_ring() -> void:
	if _ring == null:
		return
	_ring.visible = pill.has_focus() and not joining
	var marked := _ring.visible and hot != Face.NONE
	_material.set_shader_parameter("focus", 1.0 if marked else 0.0)
	_material.set_shader_parameter("focus_side", -1.0 if hot == Face.HOST else 1.0)


## The line under the pill: `text`, as an error (the alert icon, body ink) or as progress (a
## soft caption).
func _show_status(text: String, error: bool) -> void:
	slot.show_status(text, error, ThemeColors.of(status_icon, ThemeColors.DANGER))


func _set_busy(on: bool) -> void:
	busy = on
	code_edit.editable = not on
	join_button.disabled = on


## Join mode's controls go; the slot settles to what rest needs over `duration`.
func _close_join_mode(duration := 0.0) -> void:
	var was_open := joining
	joining = false
	_set_busy(false)
	_kill(_field_tween)
	_field_row.visible = false
	disc_button.visible = false
	slot.hide_status()
	if was_open:
		join_mode_changed.emit(false)
	slot.set_open(false, duration)


## Seam and colours for the current pick, eased over `duration` (0: at once).
func _apply_wash(duration: float) -> void:
	var split := 0.5
	if hot == Face.HOST:
		split = 0.5 + SWING
	elif hot == Face.JOIN:
		split = 0.5 - SWING
	var warm := ThemeColors.PERSIMMON_HOVER if hot == Face.HOST else ThemeColors.PERSIMMON
	if stepped_back:
		warm = ThemeColors.PAPER_INSET
	var cool := ThemeColors.LAKE_HOVER if hot == Face.JOIN else ThemeColors.LAKE
	_set_colours(warm, cool, duration)
	if duration <= 0.0:
		# An easing still running would land after this instant set.
		_kill(_wash_tween)
		_material.set_shader_parameter("split", split)
		_material.set_shader_parameter("disc", 0.0)
		_material.set_shader_parameter("press", 0.0)
	else:
		_tween_wash(split, 0.0, duration)


## Eases the seam to `split` and the disc to `disc`; null (set at once) when `duration` is 0.
func _tween_wash(split: float, disc: float, duration: float) -> Tween:
	_kill(_wash_tween)
	if duration <= 0.0:
		_material.set_shader_parameter("split", split)
		_material.set_shader_parameter("disc", disc)
		return null
	_wash_tween = create_tween().set_parallel(true)
	_wash_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wash_tween.tween_property(_material, "shader_parameter/split", split, duration)
	_wash_tween.tween_property(_material, "shader_parameter/disc", disc, duration)
	return _wash_tween


## Sets or eases the two wash colours. A newer call kills an easing still running, which
## otherwise lands after an instant set.
func _set_colours(warm: Color, cool: Color, duration: float) -> void:
	_kill(_colour_tween)
	if duration <= 0.0:
		_material.set_shader_parameter("warm", warm)
		_material.set_shader_parameter("cool", cool)
		return
	_colour_tween = create_tween().set_parallel(true)
	_colour_tween.tween_property(_material, "shader_parameter/warm", warm, duration)
	_colour_tween.tween_property(_material, "shader_parameter/cool", cool, duration)


## The press: the pill squashes and the pigment deepens, then both come back.
func _squash() -> void:
	_kill(_press_tween)
	if UiMotion.reduced():
		return
	# On offset_transform_scale, which the column never resets or relays out for.
	_press_tween = create_tween()
	var squash := Vector2.ONE * PRESS_SCALE
	_press_tween.tween_property(pill, "offset_transform_scale", squash, PRESS_IN)
	_press_tween.parallel().tween_property(_material, "shader_parameter/press", 1.0, PRESS_IN)
	_press_tween.tween_property(pill, "offset_transform_scale", Vector2.ONE, PRESS_OUT)
	_press_tween.parallel().tween_property(_material, "shader_parameter/press", 0.0, PRESS_OUT)


## The easings under way (the seam, the colours, the press, the field's fade), for a probe that
## holds a transition part way for a filmstrip.
func easings() -> Array[Tween]:
	var running: Array[Tween] = []
	for tween: Tween in [_wash_tween, _colour_tween, _press_tween, _field_tween, slot.easing()]:
		if tween != null and tween.is_valid():
			running.append(tween)
	return running


## `duration`, or 0 under Reduce motion (the seam moves at once).
static func _motion(duration: float) -> float:
	return 0.0 if UiMotion.reduced() else duration


static func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
