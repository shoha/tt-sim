class_name GroundLookBake
extends Node

## The ground look's bake and bindings on an authored map (ground ship card 3b; contract:
## docs/ASSET_PIPELINE.md section 9 "Ground look and grass masses"; system doc:
## docs/systems/authored_terrain.md "Ground look"). AuthoredTerrain owns one, as a child.
##
## Each biome on the map whose palette entry carries a ground_look (GroundLook) takes a look
## slot (GroundLookUniforms.plan, up to GroundLookUniforms.SLOTS), and each slot one SubViewport
## that bakes its zones and painted light over the map plus MARGIN_M at TEXELS_PER_M
## (shaders/ground_light_field_bake.gdshader, square-root RGBA8, rendered once), with the grass
## masses' shade and lift stamped over it (GroundMassStamps). The ground and its skirt read every
## slot's texture and per-slot values, and per pixel weigh today's ground against the looked one
## by the share of their biome components that carry a look, so a map of several biomes draws
## each with its own look and a biome without one (a fire's burnt forest included) as today. The
## grass of a looked biome (its palette species of kind grass) takes the tuft and mass shading
## and reads its biome's bake.
##
## When: build() calls sync(true) (map open, resize); update_ground_region() calls sync(false)
## (biome paint, fire), which only re-tables the slots unless the set of looked biomes changed;
## the scatter's applied regeneration restamps the masses once it has settled (DEBOUNCE_S, and
## not while growing); a species resolved later gets the grass uniforms; the sun's direction
## (the first DirectionalLight3D) is polled each frame and a change reapplies the grass's lit
## side and restamps. A map whose biomes carry no look binds look_present 0 and runs nothing.

const NODE_NAME := "GroundLookBake"
const BAKE_SHADER := preload("res://shaders/ground_light_field_bake.gdshader")
## The bake's density and the margin past the map edge it covers (the skirt reads the edge
## texel beyond), as round 20 baked.
const TEXELS_PER_M := 10.0
const MARGIN_M := 24.0
const MIN_PX := 16
const MAX_PX := 2048
## Quiet seconds after the last scatter change before the masses are restamped.
const DEBOUNCE_S := 0.5
## The palette species kind whose assets take the tuft shading.
const GRASS_KIND := "grass"
const SCATTER_NODE := "AuthoredScatter"
## A sun direction change under this (unit XZ) is ignored.
const SUN_EPSILON := 1e-4

var terrain: AuthoredTerrain = null
## Bakes run (each slot rendered once), for tests and measurement.
var bakes: int = 0
## Microseconds the last bake's CPU side took (tables, stamps; the GPU render is not counted).
var last_bake_usec: int = 0

var _plan: Dictionary = {}
var _looks: Array[Dictionary] = []
var _refs: Array[Color] = []
var _viewports: Array[SubViewport] = []
var _rect := Vector4.ZERO
var _px := Vector2i.ZERO
var _seed_m := Vector2.ZERO
var _stamp_wait: float = -1.0
var _grass_dirty: bool = false
var _bind_pending: bool = false
var _sun: DirectionalLight3D = null
var _sun_dir := Vector2(0.0, -1.0)
## Seconds until the next search for a sun when there is none (a tree walk, so not every frame).
var _sun_search: float = 0.0
var _scatter: AuthoredScatter = null
var _grass_bound: Array[ShaderMaterial] = []
var _warned: Dictionary = {}


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	set_process(not _plan.get("biomes", PackedStringArray()).is_empty())


## The biome rows of `terrain`'s map for GroundLookUniforms.plan: row 0 the base (the most
## covered map biome on the base surface, else the palette's first biome on it, as the routing
## table's base row), then one per document biome, each with the layer its ground draws on.
static func rows_of(doc: MapDocument, binding: GroundLayerBinding, root: String) -> Array:
	var rows: Array = [{"biome": base_biome_of(doc, root), "ground": 0}]
	var ground: PackedInt32Array = binding.routing.get("ground", PackedInt32Array())
	var as_base: PackedByteArray = binding.inputs.get("as_base", PackedByteArray())
	for b in doc.biome_ids.size():
		var on_base := b < as_base.size() and as_base[b] != 0
		var layer := 0 if on_base else (ground[b + 1] if b + 1 < ground.size() else -1)
		rows.append({"biome": doc.biome_ids[b], "ground": layer})
	return rows


