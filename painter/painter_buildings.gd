class_name PainterBuildings
extends RefCounted

## The painted look's buildings: while a level is drawn Painted, the walls, roofs, timber and
## stone of every built structure (AuthoredStructures under the level's map) wear a sheet-driven
## stand-in (painter/shaders/painter_structure.gdshader; docs/systems/painter.md "Buildings").
## Owner decision D5 (2026-11-12): phase 1 paints the recipe meshes as they are; the
## prototype's hand-drawn manner (edges, piece ids, wobble) waits for procgen's data.
##
## PainterSurfaces makes one (loaded by path on the first painted map, as PainterTrees) and
## drives it from LevelEnvironmentManager.painted_look_changed: paint() swaps or re-tones,
## release() puts everything back. Events, never a poll: AuthoredStructures.child_entered_tree
## dresses a structure built later (a load's staged install, an edit's rebuild, an undo), and the
## map's child_entered_tree finds an AuthoredStructures made after the first paint.
##
## What it swaps, and the exact restore. A structure's meshes are `<role>_<kind>` MeshInstance3Ds
## (`cap_`, `wheel_`, `vane_` in front for a mill's and a vane's turning parts) sharing one Classic
## material per kind on the mesh surface. A painted part gets a material_override (the shared
## surface material is never touched); the override it had is kept per node and put back. Parts
## of kinds not in KINDS keep Classic: panes and lantern glass, doors' metal, ornaments, props,
## water, glow halos and decor plants. The yard's dressing (its planting and its ground skirt)
## takes the yard's own two shaders (YARD). Each stand-in carries META.
##
## Tones. Every colour is the sheet's: a role's ramp (PainterTones.steps over the mood's ramp
## numbers moved by the buildings' own, relative ones: wall-shade-turn, wall-pull, stone-pull,
## wall-shade-lift, roof-pull, roof-shade-lift, timber-shade-turn, timber-pull, building-lit).
## Stone takes less of the pull than a lime wash: the same chroma on a darker grey read as a
## periwinkle slab (painter-a3b round 1).
## A tile or wooden roof holds the four roof tones it may choose from by its paint (the shader's
## roof_tone). A new elevation re-tones the same materials.

