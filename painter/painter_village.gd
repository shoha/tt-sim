class_name PainterVillage
extends RefCounted

## The painted look's village furnishings: while a level is drawn Painted, the props the dressed
## streets stand (AuthoredSettlements: crates, barrels, carts, stalls, wells, signposts, lamp
## posts, haystacks, laundry, benches ...) and the decor plants baked onto the structures (ivy,
## window planters: the `decor_baked` mesh of a `Structure_<id>`) wear painted materials coloured
## from the sheet (docs/systems/painter.md "Village furnishings"). The village's field plants
## (orchards, gardens, hedges) are not here: they are drawn by the same hosts as the scatter's
## plants (AuthoredFieldPlants answers PainterSurfaces and PainterTrees like a scatter).
##
## PainterSurfaces makes one (loaded by path on the first painted map, as PainterBuildings) and
## drives it with paint() and release(). Events, never a poll: the map's child_entered_tree finds
## the layers made after the first paint, each layer's child_entered_tree dresses a cell or a
## structure built later (a refresh's re-bake, an edit's rebuild, a load's staged install).
##
## What it swaps, and the exact restore. A settlement cell is ONE MeshInstance3D with a surface per
## `<role>:<kind>` material (SettlementBake); a prop's surfaces (role `prop`, kinds wood, stone,
## thatch, accent and cloth) get painted_prop stand-ins by mesh.surface_set_material, the original
## kept per surface and put back by release(). A lantern's glass and a well's water keep Classic
## (lights; the water is no terrain water); a lantern's halo gets painter_glow.gdshader (a painted
## halo of three torn steps, one shared material). A structure's `decor_baked` mesh
## has a surface per wind material: each gets the plants' stand-in (painter_plant.gdshader, kind
## solid: the baked mesh has no per-plant origin for a leaf mass's form) in the leaf role, or the
## bark role for a material named `*bark*`; the plants' own wind, fade and cutout uniforms are
## kept. Decor plants too big to bake keep their MultiMesh and their Classic material.
##
## Tones. The props' eight ramps are the buildings' (PainterBuildings.ramp: timber, wall stone,
## thatch, clay, turf, slate, plaster), their snow the roofs'; the shader picks one by each part's
## own paint, so winter, dusk and grimdark tone the props with the houses. The decor plants take
## PainterPlantTone.tone, as the scatter's plants do. A new elevation re-tones the same
## materials.

const PROP_SHADER := "res://painter/shaders/painter_prop.gdshader"
## The lantern halo's (a prop surface of kind StructureGlow.KIND).
const GLOW_SHADER := "res://painter/shaders/painter_glow.gdshader"
## Metadata on every material this paints with.
const META := &"painter_village"
## The map's layers this follows (AuthoredSettlements.NODE_NAME, PainterBuildings.STRUCTURES).
const SETTLEMENTS := "AuthoredSettlements"
const STRUCTURES := "AuthoredStructures"
## The decor mesh of a structure (AuthoredStructures.DECOR_NODE).
const DECOR_NODE := "decor_baked"
## The surface kinds of a prop that keep Classic (a prop's lantern glass).
const CLASSIC_KINDS: Array[String] = ["glass"]
## The shader's eight tones: [sheet role, ramp family], in its order.
const TONES: Array = [
	["timber", "timber"],
	["wall-stone", "stone"],
	["roof-thatch", "roof"],
	["roof-clay", "roof"],
	["roof-turf", "roof"],
	["roof-slate", "roof"],
	["plaster", "wall"],
	["roof-thatch", "roof"],
]
## A kind whose every vertex takes one tone (the shader's force_tone), else the paint chooses.
const FORCED: Dictionary = {"stone": 1, "thatch": 2}
## A prop wood's middle tone against the timber role's (prop_wood_middle).
const WOOD_VALUE := 1.7
const WOOD_CHROMA := 1.45
const WOOD_TURN := 14.0
const WOOD_MAX_L := 0.8
## Slots of the ramps uniform (eight tones of six).
const RAMP_SLOTS := 48

