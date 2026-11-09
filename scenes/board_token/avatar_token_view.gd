class_name AvatarTokenView
extends Node3D

## The visual of an avatar token: holds the figure AvatarKit assembled from the token's
## recipe, under the token's rigid body where a pack token holds its model, so drags, leans,
## the spawn pop-in and rotation move it the same way. Built by AvatarTokenFactory.
##
## What it draws is the figure baked (AvatarFigureBake): one static MeshInstance3D, MESH_NAME,
## with one surface per part and the parts' own materials as surface overrides, so an avatar
## is a few draws instead of one per body region and casts its shadow from that one mesh
## (perf audit F-tokens-2). The assembled figure itself, `figure` (a skinned rig), stays out of
## the tree: it is the source the bake reads and what AvatarKit.apply_look and apply_stance
## change, after which the factory calls refresh_mesh. The view frees it with itself.
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
const MESH_NAME := "FigureMesh"
## The share of the figure dithered away in the GM's view of a hidden token.
const HIDDEN_FADE := 0.5
const SHADE_STEP_M := 0.2
const SUN_NAME := "LevelSunLight"
const MAP_NAME := "MapContainer"

## Draw figures baked (the default). Off, a view draws its skinned figure as before the bake:
## the perf harness's A/B (perfaudit_tokens.gd `skinned`) and a fallback; views already built
## follow on their next refresh_mesh.
static var bake_figures := true

## The assembled figure (AvatarKit.build_figure), kept out of the tree; see the header.
var figure: Node3D = null
var hidden_fade := 0.0
## The last shade value taken (tests, probes).
var shade := 0.0

var _mesh: MeshInstance3D = null
var _shaded_at := Vector3.INF
var _shaded_sun := Vector3.ZERO


func _init() -> void:
	name = NODE_NAME


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(figure) and not figure.is_inside_tree():
		figure.free()


## Replaces the figure (freeing the old one), bakes it and applies the hidden fade; the shade is
## taken again on the next frame in the tree.
func set_figure(new_figure: Node3D) -> void:
	if is_instance_valid(figure) and figure != new_figure:
		if figure.get_parent() != null:
			figure.get_parent().remove_child(figure)
		figure.queue_free()
	figure = new_figure
	if figure != null and figure.get_parent() != null and figure.get_parent() != self:
		figure.get_parent().remove_child(figure)
	refresh_mesh()
	_shaded_at = Vector3.INF


## Shows the figure as it is now: its bake (shared with every figure of the same geometry and
## pose) with its parts' current materials, the hidden fade and the last shade. Call after
## changing the figure's look or stance. With bake_figures off, the figure itself goes back
## under the view instead.
func refresh_mesh() -> void:
	if figure == null:
		if _mesh != null:
			_mesh.mesh = null
		return
	if not bake_figures:
		if _mesh != null:
			remove_child(_mesh)
			_mesh.queue_free()
			_mesh = null
		if figure.get_parent() == null:
			add_child(figure)
		AvatarKit.set_hidden_fade(self, hidden_fade)
		AvatarKit.set_shade(self, shade)
		return
	if figure.get_parent() == self:
		remove_child(figure)
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = MESH_NAME
		add_child(_mesh)
	_mesh.mesh = AvatarFigureBake.cached(figure)
	_mesh.transform = figure.transform
	var materials := {}
	for part in AvatarKit.figure_parts(figure):
		materials[String(part.name)] = part.material_override
	for i in _mesh.mesh.get_surface_count():
		_mesh.set_surface_override_material(i, materials.get(_mesh.mesh.surface_get_name(i)))
	AvatarKit.set_hidden_fade(figure, hidden_fade)
	AvatarKit.set_hidden_fade(self, hidden_fade)
	AvatarKit.set_shade(self, shade)


## The MeshInstance3D drawing the baked figure (null before a figure is set).
func figure_mesh() -> MeshInstance3D:
	return _mesh


## Dithers the figure for the GM's view of a token hidden from players, or makes it solid.
func set_hidden(hidden: bool) -> void:
	hidden_fade = HIDDEN_FADE if hidden else 0.0
	if figure != null:
		AvatarKit.set_hidden_fade(figure, hidden_fade)
		AvatarKit.set_hidden_fade(self, hidden_fade)


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
	# The view stands where the figure does; its one MeshInstance3D is the baked figure.
	if map == null:
		AvatarKit.set_shade(self, 0.0)
		shade = 0.0
		return shade
	shade = AvatarKit.update_shade(self, map, sun, AvatarShadeCache.for_map(map))
	return shade


## The level's sun (LevelEnvironmentManager adds it to the world viewport), or null.
func _sun() -> DirectionalLight3D:
	var viewport := get_viewport()
	return viewport.get_node_or_null(SUN_NAME) as DirectionalLight3D if viewport else null
