class_name RootNetworkHandler

## Handles client-side network state synchronization for the Root scene.
##
## Extracted from root.gd to keep the state machine focused on state
## transitions while this class manages the token-level network updates.
## All methods are static-style helpers that take the dependencies they need,
## making them easy to test and keeping Root's footprint small.
##
## A client builds the tokens it lacks on the shared TokenSpawnQueue, a few a frame, never all
## in the frame a state lands (a late joiner's full state at 500 avatars was one 740 ms frame).
## A queued network id is built once: a second state or add for it while it waits only updates
## GameState, and the job reads GameState when it runs, so the newest state is the one built.

## Network ids whose build waits on the spawn queue, each with the ticket of its job
static var _queued: Dictionary = {}
static var _next_ticket: int = 0


## Connect client-side signals for receiving state updates
static func connect_client_signals(handler: Node) -> void:
	if not NetworkStateSync.full_state_received.is_connected(handler._on_full_state_received):
		NetworkStateSync.full_state_received.connect(handler._on_full_state_received)
	if not NetworkStateSync.tokens_added.is_connected(handler._on_tokens_added):
		NetworkStateSync.tokens_added.connect(handler._on_tokens_added)

	var game_sync := NetworkManager.game_sync
	if not game_sync.transform_batch_received.is_connected(handler._on_transform_batch_received):
		game_sync.transform_batch_received.connect(handler._on_transform_batch_received)
	if not game_sync.token_state_received.is_connected(handler._on_token_state_received):
		game_sync.token_state_received.connect(handler._on_token_state_received)
	if not game_sync.token_removed_received.is_connected(handler._on_token_removed_received):
		game_sync.token_removed_received.connect(handler._on_token_removed_received)


## Disconnect client-side state signals
static func disconnect_client_signals(handler: Node) -> void:
	if NetworkStateSync.full_state_received.is_connected(handler._on_full_state_received):
		NetworkStateSync.full_state_received.disconnect(handler._on_full_state_received)
	if NetworkStateSync.tokens_added.is_connected(handler._on_tokens_added):
		NetworkStateSync.tokens_added.disconnect(handler._on_tokens_added)
	var game_sync := NetworkManager.game_sync
	if game_sync.transform_batch_received.is_connected(handler._on_transform_batch_received):
		game_sync.transform_batch_received.disconnect(handler._on_transform_batch_received)
	if game_sync.token_state_received.is_connected(handler._on_token_state_received):
		game_sync.token_state_received.disconnect(handler._on_token_state_received)
	if game_sync.token_removed_received.is_connected(handler._on_token_removed_received):
		game_sync.token_removed_received.disconnect(handler._on_token_removed_received)


## Handle a transform message: a drag's single update or batch (unreliable) or a
## reconciliation (reliable), all TokenTransformPack messages decoded by NetworkGameSync
static func on_transform_batch_received(controller: Node, batch: Dictionary) -> void:
	for network_id in batch:
		var data = batch[network_id]
		var pos := SerializationUtils.array_to_vec3(data["position"])
		var rot := SerializationUtils.array_to_vec3(data["rotation"])
		var scl := SerializationUtils.array_to_vec3(data["scale"], Vector3.ONE)

		var token = controller.find_token_by_network_id(network_id)
		if token and is_instance_valid(token):
			token.set_interpolation_target(pos, rot, scl)


## Handle individual token property update (reliable channel, low frequency)
static func on_token_state_received(
	controller: Node, game_map: Node, network_id: String, token_dict: Dictionary
) -> void:
	var token_state = TokenState.from_dict(token_dict)

	# Update GameState using proper API (always do this, even during loading)
	GameState.set_token_state(network_id, token_state)

	# Don't create visual tokens during async loading
	if controller and controller.is_loading():
		return

	# Apply to visual token
	var token = controller.find_token_by_network_id(network_id)
	if token and is_instance_valid(token):
		token_state.apply_to_token(token)
	elif game_map:
		# Token doesn't exist: build it (once, however many states arrive meanwhile)
		queue_token_build(controller, game_map, network_id)


## Handle token removal (reliable channel)
static func on_token_removed_received(controller: Node, network_id: String) -> void:
	GameState.remove_token_state(network_id)

	var token = controller.find_token_by_network_id(network_id)
	if token and is_instance_valid(token):
		token.play_removal_animation()
	controller.untrack_network_token(network_id)


## Apply full GameState to all visual tokens (initial sync or reconciliation)
static func apply_game_state_to_tokens(controller: Node, game_map: Node) -> void:
	apply_tokens_to_board(controller, game_map, GameState.get_all_token_states().keys())


