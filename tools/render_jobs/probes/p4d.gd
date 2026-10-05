extends RefCounted

## Render-job probe (`call` op) for the ford (phase 4d, P4d-0): a gravel bar laid across a
## river as derived geometry, its crest a little under the water surface, so the water
## shader, the landing ray and the shadow can be judged on a real render before the crossing
## kind is built. Works in authoring (the AuthoringController's document) and in play
## (LevelPlayController.loaded_map_document), where tokens can be dropped on it. Positions
## are map XZ metres. step.action:
##   bar {from, to, width, depth, name}
##                         adds a bar from `from` to `to` (across the channel, bank to bank),
##                         `width` wide along the channel, under the map root as
##                         "P4dBar_<name>" (replacing one of that name): a strip sampled every
##                         SAMPLE_M along the line and ACROSS times across it, whose top is the
##                         water level less `depth` where the ground lies below that (the
##                         channel) and SINK_M under the ground where it does not (the banks:
##                         a strip laid on the ground there drew as a pale coplanar rectangle
##                         over the grass in the first captures), its sides easing from the
##                         crest to SINK_M under the bed over SHOULDER_M; a MeshInstance3D with the
##                         palette's gravel surface (triplanar ORM) casting shadows, and a
##                         StaticBody3D of the same triangles on the terrain layer, so every
##                         ground ray lands on it. Logs the ground, water level and crest at
##                         the line's middle, the wet share of the strip and its height range.
##   remove {name}         frees the bar of that name.
##   landing {at}          what the rays read at `at`: the terrain-layer hit (and what it hit),
##                         the walkable hit on WaterSurface.WALKABLE_MASK from LANDING_TOP_M up
##                         as the drag does, the water surface, WaterSurface.landing_below, the
##                         grid field's height, the drag resolver's answer, and whether a token
##                         TOKEN_HEIGHT_M tall landing there would count as submerged
##                         (WaterSurface.is_submerged); with a document, its ground_at and
##                         level_at beside them.

const WATER := preload("res://tools/render_jobs/probes/water.gd")

const BAR_PREFIX := "P4dBar_"
## Spacing of the strip's samples along the line, and its vertex count across the width.
const SAMPLE_M := 0.25
const ACROSS := 7
## The bar's sides slope from the crest down to the bed over this much of the width.
const SHOULDER_M := 0.6
## How far under the ground the strip lies where it is not above it (the banks, the feet of
## its sides), so no part of it is coplanar with the terrain.
const SINK_M := 0.08
const GRAVEL_SURFACE := "gravel"
## A small token's height for the submerged question, and where the landing rays start.
const TOKEN_HEIGHT_M := 0.3
const LANDING_TOP_M := 10.0


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"bar":
			return _bar(base, step)
		"remove":
			return _remove(base, String(step.get("name", "bar")))
		"landing":
			return _landing(base, _xz(step.get("at")))
	return "unknown action %s" % step.get("action", "")