const SHADER := "res://painter/shaders/painter_structure.gdshader"
## Metadata on every material this paints with.
const META := &"painter_building"
## The structures' node under a map root (AuthoredStructures.NODE_NAME).
const STRUCTURES := "AuthoredStructures"
## The prefixes of a mill's and a vane's mesh names (AuthoredStructures.mill_node, vane_node).
const PART_PREFIXES: Array[String] = ["cap_", "wheel_", "vane_"]
## A picked roof's tones, in the shader's order.
const PICK_ROLES: Array[String] = ["roof-clay", "roof-slate", "roof-shingle", "roof-turf"]
## The sheet role of a picked roof (its tone comes from its paint).
const PICK := ""
## A painted door's or shutter's tones, in the shader's order (paint_tone): unpainted wood is
## timber; a red or orange paint takes the clay, a green the turf, a blue the slate (the sheet's
## accents in every mood; Classic's red doors and orange shutters became brown under A3b).
const ACCENT_ROLES: Array[String] = ["timber", "roof-clay", "roof-turf", "roof-slate"]
## The sheet role of a door or shutter whose tone comes from its paint.
const ACCENT := "accent"
## The yard's dressing (card painter-buildings-fix2): its props (YARD_SHADER) take one of four
## ramps by their Classic colour, in the shader's order, each under its own building family's
## ramp numbers; its ground skirt and path (YARD_GROUND_SHADER) the path's.
const YARD := "yard"
const YARD_ROLES: Array[String] = ["leaf", "stone", "timber", "flower-rose"]
const YARD_FAMILIES: Array[String] = ["roof", "stone", "timber", "wall"]
const YARD_GROUND_ROLE := "path"
const YARD_SHADER := "res://painter/shaders/painter_yard.gdshader"
const YARD_GROUND_SHADER := "res://painter/shaders/painter_yard_ground.gdshader"
## The pick modes (KINDS' fourth field) that draw with the yard's shaders.
const PICK_YARD := 4
const PICK_YARD_GROUND := 5
## The pick modes of a chimney's stack and of its cap and pots (card painter-look-houses2): the
## ramps are the stone's, the moss leaf's and the clay's (a brick stack, a terracotta pot, a
## roof's ridge cap), the shader picks among them; the tone never follows the recipe's paint.
const PICK_STACK := 6
const PICK_CAP := 7
## The pick mode of the roofs' snow (card painter-look-roofs-winter): the ramps are PICK_ROLES' and
## the thatch's (a fifth), the tone comes from the kind and paint the snow mesh's vertex colour
## carries (PainterMannerSnow, the shader's vertex step), so the snow can show its roof's colour.
const PICK_SNOW := 8
## The ramp slots a manner material holds (PICK_ROLES' four, the thatch's, one spare).
const MANNER_RAMP_SLOTS := 30
## The role a chimney's brick and pots, and a slate roof's ridge cap, take (the third ramp).
const BRICK_ROLE := "roof-clay"
## The role the roofs' snow takes its colour from (winter's is the snow's white, under the
## ground's ramp numbers: snow_ramp) and the number that says how deep it lies (0 in every mood
## but winter; above 0 the hand-drawn manner also builds its strips, PainterMannerSnow).
const SNOW_ROLE := "drift"
const SNOW_NUMBER := "roof-snow"
## The sheet role of the moss and lichen on stone and slate (the second ramp of such a material).
const MOSS_ROLE := "leaf"
## The shader's patterns.
const P_PLASTER := 0
const P_STONE := 1
const P_LOG := 2
const P_BOARDS := 3
const P_TIMBER := 4
const P_TILE := 5
const P_SLATE := 6
const P_SHINGLE := 7
const P_THATCH := 8
const P_TURF := 9
## `<role>_<kind>` -> [sheet role (PICK: by the roof's paint), pattern, ramp family, pick mode].
## A roof of a kind not listed (a plaster gable end) is painted as the wall of that kind.
const KINDS: Dictionary = {
	"wall_plaster": ["plaster", P_PLASTER, "wall", 0],
	"wall_adobe": ["plaster", P_PLASTER, "wall", 0],
	"wall_masonry": ["wall-stone", P_STONE, "stone", 0],
	"wall_stone": ["wall-stone", P_STONE, "stone", 0],
	"wall_brick": ["roof-clay", P_STONE, "stone", 0],
	"wall_log": ["wall-log", P_LOG, "wall", 0],
	"wall_boards": ["wall-boards", P_BOARDS, "wall", 0],
	"wall_wood": ["wall-boards", P_BOARDS, "wall", 0],
	"roof_thatch": ["roof-thatch", P_THATCH, "roof", 0],
	"roof_slate": ["roof-slate", P_SLATE, "roof", 0],
	"roof_shingle": ["roof-shingle", P_SHINGLE, "roof", 0],
	"roof_turf": ["roof-turf", P_TURF, "roof", 0],
	"roof_tile": [PICK, P_TILE, "roof", 1],
	"roof_wood": [PICK, P_SHINGLE, "roof", 2],
	"roof_snow": [PICK, P_TILE, "roof", PICK_SNOW],
	"trim_stone": ["wall-stone", P_STONE, "stone", 0],
	"trim_masonry": ["wall-stone", P_STONE, "stone", 0],
	"chimney_stone": ["wall-stone", P_STONE, "stone", PICK_CAP],
	"chimney_masonry": ["wall-stone", P_STONE, "stone", PICK_STACK],
	"chimney_brick": ["roof-clay", P_STONE, "stone", PICK_STACK],
	"trim_wood": ["timber", P_TIMBER, "timber", 0],
	"trim_trim": ["timber", P_TIMBER, "timber", 0],
	"frame_wood": ["timber", P_TIMBER, "timber", 0],
	"opening_wood": [ACCENT, P_TIMBER, "timber", 3],
	"door_wood": [ACCENT, P_TIMBER, "timber", 3],
	"dressing_props": [YARD, 0, "yard", PICK_YARD],
	"dressing_ground": [YARD, 0, "yard", PICK_YARD_GROUND],
}

## True (the default) puts the hand-drawn manner on every painted structure procgen gives manner
## records for (PainterMannerHost); false draws them all in the A3b look, the fallback a
## structure without records keeps (an A/B switch for measurements). Read when a structure is
## dressed: change it, then release() and paint() again.
static var hand_drawn := true
## False leaves the yard's dressing Classic, as before card painter-buildings-fix2 (an A/B switch
## for measurements). Read when a structure is dressed: change it, then release() and paint().
static var paint_yard := true

## What is drawn now: {"sheet", "mood", "elevation"}, {} while nothing is painted.
var applied: Dictionary = {}
## The hand-drawn manner's host, made on the first dress while hand_drawn is set.
var manner: PainterMannerHost = null

