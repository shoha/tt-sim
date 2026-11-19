extends GutTest

## The shared entrance: every target starts invisible and lifted, then settles
## back to the position its container gave it, one after another. The box's processing is off
## once laid out, so the entrance's tweens move only when the test steps them (custom_step), not
## at the pace of a loaded machine's frames (card flaky-gate-tests).


func test_stagger_in_hides_then_restores_alpha_and_position() -> void:
	var box := VBoxContainer.new()
	add_child_autofree(box)
	var rows: Array[Control] = []
	for i in range(3):
		var label := Label.new()
		label.text = "row %d" % i
		box.add_child(label)
		rows.append(label)
	await wait_process_frames(2)
	var settled_y := rows[2].position.y
	box.process_mode = Node.PROCESS_MODE_DISABLED
	var tweens: Array[Tween] = await UiMotion.stagger_in(rows, box)
	for tween in tweens:
		tween.custom_step(Constants.ANIM_ENTRANCE_STAGGER)
	assert_gt(rows[0].modulate.a, 0.0, "the first row has begun")
	assert_eq(rows[2].modulate.a, 0.0, "the last row is still waiting out its delay")
	for tween in tweens:
		tween.custom_step(Constants.ANIM_ENTRANCE + 3 * Constants.ANIM_ENTRANCE_STAGGER)
	for row in rows:
		assert_almost_eq(row.modulate.a, 1.0, 0.01)
	assert_almost_eq(rows[2].position.y, settled_y, 0.5, "rows land where the container put them")


func test_visible_children_skips_hidden_and_non_controls() -> void:
	var box := VBoxContainer.new()
	add_child_autofree(box)
	var shown := Label.new()
	box.add_child(shown)
	var hidden := Label.new()
	hidden.visible = false
	box.add_child(hidden)
	box.add_child(Timer.new())
	var targets := UiMotion.visible_children(box)
	assert_eq(targets.size(), 1)
	assert_same(targets[0], shown)
