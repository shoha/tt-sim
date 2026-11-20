class_name PainterWaterField
extends RefCounted

## The painted look's water SURFACE: one WaterField of the map's document drawn as one mesh
## (WaterFieldMesh, painter_water.gdshader's field branch) in place of AuthoredWater's surface mesh
## and the curtains of its falls. Owned by PainterWater, which makes one per painted map
## (docs/systems/water_field.md "Drawing it", docs/systems/painter.md "Water").
##
## Draw only. Gameplay (WaterSurface, zones, walkability, the ripple registry) keeps reading
## AuthoredWater's own data until the gameplay stage, so the old meshes are still built; here the
## surface mesh is hidden while the field draws (the falls mesh stays: its mist is the one part of
## a fall the field does not draw) and shown again on release(). The field mesh is a child of the
## map root, not of AuthoredWater, because AuthoredWater.apply() frees its children on every edit.
##
## Edits. Three things change what the field draws, and each redoes only a dirty rect
## (WaterField.update, equal to a full build bit for bit):
## - a water edit: AuthoredWater.refreshed fires; each body's signature (and the pond mask's
##   samples) is compared with the last one, and the rects of the changed bodies, as they were
##   (kept per body) and as they are (WaterField.rect_of_bodies), are redone;
## - a ground edit: AuthoredTerrain.ground_edited(rect) near water, redone for that rect.
## Ground edits arrive in bursts, so rects are merged and redone once per frame. The mesh is rebuilt
## whole from the field after an update (about 50 ms on a 245 x 245 grid: GDScript over the field's
## arrays); an update that changed nothing builds nothing.

## The mesh's custom bounds margin: a surface is never above its tallest sample.
const MARGIN_M := 0.5
## A ground edit within this many samples of water redoes the field there (the bank hold and the
## buried rings read the ground up to a few samples out).
const GROUND_REACH := 8
## The lowest depth the textures hold: a buried or dry sample must not drag a bicubic fetch of the
## waterline down by metres.
const DEPTH_FLOOR := -0.3

## The field, null until a map is attached.
var field: WaterField = null
## The mesh node, null when the map has no water (or nothing is attached).
var node: MeshInstance3D = null
## Milliseconds of the last build: {"field": ms, "mesh": ms}.
var timings: Dictionary = {}
## The last build's counts: {"vertices", "triangles"}.
var counts: Dictionary = {}

var _map: Node3D = null
var _terrain: AuthoredTerrain = null
var _water: AuthoredWater = null
var _material: Material = null
var _enabled: bool = true
var _signatures: Dictionary = {}
var _rects: Dictionary = {}
var _pond_mask: PackedByteArray = PackedByteArray()
var _dirty: Rect2i = Rect2i()
var _flush_queued: bool = false
var _tex_a: ImageTexture = null
var _tex_b: ImageTexture = null


## Draws the water of `map` (a map root with an AuthoredTerrain and an AuthoredWater) with
## `material` (the shared painted water material). False, drawing nothing, when the map has no
## authored terrain (a Blender map: its water planes keep the shader's depth-buffer path).
func attach(map: Node3D, material: Material) -> bool:
	detach()
	_map = map
	_material = material
	_terrain = map.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
	if _terrain == null or _terrain.document == null:
		return false
	if not _terrain.ground_edited.is_connected(_on_ground_edited):
		_terrain.ground_edited.connect(_on_ground_edited)
	_bind_water(map.get_node_or_null(NodePath(AuthoredWater.NODE_NAME)) as AuthoredWater)
	if _water == null:
		# The map's first water is made later (an authoring edit on a dry map): wait for its node.
		map.child_entered_tree.connect(_on_map_child)
	_rebuild_all()
	_apply_visibility()
	return true


func _bind_water(water: AuthoredWater) -> void:
	_water = water
	if water != null and not water.refreshed.is_connected(_on_water_refreshed):
		water.refreshed.connect(_on_water_refreshed)


func _on_map_child(child: Node) -> void:
	if child is AuthoredWater and _water == null:
		_bind_water(child as AuthoredWater)
		_map.child_entered_tree.disconnect(_on_map_child)


