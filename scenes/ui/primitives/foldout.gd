class_name Foldout
extends VBoxContainer

## Animated collapsible section: a clickable header (chevron + caption title)
## above a body slot. The body's clip height tweens between 0 and its natural
## height. Children authored under a Foldout in a .tscn are moved into
## [member body] on ready, so scenes can declare foldout content directly.

signal expanded_changed(expanded: bool)

const CHEVRON_SIZE := 16.0

@export var title: String = "Advanced":
	set(value):
		title = value
		if _title_label:
			_title_label.text = value

@export var expanded: bool = false:
	set(value):
		if expanded == value:
			return
		expanded = value
		if is_node_ready():
			_animate_body()
			expanded_changed.emit(value)

var body: VBoxContainer

var _header: HBoxContainer
var _chevron: TextureRect
var _title_label: Label
var _clip: Control
var _tween: Tween
var _target_height: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	var authored: Array[Node] = []
	for child in get_children():
		authored.append(child)
	_build_header()
	_build_body()
	for child in authored:
		# remove_child() clears `owner` on the moved subtree, which would break
		# the host scene's %unique_name lookups for rows authored under the
		# Foldout in a .tscn. Record and restore.
		var owners := _collect_owners(child)
		remove_child(child)
		body.add_child(child)
		for node in owners:
			node.owner = owners[node]
	_apply_state_immediately()


func toggle() -> void:
	expanded = not expanded
	AudioManager.play_tick()


func _build_header() -> void:
	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_header.add_theme_constant_override("separation", 6)
	_header.gui_input.connect(_on_header_gui_input)
	add_child(_header)

	_chevron = TextureRect.new()
	_chevron.name = "Chevron"
	_chevron.texture = IconButton.load_icon("chevron-right")
	_chevron.custom_minimum_size = Vector2(CHEVRON_SIZE, CHEVRON_SIZE)
	_chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chevron.pivot_offset = Vector2(CHEVRON_SIZE, CHEVRON_SIZE) / 2.0
	_chevron.self_modulate = ThemeColors.TEXT_MUTED
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(_chevron)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = title
	_title_label.theme_type_variation = &"Caption"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title_label)


func _build_body() -> void:
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_clip)

	body = VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.theme_type_variation = &"BoxContainerSpaced"
	body.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	body.resized.connect(_on_body_resized)
	_clip.add_child(body)


func _apply_state_immediately() -> void:
	body.visible = expanded
	_clip.custom_minimum_size.y = body.get_combined_minimum_size().y if expanded else 0.0
	_chevron.rotation = PI / 2.0 if expanded else 0.0


func _animate_body() -> void:
	if expanded:
		body.visible = true
	_retarget(body.get_combined_minimum_size().y if expanded else 0.0)


## Start (or restart) the height tween towards [param height]. A body that
## wraps after its first layout reports a taller size mid-tween; retargeting
## from the clip's current height keeps the motion continuous.
func _retarget(height: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_target_height = height
	var target_rotation := PI / 2.0 if expanded else 0.0
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(true)
	_tween.tween_property(_clip, "custom_minimum_size:y", height, Constants.ANIM_FOLDOUT)
	_tween.tween_property(_chevron, "rotation", target_rotation, Constants.ANIM_FOLDOUT)
	_tween.chain().tween_callback(_on_animation_finished)


func _on_animation_finished() -> void:
	body.visible = expanded
	if expanded:
		# The body is laid out by now; never leave the clip short of it.
		_clip.custom_minimum_size.y = body.size.y


## Content that grows (a weather row appearing, a tile row wrapping on its
## first layout) must grow the clip with it: retarget a running expand tween,
## or snap when idle. Collapsed bodies are hidden and never resize.
func _on_body_resized() -> void:
	if not expanded:
		return
	if _tween and _tween.is_valid() and _tween.is_running():
		if not is_equal_approx(body.size.y, _target_height):
			_retarget(body.size.y)
		return
	_clip.custom_minimum_size.y = body.size.y


func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			toggle()
			accept_event()


static func _collect_owners(root: Node) -> Dictionary:
	var owners := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.owner:
			owners[node] = node.owner
		for child in node.get_children():
			stack.append(child)
	return owners
