extends RefCounted

## Render-job probe (`call` op) for the ground shader's cost with the P3-4 layer table
## (8 slots, automatic cliff and scree, side projections on steep faces). Pairs with
## perf.gd (start / stop sampling, ground_std). step.action picks what it does:
##   shader {version}      the terrain material's shader: "new" (res://, the current
##                         include) or any other name: the include read from
##                         user://p34_<version>_ground.zip, made with `git archive
##                         --format=zip --output=<that path> <commit>
##                         shaders/authored_ground.gdshaderinc` ("old": the commit before
##                         P3-4, which reads none of the new uniforms and so draws the base
##                         surface alone, the "current shader, 0 layers" reference). Each
##                         version compiles once per run.
##   variant {name, replace}  version `name` for `shader`: the current include with each
##                         [from, to] of `replace` substituted (logs any `from` not found).
##   paint {mode}          painted surfaces written straight into the document, whole map:
##                         "strips8" eight painted surfaces in 3 m strips across the view (8
##                         slots on screen, one per pixel), "mix8" the eight in a 1 m checker at
##                         half weight (every pixel blends a painted surface and the base
##                         ground), "none" no paint.
##   terraces {rings}      concentric 1.524 m tiers (sharp faces, rounded lips) filling the
##                         home view, so a large share of the pixels are rock faces drawn
##                         through the side projections.
##   fraction              the share of the view's ground pixels steeper than the side
##                         projection threshold, from the document (a ray per 16 px).

const SURFACES := [
	"cobblestone",
	"flagstone",
	"planks",
	"stone_tiles",
	"dirt_road_packed",
	"mud",
	"sand",
	"snow",
]
const ARCHIVE := "user://p34_%s_ground.zip"
const ENTRY := "shaders/authored_ground.gdshaderinc"
const INCLUDE_LINE := '#include "res://shaders/authored_ground.gdshaderinc"'
## The shader's SIDE_START_NY: steeper pixels sample side projections.
const SIDE_START_NY := 0.72

## version -> Shader built from its archive.
static var _shaders: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var terrain := ctrl.editor.terrain
	match String(step.get("action", "")):
		"shader":
			var version := String(step.get("version", "new"))
			var shader := AuthoredTerrain.GROUND_SHADER as Shader
			if version != "new":
				shader = _archived(version)
				if shader == null:
					return "no shader at %s" % (ARCHIVE % version)
			terrain.get_material().shader = shader
			return "shader %s" % version
		"variant":
			# The current include with text replacements, compiled once as version `name`.
			var name := String(step.get("name", "variant"))
			var include := FileAccess.get_file_as_string(
				"res://shaders/authored_ground.gdshaderinc"
			)
			var missing := PackedStringArray()
			for pair: Array in step.get("replace", []):
				if not include.contains(String(pair[0])):
					missing.append(String(pair[0]))
				include = include.replace(String(pair[0]), String(pair[1]))
			var wrapper := FileAccess.get_file_as_string("res://shaders/authored_ground.gdshader")
			var shader := Shader.new()
			shader.code = wrapper.replace(INCLUDE_LINE, include)
			_shaders[name] = shader
			return (
				"variant %s built%s"
				% [name, "" if missing.is_empty() else ", missing %s" % missing]
			)
		"paint":
			return _paint(terrain, ctrl.document, String(step.get("mode", "none")))
		"terraces":
			return _terraces(base, int(step.get("rings", 5)))
		"fraction":
			return _fraction(base, ctrl)
	return "unknown action %s" % step.get("action", "")


static func _archived(version: String) -> Shader:
	if _shaders.has(version):
		return _shaders[version]
	var zip := ZIPReader.new()
	if zip.open(ARCHIVE % version) != OK:
		return null
	var include := zip.read_file(ENTRY).get_string_from_utf8()
	zip.close()
	var wrapper := FileAccess.get_file_as_string("res://shaders/authored_ground.gdshader")
	var shader := Shader.new()
	shader.code = wrapper.replace(INCLUDE_LINE, include)
	_shaders[version] = shader
	return shader


static func _paint(terrain: AuthoredTerrain, doc: MapDocument, mode: String) -> String:
	var count := doc.sample_count()
	if mode == "none":
		doc.surface_ids = PackedStringArray()
		doc.surface_weights = PackedByteArray()
	else:
		doc.surface_ids = PackedStringArray(SURFACES)
		var weights := PackedByteArray()
		weights.resize(count * MapDocument.SURFACE_CHANNELS * 2)
		for z in doc.samples_z():
			for x in doc.samples_x():
				var p := doc.sample_to_world(Vector2(x, z))
				var i := doc.sample_index(x, z)
				var slot := 0
				var value := 255
				if mode == "strips8":
					slot = clampi(floori((p.x + 12.0) / 3.0), 0, 7)
				else:
					slot = posmod(floori(p.x) + 3 * floori(p.y), 8)
					value = 128
				weights[MapDocument.surface_offset(i, slot, count)] = value
		doc.surface_weights = weights
	var started := Time.get_ticks_usec()
	terrain.update_ground_region(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	return (
		"paint %s: slots %s, %.1f ms"
		% [mode, str(terrain.ground_layers()), (Time.get_ticks_usec() - started) / 1000.0]
	)


static func _terraces(base: Node, rings: int) -> String:
	var shapes := load("res://tools/render_jobs/probes/terrain_shapes.gd")
	return (
		shapes
		. run(
			base,
			{
				"action": "plateau",
				"at": [0, -2],
				"size": [30, 40],
				"tiers": rings,
				"inset": 2.5,
				"lip": 0.25,
				"lip_width": 0.9,
				"corner": 2.0,
			}
		)
	)


static func _fraction(base: Node, ctrl: AuthoringController) -> String:
	var gm: GameMap = base.get("_game_map")
	var camera := gm.camera_node
	var size := Vector2(gm.world_viewport.size)
	var doc := ctrl.document
	var hits := 0
	var steep := 0
	for py in range(0, int(size.y), 16):
		for px in range(0, int(size.x), 16):
			var point := Vector2(px, py)
			var hit := ctrl.editor.raycast_ground(
				camera.project_ray_origin(point), camera.project_ray_normal(point)
			)
			if hit.is_empty():
				continue
			hits += 1
			var local := ctrl.editor.to_map(hit.position)
			var s := doc.world_to_sample(Vector2(local.x, local.z))
			var n := ScatterGenerator.triangle_normal(
				doc.heights, doc.samples_x(), doc.samples_z(), s, doc.sample_step()
			)
			if n.y < SIDE_START_NY:
				steep += 1
	return (
		"fraction: %d of %d ground rays steeper than n.y %.2f (%.1f %%)"
		% [steep, hits, SIDE_START_NY, 100.0 * steep / maxf(hits, 1)]
	)
