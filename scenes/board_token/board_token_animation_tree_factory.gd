extends RefCounted
class_name BoardTokenAnimationTreeFactory

## Factory for creating BoardTokenAnimationTree instances.
##
## Usage:
##   var anim_tree = BoardTokenAnimationTreeFactory.create()

const BoardTokenAnimationTreeScene = preload("uid://syx65bd6uwbf")


static func create() -> BoardTokenAnimationTree:
	var instance = BoardTokenAnimationTreeScene.instantiate() as BoardTokenAnimationTree
	instance._factory_created = true
	return instance
