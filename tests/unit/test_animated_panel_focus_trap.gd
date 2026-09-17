extends GutTest

## AnimatedCanvasLayerPanel builds its focus trap once in _ready(). A subclass
## that shows/hides content afterwards (see LobbyClient) must call
## rebuild_focus_trap() to keep the trap naming only what is actually visible.


func _panel_with_two_buttons() -> Dictionary:
	var panel := AnimatedCanvasLayerPanel.new()
	panel.play_sounds = false

	var backdrop := ColorRect.new()
	backdrop.name = "ColorRect"
	panel.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	panel.add_child(center)

	var panel_container := PanelContainer.new()
	panel_container.name = "PanelContainer"
	center.add_child(panel_container)

	var box := VBoxContainer.new()
	panel_container.add_child(box)

	var button1 := Button.new()
	button1.name = "Button1"
	box.add_child(button1)

	var button2 := Button.new()
	button2.name = "Button2"
	box.add_child(button2)

	add_child_autofree(panel)
	return {"panel": panel, "button1": button1, "button2": button2}


func test_rebuild_drops_a_control_hidden_after_ready() -> void:
	var built := _panel_with_two_buttons()
	var panel: AnimatedCanvasLayerPanel = built.panel
	var button2: Button = built.button2

	button2.visible = false
	panel.rebuild_focus_trap()

	assert_eq(panel._focusable_controls.size(), 1)
	assert_eq(panel._focusable_controls[0], built.button1)
