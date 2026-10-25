class_name LibraryTransferUi
extends RefCounted

## The dialogs of a library transfer, driven by LibraryTransferConsent (which holds every rule and
## every word): the question ("The host uses collection X ... Download?" with Download and
## Skip), a progress sheet with a bar and Cancel, and a plain notice (a toast). Both
## sheets are the confirmation dialog (ConfirmationDialogUI) the rest of the game uses, so they
## look and behave like it. LibraryTransferChannel calls these through duck typing, so a test or
## a tool can pass its own object with the same methods.


## Emitted once by an answer; one object per question.
class Answer:
	extends RefCounted
	signal chosen(yes: bool)
	var settled: bool = false

	func settle(yes: bool) -> void:
		if not settled:
			settled = true
			chosen.emit(yes)


var _progress_dialog: Node = null
var _bar: ProgressBar = null
var _label: Label = null


## Shows the question and returns true for Download, false for Skip, Escape or closing it.
func ask(model: LibraryTransferConsent) -> bool:
	var answer := Answer.new()
	UIManager.show_confirmation(
		LibraryTransferConsent.title(),
		model.message,
		LibraryTransferConsent.DOWNLOAD,
		LibraryTransferConsent.SKIP,
		func() -> void: answer.settle(true),
		func() -> void: answer.settle(false)
	)
	return await answer.chosen


## Opens the progress sheet for a transfer in RECEIVING; `on_cancel` runs when the player
## presses Cancel download.
func begin_progress(model: LibraryTransferConsent, on_cancel: Callable) -> void:
	end_progress()
	_progress_dialog = UIManager.show_confirmation(
		LibraryTransferConsent.title(),
		model.message,
		"",
		LibraryTransferConsent.CANCEL_DOWNLOAD,
		Callable(),
		on_cancel
	)
	if _progress_dialog == null or not "confirm_button" in _progress_dialog:
		return
	_progress_dialog.confirm_button.visible = false
	_label = _progress_dialog.message_label
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 12)
	var box: Node = _progress_dialog.get_node("CenterContainer/PanelContainer/VBoxContainer")
	box.add_child(_bar)
	box.move_child(_bar, 2)


## Moves the bar and the line under it to the model's state; `fraction` is 0 to 1.
func set_progress(model: LibraryTransferConsent, fraction: float) -> void:
	if is_instance_valid(_bar):
		_bar.value = clampf(fraction, 0.0, 1.0)
	if is_instance_valid(_label):
		_label.text = model.message


## Closes the progress sheet, if one is open.
func end_progress() -> void:
	if is_instance_valid(_progress_dialog):
		_progress_dialog.animate_out()
	_progress_dialog = null
	_bar = null
	_label = null


## A line for the player, as a toast.
func notify(text: String) -> void:
	UIManager.show_toast(text, UIManager.TOAST_INFO, 8.0)
