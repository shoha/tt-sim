class_name TokenMarkers
extends Node3D

## The top-down token marker: from straight above an avatar is a 20 px speck at the usual zoom
## (camera-2, 2026-11-02), so above about 55 degrees of camera pitch every token gets a map pin
## drawn on top of the board: a round head holding the token's own picture (TokenPortraits) with
## a short tail whose tip touches the top edge of the token, so the token itself is never
## covered. The head is HEAD_PX across whatever the zoom; the tip stands on the token's edge as
## it looks from the camera (a large token's footprint edge, a standing figure's head), found
## from the token's footprint and height. It fades in between 55 and 70 degrees
## (CameraRig.marker_strength) and is off below, where the model reads and the token ghost
## shows a token under cover.
##
## One MultiMesh of camera-facing quads with a no-depth-test shader (shaders/token_marker.gdshader):
## one draw call whatever the token count (the pictures are cells of one atlas texture), and
## nothing at all while the pitch is low (the node does no work below the threshold, and the
## atlas is not even made). Pins are drawn from the top of the screen down, so a pin lower on
## the screen lies over one above it. The pin's body colour is the token's own: the most vivid
## colour of its palette texture, material or vertex colours (what the token ghost is dressed
## in), made readable; it is the disc a token shows until its picture is ready.
##
## A token the players cannot see (BoardToken.is_visible_to_players false) gets no pin for a
## player and a dimmed one for the GM, as the token itself is drawn; one that is not drawn at
## all (hidden body, spawning) gets none. The pins belong to the local view: nothing is synced.

const SHADER := preload("res://shaders/token_marker.gdshader")
## The pin head's diameter on screen, in pixels, whatever the zoom or the token's size.
const HEAD_PX := 24.0
## The pin's quad in head diameters, and the height of the tip above its bottom edge; the same
## numbers as the shader's QUAD_W, QUAD_H and TIP_Y.
const QUAD_W := 1.3
const QUAD_H := 1.65
const TIP_Y := 0.14
const RENDER_PRIORITY := 20
## How often the tokens' sizes and colours are read again, seconds.
const REFRESH_PERIOD_S := 0.5
## The alpha a token hidden from the players has in the GM's view (as the token's own 0.4).
const GM_HIDDEN_ALPHA := 0.4
## The disc of a token whose colours cannot be read at all: a soft periwinkle, never white.
const NO_COLOUR := Color(0.62, 0.66, 0.78)
## Most vertex colours sampled from a mesh surface.
const VERTEX_SAMPLES := 64

var _camera: Camera3D = null
var _viewport: SubViewport = null
var _instances: MultiMeshInstance3D = null
var _portraits: TokenPortraits = null
var _since_refresh: float = REFRESH_PERIOD_S
## BoardToken instance id -> {"offset": Vector3, "radius": float, "half_height": float,
## "colour": Color, "key": String ("" while the model is not loaded)}.
var _look: Dictionary = {}
## Palette, material or mesh (by instance id) -> its colours, so a shared palette is read once.
var _colours: Dictionary = {}


## A TokenMarkers under `viewport` (the world SubViewport), looking through `camera`.
static func attach(viewport: SubViewport, camera: Camera3D) -> TokenMarkers:
	var markers := TokenMarkers.new()
	markers.name = "TokenMarkers"
	markers.process_priority = 10  # after the camera controller has placed the camera
	markers._camera = camera
	markers._viewport = viewport
	viewport.add_child(markers)
	return markers


func _ready() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = RENDER_PRIORITY
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = mesh
	_instances = MultiMeshInstance3D.new()
	_instances.multimesh = multi
	_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1000.0), Vector3(2000.0, 2000.0, 2000.0))
	_instances.visible = false
	add_child(_instances)


# --- pure rules ---


## The pin's alpha for a token: `strength` (CameraRig.marker_strength) when it is drawn and the
## players can see it, GM_HIDDEN_ALPHA of it for the GM's view of a hidden token, 0 for none (a
## player must not learn where a hidden token stands, so nothing is drawn for them).
static func pin_alpha(
	strength: float, visible_to_players: bool, body_visible: bool, gm_access: bool
) -> float:
	if not body_visible:
		return 0.0
	if visible_to_players:
		return strength
	return strength * GM_HIDDEN_ALPHA if gm_access else 0.0


## The pin head's diameter in metres: `head_px` pixels at `camera_size` metres across
## `viewport_px` pixels.
static func head_metres(camera_size: float, viewport_px: float, head_px: float = HEAD_PX) -> float:
	return head_px * camera_size / maxf(viewport_px, 1.0)


## How far a token's top edge lies from its centre along the unit screen-up vector `up`, in
## metres: a standing cylinder of `radius` and `half_height` (its footprint and body), so seen
## from straight above it is the footprint's edge and seen from the side it is the head.
static func top_edge_metres(radius: float, half_height: float, up: Vector3) -> float:
	return radius * Vector2(up.x, up.z).length() + half_height * absf(up.y)


