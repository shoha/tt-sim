class_name PainterSurfaces
extends RefCounted

## The painted look's surfaces: while a level is drawn Painted, the authored ground and the
## scatter tt-sim builds from GLBs (bushes, ferns, grass, flowers, rocks, logs) wear painted
## materials coloured from the sheet (docs/systems/painter.md "Surfaces"). The scatter's mapped
## trees are drawn by PainterTrees (painter/trees/painter_trees.gd, loaded by path here), which
## hides their GLB nodes, and the built structures' walls, roofs and timber by PainterBuildings
## (painter/painter_buildings.gd, loaded by path here too), the water and the falls by PainterWater
## (painter/painter_water.gd, loaded by path here too: the shader of the two shared materials);
## tokens keep their Classic materials (later cards).
##
## Events, never a poll. LevelEnvironmentManager owns one (made by path on the first Painted
## level, so neither the start-up nor a Classic level compiles it) and its signal
## painted_look_changed drives it: a state {"sheet", "mood", "elevation"} paints the level's map
## (LevelMap under the map container) or re-tones what is painted, {} puts everything back. While
## painted it follows the map: AuthoredTerrain.child_entered_tree (a chunk or the skirt built
## later, by a load, a rebuild or an edit) dresses the new node; AuthoredTerrain.ground_edited
## (a brush) redoes the edited rectangle of the zone maps once that frame (PainterZoneMaps);
## AuthoredScatter.cells_applied and
## species_added (a pan, a brush, a load that resolves a species later) paint any species not yet
## painted. Cells share their species' mesh, so a species is painted once for every cell.
##
## What it swaps, and the exact restore. The ground: material_override on every terrain chunk
## and on the skirt (painter_ground.gdshader; the material underneath is never touched); the
## previous override is kept per node and put back. The scatter: each species mesh surface's
## material (mesh.surface_set_material) by a STAND-IN: for a wind material a duplicate on
## painter_plant.gdshader (every wind, grow-in and fade uniform kept; WindFoliage's code is
## included by the shader, not copied), for a still asset's own material a new
## painter_solid.gdshader material. The original is kept and put back on release. A stand-in
## carries WindFoliage.META_STAND_IN, so the foliage AA swap (VisualEffectsController, also on
## entering and leaving the eye view) reaches the original in its place and never replaces the
## stand-in's shader (test_painter_surfaces.gd).
##
## Tones. Every colour is the sheet's: the ground roles' ramps (PainterGroundRoles.TONE_ROLE,
## PainterTones.ramp with the ground's numbers), each plant's role ramp (PainterPlantRoles), the
## flower accents, and the numbers for thinning, marks and the shadow step. A new elevation
## (the level's sun) re-tones the same materials.
##
## Known gaps (docs/systems/painter.md): the wind re-tuning of apply_foliage_overrides does not
## reach a stand-in made after it; a burning plant's shader swap and the stand-ins' pipeline
## warm-up are later cards'; the clipmap keeps baking the Classic ground underneath.

## The signal on LevelEnvironmentManager this follows.
const SIGNAL := &"painted_look_changed"
const GROUND_SHADER := "res://painter/shaders/painter_ground.gdshader"
const PLANT_SHADER := "res://painter/shaders/painter_plant.gdshader"
const SOLID_SHADER := "res://painter/shaders/painter_solid.gdshader"
## The painted trees' host (PainterTrees), loaded by path on the first painted map.
const TREES := "res://painter/trees/painter_trees.gd"
## The painted buildings' host (PainterBuildings), loaded by path on the first painted map.
const BUILDINGS := "res://painter/painter_buildings.gd"
## The ground's contact occlusion host (PainterOcclusion), loaded by path on the first painted map.
const OCCLUSION := "res://painter/painter_occlusion.gd"
## The painted water's host (PainterWater), loaded by path on the first painted map.
const WATER := "res://painter/painter_water.gd"
## The GLB map's host (PainterGlbMap: the ground, scatter, trees and props of a Blender-made
## map.glb), loaded by path on the first painted map.
const GLB_MAP := "res://painter/painter_glb_map.gd"
## The village furnishings' host (PainterVillage), loaded by path on the first painted map.
const VILLAGE := "res://painter/painter_village.gd"
## Metadata on every material this paints with.
const META := &"painter_surface"
## The map root's name under the map container (MapSourceLoader.install).
const LEVEL_MAP := ^"LevelMap"
## How far a biome's painted density pulls a sample to its role (the spike's 1.5).
const BIOME_PULL := 1.5
## The zone map's blur radius in samples (no sample step of the masks reaches the screen).
const ZONE_BLUR := 1