## False leaves the props Classic, the decor plants, or the field plants (orchards, gardens, hedges,
## crops: PainterSurfaces._is_plant_source) as Classic (the A/B switches for measurements). Read
## when a layer is dressed: change one, then release() and paint() again.
static var furnishings := true
static var decor_plants := true
static var field_plants := true

## What is drawn now: {"sheet", "mood", "elevation"}, {} while nothing is painted.
var applied: Dictionary = {}

var _map: Node3D = null
var _settlements: Node = null
var _structures: Node = null
## "free", "stone" or "thatch" -> the shared prop stand-in.
var _props: Dictionary = {}
## The painted lantern halo's material (null until a halo needs it).
var _glow: ShaderMaterial = null
## Original decor material instance id -> its stand-in.
var _decor: Dictionary = {}
## [WeakRef of the mesh, surface, original, stand-in, is decor] per replaced surface.
var _swapped: Array = []


## Paints the village layers of `map` (a LevelMap) in `state` ({"sheet", "mood", "elevation"}), or
## re-tones them when they are already painted; a different map than the last is released first.
## False, touching nothing, when the sheet or the mood is missing.
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
		_map.child_entered_tree.connect(_on_map_child)
		_bind_settlements(_map.get_node_or_null(SETTLEMENTS))
		_bind_structures(_map.get_node_or_null(STRUCTURES))
	_retone(sheet)
	return true


## Puts every surface back as it was before the first paint() and stops following the map.
func release() -> void:
	if is_instance_valid(_map) and _map.child_entered_tree.is_connected(_on_map_child):
		_map.child_entered_tree.disconnect(_on_map_child)
	_unbind_settlements()
	_unbind_structures()
	for swap: Array in _swapped:
		var mesh := (swap[0] as WeakRef).get_ref() as Mesh
		if mesh != null and swap[1] < mesh.get_surface_count():
			if mesh.surface_get_material(swap[1]) == swap[3]:
				mesh.surface_set_material(swap[1], swap[2])
	_swapped.clear()
	_map = null
	applied = {}


## Whether anything is painted.
func is_active() -> bool:
	return not applied.is_empty()


## The prop stand-ins now made ("free", "stone", "thatch").
func prop_materials() -> Dictionary:
	return _props


## The decor stand-ins now made.
func decor_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for stand_in: ShaderMaterial in _decor.values():
		out.append(stand_in)
	return out


## How many surfaces are painted now: props (decor false) or decor plants (true).
func painted_count(decor: bool) -> int:
	_prune()
	var n := 0
	for swap: Array in _swapped:
		if bool(swap[4]) == decor:
			n += 1
	return n


## The tone slot (0..7, the shader's prop_tone) a prop paint takes: the same rule as the shader,
## for tests and for a tool that wants to know. `paint` is the recipe's colour (sRGB-like numbers).
static func tone_of(paint: Color) -> int:
	var hi := maxf(paint.r, maxf(paint.g, paint.b))
	var lo := minf(paint.r, minf(paint.g, paint.b))
	var sat := (hi - lo) / hi if hi > 0.001 else 0.0
	if sat < 0.18:
		return 6 if hi > 0.85 else 1
	var h := paint.h * 360.0
	if h >= 18.0 and h < 36.0 and sat < 0.66 and hi < 0.88:
		return 0
	if h >= 36.0 and h < 65.0:
		return 2
	if h >= 65.0 and h < 165.0:
		return 4
	if h >= 165.0 and h < 330.0:
		return 5
	return 3


# ---------------------------------------------------------------- following the map


func _on_map_child(node: Node) -> void:
	if applied.is_empty():
		return
	if str(node.name) == SETTLEMENTS:
		_bind_settlements(node)
	elif str(node.name) == STRUCTURES:
		_bind_structures(node)


func _bind_settlements(layer: Node) -> void:
	if layer == null or layer == _settlements:
		return
	_unbind_settlements()
	_settlements = layer
	_settlements.child_entered_tree.connect(_on_cell)
	for child in _settlements.get_children():
		_dress_cell(child)