var _map: Node3D = null
var _structures: Node = null
## `<role>_<kind>` -> the shared stand-in.
var _materials: Dictionary = {}
## Node instance id -> [node, the material_override it had].
var _swapped: Dictionary = {}


## Paints the structures of `map` (a LevelMap) in `state` ({"sheet", "mood", "elevation"}), or
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
	# Structures built from now on bring their manner records with them (one evaluation).
	StructureGeometry.manner_records = hand_drawn
	if _map == null:
		_map = map
		_map.child_entered_tree.connect(_on_map_child)
		_bind(_map.get_node_or_null(STRUCTURES))
	_retone()
	return true


## Puts every override back as it was before the first paint() and stops following the map.
func release() -> void:
	if is_instance_valid(_map) and _map.child_entered_tree.is_connected(_on_map_child):
		_map.child_entered_tree.disconnect(_on_map_child)
	_unbind()
	if manner != null:
		manner.restore_all()
	for id: int in _swapped:
		var pair: Array = _swapped[id]
		if is_instance_valid(pair[0]):
			(pair[0] as GeometryInstance3D).material_override = pair[1]
	_swapped.clear()
	_map = null
	applied = {}
	StructureGeometry.manner_records = false


## Whether anything is painted.
func is_active() -> bool:
	return not applied.is_empty()


## The parts painted now (live MeshInstance3Ds).
func painted() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for id: int in _swapped:
		var node: Variant = _swapped[id][0]
		if is_instance_valid(node):
			out.append(node as MeshInstance3D)
	return out


## Hands the building `structure` (a child of AuthoredStructures) to an event that burns it (card
## painter-fire): {"structure", "nodes", "burning"} where nodes are its parts painted now (the base
## and the hand-drawn shaders both carry the `burn` instance uniform, from
## painter_building_burn.gdshaderinc), or {} when nothing of it is painted. A structure's parts
## are nodes already, so no pivot is needed to burn one; the structure's own transform is the
## event's to move. Nothing calls it yet: no event burns a building (docs/systems/painter.md "Fire
## and events").
func take(structure: Node, burning: bool = true) -> Dictionary:
	var nodes: Array[MeshInstance3D] = []
	if is_instance_valid(structure):
		for node: Node in structure.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var material := mi.material_override as ShaderMaterial
			if material != null and material.shader != null and _burnable(material.shader):
				nodes.append(mi)
	if nodes.is_empty():
		return {}
	return {"structure": structure, "nodes": nodes, "burning": burning}


## Sets the burn of a taken building (0 untouched; char climbs from the foot as it rises to about
## 1.4, FireSweep.burn_progress's scale).
func set_burn(actor: Dictionary, value: float) -> void:
	for mi: MeshInstance3D in actor.get("nodes", []):
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter(&"burn", value)


## Lets a taken building go: its parts draw unburnt again.
func drop(actor: Dictionary) -> void:
	set_burn(actor, 0.0)


func _burnable(shader: Shader) -> bool:
	return shader.resource_path in [SHADER, PainterMannerHost.SHADER]


## The stand-in of `<role>_<kind>` `key` (null before it was needed).
func material_of(key: String) -> ShaderMaterial:
	return _materials.get(key)


## [sheet role, pattern, family, pick] of a structure mesh named `node_name`; [] for a part that
## keeps Classic. Pure.
static func kind_of(node_name: String) -> Array:
	var key := part_key(node_name)
	if not paint_yard and str(KINDS.get(key, [""])[0]) == YARD:
		return []
	if KINDS.has(key):
		return KINDS[key]
	if key.begins_with("roof_"):
		var as_wall := "wall_" + key.trim_prefix("roof_")
		if KINDS.has(as_wall):
			return KINDS[as_wall]
	return []


## `node_name` without a mill's or a vane's prefix: its `<role>_<kind>`. Pure.
static func part_key(node_name: String) -> String:
	for prefix in PART_PREFIXES:
		if node_name.begins_with(prefix):
			return node_name.trim_prefix(prefix)
	return node_name


# ---------------------------------------------------------------- following the map


func _on_map_child(node: Node) -> void:
	if str(node.name) == STRUCTURES and node != _structures:
		_bind(node)


func _bind(structures: Node) -> void:
	if structures == null:
		return
	_unbind()
	_structures = structures
	_structures.child_entered_tree.connect(_on_structure)
	for child in _structures.get_children():
		_dress(child)


func _unbind() -> void:
	if is_instance_valid(_structures) and _structures.child_entered_tree.is_connected(_on_structure):
		_structures.child_entered_tree.disconnect(_on_structure)
	_structures = null


func _on_structure(node: Node) -> void:
	_prune()
	_dress(node)