## What is drawn now: {"sheet", "mood", "elevation"}, {} while nothing is painted.
var applied: Dictionary = {}

var _container: Node3D = null
var _map: Node3D = null
var _terrain: AuthoredTerrain = null
## The plant sources: AuthoredScatter and AuthoredFieldPlants (answers like a scatter; untyped).
var _scatters: Array = []
var _ground: ShaderMaterial = null
var _skirt: ShaderMaterial = null
## Node instance id -> [node, the material_override it had].
var _overrides: Dictionary = {}
## [mesh, surface, original, stand-in, plant entry] per replaced scatter surface.
var _swapped: Array = []
## Mesh instance id -> true for every species looked at (painted or left Classic).
var _seen: Dictionary = {}
var _zone_queued := false
## The painted trees (a PainterTrees), made on the first paint().
var _trees: RefCounted = null
## The painted buildings (a PainterBuildings), made on the first paint().
var _buildings: RefCounted = null
## The contact occlusion host (a PainterOcclusion), made on the first paint().
var _occlusion: RefCounted = null
## The painted water (a PainterWater), made on the first paint().
var _water: RefCounted = null
## The GLB map's host (a PainterGlbMap), made on the first paint().
var _glb: RefCounted = null
## The ground materials the GLB host made for a map.glb's own terrain meshes (toned with the rest).
var _glb_ground: Array[ShaderMaterial] = []
## The painted village furnishings (a PainterVillage), made on the first paint().
var _village: RefCounted = null
## The meadow grass drawn as painted marks (PainterGrassMarks).
var _marks := PainterGrassMarks.new()
var _field := PainterGroundField.new()  ## The ground's shading field and back-face caster.
## The map's path surfaces by slot and its cliff surface (PainterGroundPaths), from the last zone
## rebuild.
var _path_ids := PackedStringArray()
var _cliff_surface := ""
## The zone maps (PainterZoneMaps), kept current per edit; the ground and the skirt share their
## textures.
var _zones := PainterZoneMaps.new()
## The samples edited since the last zone rebuild (AuthoredTerrain.ground_edited), and whether the
## next rebuild is whole (a first paint, a new or rebuilt terrain).
var _zone_dirty := Rect2i()
var _zone_whole := true
## The path slot map's inputs at its last bind: [surface ids, base surface, surface weights, sx, sz]
## (copies of the document's arrays).
var _path_key: Array = []


## Follows `manager`'s painted_look_changed for the map under `map_container`; called again with
## each new table's container (a map painted under another container is released first).
func attach(manager: Object, map_container: Node3D) -> void:
	if map_container != _container and _map != null:
		release()
	_container = map_container
	if not manager.is_connected(SIGNAL, _on_look_changed):
		manager.connect(SIGNAL, _on_look_changed)


## Paints `map` (a LevelMap) in `state` ({"sheet", "mood", "elevation"}), or re-tones it when it
## is already painted; a different map than the last is released first. False, touching
## nothing, when the sheet or the mood is missing.
func paint(map: Node3D, state: Dictionary) -> bool:
	if map != _map:
		release()
	var sheet := PainterSheet.load_sheet(str(state.get("sheet", "")))
	if map == null or not sheet.has(str(state.get("mood", ""))):
		return false
	applied = {
		"sheet": str(state["sheet"]),
		"mood": str(state["mood"]),
		"elevation": float(state.get("elevation", 45.0))
	}
	if _map == null:
		_map = map
		_bind()
		_zone_whole = true
		_rebuild_zone()
	_paint_species()
	_retone()
	_paint_trees()
	_marks.sync(self)
	if _glb == null:
		_glb = (load(GLB_MAP) as GDScript).new()
	_glb.call("paint", _map, applied, self)
	if _buildings == null:
		_buildings = (load(BUILDINGS) as GDScript).new()
	_buildings.call("paint", _map, applied)
	if _village == null:
		_village = (load(VILLAGE) as GDScript).new()
	_village.call("paint", _map, applied)
	_ground_occlusion()
	if _water == null:
		_water = (load(WATER) as GDScript).new()
	_water.call("paint", _map, applied)
	return true


