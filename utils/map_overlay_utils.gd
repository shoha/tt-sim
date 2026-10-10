class_name MapOverlayUtils
extends RefCounted

## Shared utilities for 2D overlay tools (MeasureTool, DragRuler, etc.).
## Provides factory methods for creating CanvasLayer overlays and styled
## label panels so each tool doesn't duplicate the boilerplate. Everything made
## here sits over the live table, so it wears the glass theme: label and checkbox
## panels are glass chips (the theme's `Chip` variation, glass with its top rim, never a
## black box: UI_TASTE.md C4) with chalk text.

## The caption size, the floor for text over the board (T2).
const CAPTION_SIZE := 14


## Create a CanvasLayer + full-rect Control for 2D drawing overlays.
## The Control has mouse_filter = IGNORE and its draw signal is connected
## to [param draw_callback].
## Returns {"canvas_layer": CanvasLayer, "draw_control": Control}.
static func create_overlay(parent: Node, layer: int, draw_callback: Callable) -> Dictionary:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = layer
	parent.add_child(canvas_layer)

	var draw_control := Control.new()
	draw_control.theme = ThemeColors.glass_theme()
	draw_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_control.draw.connect(draw_callback)
	canvas_layer.add_child(draw_control)

	return {"canvas_layer": canvas_layer, "draw_control": draw_control}


## Create a glass chip PanelContainer + Label for measurement and ruler readouts, the
## label at [param font_size] (never under the caption floor).
## Returns {"panel": PanelContainer, "label": Label}.
static func create_label_panel(font_size: int = CAPTION_SIZE) -> Dictionary:
	var panel := _chip()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", maxi(font_size, CAPTION_SIZE))
	panel.add_child(lbl)

	return {"panel": panel, "label": lbl}


## The size of `text` drawn as a glass chip on `canvas` (draw_chip): the caption's line inside
## the Chip variation's margins. `canvas` wears the glass theme (create_overlay's control).
static func chip_size(canvas: Control, text: String) -> Vector2:
	var font := canvas.get_theme_font(&"font", &"Caption")
	var size := canvas.get_theme_font_size(&"font_size", &"Caption")
	var box := canvas.get_theme_stylebox(&"panel", &"Chip")
	var line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	return Vector2(line.x, font.get_height(size)) + box.get_minimum_size()


## Draws `text` as a glass chip with its top-left corner at `at` on `canvas`, the cursor's
## readouts over the board: the hint bar's and the rulers' Chip (plum glass with its top rim)
## and caption text (14, the floor, T2) in `color`, chalk (the glass TEXT role) by default.
## Drawn, not a node, so it follows a cursor every frame without a layout pass.
static func draw_chip(
	canvas: Control, at: Vector2, text: String, color: Color = Color.TRANSPARENT
) -> void:
	var font := canvas.get_theme_font(&"font", &"Caption")
	var size := canvas.get_theme_font_size(&"font_size", &"Caption")
	var box := canvas.get_theme_stylebox(&"panel", &"Chip")
	var rect := Rect2(at, chip_size(canvas, text))
	canvas.draw_style_box(box, rect)
	var ink := color if color.a > 0.0 else ThemeColors.of(canvas, ThemeColors.TEXT)
	var baseline := (
		at
		+ Vector2(box.get_margin(SIDE_LEFT), box.get_margin(SIDE_TOP))
		+ Vector2(0.0, font.get_ascent(size))
	)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


## Create a glass chip PanelContainer + VBoxContainer of CheckBox rows, one per label in
## [param labels], in order. Unlike create_label_panel, neither the panel nor its
## checkboxes set MOUSE_FILTER_IGNORE -- these controls need real mouse input to be
## clickable.
## Returns {"panel": PanelContainer, "checkboxes": Array[CheckBox]} (checkboxes in
## the same order as labels).
static func create_checkbox_panel(labels: PackedStringArray) -> Dictionary:
	var panel := _chip()

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var checkboxes: Array[CheckBox] = []
	for label_text in labels:
		var checkbox := CheckBox.new()
		checkbox.text = label_text
		vbox.add_child(checkbox)
		checkboxes.append(checkbox)

	return {"panel": panel, "checkboxes": checkboxes}


static func _chip() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme = ThemeColors.glass_theme()
	panel.theme_type_variation = &"Chip"
	panel.visible = false
	return panel