## Puts the stand-ins on every painted part under a structure's node.
func _dress(structure: Node) -> void:
	if applied.is_empty():
		return
	for node: Node in structure.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var key := part_key(str(node.name))
		if _swapped.has(mesh_instance.get_instance_id()) or kind_of(key).is_empty():
			continue
		_swapped[mesh_instance.get_instance_id()] = [mesh_instance, mesh_instance.material_override]
		mesh_instance.material_override = _material(key)
	if hand_drawn:
		if manner == null:
			manner = PainterMannerHost.new(self)
		manner.dress(structure)


## Forgets the records of freed parts (a rebuilt structure's old node).
func _prune() -> void:
	for id: int in _swapped.keys():
		if not is_instance_valid(_swapped[id][0]):
			_swapped.erase(id)


func _material(key: String) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var kind := kind_of(key)
	var material := ShaderMaterial.new()
	var pick := int(kind[3])
	var path := SHADER
	if pick == PICK_YARD:
		path = YARD_SHADER
	elif pick == PICK_YARD_GROUND:
		path = YARD_GROUND_SHADER
	material.shader = load(path) as Shader
	material.set_meta(META, true)
	if path == SHADER:
		material.set_shader_parameter(&"pattern", int(kind[1]))
		material.set_shader_parameter(&"pick", pick)
	_materials[key] = material
	if not applied.is_empty():
		_tone(material, kind, PainterSheet.load_sheet(applied["sheet"]))
	return material


# ---------------------------------------------------------------- tones


func _retone() -> void:
	_prune()
	var sheet := PainterSheet.load_sheet(applied["sheet"])
	for key: String in _materials:
		_tone(_materials[key], kind_of(key), sheet)
	if manner != null:
		manner.retone(sheet)
	if is_instance_valid(_structures):
		for child in _structures.get_children():
			_dress(child)


func _tone(material: ShaderMaterial, kind: Array, sheet: Dictionary) -> void:
	var mood: String = applied["mood"]
	var elevation: float = applied["elevation"]
	var roles: Array[String] = []
	var families: Array[String] = []
	if str(kind[0]) == PICK:
		roles.assign(PICK_ROLES)
		if int(kind[3]) == PICK_SNOW:
			roles.append("roof-thatch")
	elif str(kind[0]) == ACCENT:
		roles.assign(ACCENT_ROLES)
	elif str(kind[0]) == YARD and int(kind[3]) == PICK_YARD:
		roles.assign(YARD_ROLES)
		families.assign(YARD_FAMILIES)
	elif str(kind[0]) == YARD:
		roles.append(YARD_GROUND_ROLE)
		families.append("stone")
	else:
		roles.append(str(kind[0]))
		if int(kind[1]) == P_STONE or int(kind[1]) == P_SLATE:
			# Stone and slate carry the leaf's ramp as a second role (slots 6 to 11) for the
			# moss and lichen the manner shader lays on them (card painter-look-houses), and the
			# clay's (slots 12 to 17): a chimney's brick and pots, a slate roof's ridge cap (card
			# painter-look-houses2).
			roles.append(MOSS_ROLE)
			if int(kind[3]) >= PICK_STACK or int(kind[1]) == P_SLATE:
				roles.append(BRICK_ROLE)
	var ramps := PackedVector3Array()
	for k in roles.size():
		var family := families[k] if k < families.size() else str(kind[2])
		ramps.append_array(ramp(sheet, mood, roles[k], elevation, family))
	var manner := (
		material.shader != null and material.shader.resource_path.ends_with("_manner.gdshader")
	)
	ramps.resize(MANNER_RAMP_SLOTS if manner else PICK_ROLES.size() * 6)
	material.set_shader_parameter(&"ramps", ramps)
	material.set_shader_parameter(
		&"snow", PainterSheet.number(sheet, mood, SNOW_NUMBER, elevation)
	)
	material.set_shader_parameter(&"snow_ramp", snow_ramp(sheet, mood, elevation))
	material.set_shader_parameter(
		&"tone_lo", PainterSheet.number(sheet, mood, "tone-lo", elevation)
	)
	material.set_shader_parameter(
		&"tone_hi", PainterSheet.number(sheet, mood, "tone-hi", elevation)
	)


## How much snow lies on the roofs now (the sheet's roof-snow in the applied mood; 0 while
## nothing is painted or the mood lays none).
func snow_amount() -> float:
	if applied.is_empty():
		return 0.0
	var sheet := PainterSheet.load_sheet(applied["sheet"])
	return PainterSheet.number(sheet, applied["mood"], SNOW_NUMBER, applied["elevation"])


