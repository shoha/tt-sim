class_name MapOverlayUtils
extends RefCounted

## Shared utilities for 2D overlay tools (MeasureTool, DragRuler, etc.).
## Provides factory methods for creating CanvasLayer overlays and styled
## label panels so each tool doesn't duplicate the boilerplate.


## Create a CanvasLayer + full-rect Control for 2D drawing overlays.
## The Control has mouse_filter = IGNORE and its draw signal is connected
## to [param draw_callback].
## Returns {"canvas_layer": CanvasLayer, "draw_control": Control}.
static func create_overlay(parent: Node, layer: int, draw_callback: Callable) -> Dictionary:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = layer
	parent.add_child(canvas_layer)

	var draw_control := Control.new()
	draw_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_control.draw.connect(draw_callback)
	canvas_layer.add_child(draw_control)

	return {"canvas_layer": canvas_layer, "draw_control": draw_control}


## Create a styled PanelContainer + Label with the standard dark backdrop
## used by measurement and ruler overlays.
## Returns {"panel": PanelContainer, "label": Label}.
static func create_label_panel(
	font_size: int = 14,
	font_color: Color = Color(1.0, 0.95, 0.6),
) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false

	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	stylebox.content_margin_left = 8.0
	stylebox.content_margin_right = 8.0
	stylebox.content_margin_top = 4.0
	stylebox.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", stylebox)

	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", font_color)
	panel.add_child(lbl)

	return {"panel": panel, "label": lbl}


## Create a styled PanelContainer + VBoxContainer of CheckBox rows, one per label in
## [param labels], in order. Unlike create_label_panel, neither the panel nor its
## checkboxes set MOUSE_FILTER_IGNORE -- these controls need real mouse input to be
## clickable.
## Returns {"panel": PanelContainer, "checkboxes": Array[CheckBox]} (checkboxes in
## the same order as labels).
static func create_checkbox_panel(
	labels: PackedStringArray,
	font_size: int = 13,
	font_color: Color = Color(0.8, 1.0, 0.8),
) -> Dictionary:
	var panel := PanelContainer.new()
	panel.visible = false

	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	stylebox.content_margin_left = 8.0
	stylebox.content_margin_right = 8.0
	stylebox.content_margin_top = 4.0
	stylebox.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", stylebox)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var checkboxes: Array[CheckBox] = []
	for label_text in labels:
		var checkbox := CheckBox.new()
		checkbox.text = label_text
		checkbox.add_theme_font_size_override("font_size", font_size)
		checkbox.add_theme_color_override("font_color", font_color)
		vbox.add_child(checkbox)
		checkboxes.append(checkbox)

	return {"panel": panel, "checkboxes": checkboxes}