## Puts every material back as it was before the first paint() and stops following the map.
func release() -> void:
	if _occlusion != null:
		_occlusion.call("release")
	if _trees != null:
		_trees.call("release")
	if _buildings != null:
		_buildings.call("release")
	if _village != null:
		_village.call("release")
	if _water != null:
		_water.call("release")
	if _glb != null:
		_glb.call("release")
	_glb_ground.clear()
	_marks.release()
	_unbind()
	if _ground != null:
		FireLook.unmirror_glow(_ground)
	for id: int in _overrides:
		var pair: Array = _overrides[id]
		if is_instance_valid(pair[0]):
			(pair[0] as GeometryInstance3D).material_override = pair[1]
	_overrides.clear()
	for entry: Array in _swapped:
		var mesh := entry[0] as Mesh
		if mesh != null and mesh.surface_get_material(entry[1]) == entry[3]:
			mesh.surface_set_material(entry[1], entry[2])
	_swapped.clear()
	_seen.clear()
	_map = null
	_terrain = null
	_scatters.clear()
	_zone_dirty = Rect2i()
	_zone_whole = true
	_path_key = []
	applied = {}


## Whether anything is painted.
func is_active() -> bool:
	return not applied.is_empty()


## Every stand-in now on a scatter surface.
func stand_ins() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for entry: Array in _swapped:
		out.append(entry[3])
	return out


## The ground's material (null before the first paint()).
func ground_material() -> ShaderMaterial:
	return _ground


# ---------------------------------------------------------------- following the map


func _on_look_changed(state: Dictionary) -> void:
	if state.is_empty():
		release()
		return
	var map: Node3D = null
	if is_instance_valid(_container):
		map = _container.get_node_or_null(LEVEL_MAP) as Node3D
	paint(map, state)


func _bind() -> void:
	_terrain = _map.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
	if _terrain != null:
		_terrain.child_entered_tree.connect(_on_terrain_child)
		_terrain.ground_edited.connect(_on_ground_edited)
		for child in _terrain.get_children():
			_dress(child)
	for child in _map.get_children():
		if _is_plant_source(child):
			_bind_scatter(child)
	# A source made later (the eye view's rim, the village's field plants) is followed likewise.
	_map.child_entered_tree.connect(_on_map_child)


## True for a scatter or the village's field plants.
static func _is_plant_source(node: Node) -> bool:
	return node is AuthoredScatter or (node is AuthoredFieldPlants and PainterVillage.field_plants)


func _bind_scatter(scatter: Node) -> void:
	if scatter in _scatters:
		return
	scatter.cells_applied.connect(_on_cells_applied)
	scatter.species_added.connect(_on_species_added)
	scatter.visibility_changed.connect(_on_scatter_shown)
	_scatters.append(scatter)


func _on_map_child(node: Node) -> void:
	if not _is_plant_source(node) or applied.is_empty():
		return
	_bind_scatter(node)
	# PainterTrees keeps the same array: it only needs its child watch on the new scatter.
	_paint_trees()


## A scatter shown or hidden (the eye view's rim): its painted trees come or go with it.
func _on_scatter_shown() -> void:
	if _trees != null:
		_trees.call("sync")


func _unbind() -> void:
	_field.release()
	if is_instance_valid(_map) and _map.child_entered_tree.is_connected(_on_map_child):
		_map.child_entered_tree.disconnect(_on_map_child)
	if is_instance_valid(_terrain):
		if _terrain.child_entered_tree.is_connected(_on_terrain_child):
			_terrain.child_entered_tree.disconnect(_on_terrain_child)
		if _terrain.ground_edited.is_connected(_on_ground_edited):
			_terrain.ground_edited.disconnect(_on_ground_edited)
	for scatter in _scatters:
		if not is_instance_valid(scatter):
			continue
		if scatter.cells_applied.is_connected(_on_cells_applied):
			scatter.cells_applied.disconnect(_on_cells_applied)
		if scatter.species_added.is_connected(_on_species_added):
			scatter.species_added.disconnect(_on_species_added)
		if scatter.visibility_changed.is_connected(_on_scatter_shown):
			scatter.visibility_changed.disconnect(_on_scatter_shown)


