class_name EyeRim
extends RefCounted

## The eye view's rim: a few hedgerows and copses of the map's own trees and shrubs planted just
## past the map edge, on the ground skirt, and drawn only while the eye view is on (card eyeedge,
## owner CQ3: every side of every map must look good).
##
## Why past the edge and why only at the eye. A new map's cover feathers out over the last 3 to
## 12 m inside its edge (NewMap.edge_feather), so the orbit view's map fades out on grass instead
## of stopping in a straight line. At the eye that same band, the skirt and the painted sky's foot
## are all a viewer facing the edge sees: an empty plane up to the painted ridges (the hamlet's
## edge views had one bush in the frame). A hedge or a copse a few metres out gives the eye a
## middle ground, but planted on the map it would change the orbit view, where the feathered edge
## is the look; past the edge and hidden in the orbit view it changes nothing there.
##
## The plan is pure (plan()): the perimeter is cut into SLOT_M slots, and the map seed picks per
## slot a gap, a hedge (a loose row of shrubs along the edge, HEDGE_OUT_M out) or a copse (a few
## trees with shrubs at their feet, COPSE_OUT_M out). Species come from the dominant biome's rules
## by kind and size (species()): large trees, and medium ones (shrubs, understory trees); a
## biome with no large trees makes shrub clumps, one with no shrubs hedges of trees, one with
## neither none.
## Slots by a river running out past the edge are left open (RiverExits.exits). Heights follow
## the skirt's own fall (TerrainMeshBuilder.skirt_height), so the plants stand on it.
##
## The node (show()) is an AuthoredScatter named NODE_NAME under the map root, made the first
## time the eye opens on a map and only hidden after, so its species resolve once.

const NODE_NAME := "EyeRim"
const TREE_KIND := "tree"
## The length of perimeter one hedge, copse or gap takes.
const SLOT_M := 10.0
## Of the slots: this share is open, this share hedges, the rest copses.
const GAP_SHARE := 0.3
const HEDGE_SHARE := 0.35
## How far past the edge a hedge runs (its line wanders within this range), its plant spacing,
## and how much of its slot it spans.
const HEDGE_OUT_M := Vector2(2.0, 5.0)
const HEDGE_STEP_M := 1.8
const HEDGE_SPAN := 0.85
## A copse: its centre's distance past the edge, how many trees, how far they spread from it,
## and the shrubs at their feet.
const COPSE_OUT_M := Vector2(4.0, 10.0)
const COPSE_TREES := Vector2i(2, 5)
const COPSE_RADIUS_M := 3.5
const COPSE_SHRUBS := Vector2i(1, 3)
## A slot whose edge point lies within this far of a river's course past the edge (plus its
## half-width) stays open.
const RIVER_CLEAR_M := 5.0
## Scale range of a planted tree or shrub.
const SCALE_RANGE := Vector2(0.85, 1.25)


## The rim's species of a palette biome (PaletteLibrary.biome): {"trees": PackedStringArray,
## "shrubs": PackedStringArray} of asset ids, each species rule's assets in order. A rule of kind
## "tree" (LibraryContracts: canopy and understory trees, shrubs, snags) is a tree when large and
## a shrub when medium. Pure.
static func species(biome: Dictionary) -> Dictionary:
	var trees := PackedStringArray()
	var shrubs := PackedStringArray()
	for rule: Dictionary in biome.get("species", []):
		if String(rule.get("kind", "")) != TREE_KIND:
			continue
		var assets := PackedStringArray(rule.get("assets", []))
		match String(rule.get("size_class", "")):
			"large":
				trees.append_array(assets)
			"medium":
				shrubs.append_array(assets)
	return {"trees": trees, "shrubs": shrubs}


