class_name TokenContextMenuController
extends Node

## Manages the token right-click context menu for GameMap: instantiates the
## TokenContextMenu scene, wires its signals, and handles the HP adjustment,
## visibility toggle, transform reset, and control-permission requests it
## emits.
##
## Created as a child Node of GameMap in _ready() (mirrors the AssetManager
## facade/sub-component pattern). Reads _action_history off the injected
## GameMap reference at call time -- ownership of _action_history stays on
## GameMap since other sub-components also need it.

var _game_map: GameMap = null
var _context_menu = null  # TokenContextMenu - dynamically typed to avoid load order issues


## Wire this controller to its owning GameMap and instantiate the context menu.
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_setup_context_menu()


func _setup_context_menu() -> void:
	# Load and add the context menu to the UI layer
	var context_menu_scene = load("uid://bh84knb3smm3y")
	if context_menu_scene:
		_context_menu = context_menu_scene.instantiate()
		# Find the GameplayMenu canvas layer to add the menu to
		var menu_control = (
			_game_map.gameplay_menu.get_node_or_null("GameplayMenu")
			if _game_map.gameplay_menu
			else null
		)
		if menu_control:
			menu_control.add_child(_context_menu)
		else:
			# Fallback: add to the scene root if GameplayMenu not found
			_game_map.add_child(_context_menu)

		# Connect context menu signals
		_context_menu.hp_adjustment_requested.connect(_on_context_menu_hp_adjustment_requested)
		_context_menu.max_hp_changed.connect(_on_context_menu_max_hp_changed)
		_context_menu.visibility_toggled.connect(_on_context_menu_visibility_toggled)
		_context_menu.reset_transform_requested.connect(_on_context_menu_reset_transform)
		_context_menu.control_requested.connect(_on_context_menu_control_requested)
		_context_menu.control_revoked.connect(_on_context_menu_control_revoked)
		_context_menu.control_assign_requested.connect(_on_context_menu_control_assign_requested)


## Open the context menu for a token at the given screen position.
## Called from GameMap's _on_token_context_menu_requested() forward, which
## LevelPlayController connects directly to each token's own
## context_menu_requested signal.
func open_for_token(token: BoardToken, menu_position: Vector2) -> void:
	if _context_menu:
		_context_menu.open_for_token(token, menu_position)


func _on_context_menu_hp_adjustment_requested(amount: int) -> void:
	if not _context_menu or not _context_menu.target_token:
		return
	var token: BoardToken = _context_menu.target_token
	if _game_map._action_history and NetworkManager.has_gm_access():
		(
			_game_map
			. _action_history
			. record_property_change(
				token.network_id,
				"current_health",
				token.current_health,
				clamp(token.current_health + amount, 0, token.max_health),
			)
		)
	if amount > 0:
		token.heal(amount)
	else:
		token.take_damage(amount)


func _on_context_menu_max_hp_changed(new_max: int) -> void:
	if not _context_menu or not _context_menu.target_token:
		return
	var token: BoardToken = _context_menu.target_token
	if _game_map._action_history and NetworkManager.has_gm_access():
		var was_full: bool = token.current_health == token.max_health
		var changes: Array[Dictionary] = []
		(
			changes
			. append(
				{
					"network_id": token.network_id,
					"property": "max_health",
					"old_value": token.max_health,
					"new_value": new_max,
					"description": "max HP %d -> %d" % [token.max_health, new_max],
				}
			)
		)
		if was_full and new_max != token.max_health:
			(
				changes
				. append(
					{
						"network_id": token.network_id,
						"property": "current_health",
						"old_value": token.current_health,
						"new_value": new_max,
						"description": "HP adjusted with max",
					}
				)
			)
		_game_map._action_history.record_compound_property_change(changes)
	token.set_max_health(new_max)


func _on_context_menu_visibility_toggled() -> void:
	if not _context_menu or not _context_menu.target_token:
		return
	var token: BoardToken = _context_menu.target_token
	if _game_map._action_history and NetworkManager.has_gm_access():
		(
			_game_map
			. _action_history
			. record_property_change(
				token.network_id,
				"is_visible_to_players",
				token.is_visible_to_players,
				not token.is_visible_to_players,
			)
		)
	token.toggle_visibility()