static func _xz(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


## The open document: the authoring controller's, or in play the loaded level's.
static func _document(base: Node) -> MapDocument:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl != null and ctrl.document != null:
		return ctrl.document
	var lpc: LevelPlayController = base.get("_level_play_controller")
	return lpc.loaded_map_document if lpc != null else null


static func _map_root(base: Node) -> Node3D:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.map_container == null:
		return null
	return gm.map_container.get_node_or_null(^"LevelMap") as Node3D


# --- bar ---------------------------------------------------------------------------------------


static func _bar(base: Node, step: Dictionary) -> String:
	var doc := _document(base)
	var root := _map_root(base)
	if doc == null or root == null:
		return "no document or map root"
	var from := _xz(step.get("from"))
	var to := _xz(step.get("to"))
	var width := float(step.get("width", 2.5))
	var depth := float(step.get("depth", 0.2))
	var label := String(step.get("name", "bar"))
	var length := from.distance_to(to)
	if length < SAMPLE_M:
		return "line too short"
	_remove(base, label)
	var dir := (to - from) / length
	var across := Vector2(-dir.y, dir.x)
	var rows := int(ceil(length / SAMPLE_M)) + 1
	var vertices := PackedVector3Array()
	var wet := 0
	var lowest := INF
	var highest := -INF
	for i in rows:
		var p := from + dir * minf(i * SAMPLE_M, length)
		for j in ACROSS:
			var u := (float(j) / float(ACROSS - 1) - 0.5) * width
			var q := p + across * u
			var ground := WaterGeometry.ground_at(doc, q)
			var level := WaterGeometry.level_at(doc, q)
			# Dry ground: the crest is under the ground, so the whole strip there is sunk (with
			# the crest at the ground the centreline lay on it and drew as a pale patch).
			var crest := level - depth if level != WaterGeometry.DRY else ground - SINK_M
			var edge := clampf((width * 0.5 - absf(u)) / SHOULDER_M, 0.0, 1.0)
			var shoulder := edge * edge * (3.0 - 2.0 * edge)
			var rise := maxf(crest - ground, -SINK_M)
			var top := ground + rise * shoulder - SINK_M * (1.0 - shoulder)
			if crest > ground:
				wet += 1
			lowest = minf(lowest, top)
			highest = maxf(highest, top)
			vertices.append(Vector3(q.x, top, q.y))
	var faces := _faces(vertices, rows)
	var mesh := _mesh(vertices, faces, rows)
	var instance := MeshInstance3D.new()
	instance.name = BAR_PREFIX + label
	instance.mesh = mesh
	instance.material_override = _gravel_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = WaterSurface.TERRAIN_LAYER
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	instance.add_child(body)
	root.add_child(instance)
	var middle := (from + to) * 0.5
	var mid_ground := WaterGeometry.ground_at(doc, middle)
	var mid_level := WaterGeometry.level_at(doc, middle)
	return (
		(
			"bar %s: %d x %d samples, %d tris, wet %d of %d, top %.2f..%.2f"
			+ " | middle %s ground %.2f level %s crest %s"
		)
		% [
			label,
			rows,
			ACROSS,
			faces.size() / 3,
			wet,
			rows * ACROSS,
			lowest,
			highest,
			str(middle),
			mid_ground,
			("%.2f" % mid_level) if mid_level != WaterGeometry.DRY else "dry",
			("%.2f" % (mid_level - depth)) if mid_level != WaterGeometry.DRY else "-",
		]
	)


## The strip's triangles as a flat list of vertices (every three a face), front faces up.
## Godot's front faces wind clockwise seen from the front (PlaneMesh's own index order has
## cross(B - A, C - A) pointing away from the viewer): for a row step d and a width step a,
## cross(a, d) points up, so each quad is (v, v+d, v+a) and (v+a, v+d, v+a+d). The first
## build of this probe had them the other way round and the bar was culled from above
## while its collision still landed the tokens.
static func _faces(vertices: PackedVector3Array, rows: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in rows - 1:
		for j in ACROSS - 1:
			var v00 := vertices[i * ACROSS + j]
			var v01 := vertices[i * ACROSS + j + 1]
			var v10 := vertices[(i + 1) * ACROSS + j]
			var v11 := vertices[(i + 1) * ACROSS + j + 1]
			faces.append_array([v00, v10, v01, v01, v10, v11])
	return faces


## An indexed ArrayMesh of the strip with per-vertex normals summed from its faces.
static func _mesh(vertices: PackedVector3Array, faces: PackedVector3Array, rows: int) -> ArrayMesh:
	var indices := PackedInt32Array()
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.ZERO)
	for i in rows - 1:
		for j in ACROSS - 1:
			var a := i * ACROSS + j
			var b := a + 1
			var c := a + ACROSS
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	for f in faces.size() / 3:
		# The up-pointing normal of a clockwise face: cross(C - A, B - A).
		var n := (faces[f * 3 + 2] - faces[f * 3]).cross(faces[f * 3 + 1] - faces[f * 3])
		var quad := f / 2
		var i := quad / (ACROSS - 1)
		var j := quad % (ACROSS - 1)
		for k in [
			i * ACROSS + j, i * ACROSS + j + 1, (i + 1) * ACROSS + j, (i + 1) * ACROSS + j + 1
		]:
			normals[k] += n
	for k in normals.size():
		normals[k] = normals[k].normalized() if normals[k].length_squared() > 0.0 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The palette's gravel surface as a triplanar ORM material at its tile size, the way
## AuthoredCrossings builds its stone (a missing texture leaves a gravel-coloured albedo).
static func _gravel_material() -> ORMMaterial3D:
	var root := PaletteLibrary.DEFAULT_ROOT
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(GRAVEL_SURFACE, {})
	var material := ORMMaterial3D.new()
	material.albedo_color = Color(0.55, 0.5, 0.42)
	var albedo := GroundPalette.load_texture(root, surface.get("albedo", ""))
	if albedo != null:
		material.albedo_texture = albedo
		material.albedo_color = Color.WHITE
	var normal := GroundPalette.load_texture(root, surface.get("normal", ""))
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 1.0
	var orm := GroundPalette.load_texture(root, surface.get("orm", ""))
	if orm != null:
		material.orm_texture = orm
	else:
		material.roughness = 0.95
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE / maxf(float(surface.get("tile_m", 2.0)), 0.1)
	return material


static func _remove(base: Node, label: String) -> String:
	var root := _map_root(base)
	if root == null:
		return "no map root"
	var node := root.get_node_or_null(BAR_PREFIX + label)
	if node == null:
		return "no bar %s" % label
	root.remove_child(node)
	node.free()
	return "removed bar %s" % label


# --- landing -----------------------------------------------------------------------------------


static func _landing(base: Node, xz: Vector2) -> String:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.world_viewport == null:
		return "no map"
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var at := Vector3(xz.x, 0.0, xz.y)
	var ground := WaterSurface.cast_down(space, at, LANDING_TOP_M, WaterSurface.TERRAIN_LAYER)
	var walkable := WaterSurface.cast_down(space, at, LANDING_TOP_M, WaterSurface.WALKABLE_MASK)
	var water := WaterSurface.water_below(space, at, LANDING_TOP_M + WaterSurface.CAST_CLEARANCE_M)
	var landing := WaterSurface.landing_below(space, at, LANDING_TOP_M)
	var surface_y: float = water.y if not water.is_empty() else NAN
	var submerged := (
		WaterSurface.is_submerged(landing.y, landing.y + TOKEN_HEIGHT_M, surface_y)
		if landing != Vector3.INF
		else false
	)
	var field := gm.get_grid_ground()
	var doc := _document(base)
	var doc_text := "-"
	if doc != null:
		var level := WaterGeometry.level_at(doc, xz)
		doc_text = (
			"ground %.2f level %s"
			% [
				WaterGeometry.ground_at(doc, xz),
				("%.2f" % level) if level != WaterGeometry.DRY else "dry",
			]
		)
	return (
		(
			"landing at %s: terrain hit %s (%s) | walkable hit %s (%s) | water %s floats %s"
			+ " | landing %s | token %.2f m submerged %s | field %s | resolver %s | doc %s"
		)
		% [
			str(xz),
			_hit_y(ground),
			_hit_name(ground),
			_hit_y(walkable),
			"water" if WaterSurface.is_water_hit(walkable) else _hit_name(walkable),
			("%.2f" % surface_y) if not is_nan(surface_y) else "-",
			str(water.get("floats", "-")),
			("%.2f" % landing.y) if landing != Vector3.INF else "-",
			TOKEN_HEIGHT_M,
			str(submerged),
			("%.2f" % field.world_height_at(xz)) if field else "-",
			str(
				gm.call("_resolve_drag_ground", Vector3(xz.x, walkable.get("position", at).y, xz.y))
			),
			doc_text,
		]
	)


static func _hit_y(hit: Dictionary) -> String:
	return ("%.2f" % (hit.position as Vector3).y) if not hit.is_empty() else "miss"


## The hit's collider named by its parent (a bar's Body is under the P4dBar_ instance).
static func _hit_name(hit: Dictionary) -> String:
	var collider: Object = hit.get("collider")
	if collider == null:
		return "-"
	var node := collider as Node
	if node == null:
		return str(collider)
	var parent := node.get_parent()
	return String(parent.name) + "/" + String(node.name) if parent else String(node.name)
