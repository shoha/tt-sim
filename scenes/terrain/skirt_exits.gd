class_name SkirtExits
extends RefCounted

## The nodes AuthoredTerrain hangs under its ground skirt (phase 6, P6-1): the channel patch
## and the water of the rivers and ponds that leave the map (RiverExitMesh builds their
## geometry, PondExits the ponds' part), and
## the SkirtBackdrop that keeps the opaque skirt's fade colour and fog in step with the
## environment. Split out of AuthoredTerrain to keep that class a readable size.
##
## The channel patch draws with the skirt's own material. The ribbon draws with the shared
## water material (WaterGlbUtils.water_material(), the one every map's water uses, so the
## Water pane restyles it too), flagged per instance with the flow map (the edge's flow carries
## on, RiverExitMesh) and with the skirt's fade (water.gdshader water_skirt_fade), whose
## uniforms it sets on that material from the map. Everything is decoration: no shadow, and
## Constants.BOUNDS_EXEMPT_META keeps it out of the pan bounds and the reflection probe, as the
## skirt.

const CHANNEL_NAME := "Channel"
const RIBBON_NAME := "Ribbon"
## The water shader's per-instance switch for the skirt's fade (water.gdshader).
const WATER_SKIRT_FADE_PARAM := &"water_skirt_fade"


## Adds the children of `skirt` (its material `material`) for `exits` (RiverExitMesh.build();
## {} for none) on map `doc`, whose skirt fades over `fade_m` stretched by `wobble`.
static func decorate(
	skirt: MeshInstance3D,
	exits: Dictionary,
	material: ShaderMaterial,
	doc: MapDocument,
	fade_m: float,
	wobble: float
) -> void:
	var channel: Array = exits.get("channel", [])
	if not channel.is_empty():
		var patch := ArrayMesh.new()
		patch.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, channel)
		patch.surface_set_material(0, material)
		skirt.add_child(decoration(CHANNEL_NAME, patch))
	var backdrop := SkirtBackdrop.new()
	backdrop.name = SkirtBackdrop.NODE_NAME
	backdrop.materials.append(material)
	var ribbon: Array = exits.get("ribbon", [])
	if not ribbon.is_empty():
		var water := ArrayMesh.new()
		water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ribbon)
		var node := decoration(RIBBON_NAME, water)
		node.material_override = ribbon_material(doc, fade_m, wobble)
		node.set_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM, true)
		node.set_instance_shader_parameter(WATER_SKIRT_FADE_PARAM, true)
		skirt.add_child(node)
		backdrop.materials.append(node.material_override as ShaderMaterial)
	skirt.add_child(backdrop)


## A decoration mesh node (the skirt and its children): no shadow, outside the bounds walks.
static func decoration(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta(Constants.BOUNDS_EXEMPT_META, true)
	return node


## The shared water material with map `doc`'s skirt fade (the skirt's rectangle, fade, wobble
## and noise seed, the ground material's breakup_seed).
static func ribbon_material(doc: MapDocument, fade_m: float, wobble: float) -> ShaderMaterial:
	var water := WaterGlbUtils.water_material()
	water.set_shader_parameter("skirt_half_extent", doc.extent_m() * 0.5)
	water.set_shader_parameter("skirt_fade_m", fade_m)
	water.set_shader_parameter("skirt_wobble", wobble)
	water.set_shader_parameter("skirt_seed", doc.map_seed & 0x7FFFFFFF)
	return water


## Brings skirt material `skirt` up to ground material `ground` (`layer_count` slots) for a
## river's channel, when `channel`: the layer slots (the bed and shore surfaces among them),
## their routing and the map's dressing texture (SKIRT in the ground shader). Without a channel
## the skirt draws no dressing.
static func sync_water(
	skirt: ShaderMaterial, ground: ShaderMaterial, layer_count: int, channel: bool
) -> void:
	skirt.set_shader_parameter("skirt_channel", 1 if channel else 0)
	if not channel:
		return
	skirt.set_shader_parameter("layer_count", layer_count)
	for uniform in ["rule_bed_layer", "rule_shore_layer", "water_weights", "water_present"]:
		skirt.set_shader_parameter(uniform, ground.get_shader_parameter(uniform))