func _on_context_menu_reset_transform() -> void:
	if not _context_menu or not _context_menu.target_token:
		return
	var token: BoardToken = _context_menu.target_token
	if _game_map._action_history and NetworkManager.has_gm_access():
		var rigid_body := token.get_rigid_body()
		if rigid_body:
			(
				_game_map
				. _action_history
				. record_compound_property_change(
					(
						[
							{
								"network_id": token.network_id,
								"property": "rotation",
								"old_value": rigid_body.global_rotation,
								"new_value": Vector3.ZERO,
								"description": "reset transform",
							},
							{
								"network_id": token.network_id,
								"property": "scale",
								"old_value": rigid_body.scale,
								"new_value": Vector3.ONE,
								"description": "reset transform",
							},
						]
						as Array[Dictionary]
					)
				)
			)
	var controller := token.get_node_or_null("BoardTokenController") as BoardTokenController
	if controller:
		controller._reset_rotation_and_scale()


func _on_context_menu_control_requested(token: BoardToken) -> void:
	# Player requests CONTROL permission — send RPC to host
	if NetworkManager.is_client() and is_instance_valid(token):
		NetworkManager.permissions.request_token_permission(
			token.network_id, TokenPermissions.Permission.CONTROL
		)


func _on_context_menu_control_revoked(token: BoardToken) -> void:
	# DM revokes CONTROL permission for all players on this token
	if GameState.has_authority() and is_instance_valid(token):
		var controlling_peers = GameState.get_peers_with_permission(
			token.network_id, TokenPermissions.Permission.CONTROL
		)
		for peer_id in controlling_peers:
			GameState.revoke_token_permission(
				token.network_id, peer_id, TokenPermissions.Permission.CONTROL
			)
		# Broadcast updated permissions
		if NetworkManager.is_host():
			NetworkManager.permissions.broadcast_token_permissions(
				TokenPermissions.to_dict(GameState.get_token_permissions())
			)
			UIManager.show_info("Token control revoked")


func _on_context_menu_control_assign_requested(token: BoardToken) -> void:
	# DM assigns CONTROL permission — show player selection popup
	if not GameState.has_authority() or not is_instance_valid(token):
		return

	var players = NetworkManager.get_players()
	if players.size() <= 1:
		UIManager.show_warning("No players connected")
		return

	var dialog_scene = load("res://scenes/ui/player_selection_dialog.tscn")
	var dialog = dialog_scene.instantiate()
	get_tree().root.add_child(dialog)

	# Exclude host (peer_id 1) from the list
	var exclude: Array[int] = [1]
	var token_name: String = ""
	var token_state = GameState.get_token_state(token.network_id)
	if token_state:
		token_name = token_state.token_name

	dialog.setup('Assign Control: "%s"' % token_name, players, exclude)
	dialog.player_selected.connect(
		func(peer_id: int): _grant_token_control(token, peer_id),
		CONNECT_ONE_SHOT,
	)


func _grant_token_control(token: BoardToken, peer_id: int) -> void:
	if not is_instance_valid(token):
		return
	if not NetworkManager.get_players().has(peer_id):
		UIManager.show_warning("Player disconnected")
		return

	GameState.grant_token_permission(token.network_id, peer_id, TokenPermissions.Permission.CONTROL)

	if NetworkManager.is_host():
		# Broadcast updated permissions to all clients
		NetworkManager.permissions.broadcast_token_permissions(
			TokenPermissions.to_dict(GameState.get_token_permissions())
		)

		# Notify the assigned player
		NetworkManager.permissions.send_permission_response(
			peer_id, token.network_id, TokenPermissions.Permission.CONTROL, true
		)

		# Toast on host
		var token_state = GameState.get_token_state(token.network_id)
		var token_name: String = token_state.token_name if token_state else "token"
		var players = NetworkManager.get_players()
		var player_name: String = (
			players[peer_id].get("name", "Player") if players.has(peer_id) else "Player"
		)
		UIManager.show_success('%s can now control "%s"' % [player_name, token_name])
