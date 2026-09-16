extends GutTest

## The shared entrance: every target starts invisible and lifted, then settles
## back to the position its container gave it, one after another.


func test_stagger_in_hides_then_restores_alpha_and_position() -> void:
	var box := VBoxContainer.new()
	add_child_autofree(box)
	var rows: Array[Control] = []
	for i in range(3):
		var label := Label.new()
		label.text = "row %d" % i
		box.add_child(label)
		rows.append(label)
	await wait_frames(2)
	var settled_y := rows[2].position.y
	UiMotion.stagger_in(rows, box)
	await wait_frames(3)
	assert_lt(rows[2].modulate.a, 0.5, "the last row is still waiting out its delay")
	await wait_seconds(Constants.ANIM_ENTRANCE + 3 * Constants.ANIM_ENTRANCE_STAGGER + 0.1)
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
