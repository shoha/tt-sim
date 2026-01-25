extends RefCounted
class_name BoardTokenAnimationTreeFactory

## Factory for creating BoardToken instances from model scenes
## Centralizes all scene construction and component wiring logic
##
## Usage:
##   var token = BoardTokenFactory.create_from_scene(my_model_scene)
##   # or with config:
##   var token = BoardTokenFactory.create_from_config(my_token_config)

const iBoardTokenAnimationTreeScene = preload("uid://syx65bd6uwbf")

static func create() -> iBoardTokenAnimationTree:
	return iBoardTokenAnimationTreeScene.instantiate() as iBoardTokenAnimationTree