func _on_terrain_child(node: Node) -> void:
	_dress(node)
	if str(node.name) == AuthoredTerrain.SKIRT_NAME:
		# The skirt is built last by every AuthoredTerrain.build(): the document may be new.
		_zone_whole = true
		_queue_zone()


## An edit of the samples in `rect`: the next zone rebuild redoes that rectangle (PainterZoneMaps).
func _on_ground_edited(rect: Rect2i) -> void:
	_zone_dirty = _zone_dirty.merge(rect) if _zone_dirty.has_area() else rect
	_queue_zone()
	_queue_occlusion()


func _on_cells_applied(_cells: Array[Vector2i]) -> void:
	_tone_new(_paint_species())
	_marks.sync(self)
	if _trees != null:
		_trees.call("sync")
	_queue_occlusion()


func _on_species_added(_materials: Array[ShaderMaterial]) -> void:
	_tone_new(_paint_species())
	_marks.sync(self)
	if _trees != null:
		_trees.call("sync")
	_queue_occlusion()


# ---------------------------------------------------------------- contact occlusion


## Starts (or re-tones) the contact occlusion host (PainterOcclusion) and follows what changes its
## footprints: the painted trees' installs, the structures coming and going.
func _ground_occlusion() -> void:
	if _occlusion == null:
		_occlusion = (load(OCCLUSION) as GDScript).new()
	_occlusion.call("bind", self, _map)
	var sheet := PainterSheet.load_sheet(applied["sheet"])
	_occlusion.call("retone", sheet, applied["mood"], applied["elevation"])
	if _trees != null and not _trees.is_connected(&"changed", _queue_occlusion):
		_trees.connect(&"changed", _queue_occlusion)
	var structures: Node = _buildings.get("_structures") if _buildings != null else null
	if structures != null and not structures.child_entered_tree.is_connected(_on_structures_changed):
		structures.child_entered_tree.connect(_on_structures_changed)
		structures.child_exiting_tree.connect(_on_structures_changed)


func _on_structures_changed(_node: Node) -> void:
	_queue_occlusion()


func _queue_occlusion() -> void:
	if _occlusion != null and not applied.is_empty():
		_occlusion.call("queue")


## The contact occlusion host (a PainterOcclusion), null before the first paint().
func occlusion() -> RefCounted:
	return _occlusion


## The ground's materials: the chunks' and the skirt's.
func ground_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = [_ground_material()]
	if _skirt != null:
		out.append(_skirt)
	out.append_array(_glb_ground)
	return out


## The ground a GLB map's terrain mesh is dressed in (PainterGlbMap): a copy of the authored
## ground's material, so it takes the same sheet numbers; the host sets what is the mesh's own.
func make_glb_ground() -> ShaderMaterial:
	var material := _ground_material().duplicate() as ShaderMaterial
	material.set_meta(META, true)
	_glb_ground.append(material)
	return material


## A painted solid for a prop surface of `original` (a GLB map's own mesh; PainterGlbMap), null when
## `original` is not a standard material. Not toned (the host tones it).
func prop_stand_in(
	mesh: Mesh, original: Material, entry: Dictionary, height: float
) -> ShaderMaterial:
	var stand_in := stand_in_of(original, entry, height)
	if stand_in != null:
		stand_in.set_shader_parameter(&"selector_extent", mesh.get_aabb().size * 0.5)
	return stand_in


## Tones the plants `added` (swap_surface's records) now, when something is painted.
func tone_added(added: Array) -> void:
	_tone_new(added)


## The materials that darken at their base: the rocks' and logs' stand-ins and the trees' own.
func base_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for entry: Array in _swapped:
		if int(entry[4]["kind"]) == PainterPlantRoles.KIND_SOLID:
			out.append(entry[3])
	if _glb != null:
		out.append_array(_glb.call("base_materials"))
	if _trees != null:
		out.append_array(_trees.call("materials"))
		var fast: Variant = _trees.get("fast_material")
		if fast != null:
			out.append(fast as ShaderMaterial)
	return out


