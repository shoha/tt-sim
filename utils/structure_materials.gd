class_name StructureMaterials
extends RefCounted

## The materials of built structures and street lots (card S6), one per (surface kind, role, style)
## that the nodes share: the painterly wall shader over the baked masonry set or the planks, the
## roof tile shader, the modelled-stone material and the unshaded panes. The look and the budget are
## in docs/systems/structures.md "Look"; the shaders are shaders/structure_wall.gdshader and
## structure_roof.gdshader (both include structure_painterly.gdshaderinc). Main thread only: it
## makes resources.

const WALL_SHADER := preload("res://shaders/structure_wall.gdshader")
const ROOF_SHADER := preload("res://shaders/structure_roof.gdshader")
const PANE_SHADER := preload("res://shaders/structure_pane.gdshader")
## The architecture styles' materials: plaster, adobe, brick and log walls; slate, shingle, thatch
## and turf roofs (docs/systems/structures.md "Styles").
const STYLE_WALL_SHADER := preload("res://shaders/structure_style_wall.gdshader")
const STYLE_ROOF_SHADER := preload("res://shaders/structure_style_roof.gdshader")

## The lift toward cream a grey rock gets (saturation about the texture's luminance, then a warm
## bias), for masonry, and for planks (already warm, so less).
const MASONRY_SATURATION := 1.2
const MASONRY_WARM := Vector3(1.12, 1.13, 1.07)
## How much of a rock's own hue is replaced by cream (the rest keeps a biome's stone its own).
const MASONRY_CREAM := 0.75
const TIMBER_SATURATION := 1.1
const TIMBER_WARM := Vector3(1.12, 1.08, 0.95)
## Planks lean toward honey as stone leans toward cream (the wall shader's `cream`, here a share).
const TIMBER_CREAM := 0.6
## A lift on the planks' tint: the library's oak read a deep brown on a big barn (2026-10-28).
const TIMBER_LIFT := Vector3(1.5, 1.5, 1.3)
## The plants' light model's balance for walls (structure_painterly.gdshaderinc defaults, tuned for
## roofs): shade leans a soft cream-lavender, lighter and warmer than the crowns' violet, so a
## shaded stone face stays a colour instead of a brown or a mauve grey (look integration and ink
## card, 2026-10-28). Timber takes more light.
const WALL_SHADE_TINT := Vector3(0.96, 0.92, 1.0)
const WALL_SHADE_FLOOR := Vector3(0.31, 0.27, 0.36)
## Plaster's shade (structure_look2, 2026-10-29): the shade FLOOR, not the ramp tint, is the light a
## shaded face gets (the ramp tint is a small multiplier on top, which is why a warmer one changed
## nothing). WALL_SHADE_FLOOR's red over green (1.15) multiplied a warm cream's own red over green
## and read salmon; plaster takes a floor whose red sits under its green (0.93) and a neutral ramp,
## so the shade is a soft lavender over cream, a warm grey beige.
const PLASTER_SHADE_TINT := Vector3(0.92, 0.95, 1.0)
const PLASTER_SHADE_FLOOR := Vector3(0.26, 0.30, 0.35)
const STONE_LIT_GAIN := Vector3(1.42, 1.35, 1.2)
## A castle's grey stone (the style's `stone_tone` hint): the rock's light and dark kept, its hue
## replaced by a cool grey instead of warm cream.
const GREY_TONE := "grey"
const GREY_STONE_CREAM := Vector3(0.9, 1.0, 1.03)
const GREY_STONE_AMOUNT := 0.9
const GREY_STONE_WARM := Vector3(1.22, 1.22, 1.22)
const GREY_STONE_SATURATION := 1.0
const TIMBER_LIT_GAIN := Vector3(1.6, 1.5, 1.25)
## Slate leans from the styles' navy blue greys toward a teal slate (structure_style_roof
## `tone_shift`; styles integration 3, after the last look round called it navy).
const SLATE_TONE_SHIFT := Vector3(0.78, 1.5, 1.36)


## The material of surface `kind` in `role` for style `style`, with the palette at `root`.
## `tone` is the style's `stone_tone` hint ("grey" for castles, "" or "warm" for the cream default);
## only masonry reads it.
static func make(
	kind: String, role: String, style: String, root: String, tone: String = ""
) -> Material:
	var material: Material = null
	match kind:
		StructureLook.GLASS_KIND:
			return pane()
		"masonry":
			material = _masonry(style, root, role, tone)
		"wood":
			material = _roof() if role == StructureLook.ROOF else _timber(style, root, role)
		"boards":
			material = _timber(style, root, role)
		"tile":
			material = _roof()
		"slate", "shingle", "thatch", "turf":
			material = _style_roof(kind)
		"plaster", "adobe", "brick", "log":
			material = _style_wall(kind)
		_:
			var stone := _stone(style, root)
			stone.albedo_color *= StructureLook.tint_of(role)
			material = stone
	return material


