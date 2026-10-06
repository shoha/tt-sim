class_name AvatarKit
extends RefCounted

## The avatar kit consumer (docs/ASSET_PIPELINE.md section 10): loads figurine's kit from
## res://assets/avatar_kit/ and assembles a figure from a recipe.
##
## A kit is kit.json (parts, palette, face sheet, colour sets, skeleton, proportions,
## stances), skeleton.glb (the armature and the one-key stance clips), a GLB per part and the
## face sheet and mask. Every GLB is loaded as the imported PackedScene through
## ResourceLoader, which is what an exported pack holds (section 9 "Import path"); kit.json is
## read with FileAccess, which an exported pack serves too.
##
## A figure (build_figure) is a Node3D holding one Skeleton3D built from skeleton.glb's
## armature, with a MeshInstance3D per part bound to it:
## - proportions move the skeleton's rest origins and reshape each part's binds on a Skin
##   duplicated for this figure (AvatarProportions), so stances stay valid;
## - the stance is the clip's local rotations set as the pose;
## - hides: the body's surfaces are its regions, each named by its material, and every
##   region a chosen part `hides` is left out of the body's mesh (one cached mesh per set);
## - one ShaderMaterial per part (shaders/avatar_figure.gdshader, or its double-sided twin)
##   carries the figure's palette (AvatarPalette), the part's detail texture and, on the head,
##   the face rect and the chosen cells.
## The figure faces +Z with its soles on its origin. `shade` and `hidden_fade` are per
## figure instance values (set_shade, set_hidden_fade, update_shade).
##
## A part whose armature differs from the kit's (bone names, parents or rest poses, or a skin
## bind naming a bone the kit lacks) is rejected at load, naming the part, and left out of
## every figure. Recipe fallbacks follow figurine (AvatarRecipe) and are printed.

const DEFAULT_ROOT := "res://assets/avatar_kit"
const FIGURE_SHADER := preload("res://shaders/avatar_figure.gdshader")
const FIGURE_SHADER_DOUBLE := preload("res://shaders/avatar_figure_double_sided.gdshader")
const REST_TOLERANCE := 1e-4
## Composition order of the face cells in the shader.
const FACE_ORDER: Array[String] = ["marks", "mouths", "eyes", "brows"]
const LOG_PREFIX := "AvatarKit: "

## Build mipmaps for the parts' detail textures at load (_with_mipmaps).
static var detail_mipmaps := true

var root := DEFAULT_ROOT
var manifest: Dictionary = {}
var parts_by_id: Dictionary = {}  # id -> kit.json part entry
var parts_by_slot: Dictionary = {}  # slot -> [ids in kit order]
## The kit armature: bone names in Skeleton3D order, their parents (index) and local rests.
var bone_names := PackedStringArray()
var bone_parents := PackedInt32Array()
var bone_rests: Array[Transform3D] = []
## stance name -> {bone name: Quaternion}
var stances: Dictionary = {}
var face_sheet: Texture2D = null
var face_mask: Texture2D = null
## Every problem found while loading (missing files, rejected parts), also printed.
var errors := PackedStringArray()

var _parts: Dictionary = {}  # id -> {"mesh", "skin", "detail", "error"}
var _hidden_meshes: Dictionary = {}  # "id|region,region" -> ArrayMesh


## Loads the kit under `kit_root`; null when kit.json or the skeleton is missing or broken.
static func load_kit(kit_root: String = DEFAULT_ROOT) -> AvatarKit:
	var kit := AvatarKit.new()
	kit.root = kit_root
	return kit if kit._load() else null


