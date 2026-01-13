extends Camera3D

@onready var fsquad = $MeshInstance3D
@onready var ray_cast = $RayCast3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

 #Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	ray_cast.force_raycast_update()
	
	if ray_cast.is_colliding():
		fsquad.mesh.material.set_shader_parameter(&"focal_point", ray_cast.get_collision_point())
