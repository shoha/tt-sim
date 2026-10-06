class_name AvatarTokenView
extends Node3D

## The visual of an avatar token: holds the figure AvatarKit assembled from the token's
## recipe, under the token's rigid body where a pack token holds its model, so drags, leans,
## the spawn pop-in and rotation move it the same way. Built by AvatarTokenFactory.
##
## It owns the two per-figure values the figure shader takes:
## - `hidden_fade`, the GM's dithered view of a token hidden from players (set_hidden, from
##   BoardToken's visibility visuals; a figure's ShaderMaterial has no alpha to fade);
## - `shade`, from the figure's shade ray (AvatarKit.update_shade), taken again whenever the
##   figure has moved SHADE_STEP_M from where it was last taken or the sun has turned, so a
##   drag, a synced move, an undo and a sun edit all re-shade it without a hook in each path.
##   The ray uses the map's AvatarShadeCache, so a re-shade costs a few box tests.
## A new figure (set_figure, the builder changing the recipe) keeps both.

const NODE_NAME := "AvatarView"
## The share of the figure dithered away in the GM's view of a hidden token.
const HIDDEN_FADE := 0.5
const SHADE_STEP_M := 0.2
const SUN_NAME := "LevelSunLight"
const MAP_NAME := "MapContainer"

var figure: Node3D = null
var hidden_fade := 0.0
## The last shade value taken (tests, probes).
var shade := 0.0

var _shaded_at := Vector3.INF
var _shaded_sun := Vector3.ZERO


func _init() -> void:
	name = NODE_NAME


## Replaces the figure (freeing the old one) and applies the hidden fade; the shade is taken
## again on the next frame in the tree.
func set_figure(new_figure: Node3D) -> void:
	if figure != null:
		remove_child(figure)
		figure.queue_free()
	figure = new_figure
	add_child(figure)
	AvatarKit.set_hidden_fade(figure, hidden_fade)
	_shaded_at = Vector3.INF


## Dithers the figure for the GM's view of a token hidden from players, or makes it solid.
func set_hidden(hidden: bool) -> void:
	hidden_fade = HIDDEN_FADE if hidden else 0.0
	if figure != null:
		AvatarKit.set_hidden_fade(figure, hidden_fade)


func _process(_delta: float) -> void:
	if figure == null:
		return
	var sun := _sun()
	var sun_dir := sun.global_basis.z if sun != null and sun.is_visible_in_tree() else Vector3.ZERO
	var moved := global_position.distance_squared_to(_shaded_at) >= SHADE_STEP_M * SHADE_STEP_M
	if moved or not sun_dir.is_equal_approx(_shaded_sun):
		refresh_shade()


## Takes the shade ray now against the map this token stands on; returns the value.
func refresh_shade() -> float:
	if figure == null or not is_inside_tree():
		return shade
	_shaded_at = global_position
	var sun := _sun()
	_shaded_sun = sun.global_basis.z if sun != null and sun.is_visible_in_tree() else Vector3.ZERO
	var map := get_viewport().get_node_or_null(MAP_NAME) as Node3D
	if map == null:
		AvatarKit.set_shade(figure, 0.0)
		shade = 0.0
		return shade
	shade = AvatarKit.update_shade(figure, map, sun, AvatarShadeCache.for_map(map))
	return shade


## The level's sun (LevelEnvironmentManager adds it to the world viewport), or null.
func _sun() -> DirectionalLight3D:
	var viewport := get_viewport()
	return viewport.get_node_or_null(SUN_NAME) as DirectionalLight3D if viewport else null