## True when the base biome or any biome of `doc` carries a ground look (AuthoredTerrain makes
## its GroundLookBake only then).
static func has_look(doc: MapDocument, root: String) -> bool:
	var ids := doc.biome_ids.duplicate()
	ids.append(base_biome_of(doc, root))
	for biome_id in ids:
		if biome_id != "" and not PaletteLibrary.ground_look(biome_id, root).is_empty():
			return true
	return false


## The palette biome the base row draws (see rows_of), or "".
static func base_biome_of(doc: MapDocument, root: String) -> String:
	var on_base: Array[int] = []
	for b in doc.biome_ids.size():
		if PaletteLibrary.biome(doc.biome_ids[b], root).get("ground_surface", "") == doc.base_surface:
			on_base.append(b)
	if on_base.size() == 1:
		return doc.biome_ids[on_base[0]]
	if on_base.size() > 1:
		# A walk over every sample, so only when two biomes on the base surface compete.
		var coverage := GroundLayerTable.biome_coverage(
			doc.biome_slots, doc.biome_density, doc.biome_ids.size()
		)
		var best := on_base[0]
		for b in on_base:
			if coverage[b] > coverage[best]:
				best = b
		return doc.biome_ids[best]
	for biome in PaletteLibrary.biomes(root):
		if biome.get("ground_surface", "") == doc.base_surface:
			return String(biome.id)
	return ""


## The looked biomes bound now, in slot order.
func biomes() -> PackedStringArray:
	return _plan.get("biomes", PackedStringArray())


## Brings the slots up to the terrain's document: the plan from its biome rows, the ground's
## tables, and a bake of every slot when `rebake` (map open, resize) or when the looked biomes
## changed. With no look on the map: look_present 0, the viewports freed, the grass unbound.
func sync(rebake: bool) -> void:
	if terrain == null or terrain.document == null:
		return
	var started := Time.get_ticks_usec()
	var root := terrain.palette_root
	var rows := rows_of(terrain.document, terrain.layer_binding(), root)
	var looks := {}
	for row: Dictionary in rows:
		var biome_id := String(row.biome)
		if biome_id != "" and not looks.has(biome_id):
			looks[biome_id] = GroundLook.for_biome(biome_id, root)
	var binding := terrain.layer_binding()
	var the_plan := GroundLookUniforms.plan(rows, looks, binding.layer_of)
	for dropped: String in the_plan.dropped:
		if not _warned.has(dropped):
			_warned[dropped] = true
			push_warning(
				(
					"GroundLookBake: more than %d biomes with a ground look; '%s' draws today's ground"
					% [GroundLookUniforms.SLOTS, dropped]
				)
			)
	var changed: bool = the_plan.biomes != biomes()
	_plan = the_plan
	if biomes().is_empty():
		_unbind()
		return
	_looks.clear()
	_refs.clear()
	for biome_id in biomes():
		var look: Dictionary = looks[biome_id]
		_looks.append(look)
		_refs.append(GroundLookUniforms.ref_linear(String(look.ref_surface), root))
	if rebake or changed or _viewports.size() != biomes().size():
		_bake_all()
	else:
		_bind_ground()
	set_process(true)
	last_bake_usec = Time.get_ticks_usec() - started


## Asks for the masses to be restamped once the scatter settles (its regeneration applied).
func request_stamps() -> void:
	if not biomes().is_empty():
		_stamp_wait = DEBOUNCE_S


