class_name AuthoringActions
extends PanelContainer

## The map tools' actions, a small floating paper pill beside the rail and the card: Undo, Redo, a
## gap, Save, a gap, Leave (card ui-authoring3; they stood in the rail's second column before, which
## the owner did not like). Icon buttons with the same tooltips as ever, Undo and Redo drawn off
## while they have nothing to do, Save with a dot and the word "Unsaved" while there is anything to
## save. Ctrl+Z, Ctrl+Y, Ctrl+S and Esc are the controller's and the panel's, unchanged. Leave is
## set apart by a wider gap, so a click that aims at Save does not leave the map. The buttons take
## keyboard focus. The surface is the theme's (ActionPill), paper or glass with the chrome.

## An action was pressed: AuthoringChrome.ACTION_UNDO, REDO, SAVE or LEAVE.
signal action_pressed(id: StringName)

## The step between Undo / Redo, Save and Leave, over the rail's own 4 px either side.
const GROUP_GAP := 12.0

var _rail: IconRail
var _tween: Tween


func _init() -> void:
	name = "AuthoringActions"
	theme_type_variation = &"ActionPill"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rail = IconRail.new()
	_rail.name = "ActionRail"
	_rail.vertical = false
	_rail.auto_select = false
	_rail.focusable = true
	_rail.item_size = AuthoringChrome.ACTION_ITEM_SIZE
	add_child(_rail)
	for item in AuthoringChrome.ACTION_ITEMS:
		var id := StringName(item["id"])
		if id == AuthoringChrome.ACTION_SAVE or id == AuthoringChrome.ACTION_LEAVE:
			_rail.add_gap(GROUP_GAP)
		_rail.add_item(id, String(item["icon"]), String(item["tooltip"]))
	_rail.item_pressed.connect(func(id: StringName) -> void: action_pressed.emit(id))


## Undo and Redo are live only while they have something to do; their tooltips say what.
func set_history(can_undo: bool, can_redo: bool, undo_tip: String, redo_tip: String) -> void:
	_rail.set_enabled(AuthoringChrome.ACTION_UNDO, can_undo)
	_rail.set_enabled(AuthoringChrome.ACTION_REDO, can_redo)
	_rail.set_item_tooltip(AuthoringChrome.ACTION_UNDO, undo_tip)
	_rail.set_item_tooltip(AuthoringChrome.ACTION_REDO, redo_tip)


## Badges Save with a dot and the word while the map has unsaved changes.
func set_dirty(dirty: bool, tip: String) -> void:
	_rail.set_badge(AuthoringChrome.ACTION_SAVE, dirty)
	_rail.set_item_caption(
		AuthoringChrome.ACTION_SAVE, AuthoringChrome.UNSAVED_WORD if dirty else ""
	)
	_rail.set_item_tooltip(AuthoringChrome.ACTION_SAVE, tip)


## Moves the pill to `at` (level with the rail and card tops) and shows it while `revealed`, easing
## over `seconds` (0, or Reduce motion: a cut, with the drawer's own fade-only rule).
func glide_to(at: Vector2, revealed: bool, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	position.y = at.y
	if seconds <= 0.0 or UiMotion.reduced():
		position.x = at.x
		modulate.a = 1.0
		visible = revealed
		return
	if revealed and not visible:
		visible = true
		modulate.a = 0.0
		position.x = at.x
	_tween = create_tween().set_parallel().set_trans(UiMotion.ARRIVE_TRANS)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:x", at.x, seconds)
	_tween.tween_property(self, "modulate:a", 1.0 if revealed else 0.0, seconds)
	if not revealed:
		_tween.chain().tween_callback(func() -> void: visible = false)


## The button of action `id` (a test or the bridge clicks it), or null.
func button(id: StringName) -> Button:
	return _rail.get_node_or_null(NodePath(String(id))) as Button
