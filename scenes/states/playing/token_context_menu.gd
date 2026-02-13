extends AnimatedVisibilityContainer
class_name TokenContextMenu

## Context menu for board tokens
## Provides actions like dealing damage, healing, and toggling visibility

signal hp_adjustment_requested(amount: int)
signal visibility_toggled
signal control_requested(token: BoardToken)
signal control_revoked(token: BoardToken)
signal menu_closed

var target_token: BoardToken = null

@onready var input_field: LineEdit = $MenuPanel/VBoxContainer/CustomDamageContainer/HPAdjustmentInput
@onready
var heal_hurt_toggle: CheckButton = $MenuPanel/VBoxContainer/CustomDamageContainer/HealHurtToggle
@onready var request_control_button: Button = $MenuPanel/VBoxContainer/RequestControlButton
@onready var revoke_control_button: Button = $MenuPanel/VBoxContainer/RevokeControlButton


func _ready() -> void:
	# Quick snap-in menu with a subtle bounce for game feel
	fade_in_duration = 0.12
	fade_out_duration = 0.08
	scale_in_from = Vector2(0.85, 0.85)
	scale_out_to = Vector2(0.92, 0.92)
	trans_in_type = Tween.TRANS_BACK
	trans_out_type = Tween.TRANS_CUBIC
	super._ready()


func open_for_token(token: BoardToken, at_position: Vector2) -> void:
	target_token = token
	_update_menu_content()
	# Only grab focus on input field if it's visible (DM-only)
	if input_field.visible:
		input_field.grab_focus()

	# Position menu and adjust to stay within viewport bounds
	await get_tree().process_frame  # Wait for size to be calculated
	_position_menu_in_viewport(at_position)

	animate_in()


func _update_menu_content() -> void:
	if not target_token or not is_instance_valid(target_token):
		return

	var is_gm = NetworkManager.is_gm() or not NetworkManager.is_networked()
	var is_networked = NetworkManager.is_networked()
	var my_peer_id = (
		multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0
	)

	# Update visibility toggle button text
	var visibility_button = get_node_or_null("MenuPanel/VBoxContainer/ToggleVisibilityButton")
	if visibility_button:
		if target_token.is_visible_to_players:
			visibility_button.text = "Hide Token"
		else:
			visibility_button.text = "Show Token"
		# Only DM can toggle visibility
		visibility_button.visible = is_gm or not is_networked

	# Update health label
	var health_label = get_node_or_null("MenuPanel/VBoxContainer/HealthLabel")
	if health_label:
		health_label.text = "HP: %d/%d" % [target_token.current_health, target_token.max_health]

	# Hide DM-only actions for players
	var damage_label = get_node_or_null("MenuPanel/VBoxContainer/DamageLabel")
	var damage_container = get_node_or_null("MenuPanel/VBoxContainer/CustomDamageContainer")
	var separator2 = get_node_or_null("MenuPanel/VBoxContainer/HSeparator2")
	var separator4 = get_node_or_null("MenuPanel/VBoxContainer/HSeparator4")
	var show_gm_actions = is_gm or not is_networked
	if damage_label:
		damage_label.visible = show_gm_actions
	if damage_container:
		damage_container.visible = show_gm_actions
	if separator2:
		separator2.visible = show_gm_actions
	if separator4:
		separator4.visible = show_gm_actions

	# Permission buttons
	_update_permission_buttons(is_gm, is_networked, my_peer_id)