func _process(delta: float) -> void:
	if biomes().is_empty():
		set_process(false)
		return
	_watch_scatter()
	_sun_search -= delta
	var sun := _sun_direction()
	if sun.distance_to(_sun_dir) > SUN_EPSILON:
		_sun_dir = sun
		_grass_dirty = true
		_stamp_wait = maxf(_stamp_wait, 0.0)
	if _stamp_wait >= 0.0:
		_stamp_wait -= delta
		var busy := _scatter != null and (_scatter.is_regenerating() or _scatter.is_growing())
		if _stamp_wait < 0.0 and busy:
			_stamp_wait = 0.0
		elif _stamp_wait < 0.0:
			_stamp_wait = -1.0
			_restamp()
	if _grass_dirty:
		_grass_dirty = false
		_bind_grass()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_baked):
		RenderingServer.frame_post_draw.disconnect(_on_baked)


## Bakes every slot: the rect and seed offset from the document, one viewport per slot (the
## bake material's uniforms, the stamps), rendered once on the next frame; the ground and grass
## bind their textures after it is drawn (_on_baked), so no frame reads an empty bake.
func _bake_all() -> void:
	var doc := terrain.document
	var half := doc.extent_m() * 0.5 + Vector2(MARGIN_M, MARGIN_M)
	_px = Vector2i(
		clampi(ceili(half.x * 2.0 * TEXELS_PER_M), MIN_PX, MAX_PX),
		clampi(ceili(half.y * 2.0 * TEXELS_PER_M), MIN_PX, MAX_PX)
	)
	_rect = Vector4(-half.x, -half.y, half.x * 2.0, half.y * 2.0)
	_seed_m = GroundZones.seed_offset(doc.map_seed)
	while _viewports.size() > biomes().size():
		_viewports.pop_back().queue_free()
	var sums := GroundMassStamps.collect(_stamp_root())
	_sun_dir = _sun_direction()
	for s in biomes().size():
		var vp := _viewport(s)
		vp.size = _px
		var fill := vp.get_node("Rect") as ColorRect
		fill.position = Vector2.ZERO
		fill.size = Vector2(_px)
		var params := GroundLookUniforms.bake_params(_looks[s], _refs[s], _seed_m, _rect)
		var mat := fill.material as ShaderMaterial
		for key: String in params:
			mat.set_shader_parameter(key, params[key])
		GroundMassStamps.draw(vp, sums, _rect, _px, _looks[s].mass, _sun_dir)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1
	_await_draw()


## Redraws every slot's mass stamps from the scatter now (and the bake under them).
func _restamp() -> void:
	if _viewports.is_empty():
		return
	var sums := GroundMassStamps.collect(_stamp_root())
	for s in _viewports.size():
		GroundMassStamps.draw(_viewports[s], sums, _rect, _px, _looks[s].mass, _sun_dir)
		_viewports[s].render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1


## Slot `s`'s viewport (made on first use): a transparent 2D SubViewport whose ColorRect runs the
## bake shader.
func _viewport(s: int) -> SubViewport:
	if s < _viewports.size():
		return _viewports[s]
	var vp := SubViewport.new()
	vp.name = "LookBake%d" % s
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.name = "Rect"
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = BAKE_SHADER
	rect.material = shader_mat
	vp.add_child(rect)
	add_child(vp)
	_viewports.append(vp)
	return vp


func _await_draw() -> void:
	if not is_inside_tree():
		_bind_pending = true
		return
	if not RenderingServer.frame_post_draw.is_connected(_on_baked):
		RenderingServer.frame_post_draw.connect(_on_baked, CONNECT_ONE_SHOT)


func _enter_tree() -> void:
	if _bind_pending:
		_bind_pending = false
		for vp in _viewports:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_await_draw()


func _on_baked() -> void:
	if terrain == null or biomes().is_empty():
		return
	_bind_ground()
	_bind_grass()


## The ground's and the skirt's GROUND LOOK uniforms (look_present 0 when nothing is bound).
func _bind_ground() -> void:
	var tables := GroundLookUniforms.OFF.duplicate()
	if not biomes().is_empty() and _viewports.size() == biomes().size():
		var textures := _viewports.map(func(vp: SubViewport) -> Texture2D: return vp.get_texture())
		tables = GroundLookUniforms.ground_tables(_plan, _looks, _refs, textures, _rect)
	for mat in [terrain.get_material(), terrain.get_skirt_material()]:
		if mat != null:
			for key: String in tables:
				(mat as ShaderMaterial).set_shader_parameter(key, tables[key])


