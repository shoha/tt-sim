class_name ForestFall
extends Node3D

## A stand of trees falling (TerrainEvent.Kind.FOREST_FALL), played on one board. The trees
## are the map's own scatter instances: the drawn tree instances (wind category "tree", within
## the density budget's visible count) standing within the event's radius, the nearest
## MAX_TREES of them, are hidden in their chunk's MultiMesh (scaled to nothing in place) and
## drawn instead by one stand-in MultiMesh per species with the same mesh and materials, whose
## transforms this animates. They topple away from the centre in a ripple: the nearest go
## first, each eased in like a falling trunk, with a small rebound where it lands and a soft
## dust puff over its crown, then they settle into the ground under the dust.
##
## A falling tree goes still: the stand-in's instance colour multiplies the mesh's authored
## wind weights (vertex COLOR: R sway, G flutter), and calm_weight() takes both to 0 over the
## first part of its fall. That stops its sway and flutter, and the canopy fade, which always
## keeps a trunk (flutter under CANOPY_LIMB_FLUTTER), keeps the whole tree: a crown lying in
## front of the view centre stays whole instead of dissolving card by card, which left bare
## logs. A tree waiting for the ripple keeps colour 1, so it matches the tree it replaced.
##
## The map change follows as a Clear over the area (TerrainEvents), and its rebuild drops the
## hidden instances; ScatterShrink holds their origins meanwhile, so that rebuild lets them go
## at once instead of shrinking them away from upright. When the rebuild never comes (the op
## was refused), release() lets go of the holds and has the scatter rebuild the area, which
## stands the trees up again.
##
## Lives under the map root (the map frame, as AuthoredScatter is), made by TerrainEvents.
## Cost: the search is one pass over the rows of the cells the circle touches; each frame sets
## at most MAX_TREES stand-in transforms and steps the puff pool.

const MAX_TREES := 48
## The ripple: the farthest tree starts this long after the nearest, plus up to RIPPLE_JITTER.
const RIPPLE_S := 0.6
const RIPPLE_JITTER := 0.15
## The share of its fall a tree leans at once, before it tips past its balance.
const LEAN := 0.14
## A fall's length, and the range of angles a tree comes to rest at (from upright; rest_angle).
const FALL_S := Vector2(0.8, 1.0)
const REST_DEG := Vector2(62.0, 88.0)
## How much of its radius a resting crown keeps above the ground (the rest gives a little).
const CROWN_PROP := 0.7
## The rebound where it lands: degrees, over seconds.
const BOUNCE_DEG := 5.0
const BOUNCE_S := 0.25
## How long a fallen tree lies, then how long it takes to settle away.
const LIE_S := 0.15
const SETTLE_S := 0.45
## Spread of each tree's direction around "away from the centre".
const SWAY_DEG := 16.0
## The share of its fall over which a tree's wind weights go to 0 (calm_weight).
const CALM := 0.4
## Warm sunlit dust: golden ochre, well see-through, so overlapping puffs stay dust rather than
## the cream mass that read as cotton in the third look.
const DUST := Color(0.9, 0.76, 0.52, 0.4)
const TREE_CATEGORY := "tree"

var duration: float = 2.8
## Per tree: {"stand_in": MultiMeshInstance3D, "slot", "base": Transform3D, "axis", "height",
## "dir": Vector3, "start", "fall", "rest", "landed"}
var _trees: Array[Dictionary] = []
var _scatter: AuthoredScatter = null
var _origins: Array[Vector3] = []
var _cells: Dictionary = {}
var _area := Rect2()
var _applied_after_end := {}
var _ended := false
var _puffs: EventPuffs = null
var _rng := RandomNumberGenerator.new()


