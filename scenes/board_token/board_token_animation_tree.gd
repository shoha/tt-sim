class_name BoardTokenAnimationTree
extends Node3D

## Animation tree component for BoardToken.
##
## @warning Do not create with .new() - use BoardTokenAnimationTreeFactory instead.
## This class requires its scene structure to function properly.

## The idle clip the state machine starts in (and the model's clip of that name loops).
const IDLE := &"battlewait01"

@export var anim_player: AnimationPlayer

## Set to true by BoardTokenAnimationTreeFactory - detects improper instantiation
var _factory_created: bool = false
var _board_token: BoardToken
var _state_machine: AnimationNodeStateMachinePlayback
## The viewport's TokenAnimationLod, which steps the tree while it is in the tree.
var _lod: TokenAnimationLod = null

@onready var tree: AnimationTree = $AnimationTree


func _enter_tree() -> void:
	if not _factory_created:
		push_error(
			"BoardTokenAnimationTree: Use BoardTokenAnimationTreeFactory.create(), not .new()"
		)
	# _ready registers the first time; a token moved to a new parent registers again here.
	if is_node_ready():
		_register_lod()


func _ready() -> void:
	if anim_player:
		# Set the animation player path
		tree.anim_player = tree.get_path_to(anim_player)

		# A glTF clip carries no loop flag, so a model's idle would play once and freeze. The clip
		# is shared by every token of the model (one cached scene), and setting loop_mode emits
		# `changed` even when the value is the same, which makes every mixer playing the clip
		# drop its caches and rebuild them on its next process: written once, by the first token.
		var idle := anim_player.get_animation(IDLE) if anim_player.has_animation(IDLE) else null
		if idle != null and idle.loop_mode != Animation.LOOP_LINEAR:
			idle.loop_mode = Animation.LOOP_LINEAR

		# Set root_node to the model scene (AnimationPlayer's parent) where animation tracks are valid
		# Animation tracks target paths like "Armature/Skeleton3D:bone" relative to this root
		var model_root = anim_player.get_parent()
		if model_root:
			tree.root_node = tree.get_path_to(model_root)

		# Ensure the tree is active
		tree.active = true

		_init_state_machine.call_deferred()
	else:
		push_warning("BoardTokenAnimationTree: anim_player not set")
	_connect_to_board_token()
	_register_lod()


## Hands the tree (and the players it reads, which play nothing themselves) to the viewport's
## animation level of detail (TokenAnimationLod).
func _register_lod() -> void:
	if anim_player == null or tree == null:
		return
	_lod = TokenAnimationLod.for_viewport(get_viewport())
	var sources: Array = [anim_player]
	var dummy := tree.get_node_or_null("Dummy")
	if dummy is AnimationMixer:
		sources.append(dummy)
	_lod.register(tree, _board_token, sources)


func _init_state_machine() -> void:
	_state_machine = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	# Start playing the default idle animation
	if _state_machine:
		_state_machine.travel("battlewait01")


func _exit_tree() -> void:
	if is_instance_valid(_lod):
		_lod.unregister(tree)
	_lod = null
	if _board_token and is_instance_valid(_board_token):
		if _board_token.health_changed.is_connected(_on_health_changed):
			_board_token.health_changed.disconnect(_on_health_changed)


func _connect_to_board_token() -> void:
	_board_token = _find_ancestor_board_token()
	if not _board_token:
		push_warning("BoardTokenAnimationTree: No BoardToken ancestor found.")
		return

	_board_token.health_changed.connect(_on_health_changed)


func _find_ancestor_board_token() -> BoardToken:
	var node = get_parent()
	while node:
		if node is BoardToken:
			return node
		node = node.get_parent()
	return null


func _on_health_changed(new_health: int, _max_health: int, previous_health: int) -> void:
	if not _state_machine:
		push_warning("BoardTokenAnimationTree: No state machine found.")
		return

	# A reaction plays at the full frame rate, however idle the token was.
	if is_instance_valid(_lod):
		_lod.touch(tree)
	if new_health == 0:
		_state_machine.travel("down01")
	elif previous_health > new_health:
		_state_machine.travel("damage01")
	else:
		_state_machine.travel("battlewait01")
