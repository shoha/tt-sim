class_name ScatterShrink
extends RefCounted

## Shrink-out for scatter instances a brush removes, the reverse of AuthoredScatter's
## grow-in: the removed instances move to a temporary MultiMeshInstance3D beside their
## chunk, which shrinks away over SECONDS and frees itself. Without it, Thin / Clear and a
## repaint make trees pop out of existence, which reads as a glitch rather than as the
## world responding. Used by AuthoredScatter (regenerated cells) and BaseScatterEraser (a
## dressed Blender map's own scatter under the erase mask).
##
## Same two modes as the grow-in: a species whose every surface is a wind ShaderMaterial
## shrinks through instance uniforms every wind shader variant reads (per node; each instance
## works out its own size in the shader); anything else (rocks, whose material has no such
## uniform) sinks into the ground by moving the temporary node. The motion itself (staged by
## size class, a swell and collapse rippling out from the brush, rocks hopping before they
## sink) is ScatterArrival's. The node is built with ScatterGlbUtils.build_chunk, so it shares
## the chunk's mesh and materials and creates nothing new.

## Long enough to read as the plant withdrawing, short enough to keep up with a stroke.
const SECONDS := 0.3
const INFIX := "_shrink"
const GROW_UNIFORM := &"grow"

static var _serial: int = 0
## Held instances, per parent (its instance id): origin -> true. A terrain event that takes
## instances down itself (ForestFall) holds them, so the rebuild that removes them lets them go
## at once instead of standing them up again to shrink.
static var _held: Dictionary = {}


## Holds the instances of `parent`'s scatter standing at `origins` (see _held).
static func hold(parent: Node, origins: Array[Vector3]) -> void:
	var id := parent.get_instance_id()
	if not _held.has(id):
		_held[id] = {}
	for origin in origins:
		_held[id][origin] = true


## Lets go of instances hold() took.
static func release(parent: Node, origins: Array[Vector3]) -> void:
	var id := parent.get_instance_id()
	var held: Dictionary = _held.get(id, {})
	for origin in origins:
		held.erase(origin)
	if held.is_empty():
		_held.erase(id)


## `transforms` without the instances `parent` holds (all of them when it holds none).
static func unheld(parent: Node, transforms: Array[Transform3D]) -> Array[Transform3D]:
	var held: Dictionary = _held.get(parent.get_instance_id(), {})
	if held.is_empty():
		return transforms
	var kept: Array[Transform3D] = []
	for xform in transforms:
		if not held.has(xform.origin):
			kept.append(xform)
	return kept


## True when `mesh` can shrink through the grow uniform (every surface a wind
## ShaderMaterial); false means it sinks instead.
static func shrinks_by_shader(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if not (material is ShaderMaterial and material.has_meta("wind_category")):
			return false
	return true


## Starts a shrink-out of `transforms` of `mesh` under `parent` (which must be in the tree)
## and returns the temporary node, or null when there is nothing to animate. `stem`,
## `suffix` and `wind_category` are the chunk's (see ScatterGlbUtils.build_chunk; the node
## is named after it plus INFIX and a serial); `sink_depth` is how far a sinking species
## travels down (its height). A grass mass's tufts keep their anchors (`anchors`, the owner's
## ScatterMass table) in custom data while they shrink, so they keep their mass's hue. `from`
## is the share of their full size they start at under ScatterArrival.classic (an instance
## removed mid-grow-in), and the shrink takes that share of `seconds`; otherwise the shrink waits
## `delay` seconds (its stage) and ripples out from `centre` (ScatterArrival.origin_of's forms).
static func start(
	parent: Node3D,
	mesh: Mesh,
	stem: String,
	suffix: String,
	transforms: Array[Transform3D],
	wind_category: String,
	sink_depth: float,
	seconds: float = SECONDS,
	anchors: Dictionary = {},
	from: float = 1.0,
	delay: float = 0.0,
	centre: Variant = null
) -> MultiMeshInstance3D:
	transforms = unheld(parent, transforms)
	if transforms.is_empty() or mesh == null or seconds <= 0.0 or not parent.is_inside_tree():
		return null
	from = clampf(from, 0.0, 1.0)
	if from < 0.01:
		return null
	_serial += 1
	var node := ScatterGlbUtils.build_chunk(
		parent, mesh, stem, transforms, wind_category, suffix + INFIX + str(_serial), anchors
	)
	if node == null:
		return null
	var by_shader := shrinks_by_shader(mesh)
	var depth := maxf(sink_depth, 0.05)
	var tween := node.create_tween()
	if ScatterArrival.classic:
		_apply(from, node, by_shader, depth)
		(
			tween
			. tween_method(_apply.bind(node, by_shader, depth), from, 0.0, seconds * from)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN)
		)
	else:
		ScatterArrival.shrink_out(tween, node, by_shader, transforms, centre, delay, depth)
	tween.tween_callback(node.queue_free)
	return node


