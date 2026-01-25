extends Node3D

@onready var tree: AnimationTree = $AnimationTree
@export var anim_player: AnimationPlayer

var _board_token: iBoardToken
var _state_machine: AnimationNodeStateMachinePlayback

func _ready() -> void:
	tree.set_animation_player(tree.get_path_to(anim_player))
	_init_state_machine.call_deferred()
	_connect_to_board_token()

func _init_state_machine() -> void:
	_state_machine = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

func _connect_to_board_token() -> void:
	_board_token = _find_ancestor_board_token()
	if not _board_token:
		push_warning("PokemonAnimationTree: No BoardToken ancestor found.")
		return

	_board_token.health_changed.connect(_on_health_changed)

func _find_ancestor_board_token() -> iBoardToken:
	var node = get_parent()
	while node:
		if node is iBoardToken:
			return node
		node = node.get_parent()
	return null

func _on_health_changed(new_health: int, _max_health: int, previous_health: int) -> void:
	if not _state_machine:
		push_warning("PokemonAnimationTree: No state machine found.")
		return

	if new_health == 0:
		_state_machine.travel("down01")
	elif previous_health > new_health:
		_state_machine.travel("damage01")
	else:
		_state_machine.travel("battlewait01")
