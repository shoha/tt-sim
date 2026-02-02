extends Node3D
class_name BoardTokenAnimationTree

## Animation tree component for BoardToken.
##
## @warning Do not create with .new() - use BoardTokenAnimationTreeFactory instead.
## This class requires its scene structure to function properly.

@onready var tree: AnimationTree = $AnimationTree
@export var anim_player: AnimationPlayer

## Set to true by BoardTokenAnimationTreeFactory - detects improper instantiation
var _factory_created: bool = false
var _board_token: BoardToken
var _state_machine: AnimationNodeStateMachinePlayback

func _enter_tree() -> void:
	if not _factory_created:
		push_error("BoardTokenAnimationTree: Use BoardTokenAnimationTreeFactory.create(), not .new()")


func _ready() -> void:
	if anim_player:
		# Set the animation player path
		tree.anim_player = tree.get_path_to(anim_player)

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


func _init_state_machine() -> void:
	_state_machine = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	# Start playing the default idle animation
	if _state_machine:
		_state_machine.travel("battlewait01")

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

	if new_health == 0:
		_state_machine.travel("down01")
	elif previous_health > new_health:
		_state_machine.travel("damage01")
	else:
		_state_machine.travel("battlewait01")