## The instance ids of the scatter meshes drawn as stones and wood (rocks, logs, stumps, and the
## bark of the trees the painter does not grow): the solids whose footprint the ground's field
## holds. Each maps to whether the mesh also carries a leaf surface (an acacia's or a palm's
## crown: a tree, whose pool is a crown's disc).
func solid_meshes() -> Dictionary:
	var out := {}
	var leafy := {}
	for entry: Array in _swapped:
		var id := (entry[0] as Mesh).get_instance_id()
		if int(entry[4]["kind"]) != PainterPlantRoles.KIND_SOLID:
			leafy[id] = true
		elif str(entry[4]["role"]) in ["stone", "bark", PainterPlantRoles.CHARCOAL_ROLE]:
			out[id] = false
	for id: int in out:
		out[id] = leafy.has(id)
	return out


## The plant sources painted: the map's scatters and its village field plants.
func scatters() -> Array:
	return _scatters


## The map's extent in metres (zero before a terrain is bound).
func map_extent() -> Vector2:
	if is_instance_valid(_terrain) and _terrain.document != null:
		return _terrain.document.extent_m()
	return Vector2.ZERO


## Draws the scatter's mapped trees painted (PainterTrees), or re-tones and re-syncs them.
func _paint_trees() -> void:
	if _trees == null:
		_trees = (load(TREES) as GDScript).new()
	var doc: MapDocument = _terrain.document if is_instance_valid(_terrain) else null
	_trees.call("paint", _map, _scatters, doc, applied)


## The painted trees (a PainterTrees), null before the first paint().
func trees() -> RefCounted:
	return _trees


## The painted buildings (a PainterBuildings), null before the first paint().
func buildings() -> RefCounted:
	return _buildings


## The painted water (a PainterWater), null before the first paint().
func water() -> RefCounted:
	return _water


## The GLB map's host (a PainterGlbMap), null before the first paint().
func glb_map() -> RefCounted:
	return _glb


# ---------------------------------------------------------------- the ground


## Puts the painted ground on a terrain chunk or the skirt (anything else is left).
func _dress(node: Node) -> void:
	var geometry := node as GeometryInstance3D
	if geometry == null or _overrides.has(geometry.get_instance_id()):
		return
	var named := str(node.name)
	var material: ShaderMaterial = null
	if named.begins_with(AuthoredTerrain.CHUNK_NAME_PREFIX):
		material = _ground_material()
	elif named == AuthoredTerrain.SKIRT_NAME:
		_ground_material()
		material = _skirt
		# The channel patch where a river leaves the map is a child of the skirt with the skirt's
		# own Classic material: it showed as a dark, unbrushed rectangle against the painted ground
		# (card painter-edges). UV is the map-frame XZ, as the skirt's.
		var patch := node.get_node_or_null(SkirtExits.CHANNEL_NAME)
		if patch != null:
			_dress_as(patch as GeometryInstance3D, material)
	if material == null:
		return
	_dress_as(geometry, material)


## Draws `geometry` with `material`, remembering what it had (released with the rest).
func _dress_as(geometry: GeometryInstance3D, material: ShaderMaterial) -> void:
	if geometry == null or _overrides.has(geometry.get_instance_id()):
		return
	_overrides[geometry.get_instance_id()] = [geometry, geometry.material_override]
	geometry.material_override = material


func _ground_material() -> ShaderMaterial:
	if _ground == null:
		_ground = ShaderMaterial.new()
		_ground.shader = load(GROUND_SHADER) as Shader
		_ground.set_meta(META, true)
		_ground.set_shader_parameter(&"brushes", PainterBrushes.texture())
		_ground.set_shader_parameter(&"brushes_present", true)
		_skirt = _ground.duplicate() as ShaderMaterial
		_skirt.set_meta(META, true)
		_skirt.set_shader_parameter(&"skirt", true)
	if not FireLook.glow_mirrors.has(_ground):
		# The persistent ground fire (FireField) binds its bake to the terrain's own material, which
		# this one replaces: it takes the same bake and draws the char and the glow its own way.
		FireLook.mirror_glow(_ground, _terrain.get_material() if is_instance_valid(_terrain) else null)
	return _ground