## Update visibility of Request Control / Revoke Control buttons.
func _update_permission_buttons(is_gm: bool, is_networked: bool, my_peer_id: int) -> void:
	var separator_before = get_node_or_null("MenuPanel/VBoxContainer/HSeparator5")
	var separator_after = get_node_or_null("MenuPanel/VBoxContainer/HSeparator6")

	if not target_token or not is_instance_valid(target_token) or not is_networked:
		# No permission UI in single-player — hide buttons and extra separator
		if request_control_button:
			request_control_button.visible = false
		if revoke_control_button:
			revoke_control_button.visible = false
		# HSeparator5 stays visible (original separator before Close)
		# HSeparator6 is hidden (no permission buttons between them)
		if separator_after:
			separator_after.visible = false
		return

	var has_control = GameState.has_token_permission(
		target_token.network_id, my_peer_id, TokenPermissions.Permission.CONTROL
	)

	# "Request Control" — shown for players who don't already control this token
	if request_control_button:
		request_control_button.visible = not is_gm and not has_control
		request_control_button.disabled = false
		request_control_button.text = "Request Control"

	# "Revoke Control" — shown for DM when any player has CONTROL on this token
	if revoke_control_button:
		var controlling_peers = GameState.get_peers_with_permission(
			target_token.network_id, TokenPermissions.Permission.CONTROL
		)
		if is_gm and not controlling_peers.is_empty():
			# Show who has control
			var players = NetworkManager.get_players()
			var names: Array[String] = []
			for pid in controlling_peers:
				names.append(players[pid].get("name", "Player") if players.has(pid) else "Player")
			revoke_control_button.text = "Revoke Control (%s)" % ", ".join(names)
			revoke_control_button.visible = true
		else:
			revoke_control_button.visible = false

	# Separators: when permission buttons are visible, show both separators
	# (one before buttons, one after). When hidden, keep only the original separator.
	var any_button_visible = (
		(request_control_button and request_control_button.visible)
		or (revoke_control_button and revoke_control_button.visible)
	)
	if separator_before:
		separator_before.visible = true  # Always visible (original separator)
	if separator_after:
		separator_after.visible = any_button_visible


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
		amount = -amount

	if amount != 0:
		input_field.clear()
		hp_adjustment_requested.emit(amount)
		_update_menu_content()
		# Brief flash on the health label to confirm the change
		_flash_health_label(amount > 0)
		close_menu()


func _on_toggle_visibility_pressed() -> void:
	if target_token:
		visibility_toggled.emit()
		_update_menu_content()
		AudioManager.play_tick()


## Quick color flash on the health label after an HP change
func _flash_health_label(is_heal: bool) -> void:
	var health_label = get_node_or_null("MenuPanel/VBoxContainer/HealthLabel")
	if not health_label:
		return
	var color = Color(0.5, 0.9, 0.5) if is_heal else Color(0.9, 0.4, 0.4)
	health_label.add_theme_color_override("font_color", color)
	var tw = create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(func(): health_label.remove_theme_color_override("font_color"))


func _on_request_control_pressed() -> void:
	if target_token and is_instance_valid(target_token):
		control_requested.emit(target_token)
		# Disable button to prevent duplicate requests
		if request_control_button:
			request_control_button.disabled = true
			request_control_button.text = "Waiting..."
		UIManager.show_info("Request sent, waiting for DM...")
		AudioManager.play_tick()
		close_menu()


func _on_revoke_control_pressed() -> void:
	if target_token and is_instance_valid(target_token):
		control_revoked.emit(target_token)
		AudioManager.play_tick()
		close_menu()


func _on_close_button_pressed() -> void:
	close_menu()


func close_menu() -> void:
	menu_closed.emit()
	animate_out()


# Close menu when clicking outside or pressing Escape.
# Uses _input instead of _unhandled_input because full-screen Controls in the
# same CanvasLayer (e.g. LevelEditPanel) have mouse_filter STOP, which causes
# the GUI system to consume clicks before _unhandled_input fires.
func _input(event: InputEvent) -> void:
	if not visible or is_animating():
		return

	# Close on Escape key
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		# Check if click is outside the menu panel
		var menu_panel = get_node_or_null("MenuPanel")
		if menu_panel:
			var menu_rect = Rect2(menu_panel.global_position, menu_panel.size)
			if not menu_rect.has_point(event.position):
				close_menu()
				get_viewport().set_input_as_handled()
