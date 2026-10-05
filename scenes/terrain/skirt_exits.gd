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
		# As the skirt's: an edge edit moves its vertices in place (update_channel_in_place).
		var box := patch.get_aabb()
		var half := AuthoredTerrain.SKIRT_AABB_HALF_HEIGHT_M
		patch.custom_aabb = AABB(
			Vector3(box.position.x, -half, box.position.z),
			Vector3(box.size.x, 2.0 * half, box.size.z)
		)
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


## A CPU copy of the channel patch's positions and normals (exits' "channel" arrays) for
## update_channel_in_place(): {"vertices", "normals", "loop": the boundary samples}; {} when
## there is no patch.
static func channel_mirror(exits: Dictionary, doc: MapDocument) -> Dictionary:
	var channel: Array = exits.get("channel", [])
	if channel.is_empty():
		return {}
	return {
		"vertices": (channel[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(),
		"normals": (channel[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate(),
		"loop": TerrainMeshBuilder.boundary_samples(doc),
	}


## Moves the channel patch's columns over the boundary samples in `rect` (grid coordinates) to
## their current heights in `doc` (RiverExitMesh.move_column) and uploads just those columns
## (surface_update_vertex_region on `channel`, the patch's mesh), so during a sculpt stroke on
## the edge the patch follows the skirt's in-place update (P6-3 follow-up: it kept the stroke's
## start heights until the stroke's water refresh). `mirror` from channel_mirror(), updated.
## `width`, `fall`: the skirt's. Returns how many columns moved.
static func update_channel_in_place(
	channel: ArrayMesh,
	mirror: Dictionary,
	exits: Dictionary,
	doc: MapDocument,
	rect: Rect2i,
	width: float,
	fall: float
) -> int:
	if mirror.is_empty():
		return 0
	var loop: Array[Vector2i] = mirror.loop
	var count := loop.size()
	var touched := PackedByteArray()
	touched.resize(count)
	var any := false
	for span in TerrainMeshBuilder.skirt_ranges(doc, rect):
		for i in range(span.x, span.y):
			touched[i] = 1
			any = true
	if not any:
		return 0
	var windows: Array = exits.get("windows", [])
	var columns_total := 0
	for window: Vector2i in windows:
		columns_total += window.y + 1
	var vertices: PackedVector3Array = mirror.vertices
	var normals: PackedVector3Array = mirror.normals
	var total := vertices.size()
	var rings := total / maxi(columns_total, 1)
	var base := 0
	var moved := 0
	for window: Vector2i in windows:
		var columns := window.y + 1
		for c in columns:
			var index := (window.x + c) % count
			if touched[index] == 0:
				continue
			var first := base + c * rings
			var outer := c == 0 or c == columns - 1
			RiverExitMesh.move_column(
				doc, loop[index], vertices, normals, first, rings, outer, width, fall
			)
			# An inner column's normals change at ring 0 alone (move_column).
			var changed := rings if outer else 1
			var encoded := PackedInt32Array()
			encoded.resize(changed * 2)
			for k in changed:
				encoded[k * 2] = TerrainMeshBuilder.encode_normal(normals[first + k])
				encoded[k * 2 + 1] = TerrainMeshBuilder.encode_tangent(normals[first + k])
			channel.surface_update_vertex_region(
				0, first * 12, vertices.slice(first, first + rings).to_byte_array()
			)
			channel.surface_update_vertex_region(0, total * 12 + first * 8, encoded.to_byte_array())
			moved += 1
		base += columns * rings
	mirror.vertices = vertices
	mirror.normals = normals
	return moved


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