## Shrinks out the rows at `indices` of a cell's flat `rows` (MapDocument.ROW_STRIDE) under
## `parent`, an AuthoredScatter, for its `species` record ("mesh", "stem", "wind_category",
## "stage"), from `from` of their full size. A brush landing (AuthoredScatter.landing_centre) is
## staged and ripples from its brush centre; a direct rebuild shrinks at once from the centroid.
static func start_rows(
	parent: Node3D,
	species: Dictionary,
	cell: Vector2i,
	rows: PackedFloat32Array,
	indices: PackedInt32Array,
	seconds: float,
	anchors: Dictionary,
	from: float = 1.0
) -> void:
	if indices.is_empty():
		return
	var transforms := ScatterRows.transforms_from_rows(rows, indices)
	var centre: Variant = null
	if parent is AuthoredScatter:
		centre = (parent as AuthoredScatter).landing_centre(cell)
	var delay := ScatterArrival.stage_delay(int(species.get("stage", 1))) if centre != null else 0.0
	_start_transforms(parent, species, cell, transforms, seconds, anchors, from, delay, centre)


static func _start_transforms(
	parent: Node3D,
	species: Dictionary,
	cell: Vector2i,
	transforms: Array[Transform3D],
	seconds: float,
	anchors: Dictionary,
	from: float,
	delay: float,
	centre: Variant
) -> void:
	var suffix := ScatterChunker.cell_suffix(cell)
	var depth := sink_depth_for(species.mesh, transforms)
	var wind: String = species.wind_category
	var mesh: Mesh = species.mesh
	var stem: String = species.stem
	start(parent, mesh, stem, suffix, transforms, wind, depth, seconds, anchors, from, delay, centre)


## Rows still growing in that a rebuild removes (a stroke's provisional result can drop what an
## earlier one started) shrink away from the size they had reached, instead of vanishing.
## `growing` is AuthoredScatter's list for the cell's asset ({"keys", "tween"} entries growing
## over `seconds`, with "arrival" when ScatterArrival built them: each instance then leaves from
## its own size, rippling from the same centre), `old_list` the row keys of `old_rows`, `present`
## the keys the cell keeps.
static func start_growing(
	parent: Node3D,
	species: Dictionary,
	cell: Vector2i,
	growing: Array,
	old_rows: PackedFloat32Array,
	old_list: PackedInt64Array,
	present: Dictionary,
	seconds: float,
	anchors: Dictionary
) -> void:
	for entry: Dictionary in growing:
		var entry_keys: Dictionary = entry.keys
		var gone := PackedInt32Array()
		for i in old_list.size():
			if entry_keys.has(old_list[i]) and not present.has(old_list[i]):
				gone.append(i)
		if gone.is_empty():
			continue
		if entry.has("arrival"):
			var leaving := unheld(parent, ScatterRows.transforms_from_rows(old_rows, gone))
			var by_shader := shrinks_by_shader(species.mesh)
			var shown := ScatterArrival.as_shown(entry, parent, leaving, by_shader, species.height)
			var at: Vector3 = entry.arrival.at
			_start_transforms(parent, species, cell, shown, seconds, anchors, 1.0, 0.0, at)
			continue
		var tween: Tween = entry.tween
		var t := 1.0
		if tween != null and tween.is_valid() and seconds > 0.0:
			t = clampf(tween.get_total_elapsed_time() / seconds, 0.0, 1.0)
		# The grow-in's cubic ease-out, so the shrink starts at the size on screen.
		start_rows(parent, species, cell, old_rows, gone, seconds, anchors, 1.0 - pow(1.0 - t, 3.0))


## The tallest a set of instances stands: `mesh`'s height times the largest Y scale.
static func sink_depth_for(mesh: Mesh, transforms: Array[Transform3D]) -> float:
	var tallest := 0.0
	for xform in transforms:
		tallest = maxf(tallest, xform.basis.get_scale().y)
	var height := maxf(mesh.get_aabb().end.y, 0.0) if mesh else 0.0
	return height * tallest


static func _apply(value: float, node: MultiMeshInstance3D, by_shader: bool, depth: float) -> void:
	if not is_instance_valid(node):
		return
	if by_shader:
		node.set_instance_shader_parameter(GROW_UNIFORM, value)
	else:
		node.position.y = -depth * (1.0 - value)