func _unbind_settlements() -> void:
	if is_instance_valid(_settlements) and _settlements.child_entered_tree.is_connected(_on_cell):
		_settlements.child_entered_tree.disconnect(_on_cell)
	_settlements = null


func _bind_structures(layer: Node) -> void:
	if layer == null or layer == _structures:
		return
	_unbind_structures()
	_structures = layer
	_structures.child_entered_tree.connect(_on_structure)
	for child in _structures.get_children():
		_dress_decor(child)


func _unbind_structures() -> void:
	if is_instance_valid(_structures) and _structures.child_entered_tree.is_connected(_on_structure):
		_structures.child_entered_tree.disconnect(_on_structure)
	_structures = null


func _on_cell(node: Node) -> void:
	_prune()
	_dress_cell(node)


func _on_structure(node: Node) -> void:
	_prune()
	_dress_decor(node)


## Forgets the records of freed meshes (a re-baked cell, a rebuilt structure).
func _prune() -> void:
	var kept: Array = []
	for swap: Array in _swapped:
		if (swap[0] as WeakRef).get_ref() != null:
			kept.append(swap)
	_swapped = kept


# ---------------------------------------------------------------- the furnishings


## Puts the prop stand-ins on the prop surfaces of a baked settlement cell.
func _dress_cell(node: Node) -> void:
	var cell := node as MeshInstance3D
	if applied.is_empty() or not furnishings or cell == null or cell.mesh == null:
		return
	if not cell.has_meta(AuthoredSettlements.META):
		return
	var mesh := cell.mesh
	for i in mesh.get_surface_count():
		var original := mesh.surface_get_material(i)
		if original == null or original.has_meta(META):
			continue
		var part := str(original.get_meta(AuthoredSettlements.PART_META, "")).split(":")
		if part.size() != 2 or part[0] != StructureLook.PROP or CLASSIC_KINDS.has(part[1]):
			continue
		var stand_in: ShaderMaterial = (
			_glow_material() if part[1] == StructureGlow.KIND else _prop_material(str(part[1]))
		)
		_swapped.append([weakref(mesh), i, original, stand_in, false])
		mesh.surface_set_material(i, stand_in)


## The painted lantern halo (painter_glow.gdshader), shared by every halo; it takes no sheet tone
## (the lantern's amber is a light, not a mood's colour).
func _glow_material() -> ShaderMaterial:
	if _glow == null:
		_glow = ShaderMaterial.new()
		_glow.shader = load(GLOW_SHADER) as Shader
		_glow.set_meta(META, true)
	return _glow


## The shared stand-in for a prop surface of `kind` (made on first use, toned at once).
func _prop_material(kind: String) -> ShaderMaterial:
	var key := "free"
	if FORCED.has(kind):
		key = kind
	if _props.has(key):
		return _props[key]
	var material := ShaderMaterial.new()
	material.shader = load(PROP_SHADER) as Shader
	material.set_meta(META, true)
	material.set_shader_parameter(&"force_tone", int(FORCED.get(key, -1)))
	_props[key] = material
	if not applied.is_empty():
		_tone_prop(material, PainterSheet.load_sheet(applied["sheet"]))
	return material


## The middle tone (OKLCH) of a prop's wood from the timber role's (`timber`, the houses' dark
## beams): `WOOD_VALUE` times its lightness (at most `WOOD_MAX_L`), `WOOD_CHROMA` times its chroma
## and its hue turned `WOOD_TURN` degrees toward honey, so a fence, a barrel or a cart reads as
## honey oak beside the painted houses (Classic's props are honey) and follows every mood and sun
## as the beams do. Relative: night's and grimdark's timber stays darker. Pure.
static func prop_wood_middle(timber: Vector3) -> Vector3:
	return Vector3(
		minf(timber.x * WOOD_VALUE, WOOD_MAX_L),
		timber.y * WOOD_CHROMA,
		fposmod(timber.z + WOOD_TURN, 360.0)
	)


