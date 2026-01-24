extends AnimatedVisibilityContainer
class_name TokenContextMenu

## Context menu for board tokens
## Provides actions like dealing damage, healing, and toggling visibility

signal hp_adjustment_requested(amount: int)
signal visibility_toggled()
signal menu_closed()

var target_token: BoardToken = null

@onready var input_field: LineEdit = $MenuPanel/VBoxContainer/CustomDamageContainer/HPAdjustmentInput
@onready var heal_hurt_toggle: CheckButton = $MenuPanel/VBoxContainer/CustomDamageContainer/HealHurtToggle

func _ready():
	# Quick fade-in menu
	fade_in_duration = 0.15
	fade_out_duration = 0.1
	scale_in_from = Vector2(0.9, 0.9)
	trans_in_type = Tween.TRANS_CUBIC
	trans_out_type = Tween.TRANS_CUBIC
	super._ready()

func open_for_token(token: BoardToken, at_position: Vector2) -> void:
	target_token = token
	_update_menu_content()
	input_field.grab_focus()

	# Position menu and adjust to stay within viewport bounds
	await get_tree().process_frame # Wait for size to be calculated
	_position_menu_in_viewport(at_position)

	animate_in()

func _update_menu_content() -> void:
	if not target_token:
		return

	# Update visibility toggle button text
	var visibility_button = get_node_or_null("MenuPanel/VBoxContainer/ToggleVisibilityButton")
	if visibility_button:
		if target_token.is_visible_to_players:
			visibility_button.text = "Hide Token"
		else:
			visibility_button.text = "Show Token"

	# Update health label
	var health_label = get_node_or_null("MenuPanel/VBoxContainer/HealthLabel")
	if health_label:
					health_label.text = "HP: %d/%d" % [target_token.current_health, target_token.max_health]

func _position_menu_in_viewport(cursor_position: Vector2) -> void:
	var menu_panel = get_node_or_null("MenuPanel")
	if not menu_panel:
		global_position = cursor_position
		return

	# Get viewport size
	var viewport_size = get_viewport().get_visible_rect().size
	var menu_size = menu_panel.size

	# Add small offset from cursor to avoid blocking it
	var offset = Vector2(10, 10)
	var target_position = cursor_position + offset

	# Check if menu would go off the right edge
	if target_position.x + menu_size.x > viewport_size.x:
		# Position to the left of cursor instead
		target_position.x = cursor_position.x - menu_size.x - offset.x

	# Check if menu would go off the bottom edge
	if target_position.y + menu_size.y > viewport_size.y:
		# Position above cursor instead
		target_position.y = cursor_position.y - menu_size.y - offset.y

	# Ensure menu doesn't go off the left edge
	if target_position.x < 0:
		target_position.x = 0

	# Ensure menu doesn't go off the top edge
	if target_position.y < 0:
		target_position.y = 0

	global_position = target_position

func _on_hp_adjustment_requested(input_amount: String = "") -> void:
	var amount: int = 0

	if input_amount == "":
		amount = int(input_field.text)
	else:
		amount = int(input_amount)

	if !heal_hurt_toggle.button_pressed:
		amount = - amount

	if amount != 0:
		input_field.clear()
		hp_adjustment_requested.emit(amount)
		_update_menu_content()
		close_menu()

func _on_toggle_visibility_pressed() -> void:
	if target_token:
		visibility_toggled.emit()
		_update_menu_content()

func _on_close_button_pressed() -> void:
	close_menu()

func close_menu() -> void:
	menu_closed.emit()
	animate_out()

# Close menu when clicking outside
func _unhandled_input(event: InputEvent) -> void:
	if not visible or is_animating():
		return

	if event is InputEventMouseButton and event.pressed:
		# Check if click is outside the menu
		var menu_panel = get_node_or_null("MenuPanel")
		if menu_panel:
			var menu_rect = Rect2(menu_panel.global_position, menu_panel.size)
			if not menu_rect.has_point(event.position):
				close_menu()
