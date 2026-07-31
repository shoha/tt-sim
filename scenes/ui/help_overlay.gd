extends AnimatedCanvasLayerPanel

## Full-screen overlay showing all keyboard shortcuts.
## Triggered by F1. Uses InputProfile.label() for device-aware key labels.
## Built programmatically from a data array for easy maintenance.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		UIManager.close_help()
		get_viewport().set_input_as_handled()


func _on_panel_ready() -> void:
	var panel: PanelContainer = get_node("CenterContainer/PanelContainer")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Keyboard Shortcuts"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(_spacer(8))

	var sections := _get_shortcut_data()
	for section in sections:
		_add_section(vbox, section.header, section.entries)

	vbox.add_child(_spacer(8))

	var close_label := Label.new()
	close_label.text = "Press F1 or Escape to close"
	close_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	close_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(close_label)

	# Register as overlay (cast to Control for type compatibility)
	UIManager.register_overlay($ColorRect as Control)


func _on_before_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)


func _on_after_animate_out() -> void:
	UIManager.on_help_overlay_closed()
	queue_free()


func _get_shortcut_data() -> Array:
	return [
		{
			"header": "Navigation",
			"entries":
			[
				[InputProfile.label(&"wasd"), "Pan camera"],
				[InputProfile.label(&"zoom"), "Zoom"],
				[InputProfile.label(&"reset_camera"), "Reset camera"],
			],
		},
		{
			"header": "Tokens",
			"entries":
			[
				["Left Click", "Select token"],
				["Left Drag", "Move token"],
				["Right Click", "Context menu"],
				[InputProfile.label(&"rotate"), "Rotate token"],
				[InputProfile.label(&"scale"), "Scale token"],
				[InputProfile.label(&"reset_transform"), "Reset rotation & scale"],
				["Shift (drag)", "Free move (bypass grid snap)"],
			],
		},
		{
			"header": "Tools",
			"entries":
			[
				[InputProfile.label(&"measure"), "Toggle measure tool"],
				[InputProfile.label(&"grid"), "Toggle grid overlay"],
				[InputProfile.label(&"cycle_mode"), "Cycle measure mode"],
				["Ctrl (measure)", "Snap to token"],
				["Right Click / Esc", "Finish measurement"],
			],
		},
		{
			"header": "General",
			"entries":
			[
				[InputProfile.label(&"pause"), "Pause / close menu"],
				["Ctrl+Z", "Undo last action"],
				["F1", "Toggle this help"],
			],
		},
	]


func _add_section(parent: VBoxContainer, header_text: String, entries: Array) -> void:
	parent.add_child(_spacer(6))

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1.0))
	parent.add_child(header)

	for entry in entries:
		var row := _create_shortcut_row(entry[0], entry[1])
		parent.add_child(row)


func _create_shortcut_row(key_text: String, action_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var badge_panel := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.25, 0.25, 0.28, 1.0)
	badge_style.corner_radius_top_left = 4
	badge_style.corner_radius_top_right = 4
	badge_style.corner_radius_bottom_left = 4
	badge_style.corner_radius_bottom_right = 4
	badge_style.content_margin_left = 8
	badge_style.content_margin_right = 8
	badge_style.content_margin_top = 2
	badge_style.content_margin_bottom = 2
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	badge_panel.custom_minimum_size = Vector2(140, 0)

	var key_label := Label.new()
	key_label.text = key_text
	key_label.add_theme_font_size_override("font_size", 13)
	badge_panel.add_child(key_label)
	row.add_child(badge_panel)

	var action_label := Label.new()
	action_label.text = action_text
	action_label.add_theme_font_size_override("font_size", 13)
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(action_label)

	return row


func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s