## Apply GameState's tokens `network_ids` to the board: a token already there takes its state,
## a missing one is queued for building (queue_token_build; keyed by network_id, so applying a
## token twice never duplicates it). A full state passes every id; a token add
## (NetworkStateSync.tokens_added) its own.
static func apply_tokens_to_board(
	controller: Node, game_map: Node, network_ids: Array
) -> void:
	if not controller or not game_map:
		return
	if controller.is_loading():
		return

	var drag_and_drop = game_map.drag_and_drop_node
	if not drag_and_drop:
		return

	for network_id in network_ids:
		var token_state: TokenState = GameState.get_token_state(network_id)
		if token_state == null:
			continue
		var token = controller.find_token_by_network_id(network_id)

		if token and is_instance_valid(token):
			token_state.apply_to_token(token)
			# Any active drag lock (for late joiners); a queued token takes its own when built
			_apply_drag_lock(token, network_id)
		else:
			queue_token_build(controller, game_map, network_id)


## Queue the build of GameState's token `network_id` on the shared TokenSpawnQueue, unless its
## build is already waiting there. The job reads GameState when it runs (the newest state, or
## nothing if the token was removed meanwhile) and builds nothing if the token is on the board
## by then, the board is gone or a table load has started (whose end applies the state again).
static func queue_token_build(controller: Node, game_map: Node, network_id: String) -> void:
	if _queued.has(network_id):
		return
	_next_ticket += 1
	_queued[network_id] = _next_ticket
	var spawn_queue: Variant = load("res://scenes/states/playing/token_spawn_queue.gd")
	spawn_queue.shared().enqueue(
		_build_queued.bind(
			controller.get_instance_id(), game_map.get_instance_id(), network_id, _next_ticket
		)
	)


## Whether `network_id`'s build waits on the spawn queue
static func is_build_queued(network_id: String) -> bool:
	return _queued.has(network_id)


## One spawn-queue job of queue_token_build. The controller and map come as instance ids, so
## a job outliving its table finds them gone instead of holding freed objects.
static func _build_queued(controller_id: int, map_id: int, network_id: String, ticket: int) -> void:
	if _queued.get(network_id, 0) != ticket:
		return
	_queued.erase(network_id)
	var controller := instance_from_id(controller_id) as Node
	var game_map := instance_from_id(map_id) as Node
	if controller == null or game_map == null or controller.is_loading():
		return
	var token_state: TokenState = GameState.get_token_state(network_id)
	if token_state == null or is_instance_valid(controller.find_token_by_network_id(network_id)):
		return
	var drag_and_drop: Node = game_map.drag_and_drop_node
	if not is_instance_valid(drag_and_drop):
		return
	var new_token := create_token_from_state(token_state, controller)
	if new_token == null:
		return
	drag_and_drop.add_child(new_token)
	controller.track_network_token(new_token)
	controller._connect_token_context_menu(new_token)
	_apply_drag_lock(new_token, network_id)


static func _apply_drag_lock(token: Node3D, network_id: String) -> void:
	var lock_holder := GameState.get_drag_lock(network_id)
	if lock_holder > 0:
		token.set_drag_lock(lock_holder)


## Create a BoardToken from a TokenState (for network-spawned tokens)
## @param controller: Optional LevelPlayController, used to compute interactivity
## the same way locally-driven token creation does (GM sees all tokens as
## interactive; players only tokens they hold CONTROL permission for). Without
## it, interactivity falls back to has_gm_access() only.
static func create_token_from_state(
	token_state: TokenState, controller: Node = null
) -> Node3D:
	var token: Node3D = null
	if not token_state.avatar_recipe.is_empty():
		# An avatar: rebuilt here from the recipe and this client's own kit.
		var avatar_factory: Variant = load("res://scenes/board_token/avatar_token_factory.gd")
		token = avatar_factory.create(token_state.avatar_recipe, token_state.token_name)
	else:
		if token_state.pack_id == "" or token_state.asset_id == "":
			push_warning("RootNetworkHandler: Cannot create token — missing pack_id or asset_id")
			return null

		var priority = (
			Constants.ASSET_PRIORITY_HIGH
			if token_state.is_visible_to_players
			else Constants.ASSET_PRIORITY_DEFAULT
		)

		var token_factory: Variant = load("res://scenes/board_token/board_token_factory.gd")
		var result = token_factory.create_from_asset_async(
			token_state.pack_id, token_state.asset_id, token_state.variant_id, priority
		)
		token = result.token

	if not token:
		push_error("RootNetworkHandler: Failed to create token from state")
		return null

	token.network_id = token_state.network_id
	token.set_meta("placement_id", token_state.network_id)
	token.pack_id = token_state.pack_id
	token.asset_id = token_state.asset_id
	token.variant_id = token_state.variant_id

	# Apply state without interpolation for initial placement
	token_state.apply_to_token(token, false)

	# Wire up interactivity the same way locally-driven token creation does
	# (level_play_controller.gd's _track_token / add_token_to_level). Without this,
	# DraggableToken.dragging_allowed defaults to true and a freshly
	# network-created token is draggable by clients without permission until the
	# next full sync happens to touch it.
	var is_gm = NetworkManager.has_gm_access()
	var can_interact = is_gm
	if not can_interact and controller and controller.multiplayer.multiplayer_peer:
		can_interact = GameState.has_token_permission(
			token.network_id,
			controller.multiplayer.get_unique_id(),
			TokenPermissions.Permission.CONTROL
		)
	token.set_interactive(can_interact)

	return token