## The world box of `body`'s collision shapes (an empty AABB when it has none).
static func shape_box(body: Node) -> AABB:
	var box := AABB()
	var first := true
	for node in body.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled or not shape_node.is_inside_tree():
			continue
		var world := shape_node.global_transform * shape_extent(shape_node.shape)
		box = world if first else box.merge(world)
		first = false
	return box


## A shape's box in its own space.
static func shape_extent(shape: Shape3D) -> AABB:
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var r := capsule.radius
		return AABB(Vector3(-r, -capsule.height * 0.5, -r), Vector3(2.0 * r, capsule.height, 2.0 * r))
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var s := (shape as SphereShape3D).radius
		return AABB(Vector3.ONE * -s, Vector3.ONE * 2.0 * s)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var c := cylinder.radius
		return AABB(Vector3(-c, -cylinder.height * 0.5, -c), Vector3(2.0 * c, cylinder.height, 2.0 * c))
	return shape.get_debug_mesh().get_aabb()


## The pin's transform: its tip at `tip`, `head` metres across, turned to `camera_basis`.
static func pin_transform(tip: Vector3, head: float, camera_basis: Basis) -> Transform3D:
	var up := camera_basis.y.normalized()
	var scaled := camera_basis * Basis.from_scale(Vector3(QUAD_W * head, QUAD_H * head, 1.0))
	return Transform3D(scaled, tip + up * (QUAD_H * 0.5 - TIP_Y) * head)


## The most vivid of `colours` (saturation times value, ignoring near-white and near-black),
## made readable on the board: at least half saturated (unless it is grey) and bright.
## NO_COLOUR when there are none.
static func vivid(colours: PackedColorArray) -> Color:
	var best := NO_COLOUR
	var best_score := -1.0
	for c in colours:
		if c.a < 0.5 or c.v < 0.12 or (c.s < 0.12 and c.v > 0.92):
			continue
		var score := c.s * c.v + 0.05 * c.v
		if score > best_score:
			best_score = score
			best = c
	if best_score < 0.0:
		return NO_COLOUR
	# A grey token keeps a grey pin (forcing saturation on it would paint it pink).
	var saturation := best.s if best.s < 0.15 else maxf(best.s, 0.5)
	return Color.from_hsv(best.h, saturation, maxf(best.v, 0.8))


## Up to `count` colours spread over a vertex colour array, each times `tint` (the material's
## albedo colour).
static func sample_colours(
	vertex_colours: PackedColorArray, tint: Color, count: int = VERTEX_SAMPLES
) -> PackedColorArray:
	var out := PackedColorArray()
	var step := maxi(1, vertex_colours.size() / maxi(count, 1))
	for i in range(0, vertex_colours.size(), step):
		out.append(vertex_colours[i] * tint)
	return out


# --- per frame ---


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var strength := CameraRig.marker_strength(CameraRig.pitch_of_back_y(_camera.global_basis.z.y))
	if strength <= 0.0:
		if _instances.visible:
			_instances.visible = false
			_instances.multimesh.visible_instance_count = 0
		return
	_since_refresh += delta
	var refresh := _since_refresh >= REFRESH_PERIOD_S
	if refresh:
		_since_refresh = 0.0
	_draw(strength, refresh)


func _draw(strength: float, refresh: bool) -> void:
	if _portraits == null:
		_portraits = TokenPortraits.new()
		add_child(_portraits)
		(_instances.multimesh.mesh.material as ShaderMaterial).set_shader_parameter(
			"atlas", _portraits.atlas
		)
	var gm_access := NetworkManager.has_gm_access()
	var multi := _instances.multimesh
	var tokens := get_tree().get_nodes_in_group(BoardToken.GROUP_NAME)
	if multi.instance_count < tokens.size():
		multi.instance_count = maxi(tokens.size() * 2, 8)
	var camera_basis := _camera.global_basis
	var up := camera_basis.y.normalized()
	var head := head_metres(_camera.size, float(_viewport.size.y))
	var pins: Array[Array] = []
	for node in tokens:
		var token := node as BoardToken
		if token == null or token.rigid_body == null or not token.rigid_body.is_inside_tree():
			continue
		var alpha := pin_alpha(
			strength, token.is_visible_to_players, token.rigid_body.visible, gm_access
		)
		if alpha <= 0.0:
			continue
		var id := token.get_instance_id()
		if refresh or not _look.has(id):
			_look[id] = _read_look(token)
		var look: Dictionary = _look[id]
		var cell := -1
		var key: String = look.key
		if key != "":
			cell = _portraits.cell_of(key)
			if cell < 0 and not _portraits.knows(key):
				_portraits.request(key, _source_for(token))
		var centre := token.rigid_body.global_position + (look.offset as Vector3)
		var tip := centre + up * top_edge_metres(look.radius, look.half_height, up)
		var colour: Color = look.colour
		colour.a = alpha
		pins.append([tip.dot(up), tip, colour, cell])
	# Higher on the screen first, so a lower pin lies over the one above it.
	pins.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in pins.size():
		var pin: Array = pins[i]
		multi.set_instance_transform(i, pin_transform(pin[1], head, camera_basis))
		multi.set_instance_color(i, pin[2])
		var cell: int = pin[3]
		var uv := TokenPortraits.picture_uv(maxi(cell, 0))
		multi.set_instance_custom_data(i, Color(uv.x, uv.y, 1.0 if cell >= 0 else 0.0, 0.0))
	multi.visible_instance_count = pins.size()
	_instances.visible = not pins.is_empty()


