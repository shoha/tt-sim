class_name SliderSpinBox
extends HBoxContainer

## Reusable slider + spinbox pair with automatic bidirectional sync.
## The slider provides quick approximate adjustment, and the spinbox
## allows precise value entry (optionally beyond the slider range).

signal value_changed(new_value: float)

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		_sync_properties()

@export var max_value: float = 1.0:
	set(v):
		max_value = v
		_sync_properties()

@export var step: float = 0.01:
	set(v):
		step = v
		_sync_properties()

@export var value: float = 0.0:
	set(v):
		value = v
		_sync_properties()

@export var exp_edit: bool = false:
	set(v):
		exp_edit = v
		_sync_properties()

@export var allow_greater: bool = false:
	set(v):
		allow_greater = v
		_sync_properties()

@export var allow_lesser: bool = false:
	set(v):
		allow_lesser = v
		_sync_properties()

@onready var _slider: HSlider = $Slider
@onready var _spin_box: SpinBox = $SpinBox

var _syncing: bool = false


func _ready() -> void:
	_sync_properties()
	_slider.value_changed.connect(_on_slider_value_changed)
	_spin_box.value_changed.connect(_on_spin_value_changed)


## Set the value without emitting value_changed.
func set_value_no_signal(new_value: float) -> void:
	_syncing = true
	value = new_value
	if is_node_ready():
		_slider.set_value_no_signal(clampf(new_value, _slider.min_value, _slider.max_value))
		_spin_box.set_value_no_signal(new_value)
	_syncing = false


func _sync_properties() -> void:
	if _syncing or not is_node_ready():
		return
	_syncing = true
	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.step = step
	_slider.exp_edit = exp_edit
	_slider.set_value_no_signal(clampf(value, min_value, max_value))
	_spin_box.min_value = min_value
	_spin_box.max_value = max_value
	_spin_box.step = step
	_spin_box.allow_greater = allow_greater
	_spin_box.allow_lesser = allow_lesser
	_spin_box.set_value_no_signal(value)
	_syncing = false


func _on_slider_value_changed(new_value: float) -> void:
	if _syncing:
		return
	_syncing = true
	value = new_value
	_spin_box.set_value_no_signal(new_value)
	_syncing = false
	value_changed.emit(new_value)


func _on_spin_value_changed(new_value: float) -> void:
	if _syncing:
		return
	_syncing = true
	value = new_value
	_slider.set_value_no_signal(clampf(new_value, _slider.min_value, _slider.max_value))
	_syncing = false
	value_changed.emit(new_value)
