extends Node3D
class_name BoardToken

## Represents a PC or NPC token on the game board.
## Manages entity data like health, visibility, status, and visual feedback.
## Separated from interaction logic (BoardTokenController) and drag mechanics (DraggableToken).
##
## @warning Do not create with BoardToken.new() - use BoardTokenFactory instead.
## This class requires its scene structure to function properly.
##
## Runtime Scene Tree Structure (built by BoardTokenFactory):
## BoardToken (Node3D) - this script
## ├── DraggingObject3D (DraggableToken)
## │   └── RigidBody3D
## │       ├── CollisionShape3D
## │       ├── SelectionGlow (SelectionGlowRenderer) - hover/selection highlight
## │       ├── Model Scene (Armature, etc.)
## │       └── AnimationTree
## └── BoardTokenController
##
## HIGHLIGHT SYSTEM:
## Tokens can be visually highlighted via set_highlighted(bool). This shows/hides
## a glowing disc beneath the token using SelectionGlowRenderer. By default,
## BoardTokenController triggers this on mouse hover, but it can also be used
## for selection, targeting, or other visual states.
##
##   token.set_highlighted(true)           # Show glow
##   token.set_highlighted(false)          # Hide glow
##   token.set_highlight_color(Color.RED)  # Change glow color
##
## Usage:
##   Use BoardTokenFactory.create_from_scene() or BoardTokenFactory.create_from_config()
##   to create properly configured BoardToken instances.

## Set to true by BoardTokenFactory - detects improper instantiation
var _factory_created: bool = false

# Network identification - stable unique ID for network synchronization
@export var network_id: String = ""

# Entity identification
@export var token_name: String = "Token"
@export var is_player_controlled: bool = false
@export var character_id: String = ""

# Health and status
@export var max_health: int = 100
@export var current_health: int = 100
@export var is_alive: bool = true

# Visibility and game state
@export var is_visible_to_players: bool = true
@export var is_hidden_from_gm: bool = false

# Selection/highlight state
var is_highlighted: bool = false

# Status effects (could be expanded to a proper status effect system)
@export var status_effects: Array[String] = []

# Spawn/removal animation constants
const SPAWN_ANIM_DURATION: float = 0.25
const REMOVAL_ANIM_DURATION: float = 0.2

# References to child components (set by BoardTokenFactory)
var _dragging_object: DraggableToken
var _token_controller: BoardTokenController
var _selection_glow: SelectionGlowRenderer
var rigid_body: RigidBody3D
var _spawn_tween: Tween
var _removal_tween: Tween
var _spawn_target_scale: Vector3 = Vector3.ONE

# Signals for game state changes
signal health_changed(new_health: int, max_health: int)
signal health_depleted
signal died
signal revived
signal token_visibility_changed(is_visible: bool)
signal status_effect_added(effect: String)
signal status_effect_removed(effect: String)
signal position_changed
signal rotation_changed
signal scale_changed
signal transform_updated  # Emitted during continuous manipulation (drag/rotate/scale)
signal highlight_changed(is_highlighted: bool)


func _enter_tree() -> void:
	if not _factory_created:
		push_error("BoardToken: Use BoardTokenFactory.create_from_scene(), not .new()")


## Set interpolation target (called by network sync on clients)
## Delegates to DraggableToken for smooth movement with lean effects
func set_interpolation_target(p_position: Vector3, p_rotation: Vector3, p_scale: Vector3) -> void:
	if _dragging_object:
		_dragging_object.set_network_target(p_position, p_rotation, p_scale)
	elif rigid_body:
		# Fallback if no draggable component
		rigid_body.global_position = p_position
		rigid_body.global_rotation = p_rotation
		rigid_body.scale = p_scale


## Directly set transform without interpolation (for initial placement or host)
func set_transform_immediate(p_position: Vector3, p_rotation: Vector3, p_scale: Vector3) -> void:
	if _dragging_object:
		_dragging_object.set_transform_immediate(p_position, p_rotation, p_scale)
	elif rigid_body:
		if rigid_body.is_inside_tree():
			rigid_body.global_position = p_position
			rigid_body.global_rotation = p_rotation
		else:
			rigid_body.position = p_position
			rigid_body.rotation = p_rotation
		rigid_body.scale = p_scale


# Health management
func take_damage(amount: int) -> void:
	if not is_alive:
		return

	var old_health = current_health
	current_health = max(0, current_health + amount)
	health_changed.emit(current_health, max_health, old_health)

	if current_health == 0 and old_health > 0:
		health_depleted.emit()
		_on_health_depleted()


func heal(amount: int) -> void:
	if not is_alive:
		return

	var old_health = current_health
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health, old_health)


func set_max_health(new_max: int) -> void:
	max_health = new_max
	current_health = min(current_health, max_health)
	health_changed.emit(current_health, max_health)


func _on_health_depleted() -> void:
	is_alive = false
	died.emit()


func revive(health_amount: int = -1) -> void:
	if is_alive:
		return

	is_alive = true
	if health_amount < 0:
		current_health = max_health
	else:
		current_health = min(health_amount, max_health)

	revived.emit()
	health_changed.emit(current_health, max_health)


# Visibility management
func set_visible_to_players(is_visible_value: bool) -> void:
	is_visible_to_players = is_visible_value
	token_visibility_changed.emit(is_visible_value)
	_update_visibility_visuals()


func toggle_visibility() -> void:
	set_visible_to_players(not is_visible_to_players)