## Each looked biome's grass materials: its tuft and mass uniforms, its bake, the sun, and each
## material's own tuft reference. A material bound before and no longer looked is turned off.
func _bind_grass() -> void:
	var scatter := _find_scatter()
	var bound: Array[ShaderMaterial] = []
	if scatter != null and _viewports.size() == biomes().size():
		for s in biomes().size():
			var params := GroundLookUniforms.tuft_params(
				_looks[s], _refs[s], _sun_dir, _viewports[s].get_texture(), _rect
			)
			for asset_id in _grass_assets(biomes()[s]):
				for mat in scatter.species_materials(asset_id):
					if mat in bound:
						continue
					for key: String in params:
						mat.set_shader_parameter(key, params[key])
					var albedo := mat.get_shader_parameter("albedo_texture") as Texture2D
					var tuft_ref := GroundLookUniforms.opaque_mean_linear(albedo)
					mat.set_shader_parameter(
						"zone_tuft_ref", GroundLookUniforms.as_r20_spatial(tuft_ref)
					)
					bound.append(mat)
	for mat in _grass_bound:
		if is_instance_valid(mat) and not mat in bound:
			mat.set_shader_parameter("zone_tuft_strength", 0.0)
	_grass_bound = bound


## Everything off: today's ground and grass.
func _unbind() -> void:
	_looks.clear()
	_refs.clear()
	for vp in _viewports:
		vp.queue_free()
	_viewports.clear()
	_bind_ground()
	_bind_grass()
	_stamp_wait = -1.0
	set_process(false)


## The asset ids of `biome_id`'s palette species of kind GRASS_KIND.
func _grass_assets(biome_id: String) -> PackedStringArray:
	var ids := PackedStringArray()
	var biome := PaletteLibrary.biome(biome_id, terrain.palette_root)
	for rule: Dictionary in biome.get("species", []):
		if String(rule.get("kind", "")) == GRASS_KIND:
			for asset_id: String in rule.get("assets", []):
				if not asset_id in ids:
					ids.append(asset_id)
	return ids


## Where the anchored grass lives: the terrain's parent (LevelMap), as the scatter's sibling.
func _stamp_root() -> Node:
	return terrain.get_parent() if terrain != null else null


func _find_scatter() -> AuthoredScatter:
	if _scatter != null and is_instance_valid(_scatter):
		return _scatter
	var parent := _stamp_root()
	_scatter = parent.get_node_or_null(SCATTER_NODE) as AuthoredScatter if parent else null
	return _scatter


## Connects the scatter (once found): an applied regeneration restamps, a species resolved later
## is bound.
func _watch_scatter() -> void:
	var scatter := _find_scatter()
	if scatter == null or scatter.cells_applied.is_connected(_on_cells_applied):
		return
	scatter.cells_applied.connect(_on_cells_applied)
	scatter.species_added.connect(_on_species_added)
	_grass_dirty = true


func _on_cells_applied(_cells: Array[Vector2i]) -> void:
	request_stamps()


func _on_species_added(_materials: Array[ShaderMaterial]) -> void:
	_grass_dirty = true


## Unit world XZ toward the sun: the first DirectionalLight3D's +Z axis (it shines along -Z);
## (0, -1) without one.
func _sun_direction() -> Vector2:
	if _sun == null or not is_instance_valid(_sun) or not _sun.is_inside_tree():
		_sun = null
		if is_inside_tree() and _sun_search <= 0.0:
			var found := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
			_sun = found[0] as DirectionalLight3D if not found.is_empty() else null
			_sun_search = 1.0
	if _sun == null:
		return _sun_dir
	var b := _sun.global_basis
	var xz := Vector2(b.z.x, b.z.z)
	return xz.normalized() if xz.length() > 1e-3 else _sun_dir
