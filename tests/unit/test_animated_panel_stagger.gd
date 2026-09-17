extends GutTest

## A panel's staggered rows must be invisible before the first frame is drawn and only
## then fade in with the panel: the pause menu used to arrive fully visible, vanish when
## UiMotion.stagger_in reset its rows after the panel fade, and animate in a second time.

const PAUSE_SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")


func _rows(overlay: Node) -> Array[Control]:
	return UiMotion.visible_children(
		overlay.get_node("CenterContainer/PanelContainer/VBoxContainer")
	)


func test_pause_rows_are_hidden_synchronously_when_the_overlay_enters_the_tree() -> void:
	var overlay := PAUSE_SCENE.instantiate()
	add_child_autofree(overlay)

	var rows := _rows(overlay)
	assert_gt(rows.size(), 3, "the pause menu builds its rows in _on_panel_ready")
	for row in rows:
		assert_eq(row.modulate.a, 0.0, "%s must be hidden before the first frame" % row.name)


func test_pause_rows_fade_in_once_and_settle_at_full_alpha() -> void:
	var overlay := PAUSE_SCENE.instantiate()
	add_child_autofree(overlay)
	var rows := _rows(overlay)

	var total := (
		Constants.ANIM_FADE_IN_DURATION
		+ Constants.ANIM_ENTRANCE
		+ rows.size() * Constants.ANIM_ENTRANCE_STAGGER
		+ 0.25
	)
	await wait_seconds(total)

	for row in rows:
		assert_almost_eq(row.modulate.a, 1.0, 0.01, row.name)
	assert_almost_eq(overlay.get_node("CenterContainer").modulate.a, 1.0, 0.01)


func test_rows_never_return_to_zero_after_the_panel_fade() -> void:
	# The old bug: rows reached 1.0 with the panel fade, then were reset to 0.0 by the
	# stagger. Sample after the panel fade has finished; every row must be at or above
	# whatever alpha it had two frames earlier, never snapped back to zero.
	var overlay := PAUSE_SCENE.instantiate()
	add_child_autofree(overlay)
	var rows := _rows(overlay)
	await wait_seconds(Constants.ANIM_FADE_IN_DURATION + 0.05)
	var before: Array[float] = []
	for row in rows:
		before.append(row.modulate.a)
	await wait_frames(2)
	for i in range(rows.size()):
		assert_true(
			rows[i].modulate.a >= before[i] - 0.001,
			"%s dropped from %.2f to %.2f" % [rows[i].name, before[i], rows[i].modulate.a]
		)


func test_panel_without_targets_still_animates_in() -> void:
	var panel := AnimatedCanvasLayerPanel.new()
	var backdrop := ColorRect.new()
	backdrop.name = "ColorRect"
	panel.add_child(backdrop)
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	panel.add_child(center)
	center.add_child(PanelContainer.new())
	center.get_child(0).name = "PanelContainer"
	panel.play_sounds = false
	add_child_autofree(panel)
	await wait_seconds(Constants.ANIM_FADE_IN_DURATION + 0.1)
	assert_almost_eq(center.modulate.a, 1.0, 0.01)
