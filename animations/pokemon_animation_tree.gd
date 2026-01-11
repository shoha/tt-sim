extends Node3D

@onready var tree: AnimationTree = $AnimationTree
@export var anim_player: AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	tree.set_animation_player(tree.get_path_to(anim_player))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
