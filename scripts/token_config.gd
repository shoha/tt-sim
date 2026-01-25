extends Resource
class_name TokenConfig

## Configuration resource for token creation
## Defines how a token should be built from a model scene

## The model scene to use (e.g., a Pokemon GLTF import)
@export var model_scene: PackedScene

## Optional custom animation tree scene (uses default if not set)
@export var animation_tree_scene: PackedScene

## Whether to automatically generate a convex collision shape from the mesh
@export var use_convex_collision: bool = true

## Lock physics rotation on all axes (typical for board tokens)
@export var lock_rotation: bool = true

## Initial token properties
@export_group("Token Properties")
@export var token_name: String = "Token"
@export var is_player_controlled: bool = false
@export var max_health: int = 100