## Stops drawing: frees the mesh, shows AuthoredWater's own surface and lets go of the map.
func detach() -> void:
	if _map != null and is_instance_valid(_map):
		if _map.child_entered_tree.is_connected(_on_map_child):
			_map.child_entered_tree.disconnect(_on_map_child)
	if _water != null and is_instance_valid(_water):
		if _water.refreshed.is_connected(_on_water_refreshed):
			_water.refreshed.disconnect(_on_water_refreshed)
		var old := _water.get_mesh_instance()
		if old != null:
			old.visible = true
	if _terrain != null and is_instance_valid(_terrain):
		if _terrain.ground_edited.is_connected(_on_ground_edited):
			_terrain.ground_edited.disconnect(_on_ground_edited)
	_free_node()
	field = null
	_signatures.clear()
	_rects.clear()
	_pond_mask = PackedByteArray()
	_dirty = Rect2i()
	_map = null
	_terrain = null
	_water = null
	_material = null


## Whether the field is attached to a map.
func is_attached() -> bool:
	return field != null


## Whether the field draws now (false: AuthoredWater's own surface does).
func is_enabled() -> bool:
	return _enabled


## Draws the field (true) or AuthoredWater's own surface and curtains (false), for an A/B of the
## two in one run.
func set_enabled(on: bool) -> void:
	_enabled = on
	_apply_visibility()


## Redoes the field over `rect` (sample coordinates) now and rebuilds the mesh when it changed
## (tests, probes; the signals queue this once per frame).
func update_rect(rect: Rect2i) -> void:
	if field == null or _terrain == null:
		return
	var t0 := Time.get_ticks_usec()
	var changed := field.update(_terrain.document, rect)
	timings["field"] = (Time.get_ticks_usec() - t0) / 1000.0
	if changed.has_area():
		_build_mesh()


func _rebuild_all() -> void:
	var doc := _terrain.document
	var t0 := Time.get_ticks_usec()
	field = WaterField.build(doc)
	timings["field"] = (Time.get_ticks_usec() - t0) / 1000.0
	_remember(doc)
	_build_mesh()


