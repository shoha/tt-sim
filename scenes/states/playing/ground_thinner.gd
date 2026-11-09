class_name GroundThinner
extends Node

## Feeds the camera's zoom to FoliageDensityController: each frame it reads the orthographic
## size, turns it into the share of ground cover to draw (keep_fraction) and, only when that
## share has moved a step, re-sizes the ground chunks. A frame that changes nothing costs a
## comparison. The eye view (a perspective camera at the ground) draws all of it.
##
## Created by GameMap and given the map so it can read the camera and the Home zoom: a map whose
## home view is zoomed further out than FoliageDensityController.FULL_UNTIL_SIZE keeps all of its
## ground cover at home.

var _game_map: GameMap = null


## Binds the thinner to `game_map`, whose camera and camera controller it reads.
func setup(game_map: GameMap) -> void:
	_game_map = game_map


func _process(_delta: float) -> void:
	if _game_map == null or _game_map.camera_node == null:
		return
	FoliageDensityController.set_fraction(get_tree(), target_fraction())


## The share of ground cover to draw for the camera as it is now.
func target_fraction() -> float:
	var camera := _game_map.camera_node
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return 1.0
	var controller := _game_map.get_camera_controller()
	# CameraController forwards its orbit view's Home zoom under the old private name.
	var home := float(controller.get("_home_zoom")) if controller != null else 0.0
	return FoliageDensityController.keep_fraction(camera.size, home)