## The rim's rows (asset id -> PackedFloat32Array, MapDocument.ROW_STRIDE floats each, map frame)
## for a map of half extent `half` and seed `seed_value`, planting `kinds` (species()). `edge_y`
## gives the ground height at a point on the edge (Vector2 -> float); `blocked` the edge points
## where nothing goes (Vector2 -> bool, a river's mouth). Deterministic. Pure.
static func plan(
	half: Vector2, seed_value: int, kinds: Dictionary, edge_y: Callable, blocked: Callable
) -> Dictionary:
	var trees: PackedStringArray = kinds.get("trees", PackedStringArray())
	var shrubs: PackedStringArray = kinds.get("shrubs", PackedStringArray())
	var rows := {}
	if trees.is_empty() and shrubs.is_empty():
		return rows
	for side in 4:
		var frame := _side(side, half)
		var length: float = frame.length
		var slots := maxi(1, floori(length / SLOT_M))
		var step := length / slots
		for k in slots:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, side, k, 7919])
			var along := -length * 0.5 + (k + 0.5) * step
			var edge_point: Vector2 = frame.origin + frame.tangent * along
			var pick := rng.randf()
			if pick < GAP_SHARE or blocked.call(edge_point):
				continue
			var plant := {"rows": rows, "rng": rng, "frame": frame, "edge_y": edge_y}
			if pick < GAP_SHARE + HEDGE_SHARE:
				_hedge(plant, along, step, shrubs if not shrubs.is_empty() else trees)
			else:
				_copse(plant, along, trees if not trees.is_empty() else shrubs, shrubs)
	return rows


## The rim's rows for map document `doc` with palette `root`: its dominant biome's species, its
## seed, its edge heights and its river mouths kept open.
static func plan_for(doc: MapDocument, root: String) -> Dictionary:
	var biome_id := StreetSkyLook.dominant_biome(doc.biome_ids, doc.biome_slots)
	if biome_id == "":
		return {}
	var kinds := species(PaletteLibrary.biome(biome_id, root))
	var courses: Array[Dictionary] = RiverExits.exits(doc)
	var edge_y := func(p: Vector2) -> float:
		var s := doc.world_to_sample(p).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		return TerrainMeshBuilder.height_at(doc, x, z)
	var blocked := func(p: Vector2) -> bool:
		for exit: Dictionary in courses:
			var course: PackedVector2Array = exit.get("course", PackedVector2Array())
			var clear := float(exit.get("half_width", 0.0)) + RIVER_CLEAR_M + SLOT_M * 0.5
			if near_line(p, course, clear):
				return true
		return false
	return plan(doc.extent_m() * 0.5, doc.map_seed, kinds, edge_y, blocked)


## Whether point `p` lies within `reach` of polyline `line` (a single point counts as a line).
## Pure.
static func near_line(p: Vector2, line: PackedVector2Array, reach: float) -> bool:
	if line.size() == 1:
		return p.distance_to(line[0]) <= reach
	for i in range(line.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		if p.distance_to(q) <= reach:
			return true
	return false


## Shows the rim under map root `level_map` (built from `doc` the first time, with the foliage
## materials handed to `game_map`), or hides it when `on` is false. Does nothing without a
## document.
static func show(level_map: Node3D, doc: MapDocument, on: bool, game_map: GameMap = null) -> void:
	if not is_instance_valid(level_map):
		return
	var rim := level_map.get_node_or_null(NODE_NAME) as AuthoredScatter
	if not on or doc == null:
		if rim != null:
			rim.visible = false
		return
	if rim == null:
		var main := level_map.get_node_or_null(^"AuthoredScatter") as AuthoredScatter
		var root := main.palette_root if main != null else PaletteLibrary.DEFAULT_ROOT
		rim = AuthoredScatter.create(root, main.foliage_overrides if main != null else {})
		rim.name = NODE_NAME
		rim.warm_pipelines = false
		if game_map != null:
			rim.species_added.connect(
				func(materials: Array[ShaderMaterial]) -> void:
					if is_instance_valid(game_map):
						game_map.adopt_foliage_materials(materials)
			)
		level_map.add_child(rim)
	# Planned again on each opening (a fraction of a millisecond, the species already resolved),
	# so an edit to the map's edge or biome since the last is followed.
	rim.build_all(plan_for(doc, rim.palette_root))
	rim.visible = true


## Side `side` (0 +z, 1 +x, 2 -z, 3 -x) of a map of half extent `half`: its middle on the edge,
## its outward normal, its tangent and its length.
static func _side(side: int, half: Vector2) -> Dictionary:
	var normal: Vector2 = [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)][side]
	var tangent := Vector2(normal.y, -normal.x)
	var length := 2.0 * (half.x if side % 2 == 0 else half.y)
	var reach := half.y if side % 2 == 0 else half.x
	return {"origin": normal * reach, "normal": normal, "tangent": tangent, "length": length}


