class_name AuthoringWelcome
extends PanelContainer

## The card a newcomer sees the first time they open map building: what to do for a first stroke,
## in two lines, and one quiet button to put it away. It stands at the top centre of the board
## (clear of the tool drawer on its left, the actions pill above it and the camera compass on its
## right), fades in, and goes
## for good the first time the author makes an edit or presses Got it: the choice is saved in the
## settings file (UiPreferences.load_authoring_welcome_done), so it is never shown again, and it
## never blocks a click. docs/UI_TASTE.md "Re-showing dismissed onboarding" is an anti-pattern.

## The card was put away, by the button or by the author's first edit.
signal dismissed

const TITLE := "Your first strokes"
const BODY := "Pick Biome or Place on the left, then drag across the map to paint it."
const KEYS := "Keys %s pick a tool; F1 lists all."
const BUTTON := "Got it"
## The card's widest, so its wrapped lines stay short.
const MAX_WIDTH := 340.0
## Its distance from the top edge of the screen: below the camera compass, in the board's top right
## corner, where it covers neither the middle of the board nor the drawer.
const TOP_MARGIN := 150.0
## Its distance from the right edge of the window.
const RIGHT_MARGIN := 24.0

var _fade: Tween


func _init() -> void:
	name = "AuthoringWelcome"
	theme_type_variation = &"Card"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(MAX_WIDTH, 0)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = TOP_MARGIN
	offset_right = -RIGHT_MARGIN
	offset_left = -RIGHT_MARGIN - MAX_WIDTH
	var column := VBoxContainer.new()
	column.theme_type_variation = &"BoxContainerSnug"
	add_child(column)
	var title := Label.new()
	title.name = "WelcomeTitle"
	title.text = TITLE
	title.theme_type_variation = &"Heading"
	column.add_child(title)
	column.add_child(_line("WelcomeBody", BODY, &"Body"))
	column.add_child(_line("WelcomeKeys", keys_line(), &"Caption"))
	var button := Button.new()
	button.name = "WelcomeDismiss"
	button.text = BUTTON
	button.theme_type_variation = &"Ghost"
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.pressed.connect(dismiss)
	column.add_child(button)


## The keys line: each rail tool's letter in rail order ("Keys B P T K H U F pick a tool; F1 lists
## all."), the same keys the rail's corners, its tooltips and F1 show.
static func keys_line() -> String:
	var letters: PackedStringArray = []
	for tool in ToolRegistry.rail_tools(ToolDescriptor.AUTHORING):
		if tool.shortcut_label() != "":
			letters.append(tool.shortcut_label())
	return KEYS % " ".join(letters)


## Shows the card with a fade unless this user has put it away before. True when it is showing.
func show_once() -> bool:
	if UiPreferences.load_authoring_welcome_done():
		return false
	if _fade != null and _fade.is_valid():
		_fade.kill()
	visible = true
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, UiMotion.fade_s(UiMotion.ENTRANCE_S))
	return true


## Puts the card away for good and saves that. Does nothing when it is not showing.
func dismiss() -> void:
	if not visible:
		return
	UiPreferences.save_authoring_welcome_done(true)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, UiMotion.fade_s(UiMotion.PANEL_OUT_S))
	_fade.finished.connect(func() -> void: visible = false, CONNECT_ONE_SHOT)
	dismissed.emit()


func _line(line_name: String, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.name = line_name
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