## Panes and door leaves: the vertex colour as a flat painted tone, seen from both sides. Unshaded,
## because a pane in the shade of its own reveal went black when lit (judged 2026-10-28).
static func pane() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PANE_SHADER
	return material


## The soft ground patch and path of a building's yard (StructureDressing "ground"): vertex colour
## with alpha, blended over the terrain, no specular, seen from both sides.
static func dressing_ground() -> ORMMaterial3D:
	var material := ORMMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material


## The plants, stones and slabs of a building's yard (StructureDressing "props"): vertex colour,
## matte, seen from both sides (the grass blades are single triangles).
static func dressing_props() -> ORMMaterial3D:
	var material := ORMMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material


static func _roof() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ROOF_SHADER
	# Slate and tile sit lighter and less violet in the shade than the plants' crowns do.
	material.set_shader_parameter("ramp_shade_tint", Vector3(0.91, 0.88, 0.94))
	material.set_shader_parameter("lit_gain", Vector3(1.28, 1.2, 1.1))
	material.set_shader_parameter("eave_tone", Vector3(0.85, 0.81, 0.90))
	return material


## The roof of a style's roofing `kind` (slate, shingle, thatch, turf): one shader, a `pattern`
## uniform and the light balance each wants. No textures; the colour is the building's own roof
## tone.
static func _style_roof(kind: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STYLE_ROOF_SHADER
	material.set_shader_parameter("pattern", StructureLook.STYLE_ROOF_KINDS.find(kind))
	material.set_shader_parameter("ramp_shade_tint", Vector3(0.91, 0.88, 0.94))
	match kind:
		"thatch":
			# Straw is warm and light-catching, and its shade stays golden.
			material.set_shader_parameter("ramp_shade_tint", Vector3(0.94, 0.88, 0.84))
			material.set_shader_parameter("lit_gain", Vector3(1.3, 1.22, 1.08))
			material.set_shader_parameter("eave_tone", Vector3(0.88, 0.84, 0.78))
			material.set_shader_parameter("ridge_tone", Vector3(1.08, 1.05, 0.95))
		"turf":
			material.set_shader_parameter("ramp_shade_tint", Vector3(0.88, 0.92, 0.90))
			material.set_shader_parameter("lit_gain", Vector3(1.3, 1.26, 1.1))
			material.set_shader_parameter("eave_tone", Vector3(0.9, 0.9, 0.86))
			material.set_shader_parameter("ridge_tone", Vector3(1.06, 1.06, 0.96))
		"slate":
			material.set_shader_parameter("tone_shift", SLATE_TONE_SHIFT)
			material.set_shader_parameter("lit_gain", Vector3(1.3, 1.24, 1.1))
			material.set_shader_parameter("eave_tone", Vector3(0.85, 0.83, 0.88))
		_:
			material.set_shader_parameter("lit_gain", Vector3(1.28, 1.2, 1.1))
			material.set_shader_parameter("eave_tone", Vector3(0.85, 0.81, 0.90))
	return material


## The wall of a style's `kind` (plaster, adobe, brick, log): one shader, a `pattern` uniform; the
## wall's own tone is its vertex colour (StructurePaint), so one material serves every style.
static func _style_wall(kind: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STYLE_WALL_SHADER
	material.set_shader_parameter("pattern", StructureLook.STYLE_WALL_KINDS.find(kind))
	_balance_wall(material, STONE_LIT_GAIN)
	match kind:
		"plaster":
			# A pale wall under the full gain would blow out: it takes less.
			material.set_shader_parameter("lit_gain", Vector3(1.12, 1.07, 1.0))
			material.set_shader_parameter("ramp_shade_tint", PLASTER_SHADE_TINT)
			material.set_shader_parameter("shade_floor", PLASTER_SHADE_FLOOR)
		"adobe":
			material.set_shader_parameter("lit_gain", Vector3(1.18, 1.1, 1.0))
		"brick":
			material.set_shader_parameter("lit_gain", Vector3(1.3, 1.2, 1.08))
		"log":
			material.set_shader_parameter("lit_gain", TIMBER_LIT_GAIN)
	return material


## Textured masonry: the baked courses, the rock's mean colour as the tint, lifted toward cream.
static func _masonry(style: String, root: String, role: String, tone: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WALL_SHADER
	var textures := MasonryTextures.textures()
	var surface_name := AuthoredCrossings.stone_surface(style, root)
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(surface_name, {})
	var mean: Array = surface.get("albedo_mean_linear", [0.3, 0.3, 0.3])
	var tint := (
		MasonryTextures.tint_of(
			mean,
			AuthoredWalls.WALL_MASONRY_LIFTS.get(surface_name, AuthoredWalls.WALL_MASONRY_LIFT)
		)
		* StructureLook.tint_of(role)
	)
	material.set_shader_parameter("albedo_tint", Vector3(tint.r, tint.g, tint.b))
	if not textures.is_empty():
		material.set_shader_parameter("albedo_tex", textures.albedo)
		material.set_shader_parameter("normal_tex", textures.normal)
		material.set_shader_parameter("orm_tex", textures.orm)
	material.set_shader_parameter(
		"uv_scale",
		(
			Vector2(1.0 / MasonryTextures.TILE_M, 1.0 / MasonryTextures.TILE_H_M)
			/ AuthoredWalls.MASONRY_SCALE_UP
		)
	)
	material.set_shader_parameter("normal_scale", 1.0)
	material.set_shader_parameter("saturation", MASONRY_SATURATION)
	material.set_shader_parameter("warm_bias", MASONRY_WARM)
	material.set_shader_parameter("cream_amount", MASONRY_CREAM)
	if tone == GREY_TONE:
		material.set_shader_parameter("saturation", GREY_STONE_SATURATION)
		material.set_shader_parameter("warm_bias", GREY_STONE_WARM)
		material.set_shader_parameter("cream", GREY_STONE_CREAM)
		material.set_shader_parameter("cream_amount", GREY_STONE_AMOUNT)
	_balance_wall(material, STONE_LIT_GAIN)
	return material


## Timber: the library's planks tinted by climate, kept honey-warm.
static func _timber(style: String, root: String, role: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WALL_SHADER
	var biome := PaletteLibrary.biome(style, root) if style != "" else {}
	var tint: Color = (
		AuthoredCrossings.WOOD_TINTS.get(
			String(biome.get("climate", "")), AuthoredCrossings.DEFAULT_WOOD_TINT
		)
		* StructureLook.tint_of(role)
	)
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(
		LibraryBindings.crossing_planks(), {}
	)
	var albedo := GroundPalette.load_texture(root, surface.get("albedo", ""))
	if albedo != null:
		material.set_shader_parameter("albedo_tex", albedo)
	var normal := GroundPalette.load_texture(root, surface.get("normal", ""))
	if normal != null:
		material.set_shader_parameter("normal_tex", normal)
	var orm := GroundPalette.load_texture(root, surface.get("orm", ""))
	if orm != null:
		material.set_shader_parameter("orm_tex", orm)
	material.set_shader_parameter("albedo_tint", Vector3(tint.r, tint.g, tint.b) * TIMBER_LIFT)
	material.set_shader_parameter("normal_scale", AuthoredWalls.WOOD_NORMAL_SCALE)
	material.set_shader_parameter("saturation", TIMBER_SATURATION)
	material.set_shader_parameter("warm_bias", TIMBER_WARM)
	material.set_shader_parameter("cream_amount", TIMBER_CREAM)
	_balance_wall(material, TIMBER_LIT_GAIN)
	return material


## The light balance of a wall material (see WALL_SHADE_TINT).
static func _balance_wall(material: ShaderMaterial, lit_gain: Vector3) -> void:
	material.set_shader_parameter("ramp_shade_tint", WALL_SHADE_TINT)
	material.set_shader_parameter("shade_floor", WALL_SHADE_FLOOR)
	material.set_shader_parameter("lit_gain", lit_gain)


## Modelled stone (coping, the placeholder plot): the wall materials of AuthoredWalls, triplanar.
static func _stone(style: String, root: String) -> ORMMaterial3D:
	var surface := AuthoredCrossings.stone_surface(style, root)
	var tint: Color = AuthoredWalls.WALL_SURFACE_TINTS.get(surface, AuthoredWalls.WALL_STONE_TINT)
	var material := AuthoredCrossings.surface_material(
		root, surface, tint, AuthoredWalls.STONE_NORMAL_SCALE
	)
	var tile := float(PaletteLibrary.surfaces(root).get(surface, {}).get("tile_m", 3.0))
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE / maxf(tile * AuthoredCrossings.STONE_TILE_SCALE, 0.1)
	return material
