extends Control
class_name DrawerContainer

## Reusable slide-in/slide-out drawer panel with a visible tab handle.
##
## The drawer slides from a screen edge and includes a small tab button that
## remains visible when the drawer is closed, allowing the user to re-open it.
## On first load the drawer is completely hidden; call [method reveal] (or set
## [member start_revealed] to [code]true[/code]) to slide the tab into view.
##
## Subclass this and override [method _on_ready], [method _on_opened], and
## [method _on_closed] to customise behaviour. Add content to
## [member content_container].
##
## The root Control should be anchored full-rect (preset 15) inside its parent.
## The panel and tab are animated independently so neither fights the anchor
## layout system.

# -- Configuration ----------------------------------------------------------

enum DrawerEdge { LEFT, RIGHT }

@export var edge: DrawerEdge = DrawerEdge.LEFT
## Width of the sliding content panel.
@export var drawer_width: float = 220.0
## Width of the tab handle button.
@export var tab_width: float = 36.0
## Duration of the slide animation.
@export var slide_duration: float = 0.25
## Whether the drawer starts open.
@export var start_open: bool = false
## Whether to play open/close sounds.
@export var play_sounds: bool = true
## Vertical offset from the top of the screen for the tab handle.
@export var tab_top_margin: float = 12.0
## Whether the drawer tab is visible on ready. When false (default) the
## drawer is completely off-screen until [method reveal] is called.
@export var start_revealed: bool = false

# -- Public state ------------------------------------------------------------

## Whether the drawer is currently open (panel visible).
var is_open: bool = false

## Whether the tab handle is on-screen (revealed). The drawer starts fully
## hidden and must be revealed before the tab becomes visible.
var is_revealed: bool = false

## The container where subclasses should add their content.
var content_container: VBoxContainer

# -- Tab customisation -------------------------------------------------------

## Text shown on the tab handle. Set in [method _on_ready] or at any time.
var tab_text: String = "":
	set(value):
		tab_text = value
		if _tab_label:
			_tab_label.text = value

# -- Internals --------------------------------------------------------------

var _panel: PanelContainer  ## The sliding content panel
var _tab_button: Button  ## The clickable tab handle
var _tab_label: Label
var _slide_tween: Tween
var _is_animating: bool = false

# -- Colours -----------------------------------------------------------------
# Surface colours from the dark theme, used for programmatic styling.

const _PANEL_COLOR := Color("#2c1f2b")  # color_surface1 — panel background
const _TAB_COLOR_NORMAL := Color("#2c1f2b")  # color_surface1 — same as panel
const _TAB_COLOR_HOVER := Color("#3e2b3c")  # color_surface2 — hover highlight
const _TAB_COLOR_PRESSED := Color("#1a121a")  # color_background — pressed depression
const _TAB_BORDER_COLOR := Color("#50374d")  # color_surface3 — subtle border

# -- Lifecycle ---------------------------------------------------------------


func _ready() -> void:
	# Root Control is full-rect and click-through
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_ui()

	# Let subclasses configure properties (drawer_width, tab_text, etc.)
	# and populate the content_container.
	_on_ready()

	# Re-apply panel size and positions AFTER _on_ready(), because the
	# subclass may have changed drawer_width or other configuration.
	_panel.size.x = drawer_width
	_apply_initial_position()


## Override in subclasses for custom initialisation.
func _on_ready() -> void:
	pass


## Override in subclasses — called after the open animation finishes.
func _on_opened() -> void:
	pass


## Override in subclasses — called after the close animation finishes.
func _on_closed() -> void:
	pass


# -- Public API --------------------------------------------------------------


## Reveal the tab handle (slide it into view from off-screen).
## Does nothing if already revealed.
func reveal() -> void:
	if is_revealed:
		return
	is_revealed = true
	_animate_to_state()


## Hide the tab handle completely off-screen.
func conceal() -> void:
	if not is_revealed and not is_open:
		return
	is_open = false
	is_revealed = false
	_animate_to_state()


## Open the drawer with animation.
func open() -> void:
	if is_open or _is_animating:
		return
	is_open = true
	is_revealed = true
	_animate_to_state()


## Close the drawer with animation (tab stays visible).
func close() -> void:
	if not is_open or _is_animating:
		return
	is_open = false
	_animate_to_state()


## Toggle the drawer open or closed.
func toggle() -> void:
	if is_open:
		close()
	else:
		open()


# -- UI Construction ---------------------------------------------------------


