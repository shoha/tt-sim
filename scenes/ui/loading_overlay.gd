extends CanvasLayer
class_name LoadingOverlay

## Loading screen overlay for async operations.
##
## Shows a progress bar and status message during loading.

signal loading_complete

@onready var loading_label: Label = %LoadingLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel

var _tween: Tween
var _target_progress := 0.0


func _ready() -> void:
	_set_alpha(0.0)
	hide()


func _set_alpha(alpha: float) -> void:
	$ColorRect.modulate.a = alpha
	$CenterContainer.modulate.a = alpha


func _process(_delta: float) -> void:
	# Smooth progress bar animation
	if progress_bar.value < _target_progress:
		progress_bar.value = lerpf(progress_bar.value, _target_progress, 0.1)


## Show the loading overlay with optional title
func show_loading(title: String = "Loading...") -> void:
	loading_label.text = title
	status_label.text = ""
	progress_bar.value = 0.0
	_target_progress = 0.0
	
	show()
	
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property($ColorRect, "modulate:a", 1.0, 0.2)
	_tween.tween_property($CenterContainer, "modulate:a", 1.0, 0.2)


## Update the progress (0.0 to 1.0)
func set_progress(value: float, status: String = "") -> void:
	_target_progress = clampf(value, 0.0, 1.0)
	if status != "":
		status_label.text = status


## Hide the loading overlay
func hide_loading() -> void:
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property($ColorRect, "modulate:a", 0.0, 0.15)
	_tween.tween_property($CenterContainer, "modulate:a", 0.0, 0.15)
	
	await _tween.finished
	hide()
	loading_complete.emit()


## Show indeterminate loading (no progress bar)
func show_indeterminate(title: String = "Loading...") -> void:
	show_loading(title)
	progress_bar.hide()


## Restore progress bar visibility
func show_progress_bar() -> void:
	progress_bar.show()