## The drawn tree instances of `scatter` standing within `radius` of map point `centre`, the
## nearest `limit` of them, nearest first: [{"node": the chunk's MultiMeshInstance3D, "index":
## its instance, "base": the instance's transform, "distance"}].
static func trees_near(
	scatter: AuthoredScatter, centre: Vector2, radius: float, limit: int = MAX_TREES
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if scatter == null:
		return found
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var low := ScatterChunker.cell_for(Vector3(centre.x - radius, 0, centre.y - radius), size)
	var high := ScatterChunker.cell_for(Vector3(centre.x + radius, 0, centre.y + radius), size)
	for cx in range(low.x, high.x + 1):
		for cz in range(low.y, high.y + 1):
			var cell := Vector2i(cx, cz)
			var rows_by_asset := scatter.cell_rows(cell)
			for asset_id: String in rows_by_asset:
				_collect(scatter, cell, asset_id, rows_by_asset[asset_id], centre, radius, found)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	if found.size() > limit:
		found.resize(limit)
	return found


static func _collect(
	scatter: AuthoredScatter,
	cell: Vector2i,
	asset_id: String,
	rows: PackedFloat32Array,
	centre: Vector2,
	radius: float,
	found: Array[Dictionary]
) -> void:
	var node := scatter.get_cell_node(cell, asset_id)
	if node == null or node.multimesh == null:
		return
	if String(node.get_meta("wind_foliage_category", "")) != TREE_CATEGORY:
		return
	if not scatter.get_growing_nodes(cell, asset_id).is_empty():
		return
	var stride := MapDocument.ROW_STRIDE
	var keys := AuthoredScatter.row_keys(rows.to_byte_array().to_int32_array())
	var all := PackedInt32Array()
	all.resize(keys.size())
	for i in keys.size():
		all[i] = i
	var order := ScatterRows.instance_order(keys, all, AuthoredScatter.node_name_for(asset_id, cell))
	var visible := node.multimesh.visible_instance_count
	var drawn := order.size() if visible < 0 else mini(visible, order.size())
	for i in drawn:
		var row := order[i]
		var at := Vector2(rows[row * stride], rows[row * stride + 2])
		var distance := at.distance_to(centre)
		if distance <= radius:
			found.append(
				{
					"node": node,
					"index": i,
					"base": ScatterRows.row_transform(rows, row),
					"distance": distance,
				}
			)


## Prepares the fall `event` describes on `editor`'s map; false when no tree stands there.
func setup(editor: AuthoringEditor, event: TerrainEvent) -> bool:
	name = "ForestFall"
	duration = event.duration_s
	_rng.seed = event.seed_value
	_scatter = editor.scatter
	var found := trees_near(_scatter, event.centre, event.radius_m)
	if found.is_empty():
		return false
	_puffs = EventPuffs.new()
	add_child(_puffs)
	_area = Rect2(event.centre - Vector2.ONE * event.radius_m, Vector2.ONE * event.radius_m * 2.0)
	var by_mesh := {}
	for tree in found:
		var mesh: Mesh = (tree.node as MultiMeshInstance3D).multimesh.mesh
		if not by_mesh.has(mesh):
			by_mesh[mesh] = []
		(by_mesh[mesh] as Array).append(tree)
	for mesh: Mesh in by_mesh:
		_stand_in(mesh, by_mesh[mesh], event)
	ScatterShrink.hold(_scatter, _origins)
	_scatter.cells_applied.connect(_on_cells_applied)
	return true


## Plays the fall `elapsed` seconds in (after `delta` more seconds of puffs).
func step(elapsed: float, delta: float) -> void:
	for tree in _trees:
		var multimesh := (tree.stand_in as MultiMeshInstance3D).multimesh
		multimesh.set_instance_transform(tree.slot, _tree_transform(tree, elapsed))
		var calm := calm_weight(elapsed - float(tree.start), float(tree.fall))
		multimesh.set_instance_color(tree.slot, Color(calm, calm, 1.0, 1.0))
	_puffs.step(delta)
	if elapsed >= duration and not _ended:
		_ended = true
		for tree in _trees:
			(tree.stand_in as Node3D).visible = false


## True once the fall has played and its dust has settled.
func is_played(elapsed: float) -> bool:
	return elapsed >= duration and _puffs.is_idle()


## Whether the scatter has rebuilt every cell a fallen tree stood in since the fall ended (the
## Clear landed: the hidden instances are gone).
func is_removed() -> bool:
	return _ended and _applied_after_end.size() >= _cells.size()


## Lets go of the held instances; when their cells were never rebuilt, has the scatter rebuild
## the area, which stands any tree whose row is still there up again.
func release() -> void:
	if not is_instance_valid(_scatter):
		return
	if _scatter.cells_applied.is_connected(_on_cells_applied):
		_scatter.cells_applied.disconnect(_on_cells_applied)
	ScatterShrink.release(_scatter, _origins)
	if not is_removed() and _area.has_area():
		_scatter.request_region(_area)


func _on_cells_applied(cells: Array[Vector2i]) -> void:
	if not _ended:
		return
	for cell in cells:
		if _cells.has(cell):
			_applied_after_end[cell] = true


## One stand-in MultiMesh of `mesh` for `trees`, which it hides in their chunks.
func _stand_in(mesh: Mesh, trees: Array, event: TerrainEvent) -> void:
	var transforms: Array[Transform3D] = []
	for tree: Dictionary in trees:
		transforms.append(tree.base)
	var node := MultiMeshInstance3D.new()
	node.name = "Fallen%d" % get_child_count()
	# Instance colours (white: the authored wind weights as they are) let a falling tree go
	# still (calm_weight); use_colors is set before the count, as MultiMesh requires.
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, Color.WHITE)
	node.multimesh = multimesh
	node.set_meta("wind_foliage_category", TREE_CATEGORY)
	# A falling crown sweeps well past the standing tree's box.
	node.extra_cull_margin = maxf(mesh.get_aabb().size.y, 4.0)
	add_child(node)
	var box := mesh.get_aabb()
	var height := maxf(box.end.y, 1.0)
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	for slot in trees.size():
		var tree: Dictionary = trees[slot]
		var base: Transform3D = tree.base
		var chunk: MultiMeshInstance3D = tree.node
		chunk.multimesh.set_instance_transform(
			tree.index, Transform3D(Basis.from_scale(Vector3.ZERO), base.origin)
		)
		_origins.append(base.origin)
		_cells[ScatterChunker.cell_for(base.origin, size)] = true
		var away := Vector2(base.origin.x, base.origin.z) - event.centre
		var heading := away.angle() if away.length() > 0.3 else _rng.randf_range(0.0, TAU)
		heading += deg_to_rad(_rng.randf_range(-SWAY_DEG, SWAY_DEG))
		var dir := Vector3(cos(heading), 0.0, sin(heading))
		var reach := float(tree.distance) / maxf(event.radius_m, 0.1)
		_trees.append(
			{
				"stand_in": node,
				"slot": slot,
				"base": base,
				"axis": Vector3.UP.cross(dir).normalized(),
				"dir": dir,
				"height": height * base.basis.get_scale().y,
				"start": RIPPLE_S * reach + _rng.randf_range(0.0, RIPPLE_JITTER),
				"fall": _rng.randf_range(FALL_S.x, FALL_S.y),
				"rest": rest_angle(box, base.basis.get_scale()) + deg_to_rad(_rng.randf_range(-3, 3)),
				"landed": false,
			}
		)