func _queue_zone() -> void:
	if _zone_queued:
		return
	_zone_queued = true
	_rebuild_zone.call_deferred()


## Brings the ground's maps up to the terrain's document, once a frame after an edit: the shading
## field (PainterGroundField), the zone maps (PainterZoneMaps: r meadow share, g path, b rock,
## a shore, and the char and biome zone maps; whole after a first paint or a terrain build, else
## the edited rectangle alone), the path slot map (only when the painted surfaces changed: a sculpt
## step leaves it) and the cliff surface.
func _rebuild_zone() -> void:
	_zone_queued = false
	_queue_occlusion()
	if not is_instance_valid(_terrain) or _terrain.document == null:
		return
	var doc := _terrain.document
	# One field for the map and the skirt (the texture object is shared, as the zone map's): past
	# the border the skirt's reads clamp to the border's texel (painter_ground.gdshader).
	_field.sync(_terrain, [_ground_material(), _skirt])
	if _zone_whole or _zones.zone == null:
		_zones.build(doc)
	elif _zone_dirty.has_area():
		_zones.update(doc, _zone_dirty)
	_zone_whole = false
	_zone_dirty = Rect2i()
	var extent := doc.extent_m()
	for material: ShaderMaterial in [_ground_material(), _skirt]:
		material.set_shader_parameter(&"zone_map", _zones.zone_texture())
		material.set_shader_parameter(&"zone_present", true)
		material.set_shader_parameter(&"char_map", _zones.char_texture())
		material.set_shader_parameter(&"char_present", _zones.char_texture() != null)
		material.set_shader_parameter(&"zone2_map", _zones.biome_texture())
		material.set_shader_parameter(&"zone2_present", _zones.biome_texture() != null)
		material.set_shader_parameter(&"layer_grid_origin", -extent * 0.5)
		material.set_shader_parameter(&"layer_grid_step", doc.sample_step())
		material.set_shader_parameter(&"half_extent", extent * 0.5)
		material.set_shader_parameter(&"skirt_fall", AuthoredTerrain.SKIRT_FADE_M)
		material.set_shader_parameter(
			&"base_meadow", 1.0 if PainterGroundRoles.surface_role(doc.base_surface) == "meadow" else 0.0
		)
	var path_key: Array = [
		doc.surface_ids, doc.base_surface, doc.surface_weights, doc.samples_x(), doc.samples_z()
	]
	var paths_changed := path_key != _path_key
	var ids := PainterGroundPaths.bind([_ground_material(), _skirt], doc, paths_changed)
	if paths_changed:
		# Copies: a packed array is shared by assignment (measured, Godot 4.7), so a kept reference
		# would follow the document's own array and never differ.
		path_key[0] = doc.surface_ids.duplicate()
		path_key[2] = doc.surface_weights.duplicate()
		_path_key = path_key
	var cliff := PainterGroundPaths.cliff_surface(doc)
	var changed := ids != _path_ids or cliff != _cliff_surface
	_path_ids = ids
	_cliff_surface = cliff
	if changed and not applied.is_empty():
		var sheet := PainterSheet.load_sheet(applied["sheet"])
		_tone_ground(sheet, applied["mood"], applied["elevation"])
	_bind_wet()


## Gives the ground the terrain's wet dressing (its wet line darkens the bank in a brush-edged
## band). The skirt gets it too (card painter-edges2): the texture clamps at the map's edge, so the
## bank's band carries straight on along a river's channel patch, where it ended in a hard line
## at the map edge. The texture is updated in place by the terrain, so one bind serves
## every edit; a terrain that had no water yet binds it when its first one is made.
func _bind_wet() -> void:
	if _ground == null or not is_instance_valid(_terrain):
		return
	var wet := _terrain.get_water_texture()
	for material: ShaderMaterial in [_ground, _skirt]:
		material.set_shader_parameter(&"water_weights", wet)
		material.set_shader_parameter(&"water_present", wet != null)


## The zone maps (tests and probes).
func zones() -> PainterZoneMaps:
	return _zones