func _load() -> bool:
	var path := root.path_join("kit.json")
	if not FileAccess.file_exists(path):
		_error("no kit.json at %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_error("kit.json is not a JSON object")
		return false
	manifest = parsed
	for entry in manifest.get("parts", []):
		if not entry is Dictionary or not entry.has("id") or not entry.has("slot"):
			continue
		parts_by_id[String(entry.id)] = entry
		if not parts_by_slot.has(String(entry.slot)):
			parts_by_slot[String(entry.slot)] = []
		(parts_by_slot[String(entry.slot)] as Array).append(String(entry.id))
	if not _load_skeleton():
		return false
	var faces: Dictionary = manifest.get("face_sheet", {})
	face_sheet = _load_texture(String(faces.get("png", "")))
	face_mask = _load_texture(String(faces.get("mask", "")))
	return true


func _error(message: String) -> void:
	errors.append(message)
	print(LOG_PREFIX + message)


func _load_texture(relative: String) -> Texture2D:
	var path := root.path_join(relative)
	if relative.is_empty() or not ResourceLoader.exists(path):
		_error("missing texture %s" % path)
		return null
	return load(path) as Texture2D


func _load_skeleton() -> bool:
	var path := root.path_join("skeleton.glb")
	if not ResourceLoader.exists(path):
		_error("no skeleton.glb at %s" % path)
		return false
	var scene := (load(path) as PackedScene).instantiate()
	var sk := _find(scene, "Skeleton3D") as Skeleton3D
	if sk == null:
		scene.free()
		_error("skeleton.glb has no Skeleton3D")
		return false
	for b in sk.get_bone_count():
		bone_names.append(sk.get_bone_name(b))
		bone_parents.append(sk.get_bone_parent(b))
		bone_rests.append(sk.get_bone_rest(b))
	var player := _find(scene, "AnimationPlayer") as AnimationPlayer
	if player != null:
		for clip in player.get_animation_list():
			stances[String(clip)] = _stance_rotations(player.get_animation(clip))
	scene.free()
	return true


## The local rotation each rotation track holds at its first key, by bone name.
static func _stance_rotations(anim: Animation) -> Dictionary:
	var out := {}
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D or anim.track_get_key_count(t) == 0:
			continue
		var bone := String(anim.track_get_path(t).get_concatenated_subnames())
		out[bone] = anim.track_get_key_value(t, 0) as Quaternion
	return out


static func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	var found := node.find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null


## Stance names in kit.json order (the first is the fallback).
func stance_names() -> Array:
	return manifest.get("stances", stances.keys())


## Cells per face kind in the sheet.
func face_counts() -> Dictionary:
	return (manifest.get("face_sheet", {}) as Dictionary).get("rows", {})


## A recipe resolved against this kit (AvatarRecipe.resolve); fallbacks are printed.
func resolve(recipe: Dictionary) -> Dictionary:
	var resolved := (
		AvatarRecipe
		. resolve(
			recipe,
			parts_by_slot,
			manifest.get("colour_sets", {}),
			face_counts(),
			manifest.get("proportions", {}),
			stance_names(),
		)
	)
	for note in resolved.fallbacks:
		print(LOG_PREFIX + "fallback: " + note)
	return resolved


# --- parts -----------------------------------------------------------------------------------


## The loaded part: {"mesh": ArrayMesh, "skin": Skin, "detail": Texture2D or null,
## "error": ""}. A part that fails to load or whose armature differs from the kit's has a
## non-empty "error" naming it (also printed once).
func load_part(part_id: String) -> Dictionary:
	if _parts.has(part_id):
		return _parts[part_id]
	var entry: Dictionary = parts_by_id.get(part_id, {})
	var result := {"mesh": null, "skin": null, "detail": null, "error": ""}
	var path := root.path_join(String(entry.get("glb", "")))
	if entry.is_empty() or not ResourceLoader.exists(path):
		result.error = "part %s: no GLB at %s" % [part_id, path]
	else:
		var scene := (load(path) as PackedScene).instantiate()
		result.error = _read_part(part_id, scene, result)
		scene.free()
	if not String(result.error).is_empty():
		_error(String(result.error))
	_parts[part_id] = result
	return result


func _read_part(part_id: String, scene: Node, result: Dictionary) -> String:
	var sk := _find(scene, "Skeleton3D") as Skeleton3D
	var mi := _find(scene, "MeshInstance3D") as MeshInstance3D
	if sk == null or mi == null or mi.mesh == null or mi.skin == null:
		return "part %s: no skinned mesh under a Skeleton3D" % part_id
	var mismatch := armature_mismatch(sk)
	if not mismatch.is_empty():
		return "part %s rejected: its armature differs from the kit's (%s)" % [part_id, mismatch]
	for i in mi.skin.get_bind_count():
		var bind := String(mi.skin.get_bind_name(i))
		if not bone_names.has(bind):
			return "part %s rejected: its skin binds '%s', not a kit bone" % [part_id, bind]
	result.mesh = mi.mesh
	result.skin = mi.skin
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
		if mat != null and mat.albedo_texture != null:
			result.detail = _with_mipmaps(mat.albedo_texture)
			break
	return ""


## The detail texture with mipmaps. The GLBs embed it uncompressed and unmipmapped (section 9's
## sidecar), which keeps the ink exact at close zoom but aliases it at home zoom, where a
## 512-texel body covers about 120 pixels; mipmaps built here once per part fix that without
## VRAM compression. `detail_mipmaps` false keeps the imported texture (for an A/B).
static func _with_mipmaps(texture: Texture2D) -> Texture2D:
	if not detail_mipmaps:
		return texture
	var image := texture.get_image()
	if image == null or image.has_mipmaps() or image.is_compressed():
		return texture
	image = image.duplicate() as Image
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## "" when `sk` has the kit's bones (same names, parents and local rests, in any order),
## else what differs.
func armature_mismatch(sk: Skeleton3D) -> String:
	if sk.get_bone_count() != bone_names.size():
		return "%d bones, the kit has %d" % [sk.get_bone_count(), bone_names.size()]
	for b in sk.get_bone_count():
		var name := sk.get_bone_name(b)
		var k := bone_names.find(name)
		if k < 0:
			return "bone '%s' is not in the kit" % name
		var parent := sk.get_bone_parent(b)
		var parent_name := sk.get_bone_name(parent) if parent >= 0 else ""
		var kit_parent := bone_names[bone_parents[k]] if bone_parents[k] >= 0 else ""
		if parent_name != kit_parent:
			return "bone '%s' has parent '%s', the kit's '%s'" % [name, parent_name, kit_parent]
		if not _rest_matches(sk.get_bone_rest(b), bone_rests[k]):
			return "bone '%s' rest differs" % name
	return ""


static func _rest_matches(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > REST_TOLERANCE:
		return false
	for axis in 3:
		if a.basis[axis].distance_to(b.basis[axis]) > REST_TOLERANCE:
			return false
	return true


## The part's mesh without the surfaces named in `hidden` (region names); the whole mesh when
## nothing of it is hidden. Cached per part and region set.
func mesh_without(part_id: String, hidden: Array) -> ArrayMesh:
	var mesh: ArrayMesh = load_part(part_id).mesh
	if mesh == null:
		return null
	var drop := PackedStringArray()
	for s in mesh.get_surface_count():
		if hidden.has(_surface_region(mesh, s)):
			drop.append(_surface_region(mesh, s))
	if drop.is_empty():
		return mesh
	drop.sort()
	var key := part_id + "|" + ",".join(drop)
	if _hidden_meshes.has(key):
		return _hidden_meshes[key]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		if drop.has(_surface_region(mesh, s)):
			continue
		var flags := mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(
			mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {}, flags
		)
		var index := out.get_surface_count() - 1
		out.surface_set_name(index, mesh.surface_get_name(s))
		out.surface_set_material(index, mesh.surface_get_material(s))
	_hidden_meshes[key] = out
	return out


## A body surface's region: its material's name (the contract), else the surface's name.
static func _surface_region(mesh: ArrayMesh, surface: int) -> String:
	var mat := mesh.surface_get_material(surface)
	if mat != null and not mat.resource_name.is_empty():
		return mat.resource_name
	return mesh.surface_get_name(surface)


# --- figures ---------------------------------------------------------------------------------


## A figure assembled from `recipe` (see AvatarRecipe for its form). Its metadata holds the
## resolved recipe ("avatar_recipe").
func build_figure(recipe: Dictionary) -> Node3D:
	var resolved := resolve(recipe)
	var figure := Node3D.new()
	figure.name = "AvatarFigure"
	figure.set_meta("avatar_recipe", resolved)
	var sk := _new_skeleton()
	figure.add_child(sk)
	var old_rests := AvatarProportions.global_rests(sk)
	var maps := AvatarProportions.bone_maps(
		manifest.get("skeleton", {}), manifest.get("proportions", {}), resolved.proportions
	)
	AvatarProportions.apply_rests(sk, maps)
	var new_rests := AvatarProportions.global_rests(sk)
	var pose: Dictionary = stances.get(String(resolved.stance), {})
	pose_skeleton(sk, pose)
	# A Skeleton3D posed outside the tree keeps a stale global pose (measured on 4.7.1:
	# force_update_all_bone_transforms does not refresh it, and setting an unchanged value
	# is ignored), so the figure would render in the rest A-pose: pose it again, through a
	# real change, whenever the skeleton enters the tree.
	sk.tree_entered.connect(pose_skeleton.bind(sk, pose))
	var palette := AvatarPalette.build_texture(manifest.get("colour_sets", {}), resolved.colours)
	var hidden := []
	for slot in resolved.parts:
		hidden.append_array(parts_by_id[resolved.parts[slot]].get("hides", []))
	var slots: Array = resolved.parts.keys()
	slots.sort()
	for slot in slots:
		var part_id := String(resolved.parts[slot])
		var part := load_part(part_id)
		if not String(part.error).is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = part_id
		mi.mesh = mesh_without(part_id, hidden)
		mi.skin = AvatarProportions.reshaped_skin(part.skin, maps, old_rests, new_rests)
		sk.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.material_override = _material(parts_by_id[part_id], part, palette, resolved.face)
	return figure


## Sets a stance (bone name -> local rotation) as the skeleton's pose, from its rest.
static func pose_skeleton(sk: Skeleton3D, pose: Dictionary) -> void:
	sk.reset_bone_poses()
	for bone in pose:
		var b := sk.find_bone(String(bone))
		if b >= 0:
			sk.set_bone_pose_rotation(b, pose[bone])


func _new_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for b in bone_names.size():
		sk.add_bone(bone_names[b])
	for b in bone_names.size():
		sk.set_bone_parent(b, bone_parents[b])
		sk.set_bone_rest(b, bone_rests[b])
	sk.reset_bone_poses()
	return sk


func _material(
	entry: Dictionary, part: Dictionary, palette: Texture2D, face: Dictionary
) -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = FIGURE_SHADER_DOUBLE if bool(entry.get("double_sided", false)) else FIGURE_SHADER
	mat.set_shader_parameter("palette", palette)
	mat.set_shader_parameter("has_detail", part.detail != null)
	if part.detail != null:
		mat.set_shader_parameter("detail", part.detail)
	var rect: Array = entry.get("face_rect", [])
	if rect.size() == 4 and face_sheet != null and face_mask != null:
		mat.set_shader_parameter("has_face", true)
		mat.set_shader_parameter(
			"face_rect", Vector4(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		)
		mat.set_shader_parameter("face_cell_size", face_cell_size())
		mat.set_shader_parameter("face_cells", face_cells(face))
		mat.set_shader_parameter("face_sheet", face_sheet)
		mat.set_shader_parameter("face_mask", face_mask)
	return mat


## The size of one face cell in sheet UV (1 / columns, 1 / rows).
func face_cell_size() -> Vector2:
	var faces: Dictionary = manifest.get("face_sheet", {})
	var rows: Array = faces.get("row_order", AvatarRecipe.FACE_KINDS)
	return Vector2(1.0 / maxf(1.0, float(faces.get("columns", 1))), 1.0 / maxf(1.0, rows.size()))


## Each chosen cell's top-left in sheet UV (v down), in the shader's composition order.
func face_cells(face: Dictionary) -> PackedVector2Array:
	var faces: Dictionary = manifest.get("face_sheet", {})
	var rows: Array = faces.get("row_order", AvatarRecipe.FACE_KINDS)
	var size := face_cell_size()
	var out := PackedVector2Array()
	for kind in FACE_ORDER:
		out.append(Vector2(int(face.get(kind, 0)) * size.x, maxi(0, rows.find(kind)) * size.y))
	return out


## The figure's parts (MeshInstance3D under its skeleton).
static func figure_parts(figure: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in figure.find_children("*", "MeshInstance3D", true, false):
		out.append(node as MeshInstance3D)
	return out


## Sets the figure's `shade` (0 in sun, 1 in shade) on every part.
static func set_shade(figure: Node3D, value: float) -> void:
	for mi in figure_parts(figure):
		mi.set_instance_shader_parameter("shade", clampf(value, 0.0, 1.0))


## Sets the share of the figure's pixels dithered away (0 solid; the GM's view of a token
## hidden from players uses about 0.5).
static func set_hidden_fade(figure: Node3D, value: float) -> void:
	for mi in figure_parts(figure):
		mi.set_instance_shader_parameter("hidden_fade", clampf(value, 0.0, 1.0))


## Takes the figure's shade ray (AvatarShade) toward `sun` against `world_root` and sets it.
## Call at placement and after a move. No sun, or a hidden one, means no shade.
static func update_shade(figure: Node3D, world_root: Node3D, sun: DirectionalLight3D) -> float:
	var value := 0.0
	if sun != null and sun.is_visible_in_tree():
		value = AvatarShade.shade_at(world_root, figure.global_position, sun.global_basis.z)
	set_shade(figure, value)
	return value