## The angle from upright a tree of mesh bounds `box` at instance `scale` comes to rest at:
## propped on its crown, whose underside meets the ground (a crown of radius r centred d up
## the trunk rests the trunk at acos(r / d) from upright, eased by CROWN_PROP since a crown
## gives a little), within REST_DEG. Lying flat at 90 degrees, a broad crown sank half into the
## ground and left a bare log (the first full-size look). Pure.
static func rest_angle(box: AABB, scale: Vector3) -> float:
	var radius := maxf(box.size.x, box.size.z) * 0.5 * maxf(scale.x, scale.z)
	var reach := (box.position.y + box.size.y * 0.6) * scale.y
	if reach <= 0.01:
		return deg_to_rad(REST_DEG.y)
	var angle := acos(clampf(CROWN_PROP * radius / reach, 0.0, 1.0))
	return clampf(angle, deg_to_rad(REST_DEG.x), deg_to_rad(REST_DEG.y))


## The multiplier on a tree's wind weights `t` seconds after it starts a fall of `fall`
## seconds: 1 until it starts (it matches the standing tree it replaced), easing to 0 by CALM
## of the fall, so it goes still and the canopy fade keeps its whole crown (see the header).
## Pure.
static func calm_weight(t: float, fall: float) -> float:
	if t <= 0.0:
		return 1.0
	return 1.0 - smoothstep(0.0, maxf(fall * CALM, 0.01), t)


