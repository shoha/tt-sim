class_name IconButton
extends Button

## Flat, icon-only button. Icons are looked up by Tabler name under ICON_DIR
## and tinted by the theme's icon colour states (IconButton / IconButtonActive
## variations), so a white SVG takes hover, pressed and active colours with no
## per-instance colour code. Hover and press motion runs on
## offset_transform_scale so containers never relayout mid-animation.

const ICON_DIR := "res://assets/icons/ui/"
const BADGE_SIZE := 8.0
const BADGE_MARGIN := 2.0

static var _warned_icons: Dictionary = {}

## Tabler icon name without extension, e.g. "cloud-rain".
@export var icon_name: String = "":
	set(value):
		icon_name = value
		_refresh_icon()

## Active items use "<name>-filled.svg" when it exists, otherwise the outline
## icon with the IconButtonActive tint.
@export var active: bool = false:
	set(value):
		active = value
		_refresh_icon()

## Small accent dot at the top-right corner (unsaved changes etc).
@export var badge: bool = false:
	set(value):
		badge = value
		if _badge:
			_badge.visible = value

var _tween: Tween
var _badge: Panel
var _hovered: bool = false


func _ready() -> void:
	flat = true
	text = ""
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	offset_transform_enabled = true
	_build_badge()
	_refresh_icon()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


## Resolve an icon texture by Tabler name. Returns null and warns once per
## name when the file is missing, so a typo degrades to an empty button.
static func load_icon(name: String) -> Texture2D:
	if name.is_empty():
		return null
	var path := ICON_DIR + name + ".svg"
	if not ResourceLoader.exists(path):
		if not _warned_icons.has(name):
			_warned_icons[name] = true
			push_warning("IconButton: missing icon %s" % path)
		return null
	return load(path)


func _refresh_icon() -> void:
	if not is_node_ready():
		return
	theme_type_variation = &"IconButtonActive" if active else &"IconButton"
	var filled_path := ICON_DIR + icon_name + "-filled.svg"
	if active and not icon_name.is_empty() and ResourceLoader.exists(filled_path):
		icon = load(filled_path)
	else:
		icon = load_icon(icon_name)


func _build_badge() -> void:
	_badge = Panel.new()
	_badge.name = "Badge"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.ACCENT
	style.set_corner_radius_all(int(BADGE_SIZE / 2.0))
	_badge.add_theme_stylebox_override("panel", style)
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left = -BADGE_SIZE - BADGE_MARGIN
	_badge.offset_top = BADGE_MARGIN
	_badge.offset_right = -BADGE_MARGIN
	_badge.offset_bottom = BADGE_MARGIN + BADGE_SIZE
	_badge.visible = badge
	add_child(_badge)


func _on_mouse_entered() -> void:
	_hovered = true
	_scale_to(Constants.UI_HOVER_SCALE, Constants.ANIM_HOVER_IN, Tween.TRANS_BACK)


func _on_mouse_exited() -> void:
	_hovered = false
	_scale_to(Vector2.ONE, Constants.ANIM_HOVER_OUT, Tween.TRANS_CUBIC)


func _on_button_down() -> void:
	_scale_to(Constants.UI_PRESS_SCALE, Constants.ANIM_PRESS, Tween.TRANS_CUBIC)


func _on_button_up() -> void:
	var target := Constants.UI_HOVER_SCALE if _hovered else Vector2.ONE
	_scale_to(target, Constants.ANIM_HOVER_IN, Tween.TRANS_BACK)


func _scale_to(target: Vector2, duration: float, trans: Tween.TransitionType) -> void:
	if disabled:
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = null
		offset_transform_scale = Vector2.ONE
		return
	_tween = UiMotion.scale_to(self, _tween, target, duration, trans)