## A hedge in the slot centred `along` its side and `step` long: a loose row of `ids`.
static func _hedge(plant: Dictionary, along: float, step: float, ids: PackedStringArray) -> void:
	var rng: RandomNumberGenerator = plant.rng
	var span := step * HEDGE_SPAN
	var out := rng.randf_range(HEDGE_OUT_M.x, HEDGE_OUT_M.y)
	var t := along - span * 0.5
	while t <= along + span * 0.5:
		out = clampf(out + rng.randf_range(-0.6, 0.6), HEDGE_OUT_M.x, HEDGE_OUT_M.y)
		_put(plant, t + rng.randf_range(-0.3, 0.3), out, ids[rng.randi() % ids.size()])
		t += HEDGE_STEP_M * rng.randf_range(0.8, 1.25)


## A copse centred `along` its side: a few of `trees` with one to three of `shrubs` at its foot.
static func _copse(
	plant: Dictionary, along: float, trees: PackedStringArray, shrubs: PackedStringArray
) -> void:
	var rng: RandomNumberGenerator = plant.rng
	var out := rng.randf_range(COPSE_OUT_M.x, COPSE_OUT_M.y)
	var count := rng.randi_range(COPSE_TREES.x, COPSE_TREES.y)
	for i in count:
		var offset := Vector2.from_angle(rng.randf() * TAU) * COPSE_RADIUS_M * sqrt(rng.randf())
		_put(plant, along + offset.x, maxf(out + offset.y, 1.0), trees[rng.randi() % trees.size()])
	if shrubs.is_empty():
		return
	for i in rng.randi_range(COPSE_SHRUBS.x, COPSE_SHRUBS.y):
		var offset := Vector2.from_angle(rng.randf() * TAU) * COPSE_RADIUS_M * 1.3
		var shrub := shrubs[rng.randi() % shrubs.size()]
		_put(plant, along + offset.x, maxf(out + offset.y - 1.5, 1.0), shrub)


## One row of `asset_id` at `along` the side and `out` metres past the edge, on the skirt.
static func _put(plant: Dictionary, along: float, out: float, asset_id: String) -> void:
	var rng: RandomNumberGenerator = plant.rng
	var frame: Dictionary = plant.frame
	var edge_point: Vector2 = frame.origin + frame.tangent * along
	var at: Vector2 = edge_point + frame.normal * out
	var edge_y: float = plant.edge_y.call(edge_point)
	var y := TerrainMeshBuilder.skirt_height(edge_y, out, AuthoredTerrain.SKIRT_FADE_M) - 0.05
	var q := Quaternion(Vector3.UP, rng.randf() * TAU)
	var s := rng.randf_range(SCALE_RANGE.x, SCALE_RANGE.y)
	var rows: Dictionary = plant.rows
	if not rows.has(asset_id):
		rows[asset_id] = PackedFloat32Array()
	var list: PackedFloat32Array = rows[asset_id]
	list.append_array(PackedFloat32Array([at.x, y, at.y, q.x, q.y, q.z, q.w, s, s, s]))
	rows[asset_id] = list