func _build_ui() -> void:
	# Re-sync when the parent resizes
	resized.connect(_on_parent_resized)

	# -- Content panel -------------------------------------------------------
	# The panel is a direct child, positioned manually (not anchored).
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size = Vector2(drawer_width, size.y)
	_panel.position.y = 0
	_apply_panel_style()
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	content_container = VBoxContainer.new()
	content_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.theme_type_variation = &"BoxContainerSpaced"
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content_container)

	# -- Tab button ----------------------------------------------------------
	_tab_button = Button.new()
	_tab_button.custom_minimum_size = Vector2(tab_width, 64)
	_tab_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_tab_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tab_button.focus_mode = Control.FOCUS_NONE
	# Silence the default auto-connected click sound; we play open/close instead
	_tab_button.set_meta("ui_silent", true)
	_tab_button.pressed.connect(_on_tab_pressed)
	_tab_button.position.y = tab_top_margin

	# Style the tab for visibility against the dark viewport
	_apply_tab_style()

	add_child(_tab_button)

	_tab_label = Label.new()
	_tab_label.text = tab_text
	_tab_label.theme_type_variation = &"Body"
	_tab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_tab_button.add_child(_tab_label)


func _apply_panel_style() -> void:
	# Square-cornered panel — no rounded corners so the 3D scene behind
	# the drawer never peeks through at the edges.
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL_COLOR
	_panel.add_theme_stylebox_override("panel", style)


func _apply_tab_style() -> void:
	# The tab matches the panel colour and has rounded corners on the side
	# facing away from the panel. No border — keeps it clean and cohesive.
	var corner_r := 6

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = _TAB_COLOR_NORMAL
	if edge == DrawerEdge.LEFT:
		style_normal.corner_radius_top_right = corner_r
		style_normal.corner_radius_bottom_right = corner_r
	else:
		style_normal.corner_radius_top_left = corner_r
		style_normal.corner_radius_bottom_left = corner_r
	style_normal.content_margin_left = 8
	style_normal.content_margin_right = 8
	style_normal.content_margin_top = 12
	style_normal.content_margin_bottom = 12

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = _TAB_COLOR_HOVER

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = _TAB_COLOR_PRESSED

	_tab_button.add_theme_stylebox_override("normal", style_normal)
	_tab_button.add_theme_stylebox_override("hover", style_hover)
	_tab_button.add_theme_stylebox_override("pressed", style_pressed)
	_tab_button.add_theme_stylebox_override("hover_pressed", style_pressed)
	_tab_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_parent_resized() -> void:
	if _panel:
		_panel.size.y = size.y


# -- Position Helpers --------------------------------------------------------


func _apply_initial_position() -> void:
	if start_open:
		is_open = true
		is_revealed = true
	elif start_revealed:
		is_revealed = true

	_panel.position.x = _get_panel_x()
	_tab_button.position.x = _get_tab_x()


func _get_panel_x() -> float:
	## Panel X for the current state.
	## When not open the panel is pushed well past the screen edge so no
	## part of it is visible (including stylebox borders/shadows).
	if edge == DrawerEdge.LEFT:
		if is_open:
			return 0.0
		else:
			return -(drawer_width + 20)
	else:
		if is_open:
			return size.x - drawer_width
		else:
			return size.x + 20


func _get_tab_x() -> float:
	## Tab X for the current state.
	if edge == DrawerEdge.LEFT:
		if is_open:
			return drawer_width
		elif is_revealed:
			return 0.0
		else:
			# Off-screen
			return -tab_width
	else:
		if is_open:
			return size.x - drawer_width - tab_width
		elif is_revealed:
			return size.x - tab_width
		else:
			return size.x


# -- Animation ---------------------------------------------------------------


func _animate_to_state() -> void:
	if _slide_tween:
		_slide_tween.kill()

	_is_animating = true

	var panel_target := _get_panel_x()
	var tab_target := _get_tab_x()

	_slide_tween = create_tween()
	_slide_tween.set_parallel(true)
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(_panel, "position:x", panel_target, slide_duration)
	_slide_tween.tween_property(_tab_button, "position:x", tab_target, slide_duration)
	_slide_tween.finished.connect(_on_slide_finished, CONNECT_ONE_SHOT)

	if play_sounds:
		if is_open:
			AudioManager.play_open()
		elif is_revealed:
			AudioManager.play_close()


func _on_slide_finished() -> void:
	_is_animating = false
	if is_open:
		_on_opened()
	else:
		_on_closed()


# -- Input -------------------------------------------------------------------


func _on_tab_pressed() -> void:
	toggle()
