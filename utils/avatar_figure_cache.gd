class_name AvatarFigureCache
extends RefCounted

## What AvatarKit.build_figure can share between figures, kept per kit so a figure costs
## little more than its nodes, and an avatar builder can change one thing live:
## - per proportion values ("shapes"): the bone maps (AvatarProportions.bone_maps), the
##   skeleton's local rests after apply_rests, the global rests, and each part's reshaped Skin,
##   built on first use. A Skin is a resource every MeshInstance3D bound to it shares; the
##   binding to a skeleton is per instance;
## - per colour picks: the palette texture (AvatarPalette);
## - per part, colour picks and face cells: the part's ShaderMaterial. Shared between figures:
##   the per-figure values (`shade`, `hidden_fade`) are instance uniforms, never material
##   parameters.
## Keys are the resolved values (so equal recipes share), rounded so a slider's float noise
## does not miss. Each table is dropped when it passes MAX_ENTRIES (a builder dragging a slider
## makes a new shape per step), which keeps the caches bounded without bookkeeping.

const MAX_ENTRIES := 48
const KEY_DECIMALS := 0.0005

## The owning kit, weakly: the kit holds this cache, and two RefCounted holding each other
## would never be freed.
var _kit_ref: WeakRef
var _kit_rests: Dictionary = {}  # bone name -> global rest of the kit armature
var _shapes: Dictionary = {}  # proportions key -> shape (see shape())
var _palettes: Dictionary = {}  # colours key -> ImageTexture
var _materials: Dictionary = {}  # part|colours|face key -> ShaderMaterial


func _init(kit: AvatarKit) -> void:
	_kit_ref = weakref(kit)


## {"maps", "rests" (local rest per bone index), "globals" (bone name -> global rest),
## "skins" (part id -> Skin, filled by skin())} for resolved proportion `values`.
func shape(values: Dictionary) -> Dictionary:
	var key := _key(values)
	if _shapes.has(key):
		return _shapes[key]
	var kit: AvatarKit = _kit_ref.get_ref()
	var sk := kit.new_skeleton()
	if _kit_rests.is_empty():
		_kit_rests = AvatarProportions.global_rests(sk)
	var maps := AvatarProportions.bone_maps(
		kit.manifest.get("skeleton", {}), kit.manifest.get("proportions", {}), values
	)
	AvatarProportions.apply_rests(sk, maps)
	var rests: Array[Transform3D] = []
	for b in sk.get_bone_count():
		rests.append(sk.get_bone_rest(b))
	var out := {
		"maps": maps, "rests": rests, "globals": AvatarProportions.global_rests(sk), "skins": {}
	}
	sk.free()
	_store(_shapes, key, out)
	return out


## Part `part_id`'s Skin reshaped for `shape_entry` (shape()), shared by every figure of it.
func skin(shape_entry: Dictionary, part_id: String, part_skin: Skin) -> Skin:
	var skins: Dictionary = shape_entry.skins
	if not skins.has(part_id):
		skins[part_id] = AvatarProportions.reshaped_skin(
			part_skin, shape_entry.maps, _kit_rests, shape_entry.globals
		)
	return skins[part_id]


## The palette texture for resolved colour picks.
func palette(colours: Dictionary) -> Texture2D:
	var key := _key(colours)
	if not _palettes.has(key):
		var kit: AvatarKit = _kit_ref.get_ref()
		_store(
			_palettes,
			key,
			AvatarPalette.build_texture(kit.manifest.get("colour_sets", {}), colours)
		)
	return _palettes[key]


## Part `part_id`'s material for resolved colour picks and face cells.
func material(part_id: String, colours: Dictionary, face: Dictionary) -> Material:
	var kit: AvatarKit = _kit_ref.get_ref()
	var entry: Dictionary = kit.parts_by_id.get(part_id, {})
	var has_face := (entry.get("face_rect", []) as Array).size() == 4
	var key := "%s|%s|%s" % [part_id, _key(colours), _key(face) if has_face else ""]
	if not _materials.has(key):
		var part := kit.load_part(part_id)
		_store(_materials, key, kit.make_material(entry, part, palette(colours), face))
	return _materials[key]


## Drops every table (a new kit, or tests).
func clear() -> void:
	_shapes.clear()
	_palettes.clear()
	_materials.clear()


static func _store(table: Dictionary, key: String, value: Variant) -> void:
	if table.size() >= MAX_ENTRIES:
		table.clear()
	table[key] = value


## A stable key for a flat Dictionary of numbers: sorted keys, values rounded.
static func _key(values: Dictionary) -> String:
	var names := values.keys()
	names.sort()
	var parts := PackedStringArray()
	for name in names:
		var value: Variant = values[name]
		if value is float:
			value = snappedf(value, KEY_DECIMALS)
		parts.append("%s=%s" % [name, str(value)])
	return ",".join(parts)
