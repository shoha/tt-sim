class_name GroundPalette
extends RefCounted

## The palette side of an authored map's ground (AuthoredTerrain): which palette surfaces
## its layers need and where their textures are, the rule surfaces that dress the base (cliff
## and scree, and on a map with water its bed and shore), the ground material of a surface,
## and texture loading with fallbacks. Static; moved out of AuthoredTerrain (P4-3) so the
## node keeps its nodes and state. The fallback colours and meta stay AuthoredTerrain's.


## Resource paths of every palette texture AuthoredTerrain.build() binds for `doc`: the base
## surface's maps, each painted biome's ground, cliff and scree surface maps (and water bed
## and shore on a map with water), the painted surfaces' and the base's rule surfaces. A
## caller can load them on background threads first, so build() finds them in the resource
## cache instead of loading on the main thread (about 35 ms cold for one surface).
static func texture_paths(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	var surfaces := PaletteLibrary.surfaces(root)
	var names := [doc.base_surface]
	names.append_array(Array(base_rule_surfaces(doc.base_surface, root)))
	var wet := not doc.water_bodies.is_empty()
	if wet:
		names.append_array(Array(base_water_surfaces(doc.base_surface, root)))
	names.append_array(Array(doc.surface_ids))
	var accents := GroundAccents.base_accents(doc.base_surface, root)
	names.append_array(GroundAccents.surface_names(accents))
	var keys := ["ground_surface", "cliff_surface", "scree_surface"]
	if wet:
		keys.append_array(["water_bed_surface", "shore_surface"])
	for biome_id in doc.biome_ids:
		var biome := PaletteLibrary.biome(biome_id, root)
		for key in keys:
			names.append(biome.get(key, ""))
		names.append_array(GroundAccents.surface_names(biome.get("ground_accents", [])))
	var paths := PackedStringArray()
	for surface_name in names:
		var surface: Dictionary = surfaces.get(surface_name, {})
		for key in AuthoredTerrain.LAYER_MAPS:
			var relative: Variant = surface.get(key, "")
			if relative is String and relative != "":
				var path := root.path_join(relative)
				if not path in paths and ResourceLoader.exists(path):
					paths.append(path)
	return paths


## The cliff and scree surfaces [cliff, scree] that dress base surface `base` where no
## painted biome says otherwise: those of the palette's first biome on that ground, else
## the palette's first cliff surface and no scree ("" = none).
static func base_rule_surfaces(
	base: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	for biome in PaletteLibrary.biomes(root):
		if biome.get("ground_surface", "") == base:
			return PackedStringArray(
				[biome.get("cliff_surface", ""), biome.get("scree_surface", "")]
			)
	var cliffs := PaletteLibrary.surfaces_with_role("cliff", root)
	return PackedStringArray([cliffs[0] if not cliffs.is_empty() else "", ""])


## The water bed and shore surfaces [bed, shore] that dress the water on base surface `base`
## where no painted biome says otherwise: those of the palette's first biome on that ground,
## else PaletteLibrary.DEFAULT_WATER_SURFACES the palette has as ground ("" = none).
static func base_water_surfaces(
	base: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	for biome in PaletteLibrary.biomes(root):
		if biome.get("ground_surface", "") == base:
			return PackedStringArray(
				[biome.get("water_bed_surface", ""), biome.get("shore_surface", "")]
			)
	var surfaces := PaletteLibrary.surfaces(root)
	var out := PackedStringArray()
	for name: String in PaletteLibrary.DEFAULT_WATER_SURFACES:
		var ground: bool = surfaces.get(name, {}).get("role", "") == "ground"
		out.append(name if ground else "")
	return out


## The ground material for palette surface `surface_name`: the authored ground shader
## with the surface's albedo, normal and ORM bound at its tile size. A surface the palette
## does not have, or whose albedo does not load, gets flat fallback textures and a
## warning, and the material carries AuthoredTerrain.FALLBACK_META so callers can tell.
static func build_ground_material(
	surface_name: String, map_seed: int = 0, root: String = PaletteLibrary.DEFAULT_ROOT
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = AuthoredTerrain.GROUND_SHADER
	material.set_shader_parameter("breakup_seed", map_seed & 0x7fffffff)
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(surface_name, {})
	var albedo := load_texture(root, surface.get("albedo", ""))
	if albedo == null:
		push_warning(
			(
				"AuthoredTerrain: surface '%s' is not in the palette at %s; using a plain ground"
				% [surface_name, root]
			)
		)
		material.set_shader_parameter("albedo_tex", solid_texture(AuthoredTerrain.FALLBACK_ALBEDO))
		material.set_shader_parameter("orm_tex", solid_texture(AuthoredTerrain.FALLBACK_ORM))
		material.set_meta(AuthoredTerrain.FALLBACK_META, true)
		return material
	material.set_shader_parameter("albedo_tex", albedo)
	material.set_shader_parameter("tile_m", float(surface["tile_m"]))
	var normal := load_texture(root, surface.get("normal", ""))
	if normal != null:
		material.set_shader_parameter("normal_tex", normal)
	var orm := load_texture(root, surface.get("orm", ""))
	material.set_shader_parameter(
		"orm_tex", orm if orm != null else solid_texture(AuthoredTerrain.FALLBACK_ORM)
	)
	var height := load_texture(root, surface.get("height", ""))
	if height != null:
		material.set_shader_parameter("height_tex", height)
	return material


## Mean albedo of a palette surface (the last mip of its albedo, a box-filtered mean), or
## null when the surface or its albedo is missing. GroundLayerTable ranks overflow
## fallbacks by it; about 10 ms per surface (BPTC decompression), paid only on overflow.
static func surface_mean_albedo(
	surface_name: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Variant:
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(surface_name, {})
	var albedo := load_texture(root, surface.get("albedo", ""))
	if albedo == null:
		return null
	var image := albedo.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var offset := image.get_mipmap_offset(image.get_mipmap_count())
	var data := image.get_data()
	return Color8(data[offset], data[offset + 1], data[offset + 2])


## True when palette surface `surface_name` can be drawn (it exists and its albedo loads).
static func surface_available(
	surface_name: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> bool:
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(surface_name, {})
	var path: String = surface.get("albedo", "")
	return path != "" and ResourceLoader.exists(root.path_join(path))


## The texture at `relative_path` under palette root `root`, or null.
static func load_texture(root: String, relative_path: String) -> Texture2D:
	if relative_path == "":
		return null
	var path := root.path_join(relative_path)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


## A 1 x 1 texture of `color`.
static func solid_texture(color: Color) -> ImageTexture:
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