# ---------------------------------------------------------------- the scatter


## Paints every resolved species not looked at yet; returns the new [mesh, surface, original,
## stand-in, entry] records.
func _paint_species() -> Array:
	PainterPlantTone.mark_placed(_scatters)
	var added: Array = []
	for scatter in _scatters:
		if not is_instance_valid(scatter):
			continue
		var species: Dictionary = scatter.resolved_species()
		for asset_id: String in species:
			var record: Dictionary = species[asset_id]
			var mesh := record["mesh"] as Mesh
			if mesh == null or _seen.has(mesh.get_instance_id()):
				continue
			_seen[mesh.get_instance_id()] = true
			var entry := PainterPlantRoles.of_record(asset_id, record)
			if entry.is_empty():
				continue
			for i in mesh.get_surface_count():
				var swap := swap_surface(
					mesh,
					i,
					PainterPlantRoles.for_surface(entry, mesh.surface_get_material(i), mesh, i),
					float(record["height"])
				)
				if not swap.is_empty():
					added.append(swap)
	return added


## Puts a painted stand-in of `surface_entry` (PainterPlantRoles.of's shape) on surface `i` of
## `mesh`, remembering the original (released with the rest); the new [mesh, i, original, stand-in,
## entry] record, or [] when the surface's material cannot be stood in for. Not toned: the caller
## tones what it adds (_tone_new). Shared by the authored scatter's species and a GLB map's
## (PainterGlbMap).
func swap_surface(mesh: Mesh, i: int, surface_entry: Dictionary, height: float) -> Array:
	var original := mesh.surface_get_material(i)
	var stand_in := stand_in_of(original, surface_entry, height)
	if stand_in == null:
		return []
	var extent := mesh.get_aabb().size * 0.5
	stand_in.set_shader_parameter(&"selector_extent", extent)
	if int(surface_entry["kind"]) == PainterPlantRoles.KIND_GRASS:
		# A wide tuft is cut by painted dabs from the layouts' array (PainterTuftAtlas).
		stand_in.set_shader_parameter(
			&"tuft_atlas", PainterTuftAtlas.for_tuft(extent, maxf(height, 0.05))
		)
	mesh.surface_set_material(i, stand_in)
	var swap := [mesh, i, original, stand_in, surface_entry]
	_swapped.append(swap)
	return swap


## The painted material standing in for `original` (null when it cannot: no material, or one
## that is neither a wind material nor an imported one). Static: the painted village's baked decor
## makes its own (PainterVillage). A wind material is a ShaderMaterial that carries the wind
## category's meta or the vertex wind.
static func stand_in_of(original: Material, entry: Dictionary, height: float) -> ShaderMaterial:
	var stand_in: ShaderMaterial = null
	var wind := (
		original is ShaderMaterial
		and (
			original.has_meta("wind_category")
			or original.get_shader_parameter(&"use_vertex_wind") != null
		)
	)
	if wind:
		stand_in = (original as ShaderMaterial).duplicate() as ShaderMaterial
		stand_in.shader = load(PLANT_SHADER) as Shader
	elif original is BaseMaterial3D:
		var source := original as BaseMaterial3D
		stand_in = ShaderMaterial.new()
		stand_in.shader = load(SOLID_SHADER) as Shader
		stand_in.set_shader_parameter(&"albedo_texture", source.albedo_texture)
		stand_in.set_shader_parameter(
			&"cutout", source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		)
		stand_in.set_shader_parameter(&"alpha_scissor", source.alpha_scissor_threshold)
	if stand_in == null:
		return null
	stand_in.set_meta(META, true)
	stand_in.set_meta(WindFoliage.META_STAND_IN, original)
	stand_in.set_shader_parameter(&"kind", int(entry["kind"]))
	stand_in.set_shader_parameter(&"selector_height", maxf(height, 0.05))
	stand_in.set_shader_parameter(&"casts_shadow", not bool(entry["ground_cover"]))
	return stand_in


# ---------------------------------------------------------------- tones


