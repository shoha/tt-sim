class_name RootNetworkHandler

## Handles client-side network state synchronization for the Root scene.
##
## Extracted from root.gd to keep the state machine focused on state
## transitions while this class manages the token-level network updates.
## All methods are static-style helpers that take the dependencies they need,
## making them easy to test and keeping Root's footprint small.


## Connect client-side signals for receiving state updates
static func connect_client_signals(handler: Node) -> void:
	if not NetworkStateSync.full_state_received.is_connected(handler._on_full_state_received):
		NetworkStateSync.full_state_received.connect(handler._on_full_state_received)

	if not NetworkManager.token_transform_received.is_connected(handler._on_token_transform_received):
		NetworkManager.token_transform_received.connect(handler._on_token_transform_received)
	if not NetworkManager.transform_batch_received.is_connected(handler._on_transform_batch_received):
		NetworkManager.transform_batch_received.connect(handler._on_transform_batch_received)
	if not NetworkManager.token_state_received.is_connected(handler._on_token_state_received):
		NetworkManager.token_state_received.connect(handler._on_token_state_received)
	if not NetworkManager.token_removed_received.is_connected(handler._on_token_removed_received):
		NetworkManager.token_removed_received.connect(handler._on_token_removed_received)


## Disconnect client-side state signals
static func disconnect_client_signals(handler: Node) -> void:
	if NetworkStateSync.full_state_received.is_connected(handler._on_full_state_received):
		NetworkStateSync.full_state_received.disconnect(handler._on_full_state_received)
	if NetworkManager.token_transform_received.is_connected(handler._on_token_transform_received):
		NetworkManager.token_transform_received.disconnect(handler._on_token_transform_received)
	if NetworkManager.transform_batch_received.is_connected(handler._on_transform_batch_received):
		NetworkManager.transform_batch_received.disconnect(handler._on_transform_batch_received)
	if NetworkManager.token_state_received.is_connected(handler._on_token_state_received):
		NetworkManager.token_state_received.disconnect(handler._on_token_state_received)
	if NetworkManager.token_removed_received.is_connected(handler._on_token_removed_received):
		NetworkManager.token_removed_received.disconnect(handler._on_token_removed_received)


## Handle individual token transform update (unreliable channel, high frequency)
static func on_token_transform_received(
	controller: LevelPlayController,
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	var token = controller.spawned_tokens.get(network_id) as BoardToken
	if token and is_instance_valid(token):
		token.set_interpolation_target(pos, rot, scl)


## Handle batch transform update (unreliable channel)
static func on_transform_batch_received(
	controller: LevelPlayController, batch: Dictionary
) -> void:
	for network_id in batch:
		var data = batch[network_id]
		var pos_arr = data["position"]
		var rot_arr = data["rotation"]
		var scl_arr = data["scale"]

		var pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		var rot = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])
		var scl = Vector3(scl_arr[0], scl_arr[1], scl_arr[2])

		var token = controller.spawned_tokens.get(network_id) as BoardToken
		if token and is_instance_valid(token):
			token.set_interpolation_target(pos, rot, scl)


## Handle individual token property update (reliable channel, low frequency)
static func on_token_state_received(
	controller: LevelPlayController,
	game_map: Node,
	network_id: String,
	token_dict: Dictionary
) -> void:
	var token_state = TokenState.from_dict(token_dict)

	# Update GameState using proper API (always do this, even during loading)
	GameState.set_token_state(network_id, token_state)

	# Don't create visual tokens during async loading
	if controller and controller.is_loading():
		return

	# Apply to visual token
	var token = controller.spawned_tokens.get(network_id) as BoardToken
	if token and is_instance_valid(token):
		token_state.apply_to_token(token)
	else:
		# Token doesn't exist — create it
		var new_token = create_token_from_state(token_state)
		if new_token and game_map:
			game_map.drag_and_drop_node.add_child(new_token)
			controller.spawned_tokens[network_id] = new_token


## Handle token removal (reliable channel)
static func on_token_removed_received(
	controller: LevelPlayController, network_id: String
) -> void:
	GameState.remove_token_state(network_id)

	var token = controller.spawned_tokens.get(network_id)
	if token and is_instance_valid(token):
		token.play_removal_animation()
	controller.spawned_tokens.erase(network_id)


## Apply full GameState to all visual tokens (initial sync or reconciliation)
static func apply_game_state_to_tokens(
	controller: LevelPlayController, game_map: Node
) -> void:
	if not controller or not game_map:
		return
	if controller.is_loading():
		return

	var drag_and_drop = game_map.drag_and_drop_node
	if not drag_and_drop:
		return

	for network_id in GameState.get_all_token_states():
		var token_state: TokenState = GameState.get_token_state(network_id)
		var token = controller.spawned_tokens.get(network_id)

		if token and is_instance_valid(token):
			token_state.apply_to_token(token)
		else:
			var new_token = create_token_from_state(token_state)
			if new_token:
				drag_and_drop.add_child(new_token)
				controller.spawned_tokens[network_id] = new_token


## Create a BoardToken from a TokenState (for network-spawned tokens)
static func create_token_from_state(token_state: TokenState) -> BoardToken:
	if token_state.pack_id == "" or token_state.asset_id == "":
		push_warning("RootNetworkHandler: Cannot create token — missing pack_id or asset_id")
		return null

	var priority = (
		Constants.ASSET_PRIORITY_HIGH
		if token_state.is_visible_to_players
		else Constants.ASSET_PRIORITY_DEFAULT
	)

	var result = BoardTokenFactory.create_from_asset_async(
		token_state.pack_id, token_state.asset_id, token_state.variant_id, priority
	)

	var token = result.token
	if not token:
		push_error("RootNetworkHandler: Failed to create token from state")
		return null

	token.network_id = token_state.network_id
	token.set_meta("placement_id", token_state.network_id)
	token.set_meta("pack_id", token_state.pack_id)
	token.set_meta("asset_id", token_state.asset_id)
	token.set_meta("variant_id", token_state.variant_id)

	# Apply state without interpolation for initial placement
	token_state.apply_to_token(token, false)

	return token