func _update_visibility_visuals() -> void:
	# Apply visual feedback when visibility is toggled
	# GM sees hidden tokens as semi-transparent, players don't see them at all
	if rigid_body:
		if is_visible_to_players:
			# Visible to everyone
			rigid_body.visible = true
			_set_mesh_transparency(rigid_body, 1.0)
		elif NetworkManager.is_gm() or not NetworkManager.is_networked():
			# GM/local: show as semi-transparent so they can still see and interact
			rigid_body.visible = true
			_set_mesh_transparency(rigid_body, 0.4)
		else:
			# Player: completely hidden
			rigid_body.visible = false


# Highlight/selection management
func set_highlighted(highlighted: bool) -> void:
	if is_highlighted == highlighted:
		return

	is_highlighted = highlighted
	_update_highlight_visuals()
	highlight_changed.emit(is_highlighted)


func toggle_highlight() -> void:
	set_highlighted(not is_highlighted)


func _update_highlight_visuals() -> void:
	if _selection_glow:
		if is_highlighted:
			_selection_glow.show_glow()
		else:
			_selection_glow.hide_glow()


## Set the highlight glow color
func set_highlight_color(color: Color) -> void:
	if _selection_glow:
		_selection_glow.set_glow_color(color)


func _set_mesh_transparency(node: Node, alpha: float) -> void:
	# Recursively find all MeshInstance3D nodes and set their transparency
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			# Modify transparency on each surface material
			for i in range(mesh_instance.get_surface_override_material_count()):
				var mat = mesh_instance.get_surface_override_material(i)
				if mat == null and mesh_instance.mesh:
					# Get the mesh's material and create an override
					mat = mesh_instance.mesh.surface_get_material(i)
					if mat:
						mat = mat.duplicate()
						mesh_instance.set_surface_override_material(i, mat)
				if mat is StandardMaterial3D:
					var std_mat := mat as StandardMaterial3D
					std_mat.transparency = (
						BaseMaterial3D.TRANSPARENCY_ALPHA
						if alpha < 1.0
						else BaseMaterial3D.TRANSPARENCY_DISABLED
					)
					std_mat.albedo_color.a = alpha
		# Recurse into children
		_set_mesh_transparency(child, alpha)


# Status effect management
func add_status_effect(effect: String) -> void:
	if not status_effects.has(effect):
		status_effects.append(effect)
		status_effect_added.emit(effect)


func remove_status_effect(effect: String) -> void:
	if status_effects.has(effect):
		status_effects.erase(effect)
		status_effect_removed.emit(effect)


func has_status_effect(effect: String) -> bool:
	return status_effects.has(effect)


func clear_status_effects() -> void:
	for effect in status_effects:
		status_effect_removed.emit(effect)
	status_effects.clear()


# Getters for component access
func get_draggable_component() -> DraggableToken:
	return _dragging_object


func get_controller_component() -> Node:
	return _token_controller


func get_rigid_body() -> RigidBody3D:
	return rigid_body


func get_selection_glow() -> SelectionGlowRenderer:
	return _selection_glow


## Enable or disable all user interaction with this token (dragging, rotating, scaling, context menu)
## Used to make tokens view-only for clients in multiplayer
func set_interactive(enabled: bool) -> void:
	if rigid_body:
		rigid_body.input_ray_pickable = enabled


## Play a bouncy pop-in spawn animation.
## delay: seconds to wait before starting (use for staggered batch spawns).
func play_spawn_animation(delay: float = 0.0) -> void:
	if not rigid_body:
		return

	# Remember the intended scale and start at near-zero
	_spawn_target_scale = rigid_body.scale
	rigid_body.scale = Vector3(0.01, 0.01, 0.01)

	if _spawn_tween and _spawn_tween.is_valid():
		_spawn_tween.kill()

	_spawn_tween = create_tween()
	if delay > 0.0:
		_spawn_tween.tween_interval(delay)
	(
		_spawn_tween
		. tween_property(rigid_body, "scale", _spawn_target_scale, SPAWN_ANIM_DURATION)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


## Play a shrink-out removal animation, then queue_free() on completion.
func play_removal_animation() -> void:
	if not rigid_body:
		queue_free()
		return

	# Disable input so the token can't be interacted with during removal
	rigid_body.input_ray_pickable = false

	if _removal_tween and _removal_tween.is_valid():
		_removal_tween.kill()

	_removal_tween = create_tween()
	(
		_removal_tween
		. tween_property(rigid_body, "scale", Vector3(0.01, 0.01, 0.01), REMOVAL_ANIM_DURATION)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_IN)
	)
	_removal_tween.tween_callback(queue_free)


## Asynchronously load a model and upgrade this placeholder token.
## Called when the token enters the tree (for local uncached models) or when
## a downloaded asset becomes available (for remote assets).
## GLB parsing runs entirely on a background thread via GlbUtils, so the
## main thread is never blocked during the load.
func _async_upgrade_placeholder(model_path: String) -> void:
	# Load the model asynchronously (runs on background thread, no main-thread hitch)
	var model = await AssetPackManager.get_model_instance_from_path(model_path, false)
	if not model:
		push_error("BoardToken: Failed to load model for placeholder upgrade: " + model_path)
		return

	# Validate we're still valid (token might have been freed during async load)
	if not is_instance_valid(self) or not is_inside_tree():
		model.queue_free()
		return

	# Yield one more frame so the model caching / duplicate that just finished
	# doesn't share a frame with the model swap + first-render shader compilation
	await get_tree().process_frame

	# Re-validate after yield (token might have been freed)
	if not is_instance_valid(self) or not is_inside_tree():
		model.queue_free()
		return

	# Perform the fast synchronous swap now that the model is loaded/cached
	BoardTokenFactory.apply_model_upgrade(self, model)
