class_name UiActions
extends RefCounted

## The two menu action shapes, as static builders. Every menu screen builds its
## actions through these so metrics, icon loading, text alignment and the hidden
## subtitle label stay identical everywhere: one tall accent primary per screen
## (the default Button variant) and quiet Secondary rows for everything else.
## Extracted from TitleScreen, which was the first screen to use them.

const PRIMARY_HEIGHT := 56
const SECONDARY_HEIGHT := 36


## A tall accent button with an icon and a left-aligned label, appended to
## [param parent]. When [param caption] is not empty a muted Caption label
## follows it; a hidden subtitle label always follows that (see subtitle_of).
static func primary(label: String, icon: String, caption: String, parent: Control) -> Button:
	var button := AnimatedButton.new()
	button.name = label.replace(" ", "")
	button.text = label
	button.icon = IconButton.load_icon(icon)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, PRIMARY_HEIGHT)
	button.expand_icon = false
	parent.add_child(button)
	if not caption.is_empty():
		var caption_label := Label.new()
		caption_label.name = "Caption"
		caption_label.text = caption
		caption_label.theme_type_variation = &"Caption"
		caption_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		parent.add_child(caption_label)
	_add_subtitle(button, parent)
	return button


## A compact Secondary row with an icon and a left-aligned label, appended to
## [param parent] and followed by its hidden subtitle label.
static func secondary(label: String, icon: String, parent: Control) -> Button:
	var button := AnimatedButton.new()
	button.name = label.replace(" ", "")
	button.text = label
	button.icon = IconButton.load_icon(icon)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.theme_type_variation = &"Secondary"
	button.custom_minimum_size = Vector2(0, SECONDARY_HEIGHT)
	parent.add_child(button)
	_add_subtitle(button, parent)
	return button


## The hidden Caption label under [param button] — for a line a screen fills in
## only when it has something to say (the title's "with <level>").
static func subtitle_of(button: Button) -> Label:
	return button.get_meta("subtitle") as Label


## Fixed vertical gap, appended to [param parent].
static func spacer(height: int, parent: Control) -> Control:
	var control := Control.new()
	control.name = "Spacer"
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.custom_minimum_size = Vector2(0, height)
	parent.add_child(control)
	return control


static func _add_subtitle(button: Button, parent: Control) -> void:
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.theme_type_variation = &"Caption"
	subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	subtitle.visible = false
	parent.add_child(subtitle)
	button.set_meta("subtitle", subtitle)