## The roofs' snow as three LINEAR colours [shade, mid, lit]: the drift role's white under the
## ground's own ramp numbers (the ground snow's strong blue shade), its two variants averaged.
## Pure.
static func snow_ramp(sheet: Dictionary, mood: String, elevation: float) -> PackedVector3Array:
	var colours := PainterTones.ramp(sheet, mood, SNOW_ROLE, elevation, "ground-")
	var out := PackedVector3Array()
	for step in 3:
		out.append(
			PainterTones.linear(colours[step]).lerp(PainterTones.linear(colours[step + 3]), 0.5)
		)
	return out


## The six LINEAR colours [shade0, mid0, lit0, shade1, mid1, lit1] of building role `role`
## (`family` "wall", "stone", "roof" or "timber") in `mood` at `elevation`. Pure.
static func ramp(
	sheet: Dictionary, mood: String, role: String, elevation: float, family: String
) -> PackedVector3Array:
	var base := PainterSheet.tone_lch(sheet, mood, role, elevation)
	var shape := shape_of(sheet, mood, elevation, family)
	var hue_spread := PainterSheet.number(sheet, mood, "hue-spread", elevation)
	var value_spread := PainterSheet.number(sheet, mood, "value-spread", elevation)
	var out := PackedVector3Array()
	for variant in 2:
		var side := float(variant) * 2.0 - 1.0
		var lch := Vector3(base.x + side * value_spread, base.y, base.z + side * hue_spread)
		var steps := PainterTones.steps(lch, shape)
		steps[2] = lit_step(lch, shape)
		for step: Vector3 in steps:
			out.append(PainterTones.linear(PainterSheet.color_of_lch(step)))
	return out


## A building role's lit step: `lit-lift` lighter and its chroma moved toward `lit-hue` as a
## vector (as the shade's pull is), not its hue turned by an angle: a blue slate sits opposite
## summer's yellow lit hue, and turning it sent one variant to teal and the other to pink
## (painter-a3b round 2, h156 and h359 on one roof). Pure.
static func lit_step(lch: Vector3, shape: Dictionary) -> Vector3:
	var own := lch.y * PainterTones.LIT_CHROMA
	var pull := float(shape["lit-pull"]) * PainterTones.PULL_CHROMA
	var h := deg_to_rad(lch.z)
	var lh := deg_to_rad(float(shape["lit-hue"]))
	var ab := Vector2(own * cos(h) + pull * cos(lh), own * sin(h) + pull * sin(lh))
	return Vector3(
		minf(PainterTones.LIT_MAX_L, lch.x + float(shape["lit-lift"])),
		ab.length(),
		fposmod(rad_to_deg(ab.angle()), 360.0)
	)


## The ramp numbers of a building `family` in `mood` at `elevation`: the mood's, moved by the
## buildings' own (see the header). Pure.
static func shape_of(
	sheet: Dictionary, mood: String, elevation: float, family: String
) -> Dictionary:
	var num := func(prop: String) -> float:
		return PainterSheet.number(sheet, mood, prop, elevation)
	var shape := {
		"shade-hue": num.call("shade-hue"),
		"shade-pull": num.call("shade-pull"),
		"shade-depth": num.call("shade-depth"),
		"shade-keep": num.call("shade-keep"),
		"lit-hue": num.call("lit-hue"),
		"lit-pull": num.call("lit-pull") * num.call("building-lit"),
		"lit-lift": num.call("lit-lift") * num.call("building-lit"),
	}
	match family:
		"wall", "stone":
			var pull_share: String = "wall-pull" if family == "wall" else "stone-pull"
			shape["shade-hue"] = float(shape["shade-hue"]) + num.call("wall-shade-turn")
			shape["shade-pull"] = float(shape["shade-pull"]) * num.call(pull_share)
			shape["shade-depth"] = float(shape["shade-depth"]) + num.call("wall-shade-lift")
		"roof":
			shape["shade-pull"] = float(shape["shade-pull"]) * num.call("roof-pull")
			shape["shade-depth"] = float(shape["shade-depth"]) + num.call("roof-shade-lift")
		"timber":
			shape["shade-hue"] = float(shape["shade-hue"]) + num.call("timber-shade-turn")
			shape["shade-pull"] = float(shape["shade-pull"]) * num.call("timber-pull")
	shape["shade-hue"] = fposmod(float(shape["shade-hue"]), 360.0)
	shape["shade-depth"] = clampf(float(shape["shade-depth"]), 0.0, 1.0)
	return shape