func _retone() -> void:
	if applied.is_empty():
		return
	var sheet := PainterSheet.load_sheet(applied["sheet"])
	var mood: String = applied["mood"]
	var elevation: float = applied["elevation"]
	_tone_ground(sheet, mood, elevation)
	_bind_wet()
	for swap: Array in _swapped:
		PainterPlantTone.tone(swap[3], swap[4], sheet, mood, elevation)
	if _glb != null:
		_glb.call("retone", sheet, mood, elevation)


func _tone_new(added: Array) -> void:
	if applied.is_empty() or added.is_empty():
		return
	var sheet := PainterSheet.load_sheet(applied["sheet"])
	for swap: Array in added:
		PainterPlantTone.tone(swap[3], swap[4], sheet, applied["mood"], applied["elevation"])


func _tone_ground(sheet: Dictionary, mood: String, elevation: float) -> void:
	var lit := PackedVector3Array()
	var shade := PackedVector3Array()
	for role: String in PainterGroundRoles.ROLES:
		var base := Vector3(-1.0, 0.0, 0.0)
		var pull := 1.0
		var shade_lift := 0.0
		if PainterGroundRoles.DERIVED.has(role):
			base = PainterGroundRoles.derived(sheet, mood, role, elevation)
		elif role == "rock":
			# The cliff stone (PainterGroundPaths): its own tone and a lighter, less pulled shade.
			base = PainterGroundPaths.cliff_tone(sheet, mood, elevation, _cliff_surface)
			pull = PainterSheet.number(sheet, mood, "cliff-pull", elevation)
			shade_lift = PainterSheet.number(sheet, mood, "cliff-shade-lift", elevation)
		var ramp := PainterTones.ramp(
			sheet,
			mood,
			PainterGroundRoles.TONE_ROLE[role],
			elevation,
			"ground-",
			base,
			pull,
			shade_lift
		)
		var colors: Array[Vector3] = []
		for at: int in [2, 5, 0, 3]:
			var c := PainterTones.linear(ramp[at])
			colors.append(PainterGroundRoles.char_of(c) if role == "char" else c)
		lit.append_array([colors[0], colors[1]])
		shade.append_array([colors[2], colors[3]])
	var num := func(prop: String) -> float: return PainterSheet.number(sheet, mood, prop, elevation)
	var tone := func(role: String) -> Vector3:
		return PainterTones.linear(PainterSheet.tone(sheet, mood, role, elevation))
	var grounds: Array[ShaderMaterial] = [_ground_material(), _skirt]
	grounds.append_array(_glb_ground)
	var paths := PainterGroundPaths.tones(sheet, mood, elevation, _path_ids)
	for material: ShaderMaterial in grounds:
		material.set_shader_parameter(&"g_lit", lit)
		material.set_shader_parameter(&"g_shd", shade)
		PainterGroundPaths.set_tones(material, paths)
		material.set_shader_parameter(&"cliff_edge", num.call("cliff-edge"))
		material.set_shader_parameter(&"cliff_strata", num.call("cliff-strata"))
		material.set_shader_parameter(&"litter_col", tone.call("litter"))
		material.set_shader_parameter(&"drift_col", tone.call("drift"))
		material.set_shader_parameter(&"drift", num.call("drift-marks"))
		material.set_shader_parameter(&"litter", num.call("litter-marks"))
		material.set_shader_parameter(&"patches", num.call("patches"))
		material.set_shader_parameter(&"marks", num.call("marks"))
		material.set_shader_parameter(&"mark_thin", num.call("mark-thin"))
		material.set_shader_parameter(
			&"mark_px", Vector2(num.call("mark-px-lo"), num.call("mark-px-hi"))
		)
		material.set_shader_parameter(&"cut_amp", num.call("cut"))
		material.set_shader_parameter(&"stroke_dir", _stroke_dir())
		material.set_shader_parameter(
			&"foot_col", PainterTones.linear(PainterScene.foot_color(sheet, mood, elevation))
		)


## The direction the ground's marks lie along: the camera's right in the map's XZ.
func _stroke_dir() -> Vector2:
	if _map == null or not _map.is_inside_tree():
		return Vector2.RIGHT
	var camera := _map.get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.RIGHT
	var right := camera.global_basis.x
	var flat := Vector2(right.x, right.z)
	return flat.normalized() if flat.length() > 0.01 else Vector2.RIGHT
