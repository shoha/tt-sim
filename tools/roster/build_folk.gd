extends SceneTree

## Builds the Folk built-in token pack's GLBs from Quaternius's two CC0 packs (Universal Base
## Characters and Modular Character Outfits - Fantasy, the free "Standard" downloads).
##
## Each figure in folk_recipes.gd is dressed from the source parts: the head cut from the
## base body (the packs say a full body under an outfit clips and only the head is needed),
## its eyes and eyebrows, the outfit's parts, a hairstyle, an optional beard. The T-posed rig is
## lowered to an A-pose and baked into static vertices (folk_bake.gd), the parts merge into one
## surface per material, and the textures shrink: skin, hair and eyes become small tinted
## textures, the outfit atlas 1024 px. One lossy-WebP GLB per figure is written, scaled so a
## figure stands about 1.7 m tall (tt-sim reads GLBs at native scale, 1 unit = 1 m).
##
## Run (headless, the project folder is any tt-sim checkout):
##   godot --headless --path <tt-sim> --script res://tools/roster/build_folk.gd -- \
##     --ubc "<...>/Universal Base Characters[Standard]" \
##     --mof "<...>/Modular Character Outfits - Fantasy[Standard]" \
##     --out <tt-sim>/builtin_packs/folk/models [--only villager_man]
## The sources are downloads from quaternius.com / itch.io; docs/licences/builtin_packs/folk.md
## lists them with their hashes. The output is deterministic for the same sources.

const FolkBake := preload("res://tools/roster/folk_bake.gd")
const FolkGlb := preload("res://tools/roster/folk_glb.gd")
const FolkRecipes := preload("res://tools/roster/folk_recipes.gd")

## Uniform scale from the source (male 1.82 m) to a medium human.
const SCALE := 0.95
## Arms lowered from the T-pose, radians, and the part of it the clavicles take.
const ARM_DROP := 1.12
const CLAVICLE_SHARE := 0.15
const SKIN_PX := 512
const HAIR_PX := 256
const EYE_PX := 128
const OUTFIT_PX := 1024
const WEBP_QUALITY := 0.8
## The share of triangles each material keeps: the sources are 13k-triangle bodies and boots
## with laces, far more than a 100 px token shows.
const KEEP_TRIANGLES := {"outfit": 0.3, "skin": 0.6, "hair": 0.6}

var _ubc := ""
var _mof := ""
var _out := ""
var _scenes: Dictionary = {}
var _textures: Dictionary = {}


func _init() -> void:
	var only := _parse_args()
	if _ubc == "" or _mof == "" or _out == "":
		push_error("usage: -- --ubc <dir> --mof <dir> --out <dir> [--only <id>]")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var failed := 0
	for recipe in FolkRecipes.RECIPES:
		if only != "" and recipe["id"] != only:
			continue
		if not _build(recipe):
			failed += 1
	for scene in _scenes.values():
		scene.free()
	quit(1 if failed > 0 else 0)


func _parse_args() -> String:
	var only := ""
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1):
		match args[i]:
			"--ubc":
				_ubc = args[i + 1].trim_suffix("/") + "/"
			"--mof":
				_mof = args[i + 1].trim_suffix("/") + "/"
			"--out":
				_out = args[i + 1].trim_suffix("/") + "/"
			"--only":
				only = args[i + 1]
	return only


func _build(recipe: Dictionary) -> bool:
	var sex: String = recipe["sex"]
	var outfit: String = recipe["outfit"]
	var groups := {}
	var parts := PackedStringArray()
	var base := _scene(_ubc + "Base Characters/Godot - UE/Superhero_%s_FullBody.gltf" % sex)
	var skeleton: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	var matrices := FolkBake.a_pose_matrices(skeleton, ARM_DROP, CLAVICLE_SHARE)
	var head_bones := PackedInt32Array([skeleton.find_bone("neck_01"), skeleton.find_bone("Head")])

	var hair_style: String = recipe.get("hair", "")
	if recipe.get("hood", false):
		hair_style = ""
	var hair_tint: Color = FolkRecipes.HAIR_TINTS[recipe["hair_colour"]]
	var skin_tint: Color = FolkRecipes.SKIN_TINTS[recipe["skin"]]
	var body_texture := _surface_image(base.find_children("*_" + sex, "MeshInstance3D", true, false)[0])

	for mi: MeshInstance3D in base.find_children("*", "MeshInstance3D", true, false):
		parts.append("%s.gltf:%s" % [base.name, mi.name])
		var kind := "skin"
		var px := SKIN_PX
		var tint := skin_tint
		var image := body_texture
		if mi.name == "Eyes":
			kind = "eyes"
			px = EYE_PX
			tint = Color.WHITE
			image = _surface_image(mi)
		elif mi.name == "Eyebrows":
			kind = "hair"
			px = HAIR_PX
			tint = hair_tint
			image = _surface_image(mi)
		var cut := head_bones if kind == "skin" else PackedInt32Array()
		_add(groups, mi, matrices, func(_s: int) -> Array: return [kind, px, tint, image], cut)

	var outfit_scene := _scene(_mof + "Exports/glTF (Godot-Unreal)/Outfits/%s_%s.gltf" % [sex, outfit])
	var outfit_image := _outfit_image(outfit, int(recipe["colourway"]), outfit_scene)
	for mi: MeshInstance3D in outfit_scene.find_children("*", "MeshInstance3D", true, false):
		if "Head_Hood" in mi.name and not recipe.get("hood", false):
			continue
		if "Acc_Pauldron" in mi.name and not recipe.get("pauldron", false):
			continue
		parts.append("%s_%s.gltf:%s" % [sex, outfit, mi.name])
		var pick := func(surface: int) -> Array:
			var material := mi.mesh.surface_get_material(surface)
			if material.resource_name.begins_with("MI_Regular"):
				return ["skin", SKIN_PX, skin_tint, body_texture]
			return ["outfit", OUTFIT_PX, Color.WHITE, outfit_image]
		_add(groups, mi, matrices, pick, PackedInt32Array())

	var styles: Array[String] = []
	if hair_style != "":
		styles.append(hair_style)
	if recipe.get("beard", false):
		styles.append("Hair_Beard")
	for style in styles:
		var path := _ubc + "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/%s.gltf" % style
		var hair_scene := _scene(path)
		for mi: MeshInstance3D in hair_scene.find_children("*", "MeshInstance3D", true, false):
			parts.append("%s.gltf:%s" % [style, mi.name])
			var hair_image := _surface_image(mi)
			_add(groups, mi, matrices, func(_s: int) -> Array: return ["hair", HAIR_PX, hair_tint, hair_image], PackedInt32Array())
	return _export(recipe, groups, parts)