## A tree `elapsed` seconds into the fall: standing, falling (accelerating like a trunk that
## tips past its balance), rebounding where it lands, lying, then settling into the ground.
func _tree_transform(tree: Dictionary, elapsed: float) -> Transform3D:
	var base: Transform3D = tree.base
	var t := elapsed - float(tree.start)
	if t <= 0.0:
		return base
	var fall := float(tree.fall)
	var rest := float(tree.rest)
	var angle := rest
	var settle := 0.0
	if t < fall:
		# A quick creaking lean first, so the start reads, then the trunk's accelerating fall.
		var x := t / fall
		var lean := LEAN * sin(minf(x / 0.3, 1.0) * PI * 0.5) * (1.0 - x)
		angle = rest * (lean + x * x)
	else:
		if not tree.landed:
			tree.landed = true
			_dust(tree)
		var after := t - fall
		if after < BOUNCE_S:
			angle = rest - deg_to_rad(BOUNCE_DEG) * sin(PI * after / BOUNCE_S)
		var lying := after - BOUNCE_S - LIE_S
		if lying > 0.0:
			settle = smoothstep(0.0, 1.0, lying / SETTLE_S)
	var turned := Basis(tree.axis, angle) * base.basis
	var lying_at := Transform3D(turned, base.origin)
	if settle <= 0.0:
		return lying_at
	# Settles away about the middle of the fallen trunk, sinking a little.
	var middle := base.origin + (tree.dir as Vector3) * float(tree.height) * 0.45
	var keep := 1.0 - settle
	var sink := Vector3(0.0, -float(tree.height) * 0.12 * settle, 0.0)
	return Transform3D(turned * keep, middle + (base.origin - middle) * keep + sink)


## Soft dust along a fallen tree, three puffs (EventPuffs.CAPACITY holds 32 trees landing at
## once; an older puff gives its slot to a newer one past that).
func _dust(tree: Dictionary) -> void:
	var base: Transform3D = tree.base
	var dir: Vector3 = tree.dir
	var height := float(tree.height)
	# Kicked out low along the trunk where it lands, the biggest under the crown: wider than
	# tall and rolling out to either side over the ground, as dust from an impact does,
	# rather than rising as a cloud.
	var side := Vector3.UP.cross(dir)
	for k in 3:
		var along := 0.35 + 0.22 * k
		var out := 1.0 if k % 2 == 0 else -1.0
		var at := base.origin + dir * height * along + side * out * _rng.randf_range(0.1, 0.5)
		_puffs.emit(
			at + Vector3(0.0, height * 0.03, 0.0),
			side * out * _rng.randf_range(0.9, 1.4) + Vector3(0.0, _rng.randf_range(0.15, 0.35), 0.0),
			height * (0.13 + 0.05 * k) * _rng.randf_range(0.9, 1.15),
			_rng.randf_range(1.0, 1.3),
			DUST,
			0.0,
			EventPuffs.SQUAT
		)