## The mesh of the field's current state, replacing the node's.
func _build_mesh() -> void:
	var t0 := Time.get_ticks_usec()
	var built := WaterFieldMesh.build(field)
	counts = {"vertices": built.vertices, "triangles": built.triangles}
	var mesh := WaterFieldMesh.to_mesh(built, _material)
	if mesh == null:
		_free_node()
		return
	var aabb: AABB = built.aabb
	mesh.custom_aabb = aabb.grow(MARGIN_M)
	if node == null:
		node = MeshInstance3D.new()
		node.name = WaterFieldMesh.MESH_NAME
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta(Constants.BOUNDS_EXEMPT_META, true)
		_map.add_child(node)
		node.set_instance_shader_parameter(
			&"water_flow_present", not _terrain.document.water_flow.is_empty()
		)
	node.mesh = mesh
	node.visible = _enabled
	timings["mesh"] = (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	_upload_textures()
	timings["textures"] = (Time.get_ticks_usec() - t1) / 1000.0


## Shade spike (S1): the field's channels as two RGBAF textures over the sample grid, sampled per
## fragment (bicubic) so the shore, the depth tint and the white read smooth fields instead of
## per-vertex attributes on the 0.25 m grid. `fld_a` = (depth, energy, shore, steep) with the
## buried and dry samples' depth held at DEPTH_FLOOR; `fld_b` = (flow coordinate premultiplied by
## its weight, weight, 0, 0), filtered bilinear and divided back in the shader. The whole texture
## is rebuilt after an update (ImageTexture has no partial update in Godot 4.7).
func _upload_textures() -> void:
	if _material == null or not (_material is ShaderMaterial):
		return
	var sm := _material as ShaderMaterial
	var nx := field.size.x
	var nz := field.size.y
	var n := nx * nz
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	a.resize(n * 4)
	b.resize(n * 4)
	for i in n:
		a[i * 4] = maxf(field.depth[i], DEPTH_FLOOR)
		a[i * 4 + 1] = field.energy[i]
		a[i * 4 + 2] = field.shore[i]
		a[i * 4 + 3] = field.steep[i]
		var u: float = field.flow_u[i]
		if u > WaterField.NO_FLOW_U * 0.5:
			b[i * 4] = u
			b[i * 4 + 1] = 1.0
			var ft: float = field.foot[i]
			if ft < WaterFieldStroke.NO_FOOT * 0.5:
				# The foot coordinate rides the same weight (fld_b.g) and is divided by it in the shader.
				b[i * 4 + 2] = ft
				b[i * 4 + 3] = 1.0
	_tex_a = _fill_texture(_tex_a, nx, nz, a)
	_tex_b = _fill_texture(_tex_b, nx, nz, b)
	sm.set_shader_parameter(&"fld_a", _tex_a)
	sm.set_shader_parameter(&"fld_b", _tex_b)
	sm.set_shader_parameter(&"fld_origin", field.origin)
	sm.set_shader_parameter(&"fld_inv_step", Vector2.ONE / field.step)
	sm.set_shader_parameter(&"fld_dim", Vector2(nx, nz))


func _fill_texture(tex: ImageTexture, nx: int, nz: int, data: PackedFloat32Array) -> ImageTexture:
	var img := Image.create_from_data(nx, nz, false, Image.FORMAT_RGBAF, data.to_byte_array())
	if tex != null and tex.get_width() == nx and tex.get_height() == nz:
		tex.update(img)
		return tex
	return ImageTexture.create_from_image(img)


func _free_node() -> void:
	if node != null and is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()
	node = null


## The old surface shows only while the field does not draw it.
func _apply_visibility() -> void:
	if _water != null and is_instance_valid(_water):
		var old := _water.get_mesh_instance()
		if old != null:
			old.visible = not (_enabled and node != null)
	if node != null:
		node.visible = _enabled


func _on_water_refreshed() -> void:
	if field == null:
		return
	var doc := _terrain.document
	var rect := _changed_rect(doc)
	_remember(doc)
	if rect.has_area():
		update_rect(rect)
	_apply_visibility()


## The sample rect a water edit changed: the changed bodies' areas as they were (kept in _rects)
## and as they are, and the pond mask's changed samples' bodies. Empty when nothing changed.
func _changed_rect(doc: MapDocument) -> Rect2i:
	var ids := {}
	var now := {}
	for body in doc.water_bodies:
		now[body.id] = body
		if not _signatures.has(body.id) or _signatures[body.id] != _signature(body):
			ids[body.id] = true
	for id: int in _signatures:
		if not now.has(id):
			ids[id] = true
	var mask := doc.pond_mask
	if mask != _pond_mask:
		var same := mask.size() == _pond_mask.size()
		for i in mask.size():
			var was := _pond_mask[i] if same else 0
			if mask[i] != was:
				ids[int(mask[i])] = true
				ids[int(was)] = true
	var rect := Rect2i()
	var bodies: Array[WaterBody] = []
	for id: int in ids:
		if _rects.has(id):
			rect = _merge(rect, _rects[id])
		if now.has(id):
			bodies.append(now[id])
	if not bodies.is_empty():
		rect = _merge(rect, WaterField.rect_of_bodies(doc, bodies))
	return rect


## Notes each body's signature, the area it covers and the pond mask, for the next edit.
func _remember(doc: MapDocument) -> void:
	_signatures.clear()
	_rects.clear()
	for body in doc.water_bodies:
		_signatures[body.id] = _signature(body)
		var one: Array[WaterBody] = [body]
		_rects[body.id] = WaterField.rect_of_bodies(doc, one)
	_pond_mask = doc.pond_mask.duplicate()


static func _signature(body: WaterBody) -> int:
	return [
		body.kind, body.depth, body.level_m, body.speed, body.points, body.half_widths
	].hash()


static func _merge(a: Rect2i, b: Rect2i) -> Rect2i:
	if not a.has_area():
		return b
	if not b.has_area():
		return a
	return a.merge(b)


func _on_ground_edited(sample_rect: Rect2i) -> void:
	if field == null or not sample_rect.has_area():
		return
	var near := sample_rect.grow(GROUND_REACH).intersection(Rect2i(Vector2i.ZERO, field.size))
	if not _has_water(near):
		return
	_dirty = _merge(_dirty, sample_rect.grow(WaterField.RING_MARGIN))
	if not _flush_queued:
		_flush_queued = true
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.process_frame.connect(_flush_dirty, CONNECT_ONE_SHOT)


func _flush_dirty() -> void:
	_flush_queued = false
	var rect := _dirty
	_dirty = Rect2i()
	if field != null and rect.has_area():
		update_rect(rect)


## Whether any sample of `rect` holds water (the surface's height is set).
func _has_water(rect: Rect2i) -> bool:
	for z in range(rect.position.y, rect.end.y):
		var row := z * field.size.x
		for x in range(rect.position.x, rect.end.x):
			if field.w[row + x] != WaterGeometry.DRY:
				return true
	return false