## What a token's picture is made from (see TokenPortraits): the avatar's recipe, the pack's icon
## when it has one, else the token's own meshes.
func _source_for(token: BoardToken) -> Dictionary:
	if token.is_avatar():
		return {"kind": TokenPortraits.Kind.AVATAR, "recipe": token.avatar_recipe}
	if token.pack_id != "" and token.asset_id != "" and AssetManager.resolver != null:
		var path: String = AssetManager.resolver.resolve_icon_sync(
			token.pack_id, token.asset_id, token.variant_id
		)
		if path != "":
			return {"kind": TokenPortraits.Kind.ICON, "path": path}
	return {"kind": TokenPortraits.Kind.MODEL, "token": token.get_instance_id()}


## A token's pin centre (relative to its body), footprint radius, half height, colour and
## picture key, from its meshes. The key is empty while it has none (a placeholder is not a
## model worth a portrait).
func _read_look(token: BoardToken) -> Dictionary:
	var meshes := TokenGhost.meshes_of(token.rigid_body)
	var box := AABB()
	var first := true
	var colours := PackedColorArray()
	var first_mesh: Mesh = null
	for mi in meshes:
		if not mi.is_inside_tree():
			continue
		var world_box := mi.global_transform * mi.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
		first_mesh = first_mesh if first_mesh != null else mi.mesh
		colours.append_array(_colours_of(TokenGhost.source_of(mi), mi.mesh))
	if first:
		return {
			"offset": Vector3.UP * 0.5,
			"radius": 0.4,
			"half_height": 0.5,
			"colour": vivid(colours),
			"key": "",
		}
	var key := TokenPortraits.identity_key(
		token.pack_id,
		token.asset_id,
		token.variant_id,
		token.avatar_recipe,
		first_mesh.get_instance_id()
	)
	# An avatar's footprint is its capsule (AvatarExtent: the body core): the skinned meshes'
	# rest-pose bounds, arms out, would put the pin well above the figure. A pack token's
	# collision shape is not trusted (a horse's is 2.3 times its model, a pig's a speck, measured
	# 2026-11-02), so its mesh bounds stand.
	if token.is_avatar():
		var footprint := shape_box(token.rigid_body)
		if footprint.has_volume():
			box = footprint
	return {
		"offset": box.get_center() - token.rigid_body.global_position,
		"radius": maxf(box.size.x, box.size.z) * 0.5,
		"half_height": box.size.y * 0.5,
		"colour": vivid(colours),
		"key": key,
	}


## The colours a mesh source (a palette texture or a material) shows, a few dozen at most. A
## material that takes its colour from the vertices (the free "chunky" game art does, its
## albedo is plain white) is read from the mesh's vertex colours, which was the white pin.
func _colours_of(source: Variant, mesh: Mesh) -> PackedColorArray:
	var out := PackedColorArray()
	if source == null:
		return out
	var from_vertices := (
		source is BaseMaterial3D
		and (source as BaseMaterial3D).vertex_color_use_as_albedo
		and mesh != null
	)
	var key: int = mesh.get_instance_id() if from_vertices else (source as Object).get_instance_id()
	if _colours.has(key):
		return _colours[key]
	var texture: Texture2D = null
	if source is Texture2D:
		texture = source
	elif source is BaseMaterial3D:
		var material := source as BaseMaterial3D
		if from_vertices:
			out.append_array(sample_colours(_vertex_colours(mesh), material.albedo_color))
		else:
			out.append(material.albedo_color)
		texture = material.albedo_texture
	if texture != null:
		var image := texture.get_image()
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			if image.get_width() * image.get_height() > 1024:
				image.resize(16, 16, Image.INTERPOLATE_NEAREST)
			for y in image.get_height():
				for x in image.get_width():
					out.append(image.get_pixel(x, y))
	_colours[key] = out
	return out


## Every surface's vertex colours, spread to at most VERTEX_SAMPLES each.
func _vertex_colours(mesh: Mesh) -> PackedColorArray:
	var out := PackedColorArray()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var colours: Variant = arrays[Mesh.ARRAY_COLOR] if arrays.size() > Mesh.ARRAY_COLOR else null
		if colours is PackedColorArray:
			out.append_array(sample_colours(colours, Color.WHITE))
	return out
