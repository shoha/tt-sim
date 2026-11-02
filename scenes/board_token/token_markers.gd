class_name TokenMarkers
extends Node3D

## The top-down token marker: from straight above an avatar is a 20 px speck at the usual zoom
## (camera-2, 2026-11-02), so above about 55 degrees of camera pitch every token gets a ring
## drawn on top of the board around it, in the token's own colour between two ink lines, about
## TARGET_PX across whatever the zoom (a large token's ring is its footprint instead) and open in
## the middle so it never covers the token. It fades in between 55 and 70 degrees
## (CameraRig.marker_strength) and is off below, where the model reads and the token ghost
## shows a token under cover.
##
## One MultiMesh of camera-facing quads with a no-depth-test shader (shaders/token_marker.gdshader):
## one draw call whatever the token count, and nothing at all while the pitch is low (the node
## does no work below the threshold). The colour comes from the token's own look: the most vivid
## colour of its palette texture or material (what the token ghost is dressed in), made readable.
##
## A token the players cannot see (BoardToken.is_visible_to_players false) gets no ring for a
## player and a dimmed one for the GM, as the token itself is drawn; one that is not drawn at
## all (hidden body, spawning) gets none. The ring belongs to the local view: nothing is synced.

const SHADER := preload("res://shaders/token_marker.gdshader")
## The ring's diameter on screen for a small token, in pixels, and its size relative to a large
## token's footprint (so it clears the base).
const TARGET_PX := 26.0
const FOOTPRINT_MARGIN := 1.2
const RENDER_PRIORITY := 20
## How often the tokens' sizes and colours are read again, seconds.
const REFRESH_PERIOD_S := 0.5
## The alpha a token hidden from the players has in the GM's view (as the token's own 0.4).
const GM_HIDDEN_ALPHA := 0.4

var _camera: Camera3D = null
var _viewport: SubViewport = null
var _instances: MultiMeshInstance3D = null
var _since_refresh: float = REFRESH_PERIOD_S
## BoardToken instance id -> {"offset": Vector3, "radius": float, "colour": Color}.
var _look: Dictionary = {}
## Palette or material (by instance id) -> its marker colour, so a shared palette is read once.
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
	multi.mesh = mesh
	_instances = MultiMeshInstance3D.new()
	_instances.multimesh = multi
	_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1000.0), Vector3(2000.0, 2000.0, 2000.0))
	_instances.visible = false
	add_child(_instances)


# --- pure rules ---


## The ring's alpha for a token: `strength` (CameraRig.marker_strength) when it is drawn and the
## players can see it, GM_HIDDEN_ALPHA of it for the GM's view of a hidden token, 0 for none (a
## player must not learn where a hidden token stands, so nothing is drawn for them).
static func ring_alpha(
	strength: float, visible_to_players: bool, body_visible: bool, gm_access: bool
) -> float:
	if not body_visible:
		return 0.0
	if visible_to_players:
		return strength
	return strength * GM_HIDDEN_ALPHA if gm_access else 0.0


## The ring's diameter in metres: the token's footprint (`radius_m`, with a margin) or
## `target_px` pixels at `camera_size` metres across `viewport_px` pixels, whichever is larger.
static func ring_size(
	radius_m: float, camera_size: float, viewport_px: float, target_px: float = TARGET_PX
) -> float:
	var per_px := camera_size / maxf(viewport_px, 1.0)
	return maxf(radius_m * 2.0 * FOOTPRINT_MARGIN, target_px * per_px)


## The most vivid of `colours` (saturation times value, ignoring near-white and near-black),
## made readable on the board: at least half saturated (unless it is grey) and bright. Grey
## when there are none.
static func vivid(colours: PackedColorArray) -> Color:
	var best := Color(0.7, 0.7, 0.7)
	var best_score := -1.0
	for c in colours:
		if c.a < 0.5 or c.v < 0.12 or (c.s < 0.12 and c.v > 0.92):
			continue
		var score := c.s * c.v + 0.05 * c.v
		if score > best_score:
			best_score = score
			best = c
	# A grey token keeps a grey ring (forcing saturation on it would paint it pink).
	var saturation := best.s if best.s < 0.15 else maxf(best.s, 0.5)
	return Color.from_hsv(best.h, saturation, maxf(best.v, 0.8))


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
	var gm_access := NetworkManager.has_gm_access()
	var multi := _instances.multimesh
	var tokens := get_tree().get_nodes_in_group(BoardToken.GROUP_NAME)
	if multi.instance_count < tokens.size():
		multi.instance_count = maxi(tokens.size() * 2, 8)
	var camera_size := _camera.size
	var vp_height := float(_viewport.size.y)
	var shown := 0
	for node in tokens:
		var token := node as BoardToken
		if token == null or token.rigid_body == null or not token.rigid_body.is_inside_tree():
			continue
		var alpha := ring_alpha(
			strength, token.is_visible_to_players, token.rigid_body.visible, gm_access
		)
		if alpha <= 0.0:
			continue
		var id := token.get_instance_id()
		if refresh or not _look.has(id):
			_look[id] = _read_look(token)
		var look: Dictionary = _look[id]
		var size := ring_size(look.radius, camera_size, vp_height)
		var centre := token.rigid_body.global_position + (look.offset as Vector3)
		var xform := Transform3D(_camera.global_basis.scaled(Vector3.ONE * size), centre)
		multi.set_instance_transform(shown, xform)
		var colour: Color = look.colour
		multi.set_instance_color(shown, Color(colour.r, colour.g, colour.b, alpha))
		shown += 1
	multi.visible_instance_count = shown
	_instances.visible = shown > 0


## A token's ring centre (relative to its body), footprint radius and colour, from its meshes.
func _read_look(token: BoardToken) -> Dictionary:
	var meshes := TokenGhost.meshes_of(token.rigid_body)
	var box := AABB()
	var first := true
	var colours := PackedColorArray()
	for mi in meshes:
		if not mi.is_inside_tree():
			continue
		var world_box := mi.global_transform * mi.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
		colours.append_array(_colours_of(TokenGhost.source_of(mi)))
	if first:
		return {"offset": Vector3.UP * 0.5, "radius": 0.4, "colour": vivid(colours)}
	var centre := box.get_center()
	return {
		"offset": centre - token.rigid_body.global_position,
		"radius": maxf(box.size.x, box.size.z) * 0.5,
		"colour": vivid(colours),
	}


## The colours a mesh source (a palette texture or a material) shows, a few dozen at most.
func _colours_of(source: Variant) -> PackedColorArray:
	var out := PackedColorArray()
	if source == null:
		return out
	var key: int = (source as Object).get_instance_id()
	if _colours.has(key):
		return _colours[key]
	var texture: Texture2D = null
	if source is Texture2D:
		texture = source
	elif source is BaseMaterial3D:
		out.append((source as BaseMaterial3D).albedo_color)
		texture = (source as BaseMaterial3D).albedo_texture
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