## Skins and merges every surface of `mi` into `groups`. `describe` returns, per surface, the
## material key, texture size, tint and source image; `cut_bones` (head only) drops triangles
## that are not bound to those bones.
func _add(groups: Dictionary, mi: MeshInstance3D, matrices: Array[Transform3D], describe: Callable, cut_bones: PackedInt32Array) -> void:
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var skinned := FolkBake.skin_surface(arrays, mi.skin, matrices)
		var keep := PackedByteArray()
		if not cut_bones.is_empty():
			keep = FolkBake.triangles_bound_to(arrays, mi.skin, cut_bones)
		var info: Array = describe.call(s)
		var key: String = "%s:%d" % [info[0], hash((info[3] as Image).get_data())]
		if not groups.has(key):
			var group := FolkBake.Group.new()
			group.material = _material(key, info[1], info[2], info[3])
			groups[key] = group
		var group: FolkBake.Group = groups[key]
		group.append(skinned["verts"], skinned["normals"], arrays[Mesh.ARRAY_TEX_UV], arrays[Mesh.ARRAY_INDEX], keep)


func _material(key: String, px: int, tint: Color, source: Image) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = key.get_slice(":", 0)
	material.albedo_texture = _texture(source, px)
	material.albedo_color = tint
	material.roughness = 1.0
	material.metallic = 0.0
	return material


func _texture(source: Image, px: int) -> ImageTexture:
	var key := "%d:%d" % [hash(source.get_data()), px]
	if not _textures.has(key):
		var img: Image = source.duplicate()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGB8)
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		_textures[key] = ImageTexture.create_from_image(img)
	return _textures[key]


func _export(recipe: Dictionary, groups: Dictionary, parts: PackedStringArray) -> bool:
	var floor_y := INF
	for group: FolkBake.Group in groups.values():
		group.simplify(KEEP_TRIANGLES.get(group.material.resource_name, 1.0))
		for v in group.verts:
			floor_y = minf(floor_y, v.y)
	var triangles := 0
	var low := Vector3(INF, INF, INF)
	var high := -low
	for group: FolkBake.Group in groups.values():
		group.transform(Vector3(0.0, -floor_y, 0.0), SCALE)
		triangles += group.triangle_count()
		for v in group.verts:
			low = low.min(v)
			high = high.max(v)
	var bytes := FolkGlb.encode(
		recipe["id"], groups.values(), WEBP_QUALITY, "Quaternius, CC0 1.0 (Universal Base Characters, Modular Character Outfits - Fantasy)"
	)
	var path: String = _out + recipe["id"] + ".glb"
	var file := FileAccess.open(path, FileAccess.WRITE)
	var ok := file != null
	if ok:
		file.store_buffer(bytes)
		file.close()
		ok = FolkGlb.write_keep_sidecar(path)
	print(
		"FOLK %s ok=%s tris=%d bytes=%d height=%.3f width=%.3f parts=%s"
		% [recipe["id"], ok, triangles, bytes.size(), high.y - low.y, high.x - low.x, ",".join(parts)]
	)
	return ok


func _outfit_image(outfit: String, colourway: int, outfit_scene: Node) -> Image:
	if colourway == 1:
		return _surface_image(outfit_scene.find_children("*_Body", "MeshInstance3D", true, false)[0])
	return Image.load_from_file(_mof + "Textures/%s/T_%s_%d_BaseColor.png" % [outfit, outfit, colourway])


## The albedo image of a mesh's first surface material.
func _surface_image(mi: MeshInstance3D) -> Image:
	var material := mi.mesh.surface_get_material(0) as BaseMaterial3D
	return material.albedo_texture.get_image()


func _scene(path: String) -> Node:
	if not _scenes.has(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			push_error("cannot load " + path)
			return Node.new()
		_scenes[path] = doc.generate_scene(state)
	return _scenes[path]
