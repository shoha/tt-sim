extends GutTest

## Foldout moves authored children into its body, starts at the requested
## state without animating, and animates on toggle.


func _foldout(expanded_at_start: bool = false) -> Foldout:
	var foldout := Foldout.new()
	foldout.title = "Advanced"
	foldout.expanded = expanded_at_start
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, 40)
	foldout.add_child(row)
	add_child_autofree(foldout)
	return foldout


func test_authored_children_move_into_body() -> void:
	var foldout := _foldout()
	assert_eq(foldout.body.get_child_count(), 1)
	assert_eq(foldout.get_child_count(), 2, "header + clip only")


func test_starts_collapsed_with_zero_height_body() -> void:
	var foldout := _foldout()
	assert_false(foldout.expanded)
	assert_eq(foldout._clip.custom_minimum_size.y, 0.0)
	assert_false(foldout.body.visible)


func test_starts_expanded_at_natural_height() -> void:
	var foldout := _foldout(true)
	assert_eq(foldout._clip.custom_minimum_size.y, 40.0)
	assert_true(foldout.body.visible)
	assert_almost_eq(foldout._chevron.rotation, PI / 2.0, 0.001)


func test_toggle_emits_and_starts_tween() -> void:
	var foldout := _foldout()
	watch_signals(foldout)
	foldout.toggle()
	assert_true(foldout.expanded)
	assert_signal_emitted_with_parameters(foldout, "expanded_changed", [true])
	assert_true(foldout._tween != null and foldout._tween.is_valid())
	assert_true(foldout.body.visible, "body shows before the expand tween runs")


func test_setting_same_value_is_a_no_op() -> void:
	var foldout := _foldout()
	watch_signals(foldout)
	foldout.expanded = false
	assert_signal_not_emitted(foldout, "expanded_changed")


func test_title_reaches_label() -> void:
	var foldout := _foldout()
	foldout.title = "More"
	assert_eq(foldout._title_label.text, "More")


## Rows authored under a Foldout in a .tscn belong to the scene root; moving
## them into the body must not break the root's %unique_name lookups.
func test_authored_children_keep_their_owner() -> void:
	var host := Control.new()
	var foldout := Foldout.new()
	host.add_child(foldout)
	var row := Control.new()
	row.name = "Row"
	foldout.add_child(row)
	row.owner = host
	row.unique_name_in_owner = true
	add_child_autofree(host)
	assert_eq(row.get_parent(), foldout.body)
	assert_eq(row.owner, host)
	assert_eq(host.get_node("%Row"), row)


## An HFlowContainer body reports one row before layout and wraps to more rows
## once it has a width, so a resize during the expand tween must retarget the
## clip, and finishing must snap to the laid-out height.
func test_body_resize_mid_expand_retargets_the_tween() -> void:
	var foldout := Foldout.new()
	var flow := HFlowContainer.new()
	for i in range(6):
		var tile := Control.new()
		tile.custom_minimum_size = Vector2(64, 56)
		flow.add_child(tile)
	foldout.add_child(flow)
	foldout.size = Vector2(200, 0)
	add_child_autofree(foldout)
	foldout.expanded = true
	var first_target := foldout._target_height
	foldout.body.size = Vector2(200, 130)
	# body's horizontal anchors stretch (PRESET_TOP_WIDE); setting its size
	# directly is exactly what a real relayout does and is expected to warn.
	assert_engine_error(1, "setting body.size directly simulates a relayout")
	foldout._on_body_resized()
	assert_ne(foldout._target_height, first_target, "resize mid-tween retargets")
	assert_eq(foldout._target_height, 130.0)
	assert_true(foldout._tween != null and foldout._tween.is_valid())


func test_finish_snaps_clip_to_laid_out_body_height() -> void:
	var foldout := Foldout.new()
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, 40)
	foldout.add_child(row)
	add_child_autofree(foldout)
	foldout.expanded = true
	foldout.body.size = Vector2(200, 96)
	# Same expected relayout warning as above.
	assert_engine_error(1, "setting body.size directly simulates a relayout")
	foldout._on_animation_finished()
	assert_eq(foldout._clip.custom_minimum_size.y, 96.0)
	assert_true(foldout.body.visible)
