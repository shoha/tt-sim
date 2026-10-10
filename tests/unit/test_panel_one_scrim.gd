extends GutTest

## One scrim (docs/UI_TASTE.md G1): a confirmation opened over the pause menu lays no scrim
## of its own and takes the place of the pause sheet, which comes back, with its focus, when
## the confirmation is cancelled. A confirmation over no panel keeps its own scrim.

const PAUSE_SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")
## Long enough for a panel's entrance and the cover fade to finish.
const SETTLE_S := 0.5


func _sheet(panel: Node) -> Control:
	return panel.get_node("CenterContainer/PanelContainer") as Control


func _scrim_alpha(panel: Node) -> float:
	return (panel.get_node("ColorRect") as CanvasItem).self_modulate.a


func test_a_confirmation_over_the_pause_menu_shares_its_scrim() -> void:
	var pause: PauseOverlay = PAUSE_SCENE.instantiate()
	add_child_autofree(pause)
	await wait_seconds(SETTLE_S)
	pause.settings_button.grab_focus()
	var dialog: ConfirmationDialogUI = UIManager.show_confirmation("Quit game?", "Test.")
	assert_eq(_scrim_alpha(dialog), 0.0, "no second scrim")
	assert_eq(_scrim_alpha(pause), 1.0, "the pause menu's scrim stays")
	await wait_seconds(SETTLE_S)
	assert_false(_sheet(pause).visible, "the confirmation takes the pause sheet's place")
	dialog._on_cancel_pressed()
	await wait_seconds(SETTLE_S)
	assert_true(_sheet(pause).visible, "the pause sheet comes back")
	assert_almost_eq(_sheet(pause).modulate.a, 1.0, 0.01)
	assert_eq(get_viewport().gui_get_focus_owner(), pause.settings_button, "with its focus")


func test_a_confirmation_over_no_panel_keeps_its_own_scrim() -> void:
	var dialog: ConfirmationDialogUI = UIManager.show_confirmation("Delete?", "Test.")
	assert_eq(_scrim_alpha(dialog), 1.0)
	dialog.queue_free()