func _tone_prop(material: ShaderMaterial, sheet: Dictionary) -> void:
	var mood: String = applied["mood"]
	var elevation: float = applied["elevation"]
	var ramps := PackedVector3Array()
	for index in TONES.size():
		var tone: Array = TONES[index]
		var middle := (
			prop_wood_middle(PainterSheet.tone_lch(sheet, mood, "timber", elevation))
			if index == 0
			else Vector3(-1.0, 0.0, 0.0)
		)
		ramps.append_array(
			PainterBuildings.ramp(sheet, mood, str(tone[0]), elevation, str(tone[1]), middle)
		)
	ramps.resize(RAMP_SLOTS)
	material.set_shader_parameter(&"ramps", ramps)
	material.set_shader_parameter(
		&"snow", PainterSheet.number(sheet, mood, PainterBuildings.SNOW_NUMBER, elevation)
	)
	material.set_shader_parameter(&"snow_ramp", PainterBuildings.snow_ramp(sheet, mood, elevation))
	material.set_shader_parameter(&"tone_lo", PainterSheet.number(sheet, mood, "tone-lo", elevation))
	material.set_shader_parameter(&"tone_hi", PainterSheet.number(sheet, mood, "tone-hi", elevation))


# ---------------------------------------------------------------- the decor plants


## Puts the plants' stand-ins on the wind surfaces of a structure's baked decor mesh.
func _dress_decor(structure: Node) -> void:
	if applied.is_empty() or not decor_plants:
		return
	var decor := structure.get_node_or_null(DECOR_NODE) as MeshInstance3D
	if decor == null or decor.mesh == null:
		return
	var mesh := decor.mesh
	for i in mesh.get_surface_count():
		var original := mesh.surface_get_material(i)
		if original == null or original.has_meta(META):
			continue
		var entry := decor_entry(original)
		var stand_in: ShaderMaterial = _decor.get(original.get_instance_id())
		if stand_in == null:
			stand_in = PainterSurfaces.stand_in_of(original, entry, StructureDecor.BAKE_MESH_HEIGHT)
			if stand_in == null:
				continue
			# One form for the whole mesh: no foot darkening, no instance origin to read.
			stand_in.set_shader_parameter(&"casts_shadow", false)
			stand_in.set_meta(META, true)
			_decor[original.get_instance_id()] = stand_in
			if not applied.is_empty():
				_tone_decor(stand_in, entry, PainterSheet.load_sheet(applied["sheet"]))
		_swapped.append([weakref(mesh), i, original, stand_in, true])
		mesh.surface_set_material(i, stand_in)


## The plants' entry for a baked decor surface of `material`: a solid in the leaf role, or in the
## bark role when the material is named for bark (the form's lighting needs a plant's origin that
## a baked mesh does not have, so no leaf mass).
static func decor_entry(material: Material) -> Dictionary:
	var named := "" if material == null else material.resource_name.to_lower()
	return {
		"kind": PainterPlantRoles.KIND_SOLID,
		"role": "bark" if named.contains("bark") else "leaf",
		"ground_cover": false,
	}


func _tone_decor(material: ShaderMaterial, entry: Dictionary, sheet: Dictionary) -> void:
	PainterPlantTone.tone(material, entry, sheet, applied["mood"], applied["elevation"])


# ---------------------------------------------------------------- tones


func _retone(sheet: Dictionary) -> void:
	_prune()
	for material: ShaderMaterial in _props.values():
		_tone_prop(material, sheet)
	for swap: Array in _swapped:
		if bool(swap[4]):
			_tone_decor(swap[3], decor_entry(swap[2]), sheet)
	# Cells and structures built since the last paint (and ones a switch of the A/B flags frees).
	if is_instance_valid(_settlements):
		for child in _settlements.get_children():
			_dress_cell(child)
	if is_instance_valid(_structures):
		for child in _structures.get_children():
			_dress_decor(child)
